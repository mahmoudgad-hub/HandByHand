package store

import (
	"context"
	"fmt"
	"time"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// The intake path: an application from a family the system has never seen,
// and the queue where the centre answers it.
//
// THIS IS THE ONLY WRITE IN THE SERVICE MADE WITH NO IDENTITY. Everywhere else
// an empty identity means zero rows - that is the fail-closed rule and it does
// not bend here either: an anonymous caller still reads nothing, still cannot
// INSERT into hbh.enrolment_applications, and reaches the table through
// exactly one SECURITY DEFINER function that decides for itself whether to
// accept the row.
//
// Which is why the REASON it gives back does not travel to the browser. See
// the note on EnrolmentResult.

// EnrolmentIn is a submitted form. Every field is text a stranger typed, and
// nothing here is trusted beyond being well-formed JSON: the function checks
// the shape, the limits and the centre.
type EnrolmentIn struct {
	CenterCode           string `json:"center_code"`
	ParentNameAr         string `json:"parent_name_ar"`
	ParentMobile         string `json:"parent_mobile"`
	ParentEmail          string `json:"parent_email"`
	RelationshipCode     string `json:"relationship_code"`
	AddressAr            string `json:"address_ar"`
	PreferredContactTime string `json:"preferred_contact_time"`
	ChildNameAr          string `json:"child_name_ar"`
	// A calendar day as "2006-01-02", not an instant. A birth date has no
	// time zone: a child born on the fifteenth was born on the fifteenth in
	// Cairo and in UTC, and sending it as an instant is how it becomes the
	// fourteenth for somebody. The handler checks the shape; the cast in the
	// statement is what parses it.
	ChildBirthDate     string `json:"child_birth_date"`
	ChildGender        string `json:"child_gender"`
	MainConcernAr      string `json:"main_concern_ar"`
	PreviousTherapyAr  string `json:"previous_therapy_ar"`
	PreferredServiceID *int   `json:"preferred_service_id"`
}

// EnrolmentResult is the function's own answer.
//
// Reason is for the SERVER: the log, the audit line, the status code. It is
// not for the screen, and the handler must not forward it. REJECTED is vague
// on purpose so that an anonymous caller cannot discover which centre codes
// exist by trying them, and telling somebody the difference between
// TOO_MANY_FOR_MOBILE and TOO_MANY_FOR_IP tells them the number they typed is
// already known to this centre. One message reaches the family; the
// distinction stays here.
type EnrolmentResult struct {
	OK            bool
	Reason        string
	ApplicationNo string
}

// The reasons hbh.submit_enrolment can give.
const (
	EnrolmentOK           = "OK"
	EnrolmentTooManyMobil = "TOO_MANY_FOR_MOBILE"
	EnrolmentTooManyIP    = "TOO_MANY_FOR_IP"
	EnrolmentRejected     = "REJECTED"
)

// SubmitEnrolment records an application from an unauthenticated caller.
//
// clientIP is passed as a value rather than read from anywhere, and a nil one
// DISABLES the per-address limit - the function cannot count what it was not
// told. That is why the handler passes it even when it is unsure: an
// unenforced limit that looks enforced is worse than none.
func (d *DB) SubmitEnrolment(ctx context.Context, in EnrolmentIn, clientIP *string) (EnrolmentResult, error) {
	var out EnrolmentResult
	var no *string

	// The empty identity is the point, not an oversight. hbh.submit_enrolment
	// is SECURITY DEFINER and granted to hbh_app; the policies still see
	// nobody, so this transaction can reach nothing else.
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT ok, reason, application_no
			FROM   hbh.submit_enrolment(
			         p_center_code            => $1,
			         p_parent_name_ar         => $2,
			         p_parent_mobile          => $3,
			         p_child_name_ar          => $4,
			         p_child_birth_date       => $5::date,
			         p_child_gender           => $6,
			         p_parent_email           => nullif($7, ''),
			         p_relationship_code      => coalesce(nullif($8, ''), 'FATHER'),
			         p_main_concern_ar        => nullif($9, ''),
			         p_preferred_service_id   => $10,
			         p_address_ar             => nullif($11, ''),
			         p_preferred_contact_time => nullif($12, ''),
			         p_previous_therapy_ar    => nullif($13, ''),
			         p_source_code            => 'WEB',
			         p_client_ip              => $14::inet)`,
			in.CenterCode, in.ParentNameAr, in.ParentMobile, in.ChildNameAr,
			in.ChildBirthDate, in.ChildGender, in.ParentEmail, in.RelationshipCode,
			in.MainConcernAr, in.PreferredServiceID, in.AddressAr, in.PreferredContactTime,
			in.PreviousTherapyAr, clientIP).Scan(&out.OK, &out.Reason, &no)
	})
	if err != nil {
		return out, fmt.Errorf("submit enrolment: %w", err)
	}
	out.ApplicationNo = deref(no)
	return out, nil
}

// EnrolmentQuery filters the queue.
type EnrolmentQuery struct {
	Status   string
	Archived bool
	Limit    int
	Offset   int
}

const enrolmentCols = `
	e.application_id, e.application_no, e.status,
	e.parent_name_ar, e.parent_mobile, e.parent_email, e.relationship_code,
	e.address_ar, e.preferred_contact_time,
	e.child_name_ar, e.child_birth_date, e.child_gender,
	e.main_concern_ar, e.previous_therapy_ar,
	e.source_code, e.submitted_at,
	e.contacted_at, e.contact_note_ar, e.decided_at, e.decision_note_ar,
	e.converted_guardian_id, e.converted_child_id, e.active_flg, e.assessment_at,
	s.service_id, s.name_ar, s.kind_code, s.color_hex,
	(SELECT count(*) FROM hbh.enrolment_applications sib
	  WHERE sib.parent_mobile = e.parent_mobile
	  AND   sib.application_id <> e.application_id
	  AND   sib.active_flg),
	EXISTS (SELECT 1 FROM hbh.enrolment_applications fam
	         WHERE fam.parent_mobile = e.parent_mobile
	         AND   fam.application_id <> e.application_id
	         AND   fam.converted_child_id IS NOT NULL)`

// Enrolments lists the queue, newest first.
//
// Newest first because an intake queue is worked from the top: the family that
// wrote this morning is the one still waiting for a call. Nothing here filters
// by centre - the policy on hbh.enrolment_applications requires
// ENROLMENT.MANAGE and pins the centre, so a caller without it gets an empty
// list rather than a refusal, which is the same fail-closed shape as
// everywhere else.
func (d *DB) Enrolments(ctx context.Context, ident string, q EnrolmentQuery) ([]domain.Enrolment, int, error) {
	out := []domain.Enrolment{}
	total := 0

	where := `
		WHERE ($1::boolean OR e.active_flg)
		AND   ($2::text IS NULL OR e.status = $2::text)`

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx,
			`SELECT count(*) FROM hbh.enrolment_applications e`+where,
			q.Archived, nullif(q.Status)).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx, `
			SELECT `+enrolmentCols+`
			FROM   hbh.enrolment_applications e
			LEFT JOIN hbh.services s ON s.service_id = e.preferred_service_id`+where+`
			ORDER  BY e.submitted_at DESC, e.application_id DESC
			LIMIT  $3 OFFSET $4`,
			q.Archived, nullif(q.Status), q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()

		for rows.Next() {
			e, err := scanEnrolment(rows)
			if err != nil {
				return err
			}
			out = append(out, e)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("enrolments: %w", err)
	}
	return out, total, nil
}

// Enrolment returns one application, or ErrNotFound.
func (d *DB) Enrolment(ctx context.Context, ident string, id int) (domain.Enrolment, error) {
	var e domain.Enrolment
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		row := tx.QueryRow(ctx, `
			SELECT `+enrolmentCols+`
			FROM   hbh.enrolment_applications e
			LEFT JOIN hbh.services s ON s.service_id = e.preferred_service_id
			WHERE  e.application_id = $1`, id)
		var err error
		e, err = scanEnrolment(row)
		return err
	})
	if err != nil {
		return e, noRows(err)
	}
	return e, nil
}

// scanRow is the shared shape of pgx.Row and pgx.Rows.
type scanRow interface{ Scan(dest ...any) error }

func scanEnrolment(row scanRow) (domain.Enrolment, error) {
	var (
		e        domain.Enrolment
		email    *string
		address  *string
		contact  *string
		concern  *string
		previous *string
		cnote    *string
		dnote    *string
		svcID    *int
		svcName  *string
		svcKind  *string
		svcColor *string
	)
	err := row.Scan(&e.ApplicationID, &e.ApplicationNo, &e.Status,
		&e.ParentNameAr, &e.ParentMobile, &email, &e.RelationshipCode,
		&address, &contact,
		&e.ChildNameAr, &e.ChildBirthDate, &e.ChildGender,
		&concern, &previous,
		&e.SourceCode, &e.SubmittedAt,
		&e.ContactedAt, &cnote, &e.DecidedAt, &dnote,
		&e.ConvertedGuardianID, &e.ConvertedChildID, &e.ActiveFlg, &e.AssessmentAt,
		&svcID, &svcName, &svcKind, &svcColor,
		&e.SiblingApplications, &e.FamilyAlreadyHere)
	if err != nil {
		return e, err
	}
	e.ParentEmail, e.AddressAr, e.PreferredContactTime = deref(email), deref(address), deref(contact)
	e.MainConcernAr, e.PreviousTherapyAr = deref(concern), deref(previous)
	e.ContactNoteAr, e.DecisionNoteAr = deref(cnote), deref(dnote)
	if svcID != nil {
		e.PreferredService = &domain.ServiceRef{
			ServiceID: *svcID, NameAr: deref(svcName),
			KindCode: deref(svcKind), ColorHex: deref(svcColor),
		}
	}
	return e, nil
}

// EnrolmentUpdate is a move along the queue.
//
// Status selects the transition and the notes hang off it: a note
// about a phone call belongs to CONTACTED, a note about a refusal belongs to
// REJECTED. AssessmentAt carries the agreed time for ASSESSMENT_BOOKED;
// the database constraint and state machine remain authoritative.
type EnrolmentUpdate struct {
	Status       string     `json:"status"`
	NoteAr       string     `json:"note_ar"`
	AssessmentAt *time.Time `json:"assessment_at,omitempty"`
}

// SetEnrolmentStatus moves an application along its state machine.
//
// THE ROW COUNT IS CHECKED, and that check is the whole reason this is not a
// three-line function. Since writing was opened in migration 0012 a refusal by
// a POLICY is no longer an error: the grant exists, so a caller the policy
// does not admit updates zero rows and Postgres reports success. Returning 204
// on that would tell an operator the application had moved when nothing
// happened at all.
//
// ErrNotFound rather than a permission error, as everywhere: "no such row" and
// "not yours" are the same answer by design.
func (d *DB) SetEnrolmentStatus(ctx context.Context, ident string, id int, in EnrolmentUpdate) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE hbh.enrolment_applications
			SET    status = $2,
			       assessment_at = CASE WHEN $2 = 'ASSESSMENT_BOOKED'
			                            THEN $4::timestamptz ELSE assessment_at END,
			       contact_note_ar = CASE WHEN $2 = 'CONTACTED' AND nullif($3, '') IS NOT NULL
			                              THEN $3 ELSE contact_note_ar END,
			       decision_note_ar = CASE WHEN $2 IN ('REJECTED', 'DUPLICATE') AND nullif($3, '') IS NOT NULL
			                               THEN $3 ELSE decision_note_ar END
			WHERE  application_id = $1
			AND    active_flg`, id, in.Status, in.NoteAr, in.AssessmentAt)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("enrolment status: %w", err)
	}
	return nil
}

// ConvertEnrolment turns an application into a guardian and a child.
//
// The function refuses without ENROLMENT.MANAGE (HB092) and refuses from the
// wrong state (HB091), reuses a guardian whose mobile it already knows, and
// deliberately does NOT set can_view_live_flg: filling in a form is not
// consent to watch a child in a therapy session. See D-24.
func (d *DB) ConvertEnrolment(ctx context.Context, ident string, id int, note string) (domain.Converted, error) {
	var c domain.Converted
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT guardian_id, child_id, child_no FROM hbh.convert_enrolment($1, nullif($2, ''))`,
			id, note).Scan(&c.GuardianID, &c.ChildID, &c.ChildNo)
	})
	if err != nil {
		return c, noRows(fmt.Errorf("convert enrolment: %w", err))
	}
	return c, nil
}
