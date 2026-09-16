package store

import (
	"context"
	"fmt"
	"net"
	"time"

	"github.com/jackc/pgx/v5"
)

// MeetingGrant is what hbh.authorize_meeting_entry answered.
//
// Read the field that is NOT here: there is no token. The database decides who
// may enter and until when; the pass is signed in the service, because the
// provider's private key belongs in the environment and not in a table that
// every backup copies.
type MeetingGrant struct {
	MeetingID int64
	RoomRef   string
	Provider  string
	Moderator bool
	ExpiresAt time.Time

	// DisplayName is the ADULT's own name, for the provider's waiting room,
	// where the therapist admits people by name. It comes from hbh.users
	// inside the function rather than from the request, because a name the
	// client chooses is a name the client can choose - and the waiting room
	// is exactly where somebody would type a therapist's name to be waved
	// through. The child is never named to the provider.
	DisplayName string

	// UserRef is an opaque handle so two tabs are one person: the account
	// id and nothing else.
	UserRef string
}

// AuthorizeMeetingEntry asks whether this caller may enter this consultation.
//
// EVERY REFUSAL IS THE DATABASE'S. The function raises HB021 for an
// appointment that is not this caller's - the same answer as one that does not
// exist, because telling a stranger it exists but is not theirs is telling them
// it exists - HB250 for an appointment that is not a consultation, HB253 while
// the invoice is unpaid, and HB252 when the hour has not come or the room is
// closed. None of that is re-asked here.
//
// READ-ONLY ON PURPOSE. It decides and writes nothing, so a caller that goes on
// to fail leaves no half-issued pass behind. The evidence is RecordMeetingToken,
// and the handler calls it before it answers.
func (d *DB) AuthorizeMeetingEntry(ctx context.Context, ident string, appointmentID int) (MeetingGrant, error) {
	var g MeetingGrant
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT meeting_id, room_ref, provider, moderator_flg, expires_at,
			       display_name, user_ref
			  FROM hbh.authorize_meeting_entry($1)`, appointmentID).
			Scan(&g.MeetingID, &g.RoomRef, &g.Provider, &g.Moderator, &g.ExpiresAt,
				&g.DisplayName, &g.UserRef)
	})
	if err != nil {
		return MeetingGrant{}, fmt.Errorf("authorize_meeting_entry: %w", err)
	}
	return g, nil
}

// RecordMeetingToken writes the evidence that a pass was issued.
//
// WHY THIS IS CALLED BEFORE THE PASS IS ANSWERED, and not after: a pass handed
// out with no record of who took it is the one outcome hbh.meeting_tokens
// exists to prevent. If this fails, the family is told the service is
// unavailable and nobody enters - which is the correct trade, because a Jitsi
// token cannot be called back once it has left.
//
// The window is passed rather than computed: it is the one the database decided
// and the one the pass was signed with, and a third arithmetic here would be a
// third opinion.
func (d *DB) RecordMeetingToken(ctx context.Context, ident string, meetingID int64,
	hash []byte, moderator bool, expiresAt time.Time, clientIP *string) error {

	// A nil or unparseable address is stored as NULL rather than refused.
	// The address is context, and losing it must not be the reason a family
	// cannot enter a consultation they have paid for.
	var ip *net.IP
	if clientIP != nil && *clientIP != "" {
		if parsed := net.ParseIP(*clientIP); parsed != nil {
			ip = &parsed
		}
	}

	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			SELECT hbh.record_meeting_token($1, $2, $3, $4, $5)`,
			meetingID, hash, moderator, expiresAt, ip)
		return err
	})
	if err != nil {
		return fmt.Errorf("record_meeting_token: %w", err)
	}
	return nil
}
