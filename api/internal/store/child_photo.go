package store

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// A child's photograph.
//
// It is an attachment, not a column, and the difference is the whole point.
// hbh.children.photo_url held an address; an address is a capability that
// keeps working wherever it is pasted, and row level security protects the
// ROW, not the link once it has been read out of one. The bytes now live in
// hbh.attachments with everything that table already enforced - the digest,
// the size, the soft delete, INTERNAL until somebody approves it, the row
// policies, and an audit trigger that records the upload while stripping the
// file back out of the record.
//
// And a portrait cannot exist without a recorded PHOTO_USE consent from a
// guardian linked to the child. That is a trigger in the schema, not a check
// here: migration 0074, corrected in 0076.

// ChildPhoto is one stored portrait, ready to be served.
type ChildPhoto struct {
	AttachmentID int
	MimeType     string
	Content      []byte
}

// SetChildPhoto stores a new portrait and archives whatever was there.
//
// Replace rather than add: hbh.set_child_photo archives the previous active
// portrait in the same transaction, because a unique index allows exactly one
// and a second upload would otherwise be refused as a duplicate when what
// somebody meant was "use this one now". The old row is archived, never
// deleted - which picture the centre held, and when, is part of what makes a
// consent withdrawal answerable afterwards.
func (d *DB) SetChildPhoto(ctx context.Context, ident string, childID int,
	fileName, mime string, content []byte) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.set_child_photo($1, $2, $3, $4)`,
			childID, fileName, mime, content).Scan(&id)
	})
	if err != nil {
		return 0, err
	}
	return id, nil
}

// ChildPhoto reads the current portrait.
//
// A child this caller may not see and a child with no photograph give the
// same ErrNotFound, and the transport turns both into the same 404. "This
// child exists and is not yours" is itself something worth not saying.
//
// Only the ACTIVE row: an archived portrait is a previous picture, and the
// route that serves the current one must not be able to return it.
func (d *DB) ChildPhoto(ctx context.Context, ident string, childID int) (ChildPhoto, error) {
	var p ChildPhoto
	var mime *string
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT attachment_id, mime_type, content
			FROM   hbh.attachments
			WHERE  child_id = $1
			  AND  purpose = 'PROFILE_PHOTO'
			  AND  active_flg`, childID).Scan(&p.AttachmentID, &mime, &p.Content)
	})
	if err != nil {
		return ChildPhoto{}, fmt.Errorf("child photo: %w", noRows(err))
	}
	if len(p.Content) == 0 {
		return ChildPhoto{}, ErrNotFound
	}
	p.MimeType = deref(mime)
	return p, nil
}
