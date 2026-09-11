package store

import (
	"context"
	"encoding/json"
	"time"

	"github.com/jackc/pgx/v5"
)

// The service's own request log, and the three views that read it.
//
// It is NOT the audit log and the two must not be confused. hbh.audit_log
// records who touched a family's data and is kept for compliance; this records
// that a request took 40ms and returned 200, and is purged after
// REQUEST_LOG_RETENTION_DAYS. Mixing them would mean either throwing away an
// audit trail or keeping a performance log forever.

// RequestRecord is one finished request.
//
// Route is the TEMPLATE - /api/v1/children/{child_id} - and Path is what was
// actually called. Grouping by Path gives one row per child and answers no
// question anybody asked; grouping by Route says which endpoint is slow.
//
// Identity is deliberately absent. hbh.log_request reads it from the
// transaction, so an anonymous request is filed with a NULL user rather than
// with whatever the caller claimed to be.
type RequestRecord struct {
	Method     string
	Route      string
	Path       string
	StatusCode int
	DurationMS int
	RequestID  string
	ClientIP   *string
	UserAgent  string

	// ErrorCode is REQUIRED for any status of 400 or more - the schema
	// refuses the row otherwise (23514). It is the HB0xx class when the
	// refusal came from the database, and this service's own code when it did
	// not.
	ErrorCode    string
	ErrorMessage string
	Detail       json.RawMessage
}

// LogRequest files one record and NEVER returns an error.
//
// That is not sloppiness, it is the contract: a request that WORKED must not
// be reported as having failed because a log line could not be written. The
// database function makes the same promise on its side - it swallows its own
// failures into a warning - and this half keeps the promise for everything
// that can go wrong before the call arrives: a closed pool, a cancelled
// context, a database that has gone away.
//
// The context is detached from the request for the same reason the audit
// writer detaches: the interesting record is often the one for a request that
// was being torn down.
func (d *DB) LogRequest(ctx context.Context, ident string, rec RequestRecord) {
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
	defer cancel()

	_ = d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			SELECT hbh.log_request(
			         p_method        => $1,
			         p_route         => $2,
			         p_status_code   => $3::smallint,
			         p_duration_ms   => $4,
			         p_path          => nullif($5, ''),
			         p_request_id    => nullif($6, ''),
			         p_client_ip     => $7::inet,
			         p_user_agent    => nullif($8, ''),
			         p_error_code    => nullif($9, ''),
			         p_error_message => nullif($10, ''),
			         p_detail        => $11::jsonb)`,
			rec.Method, rec.Route, rec.StatusCode, rec.DurationMS,
			rec.Path, rec.RequestID, rec.ClientIP, rec.UserAgent,
			rec.ErrorCode, rec.ErrorMessage, nullJSON(rec.Detail))
		return err
	})
}

func nullJSON(raw json.RawMessage) any {
	if len(raw) == 0 {
		return nil
	}
	return string(raw)
}

// APIHealth is one row per route and method: calls, percentiles, error rate.
func (d *DB) APIHealth(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `hbh.v_api_health`, `calls DESC, route, method`)
}

// RecentErrors is the last failures in full.
//
// The view carries error_message and detail, which is exactly why rule 3 of
// the logging contract exists: nothing personal goes in either. A child's name
// in a stack trace would put clinical data on an operations screen that a
// centre administrator opens without a second thought.
func (d *DB) RecentErrors(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `hbh.v_recent_errors`, `occurred_at DESC, log_id DESC`)
}

// UserActivity is who used the service and when they were last seen.
func (d *DB) UserActivity(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.viewRows(ctx, ident, `hbh.v_user_activity`, `last_seen_at DESC NULLS LAST, user_id`)
}
