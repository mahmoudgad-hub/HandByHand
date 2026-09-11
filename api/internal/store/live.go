package store

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5"
)

// The live stream.
//
// Read the shape of this file before changing it. Every function here is a
// call into PL/pgSQL, and the reason is that the gate is not one check:
//
//   * hbh.can_view_live requires a guardian to be linked to the child, to
//     hold can_view_live_flg on that link, and for the session to be running
//     right now. Staff need LIVE.VIEW and the session's own centre.
//   * hbh.issue_stream_token refuses outright when the media gateway is
//     unconfigured, when it is still marked temporary, or when it is a quick
//     tunnel. A fresh install is all three, so it fails closed by default.
//   * the fifteen-minute cap is applied by the function AND written as a
//     CHECK constraint on the row, so no caller can widen the window.
//   * the token is stored as a SHA-256 and the plaintext is returned once.
//
// None of that is repeated here. Repeating it would create a second copy of
// the most safety-critical rule in the system.

// StreamToken is what issuing produces. The plaintext leaves this struct once,
// into an HttpOnly cookie, and is never written down.
type StreamToken struct {
	Token     string
	ExpiresAt time.Time
}

// IssueStreamToken opens a viewing window on a running session.
//
// It also writes the stream_views row and the READ audit record - both inside
// the database function, because watching a child in therapy is the single
// most sensitive read this system performs and it must not be possible to do
// it without leaving a trace.
func (d *DB) IssueStreamToken(ctx context.Context, ident string, sessionID int, clientIP *string) (StreamToken, error) {
	var t StreamToken
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT token, expires_at FROM hbh.issue_stream_token($1, $2::inet)`,
			sessionID, clientIP).Scan(&t.Token, &t.ExpiresAt)
	})
	if err != nil {
		return StreamToken{}, err
	}
	return t, nil
}

// StreamTarget is where the API - never the client - must go for the media.
type StreamTarget struct {
	OK     bool
	Reason string

	// GatewayPath is an internal path on the media gateway. It is returned
	// to the API and stops here: it is not part of any response body, any
	// header, any log line, or any redirect. See CLAUDE.md.
	GatewayPath string
	CameraID    int
	SessionID   int
}

// ResolveStreamToken turns a token into a gateway path, or says why not.
//
// The reasons matter and are distinct: NO_TOKEN, REVOKED, EXPIRED, and
// SESSION_ENDED. The last one is the interesting one - a token that outlived
// its therapy session would otherwise be a window into an empty room, or into
// the next child's session in the same room.
func (d *DB) ResolveStreamToken(ctx context.Context, token string) (StreamTarget, error) {
	var (
		t    StreamTarget
		path *string
		cam  *int
		sess *int
	)
	err := d.InReadTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT ok, reason, gateway_path, camera_id, session_id FROM hbh.resolve_stream_token($1)`,
			token).Scan(&t.OK, &t.Reason, &path, &cam, &sess)
	})
	if err != nil {
		return StreamTarget{}, err
	}
	if path != nil {
		t.GatewayPath = *path
	}
	if cam != nil {
		t.CameraID = *cam
	}
	if sess != nil {
		t.SessionID = *sess
	}
	return t, nil
}

// RevokeStreamToken closes a viewing window early. Revoking a token that was
// already dead is not a failure.
func (d *DB) RevokeStreamToken(ctx context.Context, token string) (bool, error) {
	var revoked bool
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.revoke_stream_token($1)`, token).Scan(&revoked)
	})
	if err != nil {
		return false, err
	}
	return revoked, nil
}

// GatewayBase returns the media gateway's base URL for the caller's centre.
//
// It is read through hbh.param and never from configuration in this service.
// That is deliberate: issue_stream_token refuses to mint a token unless the
// same parameter is set and is not marked temporary, so the API and the
// database read the one value. A second copy in an environment variable could
// disagree with the one the safety check consulted.
func (d *DB) GatewayBase(ctx context.Context, ident string) (string, error) {
	var base string
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.param(hbh.current_center_id(), 'MEDIA_GATEWAY_BASE_URL', '')`).Scan(&base)
	})
	return base, err
}

// SessionVisible reports whether the caller may see this session at all.
//
// Used to tell "no such session" from "you may see it but may not watch it",
// so a refusal to stream does not have to answer 404 for a session the caller
// can already see in their own list - and 404 stays the answer for one they
// cannot.
func (d *DB) SessionVisible(ctx context.Context, ident string, sessionID int) (bool, error) {
	var visible bool
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT EXISTS (SELECT 1 FROM hbh.therapy_sessions WHERE session_id = $1)`,
			sessionID).Scan(&visible)
	})
	return visible, err
}
