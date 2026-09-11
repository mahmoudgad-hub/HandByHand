package store

import (
	"context"
	"fmt"
	"time"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The centre-indexed reads.
//
// Same rows as the portal, same policies, different index: by day and by
// centre rather than by child. A receptionist opens a day, not a file - and
// building that from the child-scoped endpoints would mean one request per
// child and a merge in the browser, which breaks ordering, breaks paging, and
// cannot know about a child nobody asked for.
//
// Nothing here filters by centre or checks ownership. hbh.can_access_child()
// admits every child of the centre to a caller holding CHILD.VIEW_ALL and only
// their own to a guardian, so the SAME query serves both and the policy is the
// only thing that decides. That is why there is no separate "ops" endpoint: a
// second path would be a second place for the rule to live.
//
// Every row carries NAMES beside the identifiers. A day view returning
// therapist_id alone would need a lookup per row - the same defect the
// centre-indexed read exists to remove, in a smaller box.

// CenterTimeZone returns the caller's centre's zone, e.g. Africa/Cairo.
//
// It comes from the centre row, never from a constant: "today" for a screen in
// Cairo is not "today" in UTC, and which one is meant is a property of the
// centre, not of this code. A second centre in another country changes a row.
func (d *DB) CenterTimeZone(ctx context.Context, ident string) (string, error) {
	var tz string
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT time_zone FROM hbh.centers WHERE center_id = hbh.current_center_id()`).Scan(&tz)
	})
	if err != nil {
		return "", fmt.Errorf("centre time zone: %w", err)
	}
	return tz, nil
}

// DayWindow is a half-open instant range: from <= t < to.
//
// Half-open on purpose. A closed range double-counts an appointment that
// starts exactly at midnight, and a screen that shows the same row on two days
// is worse than one that shows it on neither.
type DayWindow struct {
	From time.Time
	To   time.Time
}

// OpsQuery is the shared filter for the day-indexed lists.
type OpsQuery struct {
	Window      DayWindow
	TherapistID *int
	RoomID      *int
	ServiceID   *int
	ChildID     *int
	Status      string
	Kind        string
	Limit       int
	Offset      int

	// MineOnly narrows a diary to the therapist the CALLER is, resolved in
	// the database from hbh.current_user_id() and never from the request.
	//
	// A separate field rather than the handler filling TherapistID, because
	// those two answer different questions. TherapistID is "show me this
	// therapist's day" - a filter reception picks, and one a therapist is
	// allowed to pick too: a clinician covering a colleague may read the
	// centre's diary, and the policies say so. MineOnly is "show me MY
	// day", and the only honest source for the word "my" is the session.
	//
	// It is not an authorisation boundary and does not pretend to be one -
	// RLS already decided which rows this caller may read at all. It decides
	// which of those rows a PERSONAL screen is about, which is why a
	// client-supplied therapist_id must not be able to answer it.
	MineOnly bool
}

// Appointments lists the centre's appointments in a window, earliest first.
//
// Earliest first, unlike the child-scoped list which is newest first. A day
// view is read down the page in the order it will happen; a child's history is
// read backwards from now. Same data, different question.
func (d *DB) CentreAppointments(ctx context.Context, ident string, q OpsQuery) ([]domain.Appointment, int, error) {
	out := []domain.Appointment{}
	total := 0

	// $7 is MineOnly. When false the clause disappears and every existing
	// caller - reception's /appointments above all - reads exactly what it
	// read before.
	//
	// When true, the therapist is looked up HERE, from the session identity,
	// so that the answer to "whose day is this" cannot arrive in a query
	// string. An account with no therapist row - or one whose profile has
	// been deactivated - makes the subquery NULL, and `therapist_id = NULL`
	// is UNKNOWN, so no row passes.
	//
	// That three-valued comparison is deliberate here and it is the reason
	// this is a subquery rather than a parameter the handler resolves. This
	// file's neighbours have been bitten by NULL comparisons failing OPEN
	// (see CLAUDE.md on verify_otp); this one fails CLOSED - an unmapped
	// account is shown an empty day, never the centre's. The dangerous
	// shape is the one that widens on NULL, and it is unreachable here.
	const where = `
		WHERE a.active_flg
		AND   a.starts_at >= $1 AND a.starts_at < $2
		AND   ($3::integer IS NULL OR a.therapist_id = $3::integer)
		AND   ($4::integer IS NULL OR a.room_id      = $4::integer)
		AND   ($5::text    IS NULL OR a.status       = $5::text)
		AND ($6::integer IS NULL OR a.service_id = $6::integer)
		AND   (NOT $7::boolean OR a.therapist_id = (
		        SELECT t.therapist_id FROM hbh.therapists t
		        WHERE  t.user_id = hbh.current_user_id() AND t.active_flg))`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.appointments a`+where,
			q.Window.From, q.Window.To, q.TherapistID, q.RoomID, nullif(q.Status), q.ServiceID,
			q.MineOnly).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT a.appointment_id, a.appointment_no, a.starts_at, a.ends_at, a.status, a.cancel_reason,
			       ch.child_id, ch.child_no, ch.full_name_ar,
			       r.room_id, r.name_ar,
			       ses.session_id, ses.status,
			       s.service_id, s.name_ar, s.kind_code, s.color_hex,
			       t.therapist_id, t.full_name_ar, t.title_ar
			FROM   hbh.appointments a
			JOIN      hbh.children   ch ON ch.child_id     = a.child_id
			LEFT JOIN hbh.rooms      r  ON r.room_id       = a.room_id
			-- At most one session per appointment: hbh.start_session
			-- refuses a second with HB022, so this join cannot fan out.
			LEFT JOIN hbh.therapy_sessions ses ON ses.appointment_id = a.appointment_id
			LEFT JOIN hbh.services   s  ON s.service_id    = a.service_id
			LEFT JOIN hbh.therapists t  ON t.therapist_id  = a.therapist_id`+where+`
			ORDER  BY a.starts_at, a.appointment_id
			LIMIT  $8 OFFSET $9`,
			q.Window.From, q.Window.To, q.TherapistID, q.RoomID, nullif(q.Status), q.ServiceID,
			q.MineOnly, q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var (
				a      domain.Appointment
				child  domain.ChildRef
				roomID *int
				room   *string
			)
			svc, th, err := scanRef(rows,
				&a.AppointmentID, &a.AppointmentNo, &a.StartsAt, &a.EndsAt, &a.Status, &a.CancelReason,
				&child.ChildID, &child.ChildNo, &child.FullNameAr,
				&roomID, &room,
				&a.SessionID, &a.SessionStatus)
			if err != nil {
				return err
			}
			a.Service, a.Therapist = svc, th
			a.Child = &child
			if roomID != nil {
				a.Room = &domain.RoomRef{RoomID: *roomID, NameAr: deref(room)}
			}
			out = append(out, a)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("appointments: %w", err)
	}
	return out, total, nil
}

// OpsSessions lists the centre's therapy sessions in a window.
func (d *DB) OpsSessions(ctx context.Context, ident string, q OpsQuery) ([]domain.Session, int, error) {
	out := []domain.Session{}
	total := 0

	const where = `
		WHERE ts.active_flg
		AND   ts.started_at >= $1 AND ts.started_at < $2
		AND   ($3::integer IS NULL OR ts.therapist_id = $3::integer)
		AND   ($4::text    IS NULL OR ts.status       = $4::text)
		AND ($5::integer IS NULL OR ts.room_id = $5::integer)`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.therapy_sessions ts`+where,
			q.Window.From, q.Window.To, q.TherapistID, nullif(q.Status), q.RoomID).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT ts.session_id, ts.appointment_id, ts.started_at, ts.ended_at, ts.status,
			       ch.child_id, ch.child_no, ch.full_name_ar,
			       r.room_id, r.name_ar,
			       s.service_id, s.name_ar, s.kind_code, s.color_hex,
			       t.therapist_id, t.full_name_ar, t.title_ar
			FROM   hbh.therapy_sessions ts
			JOIN      hbh.children   ch ON ch.child_id    = ts.child_id
			LEFT JOIN hbh.rooms      r  ON r.room_id      = ts.room_id
			LEFT JOIN hbh.services   s  ON s.service_id   = ts.service_id
			LEFT JOIN hbh.therapists t  ON t.therapist_id = ts.therapist_id`+where+`
			ORDER  BY ts.started_at, ts.session_id
			LIMIT  $6 OFFSET $7`,
			q.Window.From, q.Window.To, q.TherapistID, nullif(q.Status), q.RoomID, q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var (
				sess   domain.Session
				child  domain.ChildRef
				roomID *int
				room   *string
			)
			svc, th, err := scanRef(rows,
				&sess.SessionID, &sess.AppointmentID, &sess.StartedAt, &sess.EndedAt, &sess.Status,
				&child.ChildID, &child.ChildNo, &child.FullNameAr,
				&roomID, &room)
			if err != nil {
				return err
			}
			sess.Service, sess.Therapist = svc, th
			sess.Child = &child
			if roomID != nil {
				sess.Room = &domain.RoomRef{RoomID: *roomID, NameAr: deref(room)}
			}
			out = append(out, sess)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("sessions: %w", err)
	}
	return out, total, nil
}

// OpsReports lists the centre's progress reports, including drafts.
//
// A guardian asking the same endpoint still sees only published ones: the
// policy on hbh.progress_reports admits a draft to CHILD.VIEW_ALL and to
// nobody else. Status is returned so the screen can show which are still
// drafts, which is the point of the list for staff.
func (d *DB) OpsReports(ctx context.Context, ident string, q OpsQuery) ([]domain.OpsReport, int, error) {
	out := []domain.OpsReport{}
	total := 0

	const where = `
		WHERE r.active_flg
		AND   ($1::text    IS NULL OR r.status   = $1::text)
		AND   ($2::date    IS NULL OR r.period_end   >= $2::date)
		AND   ($3::date    IS NULL OR r.period_start <= $3::date)
		AND   ($4::integer IS NULL OR r.child_id = $4::integer)`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		from, to := datePtr(q.Window.From), datePtr(q.Window.To)
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.progress_reports r`+where,
			nullif(q.Status), from, to, q.ChildID).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT r.report_id, r.report_no, r.title_ar, r.period_start, r.period_end,
			       r.status, r.published_at,
			       ch.child_id, ch.child_no, ch.full_name_ar,
			       u.user_id, u.full_name_ar
			FROM   hbh.progress_reports r
			JOIN      hbh.children ch ON ch.child_id = r.child_id
			LEFT JOIN hbh.users    u  ON u.user_id   = r.published_by`+where+`
			ORDER  BY r.period_end DESC, r.report_id DESC
			LIMIT  $5 OFFSET $6`,
			nullif(q.Status), from, to, q.ChildID, q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var (
				r        domain.OpsReport
				child    domain.ChildRef
				authorID *int
				author   *string
			)
			if err := rows.Scan(&r.ReportID, &r.ReportNo, &r.TitleAr, &r.PeriodStart, &r.PeriodEnd,
				&r.Status, &r.PublishedAt,
				&child.ChildID, &child.ChildNo, &child.FullNameAr,
				&authorID, &author); err != nil {
				return err
			}
			r.Child = &child
			if authorID != nil {
				r.PublishedBy = &domain.PersonRef{UserID: *authorID, FullNameAr: deref(author)}
			}
			out = append(out, r)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("reports: %w", err)
	}
	return out, total, nil
}

// OpsInvoices lists the centre's invoices.
//
// Amounts are cast to text and travel as exact decimal strings (D-25). The
// currency comes from the invoice row and is never assumed.
func (d *DB) OpsInvoices(ctx context.Context, ident string, q OpsQuery) ([]domain.OpsInvoice, int, error) {
	out := []domain.OpsInvoice{}
	total := 0

	const where = `
		WHERE i.active_flg
		AND   ($1::text    IS NULL OR i.status     = $1::text)
		AND   ($2::date    IS NULL OR i.issue_date >= $2::date)
		AND   ($3::date    IS NULL OR i.issue_date <= $3::date)
		AND   ($4::integer IS NULL OR i.child_id   = $4::integer)`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		from, to := datePtr(q.Window.From), datePtr(q.Window.To)
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.invoices i`+where,
			nullif(q.Status), from, to, q.ChildID).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT i.invoice_id, i.invoice_no, i.issue_date, i.due_date, i.currency_code,
			       i.total_amt::text, i.paid_amt::text, i.status,
			       ch.child_id, ch.child_no, ch.full_name_ar
			FROM   hbh.invoices i
			JOIN   hbh.children ch ON ch.child_id = i.child_id`+where+`
			ORDER  BY i.issue_date DESC, i.invoice_id DESC
			LIMIT  $5 OFFSET $6`,
			nullif(q.Status), from, to, q.ChildID, q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var (
				inv   domain.OpsInvoice
				child domain.ChildRef
			)
			if err := rows.Scan(&inv.InvoiceID, &inv.InvoiceNo, &inv.IssueDate, &inv.DueDate,
				&inv.CurrencyCode, &inv.TotalAmt, &inv.PaidAmt, &inv.Status,
				&child.ChildID, &child.ChildNo, &child.FullNameAr); err != nil {
				return err
			}
			inv.Child = &child
			out = append(out, inv)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("invoices: %w", err)
	}
	return out, total, nil
}

// OpsRequests lists what families have asked the centre for.
//
// The other side of a door the portal already writes through: a guardian opens
// a request in the portal, and reception reads and decides it here.
func (d *DB) OpsRequests(ctx context.Context, ident string, q OpsQuery) ([]domain.OpsRequest, int, error) {
	out := []domain.OpsRequest{}
	total := 0

	const where = `
		WHERE pr.active_flg
		AND   ($1::text IS NULL OR pr.status    = $1::text)
		AND   ($2::text IS NULL OR pr.kind_code = $2::text)`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.parent_requests pr`+where,
			nullif(q.Status), nullif(q.Kind)).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT pr.request_id, pr.request_no, pr.kind_code, pr.status, pr.body_ar,
			       pr.preferred_at, pr.appointment_id, pr.created_at, pr.decided_at,
			       pr.decision_note_ar,
			       ch.child_id, ch.child_no, ch.full_name_ar,
			       g.guardian_id, g.full_name_ar, g.mobile, g.user_id
			FROM   hbh.parent_requests pr
			JOIN      hbh.children  ch ON ch.child_id    = pr.child_id
			LEFT JOIN hbh.guardians g  ON g.guardian_id  = pr.guardian_id`+where+`
			ORDER  BY pr.created_at DESC, pr.request_id DESC
			LIMIT  $3 OFFSET $4`,
			nullif(q.Status), nullif(q.Kind), q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			var (
				r          domain.OpsRequest
				child      domain.ChildRef
				body       *string
				decision   *string
				guardianID *int
				guardian   *string
				mobile     *string
				userID     *int
			)
			if err := rows.Scan(&r.RequestID, &r.RequestNo, &r.KindCode, &r.Status, &body,
				&r.PreferredAt, &r.AppointmentID, &r.CreatedAt, &r.DecidedAt, &decision,
				&child.ChildID, &child.ChildNo, &child.FullNameAr,
				&guardianID, &guardian, &mobile, &userID); err != nil {
				return err
			}
			r.BodyAr, r.DecisionNoteAr = deref(body), deref(decision)
			r.Child = &child
			// Keyed on guardian_id, never on user_id. A guardian without an
			// account - a paper form, a converted enrolment - is still the
			// person who asked, and this row used to arrive with no guardian
			// at all in exactly that case.
			if guardianID != nil {
				r.Guardian = &domain.GuardianRef{
					GuardianID: *guardianID, FullNameAr: deref(guardian),
					Mobile: deref(mobile), UserID: userID,
				}
			}
			out = append(out, r)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("requests: %w", err)
	}
	return out, total, nil
}

// datePtr turns a zero time into SQL NULL - "no bound on this side".
func datePtr(t time.Time) *time.Time {
	if t.IsZero() {
		return nil
	}
	return &t
}

// HasPermission asks the DATABASE whether this caller holds a permission.
//
// Every other write in this service is authorised by a row level security
// policy, so no handler checks anything - the engine refuses and the handler
// only maps the refusal. An upload has no row and no policy: it writes a file
// to a disk, where RLS cannot reach.
//
// So the check exists, but the RULE does not move. hbh.has_permission is the
// same function the policies call, evaluated under the same identity, and this
// asks it rather than re-deciding in Go what SITE.EDIT means. A second
// definition here is how the two drift and the weaker one starts deciding.
func (d *DB) HasPermission(ctx context.Context, ident, code string) (bool, error) {
	var ok bool
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.has_permission($1)`, code).Scan(&ok)
	})
	if err != nil {
		return false, fmt.Errorf("has_permission: %w", err)
	}
	return ok, nil
}
