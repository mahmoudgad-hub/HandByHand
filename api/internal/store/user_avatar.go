package store

import (
	"context"
	"github.com/jackc/pgx/v5"
)

// Compatibility endpoint: all account photographs use the personnel record.
func (d *DB) SetUserAvatar(ctx context.Context, ident string, userID int, name string) error {
	return d.SetStaffPhoto(ctx, ident, userID, name)
}

func (d *DB) UserAvatar(ctx context.Context, ident string, userID int) (string, error) {
	var name string
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT file_name FROM hbh.user_avatars WHERE user_id=$1`, userID).Scan(&name)
	})
	return name, noRows(err)
}
