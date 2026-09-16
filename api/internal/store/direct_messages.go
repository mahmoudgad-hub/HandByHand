package store

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
)

func (d *DB) ChatContacts(ctx context.Context, ident, q string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	guardian := false
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT user_type='GUARDIAN' FROM hbh.users WHERE user_id=hbh.current_user_id()`).Scan(&guardian); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT jsonb_build_object('guardian_id',-p.user_id,'user_id',p.user_id,'kind',p.kind,'role',hbh.chat_recipient_role(p.user_id),'name',p.name,'can_send',true,'can_manage',hbh.has_permission('REQUEST.MANAGE'),'last_message',last.body_ar,'last_at',last.created_at,'unread',(SELECT count(*) FROM hbh.direct_messages m WHERE m.sender_id=p.user_id AND m.recipient_id=hbh.current_user_id() AND m.read_at IS NULL))
 FROM hbh.chat_peers() p LEFT JOIN LATERAL(SELECT body_ar,created_at FROM hbh.direct_messages m WHERE m.sender_id=p.user_id OR m.recipient_id=p.user_id ORDER BY message_id DESC LIMIT 1) last ON true
 WHERE $1='' OR strpos(p.name,$1)>0 ORDER BY last.created_at DESC NULLS LAST,p.name,p.user_id`, q)
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
	if err != nil {
		return nil, err
	}
	if guardian {
		return out, nil
	}
	legacy, err := d.FamilyContacts(ctx, ident, q)
	if err != nil {
		return nil, err
	}
	// Keep existing centre/family history alongside private account conversations.
	for _, raw := range legacy {
		var row map[string]any
		if json.Unmarshal(raw, &row) == nil && row["last_message"] != nil {
			row["kind"] = "legacy"
			b, _ := json.Marshal(row)
			out = append(out, b)
		}
	}
	return out, nil
}
func (d *DB) DirectMessages(ctx context.Context, ident string, peer int, before int64) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `SELECT jsonb_build_object('message_id',message_id,'body',body_ar,'created_at',created_at,'mine',sender_id=hbh.current_user_id())
 FROM hbh.direct_messages WHERE (sender_id=$1 OR recipient_id=$1) AND ($2::bigint=0 OR message_id<$2) ORDER BY message_id DESC LIMIT 51`, peer, before)
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
func (d *DB) SendDirectMessage(ctx context.Context, ident string, peer int, body, request string) (int64, error) {
	var id int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `INSERT INTO hbh.direct_messages(center_id,recipient_id,sender_id,body_ar,request_id)
 VALUES(hbh.current_center_id(),$1,hbh.current_user_id(),$2,$3::uuid)
 ON CONFLICT(sender_id,recipient_id,request_id) DO NOTHING RETURNING message_id`, peer, body, request).Scan(&id)
		if err == pgx.ErrNoRows {
			return tx.QueryRow(ctx, `SELECT message_id FROM hbh.direct_messages WHERE sender_id=hbh.current_user_id() AND request_id=$1::uuid AND recipient_id=$2 AND body_ar=$3`, request, peer, body).Scan(&id)
		}
		return err
	})
	return id, err
}

func (d *DB) ReadDirectMessages(ctx context.Context, ident string, peer int, message int64) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `UPDATE hbh.direct_messages SET read_at=now() WHERE sender_id=$1 AND recipient_id=hbh.current_user_id() AND message_id<=$2 AND read_at IS NULL`, peer, message)
		return err
	})
}
func (d *DB) BroadcastStaff(ctx context.Context, ident, body, request string) (int, error) {
	var count int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.broadcast_staff($1,$2::uuid)`, body, request).Scan(&count)
	})
	return count, err
}
