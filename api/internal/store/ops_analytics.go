package store

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
)

func (d *DB) OpsAnalytics(ctx context.Context, ident, from, to, kind, feature string, offset int) (json.RawMessage, error) {
	var result json.RawMessage
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.ops_analytics($1::date,$2::date,$3,$4,$5)`, from, to, kind, feature, offset).Scan(&result)
	})
	return result, err
}

func (d *DB) RecordUsage(ctx context.Context, ident, app, feature, kind, action string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.record_usage($1,$2,$3,$4)`, app, feature, kind, action)
		return err
	})
}
