package store

import (
	"context"
	"fmt"
	"time"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The home programme, and the first writes this service performs.
//
// Both writes go through a PL/pgSQL function - hbh.log_activity and
// hbh.submit_request - and neither of them is a thin pass-through by accident.
// Each function re-checks the caller's right to act from inside the database:
// log_activity calls can_access_child, and submit_request requires the caller
// to be an actual guardian of that child, which is strictly narrower than
// being allowed to read them. Staff can read a child; they cannot submit a
// request on a family's behalf.
//
// So the API sends the request and reports the answer. It does not decide.

// Activities lists a child's assigned home exercises with recent adherence.
func (d *DB) Activities(ctx context.Context, ident string, childID int) ([]domain.Activity, error) {
	var out []domain.Activity
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		out, err = activitiesTx(ctx, tx, childID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

func activitiesTx(ctx context.Context, tx pgx.Tx, childID int) ([]domain.Activity, error) {
	out := []domain.Activity{}
	rows, err := tx.Query(ctx, `
			SELECT ca.child_activity_id, ca.activity_id, al.title_ar, al.how_to_ar,
			       ca.instructions_ar, ca.times_per_week, ca.minutes_each,
			       ca.start_date, ca.end_date,
			       coalesce(v.done_last_7, 0), v.adherence_pct::float8, v.last_done_on
			FROM   hbh.child_activities ca
			JOIN   hbh.activity_library al ON al.activity_id = ca.activity_id
			LEFT   JOIN hbh.v_activity_adherence v ON v.child_activity_id = ca.child_activity_id
			WHERE  ca.child_id = $1
		ORDER  BY ca.start_date DESC, ca.child_activity_id DESC`, childID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var (
			a       domain.Activity
			howTo   *string
			instr   *string
			perWeek *int
			minutes *int
		)
		if err := rows.Scan(&a.ChildActivityID, &a.ActivityID, &a.TitleAr, &howTo,
			&instr, &perWeek, &minutes, &a.StartDate, &a.EndDate,
			&a.DoneLast7, &a.AdherencePct, &a.LastDoneOn); err != nil {
			return nil, err
		}
		a.HowToAr, a.InstructionsAr = deref(howTo), deref(instr)
		if perWeek != nil {
			a.TimesPerWeek = *perWeek
		}
		if minutes != nil {
			a.MinutesEach = *minutes
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// ActivityLog lists what the family reported, newest day first.
func (d *DB) ActivityLog(ctx context.Context, ident string, childID int, limit int) ([]domain.ActivityLogEntry, error) {
	out := []domain.ActivityLogEntry{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT log_id, child_activity_id, log_date, done_flg, parent_note_ar
			FROM   hbh.activity_log
			WHERE  child_id = $1
			ORDER  BY log_date DESC, log_id DESC
			LIMIT  $2`, childID, limit)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var (
				e    domain.ActivityLogEntry
				note *string
			)
			if err := rows.Scan(&e.LogID, &e.ChildActivityID, &e.LogDate, &e.Done, &note); err != nil {
				return err
			}
			e.ParentNoteAr = deref(note)
			out = append(out, e)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// LogActivity records one day against one assigned exercise.
//
// A repeated day comes back as HB042 rather than quietly overwriting the
// earlier entry. That is the database's decision and the right one: a family
// that ticks the same day twice has almost certainly mis-tapped, and silently
// replacing what they said the first time would lose a real answer.
func (d *DB) LogActivity(ctx context.Context, ident string, childActivityID int, day *time.Time, done bool, note string) (int64, error) {
	var logID int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.log_activity($1, coalesce($2::date, current_date), $3, nullif($4, ''))`,
			childActivityID, day, done, note).Scan(&logID)
	})
	if err != nil {
		return 0, err
	}
	return logID, nil
}

// Requests lists what the family has asked the centre for.
func (d *DB) Requests(ctx context.Context, ident string, childID int) ([]domain.Request, error) {
	out := []domain.Request{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT request_id, request_no, kind_code, status, body_ar, preferred_at,
			       appointment_id, created_at, decided_at, decision_note_ar
			FROM   hbh.parent_requests
			WHERE  child_id = $1
			ORDER  BY created_at DESC, request_id DESC`, childID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var (
				r        domain.Request
				body     *string
				decision *string
			)
			if err := rows.Scan(&r.RequestID, &r.RequestNo, &r.KindCode, &r.Status, &body,
				&r.PreferredAt, &r.AppointmentID, &r.CreatedAt, &r.DecidedAt, &decision); err != nil {
				return err
			}
			r.BodyAr, r.DecisionNoteAr = deref(body), deref(decision)
			out = append(out, r)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// SubmitRequest opens a request on behalf of the calling guardian.
//
// The guardian is derived inside hbh.submit_request from the request identity,
// never taken from the caller. A client that could name the guardian could
// file a request as another family.
func (d *DB) SubmitRequest(ctx context.Context, ident string, childID int, in domain.NewRequest) (int, error) {
	var requestID int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.submit_request($1, $2, $3, nullif($4, ''), $5)`,
			childID, in.KindCode, in.AppointmentID, in.BodyAr, in.PreferredAt).Scan(&requestID)
	})
	if err != nil {
		return 0, err
	}
	return requestID, nil
}

// RequestKinds returns the request kinds this centre accepts.
//
// They are lookup rows, not a Go constant. A centre that stops accepting
// callback requests deactivates a row; nothing here is rebuilt.
func (d *DB) RequestKinds(ctx context.Context, ident string) ([]string, error) {
	out := []string{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT lv.code
			FROM   hbh.lookup_values lv
			JOIN   hbh.lookup_types lt ON lt.lookup_type_id = lv.lookup_type_id
			WHERE  lt.code = 'REQUEST_KIND'
			ORDER  BY lv.sort_order, lv.code`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var code string
			if err := rows.Scan(&code); err != nil {
				return err
			}
			out = append(out, code)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("request kinds: %w", err)
	}
	return out, nil
}
