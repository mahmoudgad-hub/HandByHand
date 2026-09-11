package store

import (
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
)

// The database raises its refusals with its own SQLSTATE class, HB0xx. Every
// one of them is a business rule that lives in PL/pgSQL, so the API's job is
// to recognise which rule fired - never to re-implement the check that would
// have fired it.
//
// The codes below are the ones a portal caller can actually provoke. Anything
// else that comes back is a genuine fault and becomes a 500 with the cause in
// the log: inventing a friendly answer for a rule this layer does not
// understand is how a real defect gets served as a polite refusal.
const (
	// Home programme
	ErrNoSuchActivity = "HB041" // no such activity, or not this caller's
	ErrAlreadyLogged  = "HB042" // that day is already recorded
	ErrNotGuardian    = "HB043" // may read the child, may not act for them

	// Live stream
	ErrLiveRefused     = "HB060" // not permitted to watch this session
	ErrLiveNotRunning  = "HB061" // no such session, or it is not in progress
	ErrGatewayUnusable = "HB063" // no gateway, or one that must not serve a family

	// Identity formats, from migration 0053. These name a FIELD rather
	// than a constraint, which is why they are recognised separately from
	// the check-violation family below: the rule is about a business value
	// the person typed, so the form can put the message beside the box
	// instead of floating it under the whole panel.
	ErrMobileFormat     = "HB170" // does not match sys_params.MOBILE_PATTERN
	ErrNationalIDFormat = "HB171" // not sys_params.NATIONAL_ID_LENGTH digits
	// From 0112. The digits are well formed but there is no country to
	// read them against - a national number for a country that is not in
	// hbh.country_dial_codes, or bare digits with neither a + nor a
	// leading 0, which are ambiguous between the two. It is about the
	// same field as HB170 and is answered the same way; it is a separate
	// code because "wrong shape" and "cannot tell which country" are
	// different things to fix.
	ErrMobileCountry = "HB173"
	// The parameter itself is missing. Not the caller's mistake - the
	// database has not been seeded - so this one stays a 500.
	ErrIdentityParamUnset = "HB172"

	// Standard SQLSTATEs a write can provoke with a well-formed but
	// unacceptable body. These are the caller's mistake, not the service's:
	// ck_req_appt, for instance, requires a RESCHEDULE to name the
	// appointment it wants moved. Answering 500 for one of these would blame
	// the server for a rule the client broke - and would hide, in a pile of
	// internal errors, the day something really did break.
	ErrCheckViolation      = "23514"
	ErrForeignKeyViolation = "23503"
)

// Code returns the SQLSTATE of a database error, or "".
func Code(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code
	}
	return ""
}

// IsCode reports whether err is the named database refusal.
func IsCode(err error, code string) bool { return Code(err) == code }

// ConstraintName returns the constraint a database error names, or "".
//
// It is read only to decide WHICH FIELD to blame. The name itself never
// leaves the service: it is a schema detail, and the caller gets the field it
// belongs to.
func ConstraintName(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.ConstraintName
	}
	return ""
}
