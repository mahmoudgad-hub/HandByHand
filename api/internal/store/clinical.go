package store

import (
	"context"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The clinical reads: appointments, sessions, plans, reports, notes.
//
// As in portal.go, not one query here filters by centre or checks ownership.
// Two policies in particular do work that would be very easy to get wrong up
// here, and are worth naming because the API must not duplicate them:
//
//   - session_notes admits a guardian only to a note that is visibility
//     'PARENT', is not a draft, and has an approver. A clinical note is
//     written for the record first; reaching the family is a separate,
//     deliberate act by somebody holding NOTE.PUBLISH.
//   - progress_reports admits a guardian only to status 'PUBLISHED'.
//
// Both are enforced underneath these queries. If either were re-stated here as
// a WHERE clause, there would be two copies of the rule, and the day they
// disagreed the weaker one would decide.

// childScoped runs fn in one read transaction, but only after establishing
// that the caller may see this child at all.
//
// Both halves happen in the SAME transaction on purpose. Two transactions
// would read two different snapshots, so a child's access could be revoked
// between the check and the query and the data would still be handed over.
//
// The check itself is not a permission test written in Go: it is an ordinary
// SELECT that the policy on hbh.children either answers or does not. It exists
// so that a nested route refuses with 404 - and records the attempt - instead
// of returning an empty list, which would quietly tell a caller walking
// identifiers that they had guessed a real child with no data.
func (d *DB) childScoped(ctx context.Context, ident string, childID int, fn func(context.Context, pgx.Tx) error) error {
	return d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		var found int
		err := tx.QueryRow(ctx, `SELECT 1 FROM hbh.children WHERE child_id = $1`, childID).Scan(&found)
		if err != nil {
			return noRows(err)
		}
		return fn(ctx, tx)
	})
}

// selectRef is the shared projection for the three flattened references. Kept
// in one place so a list and a detail can never name the child's therapist
// differently.
const selectRef = `
	s.service_id, s.name_ar, s.kind_code, s.color_hex,
	t.therapist_id, t.full_name_ar, t.title_ar`

// scanRef reads the service and therapist columns.
//
// A row can come back with them null: the policies on services and therapists
// admit only active rows, so an appointment kept for a service that was later
// retired loses its name here. That is a display consequence of an access
// rule, and the honest place to fix it is the policy, not a second query in Go
// that would read around it.
func scanRef(rows pgx.Rows, dst ...any) (*domain.ServiceRef, *domain.TherapistRef, error) {
	var (
		svcID    *int
		svcName  *string
		svcKind  *string
		svcColor *string
		thID     *int
		thName   *string
		thTitle  *string
	)
	args := append(dst, &svcID, &svcName, &svcKind, &svcColor, &thID, &thName, &thTitle)
	if err := rows.Scan(args...); err != nil {
		return nil, nil, err
	}

	var svc *domain.ServiceRef
	if svcID != nil {
		svc = &domain.ServiceRef{ServiceID: *svcID, NameAr: deref(svcName), KindCode: deref(svcKind), ColorHex: deref(svcColor)}
	}
	var th *domain.TherapistRef
	if thID != nil {
		th = &domain.TherapistRef{TherapistID: *thID, FullNameAr: deref(thName), TitleAr: deref(thTitle)}
	}
	return svc, th, nil
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// Window bounds a list of appointments or sessions. A zero field means no
// bound on that side.
type Window struct {
	From  *string // inclusive, RFC 3339
	To    *string // exclusive, RFC 3339
	Limit int
}

// Appointments lists a child's appointments, newest first.
func (d *DB) Appointments(ctx context.Context, ident string, childID int, w Window) ([]domain.Appointment, error) {
	var out []domain.Appointment
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		out, err = appointmentsTx(ctx, tx, childID, w)
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

func appointmentsTx(ctx context.Context, tx pgx.Tx, childID int, w Window) ([]domain.Appointment, error) {
	out := []domain.Appointment{}
	rows, err := tx.Query(ctx, `
			SELECT a.appointment_id, a.appointment_no, a.starts_at, a.ends_at, a.status, a.cancel_reason,
			       r.room_id, r.name_ar,`+selectRef+`
			FROM   hbh.appointments a
			LEFT JOIN hbh.services   s ON s.service_id   = a.service_id
			LEFT JOIN hbh.therapists t ON t.therapist_id = a.therapist_id
			LEFT JOIN hbh.rooms      r ON r.room_id      = a.room_id
			WHERE  a.child_id = $1
			AND    a.active_flg
			AND    ($2::timestamptz IS NULL OR a.starts_at >= $2::timestamptz)
			AND    ($3::timestamptz IS NULL OR a.starts_at <  $3::timestamptz)
			ORDER  BY a.starts_at DESC, a.appointment_id DESC
			LIMIT  $4`, childID, w.From, w.To, w.Limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var (
			a      domain.Appointment
			roomID *int
			room   *string
		)
		svc, th, err := scanRef(rows,
			&a.AppointmentID, &a.AppointmentNo, &a.StartsAt, &a.EndsAt, &a.Status, &a.CancelReason,
			&roomID, &room)
		if err != nil {
			return nil, err
		}
		a.Service, a.Therapist = svc, th
		if roomID != nil {
			a.Room = &domain.RoomRef{RoomID: *roomID, NameAr: deref(room)}
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// Sessions lists a child's therapy sessions, newest first.
func (d *DB) Sessions(ctx context.Context, ident string, childID int, w Window) ([]domain.Session, error) {
	var out []domain.Session
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		out, err = sessionsTx(ctx, tx, childID, w)
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// sessionsTx is the query itself, without a transaction of its own.
//
// It exists so the child profile can ask for six things inside ONE
// transaction instead of six. The split is deliberate: if the aggregate
// carried its own copy of this SQL, the two would drift the first time
// somebody changed one of them, and the endpoint a family actually uses
// would be the one left behind.
func sessionsTx(ctx context.Context, tx pgx.Tx, childID int, w Window) ([]domain.Session, error) {
	out := []domain.Session{}
	rows, err := tx.Query(ctx, `
			SELECT ts.session_id, ts.appointment_id, ts.started_at, ts.ended_at, ts.status,`+selectRef+`
			FROM   hbh.therapy_sessions ts
			LEFT JOIN hbh.services   s ON s.service_id   = ts.service_id
			LEFT JOIN hbh.therapists t ON t.therapist_id = ts.therapist_id
			WHERE  ts.child_id = $1
			AND    ts.active_flg
			AND    ($2::timestamptz IS NULL OR ts.started_at >= $2::timestamptz)
			AND    ($3::timestamptz IS NULL OR ts.started_at <  $3::timestamptz)
			ORDER  BY ts.started_at DESC, ts.session_id DESC
			LIMIT  $4`, childID, w.From, w.To, w.Limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var s domain.Session
		svc, th, err := scanRef(rows,
			&s.SessionID, &s.AppointmentID, &s.StartedAt, &s.EndedAt, &s.Status)
		if err != nil {
			return nil, err
		}
		s.Service, s.Therapist = svc, th
		out = append(out, s)
	}
	return out, rows.Err()
}

// Plans lists a child's treatment plans with their goals attached.
//
// Two queries, one transaction. Splitting them across transactions could
// return a plan from one snapshot and goals from another - a plan that appears
// to have lost its goals, which reads as data loss and is not.
func (d *DB) Plans(ctx context.Context, ident string, childID int) ([]domain.Plan, error) {
	out := []domain.Plan{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT p.plan_id, p.title_ar, p.start_date, p.end_date, p.status,`+selectRef+`
			FROM   hbh.treatment_plans p
			LEFT JOIN hbh.services   s ON s.service_id   = p.service_id
			LEFT JOIN hbh.therapists t ON t.therapist_id = p.therapist_id
			WHERE  p.child_id = $1
			ORDER  BY p.start_date DESC, p.plan_id DESC`, childID)
		if err != nil {
			return err
		}
		byID := make(map[int]int, 8)
		for rows.Next() {
			var p domain.Plan
			svc, th, err := scanRef(rows, &p.PlanID, &p.TitleAr, &p.StartDate, &p.EndDate, &p.Status)
			if err != nil {
				rows.Close()
				return err
			}
			p.Service, p.Therapist = svc, th
			p.Goals = []domain.Goal{}
			byID[p.PlanID] = len(out)
			out = append(out, p)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return err
		}
		if len(out) == 0 {
			return nil
		}

		// The percentages are cast to float8 in SQL rather than scanned as
		// numeric. They are progress readings for a chart, not money; nothing
		// in this project sums them or compares them for equality, which are
		// the two things that would make the exactness of numeric matter.
		grows, err := tx.Query(ctx, `
			SELECT goal_id, plan_id, title_ar, baseline_pct::float8, target_pct::float8,
			       status, sort_order, latest_pct::float8, latest_measured_on, measurement_cnt
			FROM   hbh.v_goal_progress
			WHERE  child_id = $1
			ORDER  BY plan_id, sort_order, goal_id`, childID)
		if err != nil {
			return err
		}
		defer grows.Close()

		for grows.Next() {
			var (
				g      domain.Goal
				planID int
			)
			if err := grows.Scan(&g.GoalID, &planID, &g.TitleAr, &g.BaselinePct, &g.TargetPct,
				&g.Status, &g.SortOrder, &g.LatestPct, &g.LatestMeasuredOn, &g.MeasurementCount); err != nil {
				return err
			}
			// A goal whose plan the policy withheld is dropped rather than
			// attached to nothing. The view and the plan query are filtered by
			// the same policies, so this should not happen - and if it ever
			// does, silently inventing a plan for it would be worse.
			if i, ok := byID[planID]; ok {
				out[i].Goals = append(out[i].Goals, g)
			}
		}
		return grows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// Reports lists a child's progress reports. For a guardian the policy admits
// only published ones, so a draft never appears here at all.
func (d *DB) Reports(ctx context.Context, ident string, childID int) ([]domain.ReportSummary, error) {
	var out []domain.ReportSummary
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		out, err = reportsTx(ctx, tx, childID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

func reportsTx(ctx context.Context, tx pgx.Tx, childID int) ([]domain.ReportSummary, error) {
	out := []domain.ReportSummary{}
	rows, err := tx.Query(ctx, `
		SELECT report_id, report_no, title_ar, period_start, period_end, status, published_at, plan_id
		FROM   hbh.progress_reports
		WHERE  child_id = $1
		ORDER  BY period_end DESC, report_id DESC`, childID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var r domain.ReportSummary
		if err := rows.Scan(&r.ReportID, &r.ReportNo, &r.TitleAr, &r.PeriodStart, &r.PeriodEnd,
			&r.Status, &r.PublishedAt, &r.PlanID); err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// Report returns one progress report, or ErrNotFound.
//
// It is addressed by report id alone, with no child in the path, and needs no
// ownership check for the same reason the child endpoint needs none: the
// policy on progress_reports already requires can_access_child AND, for a
// guardian, status 'PUBLISHED'. A draft belonging to the caller's own child
// answers exactly like a report that does not exist.
func (d *DB) Report(ctx context.Context, ident string, reportID int) (domain.Report, int, error) {
	var (
		r       domain.Report
		childID int
	)
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT report_id, report_no, title_ar, period_start, period_end, status, published_at,
			       plan_id, summary_ar, goals_snapshot, child_id
			FROM   hbh.progress_reports
			WHERE  report_id = $1`, reportID).
			Scan(&r.ReportID, &r.ReportNo, &r.TitleAr, &r.PeriodStart, &r.PeriodEnd, &r.Status,
				&r.PublishedAt, &r.PlanID, &r.SummaryAr, &r.GoalsSnapshot, &childID)
	})
	if err != nil {
		return domain.Report{}, 0, noRows(err)
	}
	return r, childID, nil
}

// Notes lists the session notes a caller may read for a child.
//
// For a guardian that is: marked for the parent, not a draft, and approved.
// Nothing in this query says so.
func (d *DB) Notes(ctx context.Context, ident string, childID int) ([]domain.Note, error) {
	out := []domain.Note{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT n.note_id, n.session_id, n.body_ar, n.visibility,
			       n.created_at, n.approved_at, u.full_name_ar
			FROM   hbh.session_notes n
			LEFT   JOIN hbh.users u ON u.user_id = n.author_user_id
			WHERE  n.child_id = $1
			ORDER  BY n.created_at DESC, n.note_id DESC`, childID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var n domain.Note
			if err := rows.Scan(&n.NoteID, &n.SessionID, &n.BodyAr, &n.Visibility,
				&n.CreatedAt, &n.ApprovedAt, &n.AuthorAr); err != nil {
				return err
			}
			out = append(out, n)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}
