package http

import (
	"net/http"
	"testing"
)

// The schema and this map do not move in the same step, and this file is
// what stops that costing anything.
//
// WHAT WENT WRONG. businessRefusal ended with
//
//	if strings.HasPrefix(code, "HB0") { ... }
//
// which was true of every code the schema raised on the day it was
// written. The schema then grew HB100 through HB190, and eight live
// codes - the waiting list, the assessments, backup health - fell past
// the fallback into a 500. Each one was a business rule refusing
// deliberately, and each reached a screen as "an unexpected error
// occurred".
//
// Nothing noticed for a month, because nothing compared the two. An
// acceptance suite cannot catch it either: it can only exercise the
// codes some endpoint happens to provoke today, and six of the eight had
// no endpoint at all.
//
// SO THE TEST ASSERTS THE PROPERTY, NOT A LIST. A list of codes here
// would be a second copy of the schema's vocabulary, and it would go
// stale in exactly the way the thing it is guarding went stale. What is
// checked instead is the shape: ANY code in the HB family is known to
// this layer, whatever number the schema invents next.

// TestEveryHBCodeIsKnown is the guard the original fallback needed.
//
// It walks the whole HB space rather than a list somebody maintains: if
// the schema raises HB247 tomorrow, this already covers it.
func TestEveryHBCodeIsKnown(t *testing.T) {
	for n := 0; n <= 999; n++ {
		code := "HB" + pad3(n)
		status, clientCode, ok := businessRefusal(code)
		if !ok {
			t.Fatalf("%s is not known to businessRefusal - it would become a 500 "+
				"with 'an unexpected error occurred' on the screen, for a rule the "+
				"database refused on purpose", code)
		}
		if status < 400 {
			t.Fatalf("%s maps to %d, which is not a refusal at all", code, status)
		}
		if clientCode == "" {
			t.Fatalf("%s maps to status %d with no client code", code, status)
		}
	}
}

// TestNonHBCodesAreNotSwallowed is the other half, and it matters as much.
//
// A fallback wide enough to catch everything would turn a genuine fault -
// a constraint violation, a connection that died - into a polite 409
// REFUSED, and the defect would never be seen. Only the HB family is the
// schema speaking on purpose.
func TestNonHBCodesAreNotSwallowed(t *testing.T) {
	for _, code := range []string{"23505", "42501", "08006", "XX000", "", "HB", "hb100"} {
		if _, _, ok := businessRefusal(code); ok {
			t.Fatalf("%q was treated as a deliberate business refusal; a real fault "+
				"would be answered politely and never looked at", code)
		}
	}
}

// TestTheIdentityFamilyIsNotOneThing pins the three codes that were very
// nearly collapsed into one answer.
//
// The first draft of this map read `case "HB170", "HB171", "HB172":` and
// returned 500 for all three. Two of them are a person mistyping their
// own telephone number or national id - 400, with the field named - and
// only the third is this installation's sys_params being unset, which
// the caller can do nothing about.
//
// Had it shipped, a typo would have been answered "an unexpected error
// occurred" on every path outside the CRUD handler, and the person would
// have been told to report a bug about their own phone number.
func TestTheIdentityFamilyIsNotOneThing(t *testing.T) {
	for _, c := range []struct {
		code   string
		status int
	}{
		{"HB170", http.StatusBadRequest},          // the caller's mobile
		{"HB171", http.StatusBadRequest},          // the caller's national id
		{"HB172", http.StatusInternalServerError}, // our unseeded parameter
	} {
		status, _, ok := businessRefusal(c.code)
		if !ok || status != c.status {
			t.Errorf("%s -> %d (known=%v), want %d", c.code, status, ok, c.status)
		}
	}
}

// TestKnownCodesKeepTheirMeaning pins the handful whose exact answer the
// interface is written against, so a later edit to the map cannot move
// them quietly.
//
// These are the ones where the STATUS carries meaning the client acts on:
// a 409 says "your view is out of date", a 403 says "this is not yours to
// do". Getting one wrong sends somebody to the wrong person.
func TestKnownCodesKeepTheirMeaning(t *testing.T) {
	for _, c := range []struct {
		code   string
		status int
		client string
	}{
		{"HB100", http.StatusConflict, "ILLEGAL_TRANSITION"},
		{"HB102", http.StatusConflict, "ILLEGAL_TRANSITION"},
		{"HB110", http.StatusConflict, "ILLEGAL_TRANSITION"},
		{"HB112", http.StatusConflict, "ALREADY_PUBLISHED"},
		{"HB111", http.StatusForbidden, CodeForbidden},
		{"HB130", http.StatusForbidden, CodeForbidden},
		{"HB142", http.StatusConflict, "CONSENT_REQUIRED"},
		{"HB155", http.StatusConflict, "NOT_YOUR_OWN_ROLES"},
	} {
		status, client, ok := businessRefusal(c.code)
		if !ok || status != c.status || client != c.client {
			t.Errorf("%s -> %d %q, want %d %q", c.code, status, client, c.status, c.client)
		}
	}
}

func pad3(n int) string {
	d := []byte{'0' + byte(n/100), '0' + byte(n/10%10), '0' + byte(n%10)}
	return string(d)
}
