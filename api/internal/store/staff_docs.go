package store

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// A member of staff's scanned documents.
//
// Neither function checks a permission, and neither should: both run under
// the caller's identity, so p_sd_insert and p_sd_select decide - STAFF.PII,
// or it is the caller's own record. A check here would be a second answer
// to the same question, and the weaker of the two would eventually be the
// one deciding.

// StaffDoc is what the download route needs and nothing more. The row
// carries a title and a note as well; this deliberately does not fetch
// them, because streaming a file has no use for them.
type StaffDoc struct {
	Path     string
	MimeType string
}

// AddStaffDocument records one file against a person.
//
// The INSERT is the authorisation: a caller with no STAFF.PII writing
// against somebody else's user_id matches no policy and the statement
// affects nothing, which surfaces as a refusal rather than a silent
// success because RETURNING then yields no row.
func (d *DB) AddStaffDocument(
	ctx context.Context, ident string,
	userID int, kind, path, title, mime string, size int64,
) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			INSERT INTO hbh.staff_documents
			       (center_id, user_id, kind, path, title_ar, mime_type, size_bytes)
			VALUES (hbh.current_center_id(), $1, $2, $3, nullif($4, ''), $5, $6)
			RETURNING document_id`,
			userID, kind, path, title, mime, size).Scan(&id)
	})
	if err != nil {
		return 0, fmt.Errorf("add staff document: %w", noRows(err))
	}
	return id, nil
}

// StaffDocument resolves an id to a stored file name.
//
// A caller who may not see the row gets ErrNotFound, which the transport
// turns into the same 404 as an id that does not exist. That is the point:
// "this document exists and is not yours" is itself something worth not
// saying about a colleague's identity card.
func (d *DB) StaffDocument(ctx context.Context, ident string, id int) (StaffDoc, error) {
	var doc StaffDoc
	var mime *string
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT path, mime_type
			FROM   hbh.staff_documents
			WHERE  document_id = $1 AND active_flg`, id).Scan(&doc.Path, &mime)
	})
	if err != nil {
		return StaffDoc{}, fmt.Errorf("staff document: %w", noRows(err))
	}
	doc.MimeType = deref(mime)
	return doc, nil
}

// SetStaffPhoto records the file name of a member of staff's photograph.
//
// It writes hbh.staff_profiles, so the same policy applies as everywhere
// else on that table: STAFF.PII, or it is your own record. The row is
// created if the person has no profile yet - a photograph should not
// require somebody to fill in a national identity number first.
func (d *DB) SetStaffPhoto(ctx context.Context, ident string, userID int, name string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, `
			INSERT INTO hbh.staff_profiles (center_id, user_id, photo_path)
			VALUES (hbh.current_center_id(), $1, nullif($2, ''))
			ON CONFLICT (user_id) DO UPDATE SET photo_path = nullif($2, '')`,
			userID, name)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// StaffPhoto resolves a person to the file name of their photograph.
//
// Not visible to this caller and no photograph at all give the same
// ErrNotFound, and that is deliberate: whether a colleague has uploaded a
// photograph is not something to confirm to somebody who may not see it.
func (d *DB) StaffPhoto(ctx context.Context, ident string, userID int) (string, error) {
	return d.UserAvatar(ctx, ident, userID)
}
