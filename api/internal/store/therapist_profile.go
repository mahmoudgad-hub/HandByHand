package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// The therapist's profile: what a family reads about the person who will
// sit with their child.
//
// Three of the four decisions in migration 0033 are enforced below the
// line, in PL/pgSQL and in the policies. The one this file is
// responsible for is the fourth, and it is the reason certificates are
// not an ordinary CRUD resource:
//
//	AN UNPUBLISHED CERTIFICATE IMAGE MUST NOT LEAVE THE SERVER.
//
// A scanned Egyptian certificate usually carries a national ID number, a
// date of birth and a signature. is_image_public is per CERTIFICATE and
// defaults to false, so whether the attachment may travel depends on the
// ROW as well as on the caller - and the generic projection can express
// "hide this column from a family" but not "hide this column on the rows
// that have not been released". to_jsonb(t) on this table would hand a
// family the scan of an employee's identity document.

// Languages ---------------------------------------------------------

// TherapistLanguages lists the languages one therapist works in.
//
// "Speaks" and "runs sessions in" are separate columns and both come
// back. In a speech therapy centre the second is a clinical matching
// criterion, and collapsing them would put a child with a therapist who
// cannot treat them in the language they speak.
func (d *DB) TherapistLanguages(ctx context.Context, ident string, therapistID int) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'lang_code',    l.lang_code,
			         'level_code',   l.level_code,
			         'is_native',    l.is_native_flg,
			         'runs_sessions', l.runs_sessions_flg)
			FROM   hbh.therapist_languages l
			WHERE  l.therapist_id = $1 AND l.active_flg
			ORDER  BY l.is_native_flg DESC, l.lang_code`, therapistID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("therapist languages: %w", err)
	}
	return out, nil
}

// TherapistLanguage is one language on a profile.
type TherapistLanguage struct {
	LangCode     string `json:"lang_code"`
	LevelCode    string `json:"level_code"`
	IsNative     bool   `json:"is_native"`
	RunsSessions bool   `json:"runs_sessions"`
}

// SetTherapistLanguage adds a language or updates the one already there.
//
// Upsert rather than insert-or-fail: the pair (therapist, language) is
// the key, so "add English again with a different level" is an edit and
// not a duplicate. A conflict the caller cannot see the other side of is
// a dead end on the screen.
//
// A second native language is refused by a partial unique index, not by
// this function - one statement of the rule, in the schema.
func (d *DB) SetTherapistLanguage(ctx context.Context, ident string, therapistID int, in TherapistLanguage) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			INSERT INTO hbh.therapist_languages
			       (therapist_id, lang_code, level_code, is_native_flg, runs_sessions_flg)
			VALUES ($1, $2, coalesce(nullif($3, ''), 'FLUENT'), $4, $5)
			ON CONFLICT (therapist_id, lang_code) DO UPDATE
			   SET level_code = excluded.level_code,
			       is_native_flg = excluded.is_native_flg,
			       runs_sessions_flg = excluded.runs_sessions_flg,
			       active_flg = true,
			       deleted_at = NULL`,
			therapistID, in.LangCode, in.LevelCode, in.IsNative, in.RunsSessions)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("set therapist language: %w", err)
	}
	return nil
}

// RemoveTherapistLanguage archives one language. Soft, like every removal.
func (d *DB) RemoveTherapistLanguage(ctx context.Context, ident string, therapistID int, lang string) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE hbh.therapist_languages
			   SET active_flg = false, deleted_at = now()
			 WHERE therapist_id = $1 AND lang_code = $2 AND active_flg`, therapistID, lang)
		if err != nil {
			return err
		}
		// Zero rows is "no such language, or not yours" - the policy
		// filters rather than raising since writing was opened, so a
		// handler that did not count would answer 204 for a change that
		// never happened.
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("remove therapist language: %w", err)
	}
	return nil
}

// Certificates ------------------------------------------------------

// TherapistCertificates lists the certificates on a profile.
//
// THE PROJECTION IS THE POINT. attachment_id comes back only when this
// certificate's own is_image_public is true, or when the caller is staff
// or the therapist themselves. The row still says an image EXISTS -
// has_image - because a family seeing "certificate, no scan" is honest,
// while a family that cannot tell the difference between "no scan" and
// "a scan you may not see" will ask the centre for the one it cannot have.
//
// The condition is evaluated by the database, using the same
// hbh.current_user_is_staff() the policies use. This layer names the
// columns; it does not decide who is staff.
func (d *DB) TherapistCertificates(ctx context.Context, ident string, therapistID int) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'certificate_id',  c.certificate_id,
			         'title_ar',        c.title_ar,
			         'issuer_ar',       c.issuer_ar,
			         'year_awarded',    c.year_awarded,
			         'expires_on',      c.expires_on,
			         'has_image',       (c.attachment_id IS NOT NULL),
			         'is_image_public', c.is_image_public,
			         'attachment_id',
			           CASE WHEN c.attachment_id IS NOT NULL
			                 AND (c.is_image_public
			                      OR hbh.current_user_is_staff()
			                      OR t.user_id = hbh.current_user_id())
			                THEN to_jsonb(c.attachment_id) END,
			         'registration_no',
			           CASE WHEN hbh.current_user_is_staff()
			                 OR t.user_id = hbh.current_user_id()
			                THEN to_jsonb(c.registration_no) END)
			FROM   hbh.therapist_certificates c
			JOIN   hbh.therapists t ON t.therapist_id = c.therapist_id
			WHERE  c.therapist_id = $1 AND c.active_flg
			ORDER  BY c.sort_order, c.certificate_id`, therapistID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("therapist certificates: %w", err)
	}
	return out, nil
}

// NewCertificate is one certificate being added or edited.
//
// IsImagePublic is a pointer so that "not mentioned" and "explicitly
// false" are different requests. A screen that omits the field must not
// silently publish an image, and a screen that sends false must be able
// to un-publish one.
type NewCertificate struct {
	TitleAr        string `json:"title_ar"`
	IssuerAr       string `json:"issuer_ar"`
	YearAwarded    *int   `json:"year_awarded"`
	ExpiresOn      string `json:"expires_on"`
	AttachmentID   *int   `json:"attachment_id"`
	RegistrationNo string `json:"registration_no"`
	IsImagePublic  *bool  `json:"is_image_public"`
	SortOrder      *int   `json:"sort_order"`
}

// AddTherapistCertificate records a certificate.
//
// is_image_public defaults to false when the caller does not mention it,
// and the schema defaults it to false as well. Two defaults saying the
// same thing is not redundancy here: this one stops a body from making
// the decision by omission, and that one stops any other writer from it.
func (d *DB) AddTherapistCertificate(ctx context.Context, ident string, therapistID int, in NewCertificate) (int, error) {
	var id int
	public := false
	if in.IsImagePublic != nil {
		public = *in.IsImagePublic
	}
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO hbh.therapist_certificates
			       (center_id, therapist_id, title_ar, issuer_ar, year_awarded, expires_on,
			        attachment_id, registration_no, is_image_public, sort_order)
			SELECT hbh.current_center_id(), $1, $2, nullif($3, ''), $4, nullif($5, '')::date,
			       $6, nullif($7, ''), $8,
			       coalesce($9, (SELECT coalesce(max(sort_order), 0) + 10
			                       FROM hbh.therapist_certificates
			                      WHERE therapist_id = $1))
			RETURNING certificate_id`,
			therapistID, in.TitleAr, in.IssuerAr, in.YearAwarded, in.ExpiresOn,
			in.AttachmentID, in.RegistrationNo, public, in.SortOrder).Scan(&id)
	})
	if err != nil {
		return 0, fmt.Errorf("add therapist certificate: %w", err)
	}
	return id, nil
}

// SetCertificateImagePublic is the deliberate act of releasing, or
// withdrawing, one certificate's scan.
//
// It is its OWN endpoint rather than a field on an edit, because it is
// its own decision. Folded into a general update it would ride along
// with a typo correction, and the person fixing a spelling would publish
// an identity document without ever reading the words next to it.
func (d *DB) SetCertificateImagePublic(ctx context.Context, ident string, certificateID int, public bool) error {
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			UPDATE hbh.therapist_certificates
			   SET is_image_public = $2
			 WHERE certificate_id = $1 AND active_flg`, certificateID, public)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("set certificate image visibility: %w", err)
	}
	return nil
}

// Consent and publication -------------------------------------------

// RecordTherapistConsent records that the therapist agreed to publication.
//
// Only they can call it for themselves - the function refuses anybody
// else, whatever they hold. A consent given on somebody's behalf is not
// a consent, and an administrator with every permission in the schema
// still cannot agree to have another person's photograph published.
func (d *DB) RecordTherapistConsent(ctx context.Context, ident string, therapistID int, textVersion string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`SELECT hbh.record_therapist_consent($1, coalesce(nullif($2, ''), 'v1'))`,
			therapistID, textVersion)
		return err
	})
}

// WithdrawTherapistConsent takes the consent back, and the published
// profile down with it in the same statement.
func (d *DB) WithdrawTherapistConsent(ctx context.Context, ident string, therapistID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.withdraw_therapist_consent($1)`, therapistID)
		return err
	})
}

// PublishTherapistProfile makes the profile visible to families. It
// refuses without a recorded consent (HB142).
func (d *DB) PublishTherapistProfile(ctx context.Context, ident string, therapistID int) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.publish_therapist_profile($1)`, therapistID)
		return err
	})
}

// ProfileEdit is the therapist's own part of their row.
//
// Every field is a pointer so that "not mentioned" and "set to empty"
// are different requests: a screen editing the biography must not blank
// an age range it never displayed. Clearing is said out loud, in Clear.
type ProfileEdit struct {
	BioAr             *string  `json:"bio_ar"`
	PracticeSinceYear *int     `json:"practice_since_year"`
	AgeFromMon        *int     `json:"age_from_mon"`
	AgeToMon          *int     `json:"age_to_mon"`
	Clear             []string `json:"clear"`
}

// clearable is the allow list for ProfileEdit.Clear.
//
// A name outside it is refused rather than passed through. The array
// reaches SQL as a bound parameter and is compared against column names
// inside the function, so an unknown name could not become a column -
// but a caller who typed one should be told, not ignored.
var clearable = map[string]bool{
	"bio_ar": true, "practice_since_year": true,
	"age_from_mon": true, "age_to_mon": true,
}

// ErrUnknownClear names a field the caller asked to clear that is not
// part of the profile.
type ErrUnknownClear struct{ Field string }

func (e ErrUnknownClear) Error() string { return "cannot clear " + e.Field }

// UpdateTherapistProfile edits the profile columns and no others.
func (d *DB) UpdateTherapistProfile(ctx context.Context, ident string, therapistID int, in ProfileEdit) error {
	for _, f := range in.Clear {
		if !clearable[f] {
			return ErrUnknownClear{Field: f}
		}
	}
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `
			SELECT hbh.update_therapist_profile($1, $2, $3::smallint, $4::smallint, $5::smallint, $6::text[])`,
			therapistID, in.BioAr, in.PracticeSinceYear, in.AgeFromMon, in.AgeToMon, in.Clear)
		return err
	})
	if err != nil {
		return fmt.Errorf("update therapist profile: %w", err)
	}
	return nil
}
