// Package audit writes attempt records: logins, denials, and reads of
// sensitive data.
//
// Why this is a package and not a trigger: Postgres has no autonomous
// transactions, so a row written by a trigger disappears with the transaction
// that wrote it. For a record of a CHANGE that is right - the change did not
// happen, so its record must not survive. For a record of an ATTEMPT it is
// exactly wrong: a failed login happened whether or not the transaction that
// noticed it committed, and a login trail that forgets failures is not a trail.
//
// So the split in docs/01-stack-decisions.md D-1: change records come from
// hbh.trg_audit inside the transaction, attempt records come from here,
// outside it. hbh.audit_attempt opens its own connection through dblink and
// commits on its own.
package audit

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Actions accepted by hbh.audit_attempt. Anything else is refused by the
// function with HB012 rather than silently filed under the wrong heading.
const (
	ActionLogin = "LOGIN"
	ActionDeny  = "DENY"
	ActionRead  = "READ"
)

// writeTimeout bounds one audit write. It is independent of the request: the
// record must land even when the client has gone.
const writeTimeout = 5 * time.Second

// Recorder writes attempt records.
type Recorder struct {
	pool *pgxpool.Pool
	log  *slog.Logger
}

// New returns a Recorder over the same pool the rest of the service uses.
func New(pool *pgxpool.Pool, log *slog.Logger) *Recorder {
	return &Recorder{pool: pool, log: log}
}

// Event is one attempt record.
//
// Detail is a short machine-readable reason - WRONG_CODE, NO_SESSION,
// child_id=42 - and never a personal detail. A mobile number does not belong
// in it: the audit trail is read by more people than the row it describes.
type Event struct {
	Action   string
	CenterID *int
	Actor    string
	Detail   string
	ClientIP *string
}

// Record writes one event and never returns an error.
//
// A failed audit write must not take a request down with it - refusing a
// legitimate login because a log line could not be filed is a worse outcome
// than the missing line. It must not vanish either, so the failure is logged
// at warning level, where an operator sees it.
func (r *Recorder) Record(ctx context.Context, e Event) {
	// WithoutCancel because the interesting case is precisely the one where
	// the request is being torn down: a denial, a timeout, a client that hung
	// up mid-login.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), writeTimeout)
	defer cancel()

	actor := e.Actor
	if actor == "" {
		actor = "anonymous"
	}

	// pool.Exec, not a transaction of ours: an attempt record is not part of
	// whatever the request was doing.
	_, err := r.pool.Exec(ctx,
		`SELECT hbh.audit_attempt($1, $2, $3, $4, $5::inet)`,
		e.Action, e.CenterID, actor, e.Detail, e.ClientIP)
	if err != nil {
		r.log.WarnContext(ctx, "audit record was not written",
			"action", e.Action, "actor", actor, "detail", e.Detail, "err", err)
	}
}
