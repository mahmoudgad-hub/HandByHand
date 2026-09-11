package store

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
)

func (d *DB) FamilyContacts(ctx context.Context, ident, q string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT jsonb_build_object('guardian_id',g.guardian_id,'name',g.full_name_ar,'can_send',g.user_id IS NOT NULL,'last_message',last.body_ar,'last_at',last.created_at,'can_manage',hbh.has_permission('REQUEST.MANAGE'),'unread',(SELECT count(*) FROM hbh.family_messages m WHERE m.guardian_id=g.guardian_id AND m.sender_id<>hbh.current_user_id() AND m.message_id>coalesce((SELECT message_id FROM hbh.family_message_reads WHERE user_id=hbh.current_user_id() AND guardian_id=g.guardian_id),0)))
 FROM hbh.guardians g LEFT JOIN LATERAL (
 SELECT body_ar,created_at FROM hbh.family_messages m WHERE m.guardian_id=g.guardian_id ORDER BY message_id DESC LIMIT 1
 ) last ON true WHERE g.active_flg AND g.center_id=hbh.current_center_id()
 AND (hbh.has_permission('REQUEST.MANAGE') OR g.user_id=hbh.current_user_id())
 AND ($1='' OR strpos(g.full_name_ar,$1)>0 OR strpos(coalesce(g.mobile,''),$1)>0)
 ORDER BY last.created_at DESC NULLS LAST,g.full_name_ar,g.guardian_id LIMIT 51`, q)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, raw)
		}
		return rows.Err()
	})
	return out, err
}
func (d *DB) FamilyMessages(ctx context.Context, ident string, guardian int, before int64) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT jsonb_build_object('message_id',message_id,'body',body_ar,'created_at',created_at,'mine',sender_id=hbh.current_user_id())
 FROM hbh.family_messages WHERE guardian_id=$1 AND ($2::bigint=0 OR message_id<$2) ORDER BY message_id DESC LIMIT 51`, guardian, before)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, raw)
		}
		return rows.Err()
	})
	return out, err
}
func (d *DB) SendFamilyMessage(ctx context.Context, ident string, guardian int, body, request string) (int64, error) {
	var id int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `INSERT INTO hbh.family_messages(center_id,guardian_id,sender_id,body_ar,request_id)
 VALUES(hbh.current_center_id(),$1,hbh.current_user_id(),$2,$3::uuid)
 ON CONFLICT(sender_id,request_id) DO NOTHING RETURNING message_id`, guardian, body, request).Scan(&id)
		if err == pgx.ErrNoRows {
			return tx.QueryRow(ctx, `SELECT message_id FROM hbh.family_messages WHERE sender_id=hbh.current_user_id() AND request_id=$1::uuid AND guardian_id=$2 AND body_ar=$3`, request, guardian, body).Scan(&id)
		}
		return err
	})
	return id, err
}

func (d *DB) ReadFamilyMessages(ctx context.Context, ident string, guardian int, message int64) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `INSERT INTO hbh.family_message_reads(user_id,guardian_id,message_id) VALUES(hbh.current_user_id(),$1,$2)
 ON CONFLICT(user_id,guardian_id) DO UPDATE SET message_id=greatest(family_message_reads.message_id,excluded.message_id)`, guardian, message)
		return err
	})
}
