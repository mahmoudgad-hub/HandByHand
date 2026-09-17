package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// Everything in this file is a thin call into PL/pgSQL, for the reason
// store/auth.go states about the login rules: the attempt ceiling, the
// backoff, what counts as dead and when a stuck row comes back are business
// rules and they are written once, in hbh.record_sms_failed and
// hbh.reap_stuck_sms. A retry policy in Go would be a second copy of a rule,
// and the weaker of two copies is the one that decides.

// Pending is one claimed message, ready to hand to a provider.
type Pending struct {
	ID           int64
	Purpose      string
	TemplateCode string
	Destination  string
	// Body is NULL in the database for a login code and empty here. A code is
	// never at rest - see the header of migration 0094.
	Body string
	// Vars is the same message taken apart, for a transport that assembles it
	// from an approved template rather than being handed a sentence. Nil for
	// a login code, and ck_sms_vars_otp in migration 0106 makes that
	// structural: the code IS the variable, so a row that carried one would
	// be the plaintext at rest that hbh.otp_codes exists to avoid.
	Vars     []string
	Attempts int
}

// ClaimSMS takes up to limit messages and marks them SENDING.
//
// THE TRANSACTION ENDS HERE, BEFORE ANYTHING IS SENT. That is the whole
// recovery story: a worker that dies between this commit and the provider
// call leaves rows that say SENDING with a claim time, and hbh.reap_stuck_sms
// brings them back. A worker that held the transaction open across the
// network call would instead leave rows locked by a dead session, invisible
// to every other worker until the connection timed out.
//
// hbh.claim_sms uses FOR UPDATE SKIP LOCKED, so two workers running this
// statement at the same instant take disjoint sets and neither waits.
func (d *DB) ClaimSMS(ctx context.Context, limit int, worker string) ([]Pending, error) {
	var out []Pending
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx,
			`SELECT sms_id, purpose, template_code, destination,
			        coalesce(body_ar, ''), template_vars, attempts
			   FROM hbh.claim_sms($1, $2)`, limit, worker)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var (
				p    Pending
				vars []byte
			)
			if err := rows.Scan(&p.ID, &p.Purpose, &p.TemplateCode,
				&p.Destination, &p.Body, &vars, &p.Attempts); err != nil {
				return err
			}
			// UNMARSHALLED HERE RATHER THAN SCANNED STRAIGHT INTO []string,
			// so that a row carrying anything but an array of strings fails
			// with a message naming the row. ck_sms_vars only proves it is an
			// array - a CHECK cannot hold the subquery that would walk it -
			// so this is where the element type is actually established.
			if len(vars) > 0 {
				if err := json.Unmarshal(vars, &p.Vars); err != nil {
					return fmt.Errorf("sms %d has unreadable template_vars: %w", p.ID, err)
				}
			}
			out = append(out, p)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("claim_sms: %w", err)
	}
	return out, nil
}

// RecordSMSSent marks one message delivered to the provider and clears the
// notification's pending flag in the same transaction.
//
// A false return is not an error: it means the row was no longer SENDING,
// which happens when the reaper reclaimed it while this attempt was in flight.
// The caller logs it and moves on - re-sending would be the duplicate the
// reaper's timeout is already sized to make rare.
func (d *DB) RecordSMSSent(ctx context.Context, id int64, provider, msgID string) (bool, error) {
	var ok bool
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.record_sms_sent($1, $2, nullif($3, ''))`,
			id, provider, msgID).Scan(&ok)
	})
	if err != nil {
		return false, fmt.Errorf("record_sms_sent: %w", err)
	}
	return ok, nil
}

// RecordSMSFailed reports a provider failure and returns the status the
// database decided: PENDING if it will be tried again, DEAD if it will not.
func (d *DB) RecordSMSFailed(ctx context.Context, id int64, class, detail string) (string, error) {
	var status string
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.record_sms_failed($1, $2, $3)`, id, class, detail).Scan(&status)
	})
	if err != nil {
		return "", fmt.Errorf("record_sms_failed: %w", err)
	}
	return status, nil
}

// EnqueueOTPDelivery records that a login code was handed to a provider.
//
// IT RECORDS THE ATTEMPT AND NOT THE CODE. hbh.sms_outbox.body_ar is NULL for
// every OTP row and ck_sms_body makes that structural, so no dump, no backup
// and no operations screen can ever contain a live credential. What is kept is
// the destination, the template, the provider and the outcome - which is
// everything an operator needs to answer "did the code go out" and nothing
// that helps anybody sign in.
//
// The row is written ALREADY TERMINAL, SENT or DEAD, because a login code is
// not queued: it is sent inside the request that asked for it. Queueing a
// credential whose whole life is fifteen minutes behind a worker that polls
// every few seconds adds latency to the one flow where latency is the product,
// and would put the plaintext in a table to wait there.
//
// IT GOES THROUGH hbh.record_otp_delivery AND NOT hbh.enqueue_sms. The general
// enqueue takes a destination and a BODY, which is "send any text to any
// number" and is not granted to hbh_app at all - see migration 0096. This one
// takes no body, writes a terminal row, and chooses its own dedupe key, so the
// worst it can do is record a delivery that did not happen.
func (d *DB) EnqueueOTPDelivery(ctx context.Context, centerID int, mobile,
	provider, providerMsg, errClass, errDetail string) error {
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		var id int64
		return tx.QueryRow(ctx,
			`SELECT hbh.record_otp_delivery($1, $2, $3, nullif($4,''), nullif($5,''), nullif($6,''))`,
			centerID, mobile, provider, providerMsg, errClass, errDetail).Scan(&id)
	})
	if err != nil {
		return fmt.Errorf("record otp delivery: %w", err)
	}
	return nil
}

// undefinedFunction is Postgres's answer when a function does not exist.
// It is named here, and nowhere else, because it is the one case a template
// lookup treats as "no template" rather than as a fault: see TemplateSID.
const undefinedFunction = "42883"

// TemplateSID returns the ContentSid the centre's template for this code was
// approved under, or "" when there is none.
//
// "" ALSO WHEN THE TEMPLATE TABLE DOES NOT EXIST YET. Migration 0153 is held
// until this build is running, so for a while this build runs against a
// database without hbh.message_template_sid. Treating that as "no approved
// template" is exactly the truth of that database - nothing is approved in a
// table that is not there - and it is what lets the image deploy before the
// migration instead of the two having to land in the same second. Any other
// error is returned.
func (d *DB) TemplateSID(ctx context.Context, centerID int, code string) (string, error) {
	var sid string
	err := d.InReadTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT coalesce(hbh.message_template_sid($1, $2), '')`, centerID, code).Scan(&sid)
	})
	if IsCode(err, undefinedFunction) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("message_template_sid: %w", err)
	}
	return sid, nil
}

// SMSTemplateSID is TemplateSID for a message the worker has claimed; the
// outbox row already knows its centre and its code.
func (d *DB) SMSTemplateSID(ctx context.Context, id int64) (string, error) {
	var sid string
	err := d.InReadTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT coalesce(hbh.sms_template_sid($1), '')`, id).Scan(&sid)
	})
	if IsCode(err, undefinedFunction) {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("sms_template_sid: %w", err)
	}
	return sid, nil
}

// CentresWithoutTemplateSID counts active centres that could not send a
// message of this code under an approved template.
//
// NOT tolerant of a missing function, unlike the two above, and on purpose:
// it is asked at production startup, and a production deployment that sends
// WhatsApp without the template table cannot send a login code at all. An
// error here stops the process, which is the answer.
func (d *DB) CentresWithoutTemplateSID(ctx context.Context, code string) (int, error) {
	var n int
	err := d.InReadTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.centres_without_template_sid($1)`, code).Scan(&n)
	})
	if err != nil {
		return 0, fmt.Errorf("centres_without_template_sid: %w", err)
	}
	return n, nil
}
