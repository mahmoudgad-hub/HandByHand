package store

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
)

// Everything in this file is a thin call into a PL/pgSQL function. That is the
// design, not a stage on the way to something richer: the login rules - code
// length, lifetime, attempt ceiling, resend window, what happens on the last
// wrong guess - are already written once, in the database, and rewriting any
// of them here would create a second copy to disagree with the first.
//
// Note also what these functions do NOT raise. hbh.verify_otp returns a status
// for a wrong code rather than raising, because Postgres has no autonomous
// transactions: an exception would roll back the attempt counter it had just
// incremented and make guessing free. Reading a status and acting on it is
// therefore load-bearing, and turning any of these into an error would undo
// the counter. See the THE COUNTER PROBLEM note in migration 0002.

// OTPRequest is the outcome of asking for a one-time code.
type OTPRequest struct {
	OK     bool
	Reason string
	// Code is the plaintext, present only when OK. It exists to be handed to
	// an SMS gateway and is never persisted. Until that gateway exists the
	// only other consumer is the acceptance suite, through OTP_ECHO.
	Code      *string
	ExpiresAt *time.Time

	// CenterID is which centre this number belongs to, and it comes back
	// from hbh.request_otp rather than from a second query BECAUSE A SECOND
	// QUERY CANNOT SEE IT. A code is issued before there is a session, so the
	// connection carries no identity, so the policy on hbh.users matches
	// nothing - RLS failing closed, exactly as designed. The first attempt at
	// this returned zero rows silently and the whole delivery path did
	// nothing while reporting success. See migration 0095.
	//
	// Present only when OK. It is withheld for a locked account along with
	// everything else, so its presence cannot be used to tell "locked" from
	// "unknown".
	CenterID *int

	// MobileE164 is the number as hbh.canonical_mobile read it, and it is
	// the ONLY form that may be handed to a provider. What the person typed
	// is not: "00201225283838" and "0122 528 3838" both find the account,
	// because request_otp canonicalises its own argument, and neither is
	// something a sender can dial. Passing the typed value on marked every
	// login code typed with 00 as DEAD while the screen said SENT.
	//
	// Present only when OK, for CenterID's reason.
	MobileE164 *string
}

// Reasons returned by hbh.request_otp and hbh.verify_otp. They are compared,
// never displayed: the Arabic wording is Angular's job, via translation files.
const (
	ReasonOK              = "OK"
	ReasonNotRegistered   = "NOT_REGISTERED"
	ReasonUserLocked      = "USER_LOCKED"
	ReasonResendTooSoon   = "RESEND_TOO_SOON"
	ReasonNoPendingCode   = "NO_PENDING_CODE"
	ReasonExpired         = "EXPIRED"
	ReasonTooManyAttempts = "TOO_MANY_ATTEMPTS"
	ReasonWrongCode       = "WRONG_CODE"
	ReasonNoSession       = "NO_SESSION"
	ReasonRevoked         = "REVOKED"
)

// RequestOTP issues a code for the given mobile number.
//
// A false OK is not an error: this function reports the truth so the server
// log and the audit trail can hold it, and the handler decides what a screen
// is told.
//
// THIS COMMENT USED TO SAY "NOT_REGISTERED must never reach the client" AND
// THE HANDLER HAD ALREADY BEEN CHANGED NOT TO DO THAT. The decision is the
// owner's, dated 2026-09-05 and extended 2026-09-10, and it is written out in
// auth_handlers.go beside the mapping that carries it. Two halves of one
// codebase saying opposite things is how the wrong half gets believed - the
// same failure CLAUDE.md opens by describing - so this half now points at the
// half that decides instead of contradicting it.
//
// The caller may send the mobile in any form a person types: hbh.request_otp
// canonicalises its own argument (0112) and returns the result as mobile_e164,
// which is selected here and is what delivery uses.
//
// THIS USED TO LEAVE mobile_e164 UNREAD, on the reasoning that the delivery
// path did not need it "while sms.E164 accepts what a person types". It did
// not accept it. E164 took +... and the national 01XXXXXXXXX and nothing
// else, so a number typed as 00201225283838 found its account, issued a code,
// answered SENT, and was refused at the wire as PERMANENT - no retry, and no
// sign anywhere but a DEAD row in hbh.sms_outbox. The premise was checked
// against one spelling of a number and stated for all of them.
//
// Selecting the sixth column makes this build require 0112. It is applied
// wherever this runs, and the alternative is the bug above.
func (d *DB) RequestOTP(ctx context.Context, mobile string) (OTPRequest, error) {
	var r OTPRequest
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT ok, reason, code, expires_at, center_id, mobile_e164
			   FROM hbh.request_otp($1)`, mobile).
			Scan(&r.OK, &r.Reason, &r.Code, &r.ExpiresAt, &r.CenterID, &r.MobileE164)
	})
	if err != nil {
		return OTPRequest{}, fmt.Errorf("request_otp: %w", err)
	}
	return r, nil
}

// OTPVerify is the outcome of checking a code.
type OTPVerify struct {
	OK           bool
	Reason       string
	UserID       *int
	AttemptsLeft *int
}

// VerifyOTP checks a code and consumes it.
//
// The transaction is read-write and must commit even when OK is false: the
// attempt counter was incremented inside it, and a rollback would hand the
// guess back for free.
func (d *DB) VerifyOTP(ctx context.Context, mobile, code string) (OTPVerify, error) {
	var v OTPVerify
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT ok, reason, user_id, attempts_left FROM hbh.verify_otp($1, $2)`, mobile, code).
			Scan(&v.OK, &v.Reason, &v.UserID, &v.AttemptsLeft)
	})
	if err != nil {
		return OTPVerify{}, fmt.Errorf("verify_otp: %w", err)
	}
	return v, nil
}

// Session is a freshly opened login session.
type Session struct {
	ID        int64
	ExpiresAt time.Time
}

// CreateSession stores the digest of token and returns when it dies.
// The plaintext token is never written: hbh.create_auth_session keeps only its
// SHA-256.
func (d *DB) CreateSession(ctx context.Context, userID int, token string, clientIP *string, userAgent string) (Session, error) {
	var s Session
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT auth_session_id, expires_at FROM hbh.create_auth_session($1, $2, $3::inet, $4)`,
			userID, token, clientIP, userAgent).Scan(&s.ID, &s.ExpiresAt)
	})
	if err != nil {
		return Session{}, fmt.Errorf("create_auth_session: %w", err)
	}
	return s, nil
}

// Resolution is what a bearer token resolves to.
type Resolution struct {
	OK       bool
	Reason   string
	Username string
	UserID   int
	CenterID int
}

// ResolveSession turns a bearer token into an identity, or says why it will
// not. The transaction is read-write because the function stamps last_seen_at,
// and because a suspended account has to be refused here rather than at the
// next login: a live session is not a licence.
func (d *DB) ResolveSession(ctx context.Context, token string) (Resolution, error) {
	var (
		r        Resolution
		username *string
		userID   *int
		centerID *int
	)
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT ok, reason, username, user_id, center_id FROM hbh.resolve_auth_session($1)`, token).
			Scan(&r.OK, &r.Reason, &username, &userID, &centerID)
	})
	if err != nil {
		return Resolution{}, fmt.Errorf("resolve_auth_session: %w", err)
	}
	if username != nil {
		r.Username = *username
	}
	if userID != nil {
		r.UserID = *userID
	}
	if centerID != nil {
		r.CenterID = *centerID
	}
	return r, nil
}

// RevokeSession ends a session. A token that was already dead reports false
// rather than an error - logging out twice is not a failure.
func (d *DB) RevokeSession(ctx context.Context, token, reason string) (bool, error) {
	var revoked bool
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.revoke_auth_session($1, $2)`, token, reason).Scan(&revoked)
	})
	if err != nil {
		return false, fmt.Errorf("revoke_auth_session: %w", err)
	}
	return revoked, nil
}

// VerifyPassword checks a staff sign-in.
//
// Parents sign in with a one-time code and staff with a password, and the two
// never mix: hbh.verify_password refuses a GUARDIAN outright with
// NOT_PASSWORD_USER. Same shape as VerifyOTP, and for the same reason - the
// function returns a status instead of raising, so the failed-attempt counter
// it just incremented survives the call.
func (d *DB) VerifyPassword(ctx context.Context, username, password string) (OTPVerify, error) {
	var v OTPVerify
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT ok, reason, user_id, attempts_left FROM hbh.verify_password($1, $2)`,
			username, password).Scan(&v.OK, &v.Reason, &v.UserID, &v.AttemptsLeft)
	})
	if err != nil {
		return OTPVerify{}, fmt.Errorf("verify_password: %w", err)
	}
	return v, nil
}
