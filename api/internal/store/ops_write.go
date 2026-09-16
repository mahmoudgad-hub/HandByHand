package store

import (
	"context"
	"fmt"
	"time"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The operations app's writes.
//
// Every one is a call into a PL/pgSQL function that the database acceptance
// suites already accepted. Not one re-implements a rule: double booking, legal
// status transitions, who may close a session, whether an invoice may take a
// payment - all of it is decided underneath these calls, and a copy up here
// would be a second version to disagree with the first.
//
// TWO THINGS THE CLIENT NEVER SENDS, both for the reason behind D-3:
//
//   - center_id, which is always hbh.current_center_id().
//   - branch_id, which is derived from the ROOM being booked. A client that
//     could name the branch could book a child into a building they do not
//     attend.

// NewAppointment is a booking request. The centre and the branch are absent
// deliberately - see above.
type NewAppointment struct {
	ChildID     int `json:"child_id"`
	TherapistID int `json:"therapist_id"`

	// RoomID is a POINTER because "no room" is now a real answer and not a
	// missing field. An online consultation has none, and
	// ck_appointments_room_mode makes that exact: an IN_PERSON appointment
	// has a room and any other mode has none. As a plain int, absent and
	// zero were the same value, and zero would have gone to the schema as a
	// room that does not exist.
	RoomID    *int      `json:"room_id"`
	ServiceID int       `json:"service_id"`
	StartsAt  time.Time `json:"starts_at"`
	EndsAt    time.Time `json:"ends_at"`
	NoteAr    string    `json:"note_ar"`

	// DeliveryMode is IN_PERSON, ONLINE or EXTERNAL. Empty means IN_PERSON,
	// which is what every caller written before this field meant - and the
	// default is applied HERE rather than by leaving the argument off, so
	// that the value sent to the schema is the value this struct says.
	DeliveryMode string `json:"delivery_mode"`
}

// Mode is the delivery mode to send, with the default made explicit.
//
// A client that omits the field gets IN_PERSON. That is not a guess: it is
// the same default hbh.book_appointment carries, and the console booked
// nothing else for as long as it existed.
func (n NewAppointment) Mode() string {
	if n.DeliveryMode == "" {
		return "IN_PERSON"
	}
	return n.DeliveryMode
}

// ValidateSlot asks whether a booking would be accepted, without making one.
//
// This is the call that decides whether the booking screen is usable. With it
// the receptionist learns the therapist is busy WHILE choosing; without it she
// fills the whole form and is refused at the end. Same rule, same function -
// only the moment differs, and the moment is the entire difference between a
// screen people use and one they work around.
func (d *DB) ValidateSlot(ctx context.Context, ident string, in NewAppointment, excludeID *int) (domain.SlotCheck, error) {
	var c domain.SlotCheck
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT ok, reason FROM hbh.validate_slot(
				hbh.current_center_id(), $1, $2, $3, $4, $5, $6, $7, $8)`,
			in.ChildID, in.TherapistID, in.RoomID, in.ServiceID,
			in.StartsAt, in.EndsAt, excludeID, in.Mode()).Scan(&c.OK, &c.Reason)
	})
	if err != nil {
		return domain.SlotCheck{}, fmt.Errorf("validate_slot: %w", err)
	}
	return c, nil
}

// BookAppointment books a slot and returns its identifier.
//
// The three exclusion constraints on hbh.appointments - therapist, room, child
// - are what actually prevent a double booking, so two receptionists racing
// for the same slot end with one appointment and one refusal instead of two
// appointments. Nothing here locks anything: see D-13.
func (d *DB) BookAppointment(ctx context.Context, ident string, in NewAppointment) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// The branch still comes from the room and from nowhere else - a
		// client that could name it could book a child into a building they
		// do not attend. An online consultation has no room, so the
		// subquery matches nothing and the branch is NULL, which is what
		// the column allows and what the fact is: a video call happens at
		// no branch. Inventing one - the centre's first, the therapist's -
		// would put a consultation on a building's day sheet.
		return tx.QueryRow(ctx, `
			SELECT hbh.book_appointment(
				hbh.current_center_id(),
				(SELECT branch_id FROM hbh.rooms WHERE room_id = $3),
				$1, $2, $3, $4, $5, $6, nullif($7, ''), $8)`,
			in.ChildID, in.TherapistID, in.RoomID, in.ServiceID,
			in.StartsAt, in.EndsAt, in.NoteAr, in.Mode()).Scan(&id)
	})
	return id, err
}

// SetAppointmentStatus moves an appointment along its state machine.
//
// hbh.trg_appointment_status refuses an illegal transition with HB020 -
// including a status to itself, which is not a transition. A cancellation with
// no reason is refused by a CHECK, and the reason is passed through rather
// than defaulted: inventing the word "cancelled" as the reason would satisfy
// the constraint and record nothing.
func (d *DB) SetAppointmentStatus(ctx context.Context, ident string, id int, status, reason string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE hbh.appointments
			   SET status = $2, cancel_reason = nullif($3, '')
			 WHERE appointment_id = $1`, id, status, reason)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// StartSession opens the session for a checked-in appointment.
func (d *DB) StartSession(ctx context.Context, ident string, appointmentID int) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.start_session($1)`, appointmentID).Scan(&id)
	})
	return id, err
}

// CloseSession ends a session as COMPLETED or ABORTED.
//
// hbh.can_close_session decides who may: the assigned therapist, or staff
// holding SESSION.COMPLETE. A therapist may not close another therapist's
// session - a real defect found and fixed during phase 3.
func (d *DB) CloseSession(ctx context.Context, ident string, sessionID int, status, reason string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.close_session($1, $2, nullif($3, ''))`,
			sessionID, status, reason)
		return err
	})
}

// WriteSessionNote records a clinical note against a session.
//
// The note is born INTERNAL. Reaching the family is a separate, deliberate act
// through hbh.publish_session_note by somebody holding NOTE.PUBLISH. This call
// is only the first rung of that ladder.
func (d *DB) WriteSessionNote(ctx context.Context, ident string, sessionID int, body string) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.write_session_note($1, $2)`, sessionID, body).Scan(&id)
	})
	return id, err
}

// GrantGuardianConsent records one consent for a guardian, optionally about
// one child, and returns its identifier.
//
// It exists because the schema REQUIRES a consent that nothing could record.
// trg_live_flag_needs_consent (0015) refuses to raise can_view_live_flg
// without a LIVE_VIEW consent on file - correctly, since watching a child
// inside a therapy session is the most exposing thing this system does - and
// until now the only way to satisfy that rule was to write to the database by
// hand. A control nobody can operate through the product is a control that
// gets bypassed at the console instead.
//
// Who may record one is decided inside hbh.grant_consent (GUARDIAN.MANAGE, or
// the guardian acting for themselves), not here.
func (d *DB) GrantGuardianConsent(ctx context.Context, ident string, guardianID int,
	consentType string, childID *int, textVersion, noteAr string) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.grant_consent($1, $2, $3, coalesce(nullif($4, ''), 'v1'), nullif($5, ''))`,
			guardianID, consentType, childID, textVersion, noteAr).Scan(&id)
	})
	return id, err
}

// WithdrawGuardianConsent takes a consent back. The database drops any
// permission that leaned on it in the same statement - a withdrawal that left
// the live-view flag standing would be a withdrawal in name only.
func (d *DB) WithdrawGuardianConsent(ctx context.Context, ident string, guardianID int,
	consentType string, childID *int, noteAr string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`SELECT hbh.withdraw_consent($1, $2, $3, nullif($4, ''))`,
			guardianID, consentType, childID, noteAr)
		return err
	})
}

// PublishSessionNote is the second rung of the ladder WriteSessionNote starts:
// it moves one note from INTERNAL to PARENT and stamps who approved it.
//
// Until this existed the ladder had no top. The function, the NOTE.PUBLISH
// permission and the family's read endpoint were all in place, and nothing
// called hbh.publish_session_note - so a clinician could write a note meant
// for a family and had no way on earth to send it. The screen even told them
// it would reach the family "by a separate action" that did not exist.
//
// Everything that decides whether this is allowed stays in PL/pgSQL: the
// function checks NOTE.PUBLISH itself and records the disclosure as an
// attempt-class audit row, which survives a rollback because a clinical note
// reaching a family is not something the trail may lose.
func (d *DB) PublishSessionNote(ctx context.Context, ident string, noteID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.publish_session_note($1)`, noteID)
		return err
	})
}

// PublishReport publishes a progress report to the family.
//
// It freezes a goal snapshot as it goes, so a document a parent has read
// cannot be silently rewritten by a later measurement (D-16).
func (d *DB) PublishReport(ctx context.Context, ident string, reportID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.publish_report($1)`, reportID)
		return err
	})
}

// NewReport is what a caller may decide about a report they are opening.
//
// What is NOT here is the point of the type: no centre, no branch, no
// number, no author and no status. Every one of those is derived by
// hbh.create_report from the child's row and the session identity, so a
// client cannot write a report into another tenant, number it itself, or
// open one that is already published.
type NewReport struct {
	ChildID     int     `json:"child_id"`
	TitleAr     string  `json:"title_ar"`
	PeriodStart string  `json:"period_start"`
	PeriodEnd   string  `json:"period_end"`
	PlanID      *int    `json:"plan_id,omitempty"`
	SummaryAr   *string `json:"summary_ar,omitempty"`
}

// ReportEdit carries only the fields a draft may change. A nil field is
// "leave it alone", so the editor can save one box without resending the
// whole report - and cannot blank a field by omitting it.
//
// ExpectedVersion is the version the editor opened - the "version" it
// read. It is a pointer so that leaving it out reaches the function as NULL
// and is refused there (HB029), rather than being defaulted here to a zero
// time that would read as "some other version" (migration 0141, #14).
type ReportEdit struct {
	ExpectedVersion *time.Time `json:"expected_version"`
	TitleAr         *string    `json:"title_ar,omitempty"`
	SummaryAr       *string    `json:"summary_ar,omitempty"`
	PeriodStart     *string    `json:"period_start,omitempty"`
	PeriodEnd       *string    `json:"period_end,omitempty"`
	PlanID          *int       `json:"plan_id,omitempty"`
}

// CreateReport opens a DRAFT report and returns its id.
//
// The permission, the child-access rule and every derived field live in
// hbh.create_report. This function carries values and nothing else: the
// table grants hbh_app SELECT alone, so there is no direct INSERT for it
// to make even if it wanted to.
//
// It also returns the new draft's version, read in the same transaction,
// so the editor's first save after creating has something to name.
func (d *DB) CreateReport(ctx context.Context, ident string, in NewReport) (int, time.Time, error) {
	var (
		id      int
		version time.Time
	)
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx,
			`SELECT hbh.create_report($1, $2, $3::date, $4::date, $5, $6)`,
			in.ChildID, in.TitleAr, in.PeriodStart, in.PeriodEnd, in.PlanID, in.SummaryAr,
		).Scan(&id); err != nil {
			return err
		}
		return tx.QueryRow(ctx,
			`SELECT coalesce(updated_at, created_at) FROM hbh.progress_reports WHERE report_id = $1`, id).Scan(&version)
	})
	return id, version, err
}

// UpdateReport edits a DRAFT and returns its new version. A published
// report is refused with HB033 (0088); a draft someone saved since
// in.ExpectedVersion with HB290 (0141).
func (d *DB) UpdateReport(ctx context.Context, ident string, reportID int, in ReportEdit) (time.Time, error) {
	var version time.Time
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.update_report($1, $2::timestamptz, $3, $4, $5::date, $6::date, $7)`,
			reportID, in.ExpectedVersion, in.TitleAr, in.SummaryAr, in.PeriodStart, in.PeriodEnd, in.PlanID,
		).Scan(&version)
	})
	return version, err
}

// IssueInvoice moves an invoice out of DRAFT, after which a family can see it
// and a payment may be taken against it.
func (d *DB) IssueInvoice(ctx context.Context, ident string, invoiceID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.issue_invoice($1)`, invoiceID)
		return err
	})
}

// AddPayment records money received against an invoice.
//
// The amount arrives as TEXT and is cast in SQL, never parsed into a float on
// the way through - this is money (D-25). The triggers on hbh.payments refuse
// a payment against a draft or cancelled invoice and refuse one that exceeds
// what is outstanding, so overpayment is not a check written here.
//
// The centre and branch come from the invoice, not from the caller.
func (d *DB) AddPayment(ctx context.Context, ident string, invoiceID int, amount, method, note string) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO hbh.payments (center_id, branch_id, invoice_id, amount, method_code, note_ar)
			SELECT i.center_id, i.branch_id, i.invoice_id, $2::numeric, $3, nullif($4, '')
			FROM   hbh.invoices i
			WHERE  i.invoice_id = $1
			RETURNING payment_id`,
			invoiceID, amount, method, note).Scan(&id)
	})
	return id, err
}

// SellPackage sells a block of prepaid sessions to a child.
func (d *DB) SellPackage(ctx context.Context, ident string, childID, packageID int) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.sell_package($1, $2)`, childID, packageID).Scan(&id)
	})
	return id, err
}

// DecideRequest accepts or rejects a family's request.
//
// Accepting "please move Tuesday" moves nothing by itself: the appointment is
// changed separately and deliberately. A decision that silently rescheduled
// would make the request the source of truth for the diary, which it is not.
func (d *DB) DecideRequest(ctx context.Context, ident string, requestID int, status, note string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.decide_request($1, $2, nullif($3, ''))`,
			requestID, status, note)
		return err
	})
}

// =====================================================================
// AUTHORING AN INVOICE
//
// The billing screen had two actions - issue and take payment - and no
// way to reach either, because both work on an invoice that already
// exists and nothing created one. These three close that.
//
// Every rule stays in PL/pgSQL: the number comes from a gapless series,
// the currency from the centre row, the tax rate from a parameter, and
// the totals are computed by hbh.recalc_invoice. This layer sends what
// the caller typed and nothing else. See migration 0028.
// =====================================================================

// NewInvoice is what a receptionist fills in: who it is for, and when it
// is due. Not the number, not the currency, not any amount.
type NewInvoice struct {
	ChildID    int    `json:"child_id"`
	GuardianID *int   `json:"guardian_id"`
	DueDate    string `json:"due_date"`
	NoteAr     string `json:"note_ar"`
}

// CreateInvoice opens a DRAFT invoice.
func (d *DB) CreateInvoice(ctx context.Context, ident string, in NewInvoice) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.create_invoice($1, $2, nullif($3, '')::date, nullif($4, ''))`,
			in.ChildID, in.GuardianID, in.DueDate, in.NoteAr).Scan(&id)
	})
	return id, err
}

// NewInvoiceLine is one charge.
//
// The amounts are decimal STRINGS on the way in as well as on the way out
// (D-25). A JSON number for money is a float, and the nearest float to
// 10.10 is not 10.10 - which is a strange thing to discover on a bill.
type NewInvoiceLine struct {
	DescriptionAr string `json:"description_ar"`
	Qty           string `json:"qty"`
	UnitAmt       string `json:"unit_amt"`
	ServiceID     *int   `json:"service_id"`
	SortOrder     *int   `json:"sort_order"`
}

// AddInvoiceLine adds a charge and lets the database recompute the totals.
func (d *DB) AddInvoiceLine(ctx context.Context, ident string, invoiceID int, in NewInvoiceLine) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT hbh.add_invoice_line($1, $2, coalesce(nullif($3, '')::numeric, 1),
			                            coalesce(nullif($4, '')::numeric, 0), $5, $6)`,
			invoiceID, in.DescriptionAr, in.Qty, in.UnitAmt, in.ServiceID, in.SortOrder).Scan(&id)
	})
	return id, err
}

// RemoveInvoiceLine archives one charge and recomputes the totals.
func (d *DB) RemoveInvoiceLine(ctx context.Context, ident string, lineID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.remove_invoice_line($1)`, lineID)
		return err
	})
}

// AvailableSlots lists the windows a therapist could be booked into on one
// day, each with a room that is free at the same time.
//
// It is a READ, in a read-only transaction, and it lives beside the writes
// because it is the same question as ValidateSlot asked in the other
// direction: not "would this time be accepted" but "which times would be".
// Both go through hbh.validate_slot, so the list can never offer a slot the
// booking then refuses - there is no second copy of the rules to drift.
//
// The centre is hbh.current_center_id(), never the caller's to name. The
// function compares it again for itself: it is SECURITY DEFINER, so RLS is
// not standing behind it the way it stands behind everything else here.
func (d *DB) AvailableSlots(
	ctx context.Context, ident string,
	therapistID, serviceID int, day time.Time, roomID *int, mode string,
) ([]domain.Slot, error) {
	if mode == "" {
		mode = "IN_PERSON"
	}
	out := []domain.Slot{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT starts_at, ends_at, room_id, room_name_ar
			  FROM hbh.available_slots(
			         hbh.current_center_id(), $1, $2, $3::date, $4, $5)`,
			therapistID, serviceID, day.Format("2006-01-02"), roomID, mode)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var s domain.Slot
			if err := rows.Scan(&s.StartsAt, &s.EndsAt, &s.RoomID, &s.RoomNameAr); err != nil {
				return err
			}
			out = append(out, s)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("available_slots: %w", err)
	}
	return out, nil
}
