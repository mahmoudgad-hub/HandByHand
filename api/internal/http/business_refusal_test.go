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

// TestTheCatchAllIsNotTheAnswerForALiveFamily pins the twenty-one codes
// that the widened "HB" fallback was quietly swallowing.
//
// WHAT THE FIRST FIX MISSED. Widening the fallback from "HB0" to "HB"
// stopped live refusals becoming 500s, and that was right. It also made
// the next failure invisible: twenty-one codes the schema raises today -
// HB001 through HB231, scattered through ranges this map believed it
// covered - matched the catch-all and were answered 409 REFUSED. A
// caller lacking GUARDIAN.MANAGE was told their request conflicted with
// something. Our own unseeded number series was reported as the caller's
// conflict. The live-viewing consent gate, the rule that keeps a camera
// shut to somebody who never agreed to it, answered with a word the
// screen cannot act on.
//
// TestEveryHBCodeIsKnown above cannot see any of this, and that is not a
// flaw in it: the catch-all genuinely does answer, so "is it known" is
// true. The question it does not ask is "is it known BY NAME", and the
// only authority on which names are live is the database. That check is
// `bash scripts/api.sh code-drift`, which reads pg_proc.
//
// What lives here is the half that needs no database: once a code has
// been given a meaning, nothing may move it back to the generic answer.
func TestTheCatchAllIsNotTheAnswerForALiveFamily(t *testing.T) {
	for _, c := range []struct {
		code   string
		status int
		client string
	}{
		// Ours, not the caller's. These must be logged, not filed as a
		// conflict the caller could resolve.
		{"HB001", http.StatusInternalServerError, CodeInternal},
		{"HB010", http.StatusInternalServerError, CodeInternal},
		{"HB012", http.StatusInternalServerError, CodeInternal},
		{"HB220", http.StatusInternalServerError, CodeInternal},
		{"HB230", http.StatusInternalServerError, CodeInternal},
		{"HB231", http.StatusInternalServerError, CodeInternal},

		// Permission. A missing grant is never a conflict.
		{"HB011", http.StatusForbidden, CodeForbidden},
		{"HB200", http.StatusForbidden, CodeForbidden},

		// The schema refuses to say whether the row is gone or not
		// yours, and neither does this layer.
		{"HB041", http.StatusNotFound, CodeNotFound},
		{"HB073", http.StatusNotFound, CodeNotFound},
		{"HB082", http.StatusNotFound, CodeNotFound},
		{"HB094", http.StatusNotFound, CodeNotFound},
		{"HB201", http.StatusNotFound, CodeNotFound},

		// The caller's input, with a field to name.
		{"HB072", http.StatusBadRequest, CodeValidation},
		{"HB080", http.StatusBadRequest, CodeValidation},
		{"HB113", http.StatusBadRequest, CodeValidation},
		{"HB173", http.StatusBadRequest, CodeValidation},

		// Conflicts that are genuinely conflicts - and each says which.
		{"HB042", http.StatusConflict, CodeAlreadyLogged},
		{"HB071", http.StatusConflict, "NOT_A_PASSWORD_USER"},
		{"HB081", http.StatusConflict, "CONSENT_REQUIRED"},
		{"HB203", http.StatusConflict, "TEXT_LOCKED"},
	} {
		status, client, ok := businessRefusal(c.code)
		if !ok || status != c.status || client != c.client {
			t.Errorf("%s -> %d %q, want %d %q", c.code, status, client, c.status, c.client)
		}
		if client == "REFUSED" {
			t.Errorf("%s fell back to the catch-all", c.code)
		}
	}
}

// TestAChangedDraftIsNotAClosedOne pins HB290 (0141, #14). Answered as
// ALREADY_PUBLISHED, the editor would tell a clinician the report is
// closed when a colleague merely saved it - and stop offering the newer
// text. Answered by the catch-all, the screen cannot act at all.
func TestAChangedDraftIsNotAClosedOne(t *testing.T) {
	status, client, ok := businessRefusal("HB290")
	if !ok || status != http.StatusConflict || client != "REPORT_CHANGED" {
		t.Errorf("HB290 -> %d %q, want 409 REPORT_CHANGED", status, client)
	}
	if _, published, _ := businessRefusal("HB033"); published == client {
		t.Errorf("HB290 and HB033 both answer %q", client)
	}
}

// TestPricesAndOriginsAreNamed pins the codes from 0129-0138 to the
// owner's pricing contract of 2026-09-12, and the two splits in it.
//
// HB258 used to mean both "no BILLING.PRICE_OVERRIDE" and "an override on
// a line with no service"; HB260 meant "no BILLING.PRICE_EDIT", "not this
// centre's service" and "unknown price kind". One code, answers the screen
// must handle differently - so the codes split away are asserted to land
// in DIFFERENT statuses from the permission they left. A later edit that
// folds them back into one case fails here, not on a receptionist's
// screen. ("Not this centre's service" left for HB051, which is pinned
// with the rest of the invoice codes.)
func TestPricesAndOriginsAreNamed(t *testing.T) {
	for _, c := range []struct {
		code   string
		status int
		client string
	}{
		{"HB241", http.StatusConflict, "ORIGIN_LOCKED"},
		{"HB254", http.StatusInternalServerError, CodeInternal},
		{"HB255", http.StatusForbidden, CodeForbidden},
		{"HB256", http.StatusBadRequest, CodeValidation},
		{"HB257", http.StatusConflict, "NO_EFFECTIVE_CATALOGUE_PRICE"},
		{"HB258", http.StatusForbidden, "PRICE_OVERRIDE_FORBIDDEN"},
		{"HB259", http.StatusConflict, "BILLING_MODEL_DISALLOWS_CHARGE"},
		{"HB260", http.StatusForbidden, "PRICE_MANAGEMENT_FORBIDDEN"},
		{"HB261", http.StatusConflict, "MOBILE_HELD_BY_GUARDIAN"},
		{"HB262", http.StatusUnprocessableEntity, CodeValidation},
		{"HB264", http.StatusBadRequest, CodeValidation},
	} {
		status, client, ok := businessRefusal(c.code)
		if !ok || status != c.status || client != c.client {
			t.Errorf("%s -> %d %q, want %d %q", c.code, status, client, c.status, c.client)
		}
		if client == "REFUSED" {
			t.Errorf("%s fell back to the catch-all", c.code)
		}
	}

	for _, split := range []struct{ was, now string }{
		{"HB258", "HB262"}, // permission / an override with no service
		{"HB260", "HB264"}, // permission / not a price kind
		{"HB260", "HB051"}, // permission / not this centre's service
	} {
		a, _, _ := businessRefusal(split.was)
		b, _, _ := businessRefusal(split.now)
		if a == b {
			t.Errorf("%s and %s both answer %d - the split has been folded back", split.was, split.now, a)
		}
	}
}

// TestTheHB2xxFamilyIsNotOneThing is the HB1xx test one family later.
//
// Six codes share the HB2xx prefix and mean four different things: a
// missing permission, a row that is not there, a locked row, and three
// assertions that can only mean this service called a function wrongly.
// Answering all six alike - which the catch-all did - is the same defect
// as HB101 meaning four things at once, and it is worth its own test
// because the pressure to add `case "HB2"` will come back.
func TestTheHB2xxFamilyIsNotOneThing(t *testing.T) {
	seen := map[int]bool{}
	for _, code := range []string{"HB200", "HB201", "HB203", "HB220"} {
		status, _, ok := businessRefusal(code)
		if !ok {
			t.Fatalf("%s unknown", code)
		}
		seen[status] = true
	}
	if len(seen) != 4 {
		t.Errorf("HB200/HB201/HB203/HB220 collapsed to %d distinct statuses, want 4: %v", len(seen), seen)
	}
}

// TestPaymentPlansAreNamed pins the nine codes 0142 introduces, named in
// the API before the migration raises any of them.
//
// Three families, and the test asserts they stay three: a plan or invoice
// in the wrong STATE (409), a well-formed request whose COMBINATION is
// refused (422), and HB269 - an instalment written off its state machine,
// which no request body can reach and so is our defect (500). Folding the
// 422s into 409 would tell a clerk to refresh a screen when the schedule
// they typed does not add up.
func TestPaymentPlansAreNamed(t *testing.T) {
	for _, c := range []struct {
		code   string
		status int
		client string
	}{
		{"HB265", http.StatusConflict, "PAYMENT_PLAN_TRANSITION"},
		{"HB266", http.StatusConflict, "PAYMENT_PLAN_STATE"},
		{"HB267", http.StatusUnprocessableEntity, "PAYMENT_PLAN_INCOMPLETE"},
		{"HB268", http.StatusUnprocessableEntity, "SCHEDULE_EXCEEDS_TOTAL"},
		{"HB269", http.StatusInternalServerError, CodeInternal},
		{"HB270", http.StatusForbidden, "SCHEDULE_OVERRIDE_FORBIDDEN"},
		{"HB271", http.StatusUnprocessableEntity, "OVERRIDE_REASON_REQUIRED"},
		{"HB272", http.StatusUnprocessableEntity, "SCHEDULE_TOTAL_MISMATCH"},
		{"HB273", http.StatusBadRequest, CodeValidation},
	} {
		status, client, ok := businessRefusal(c.code)
		if !ok || status != c.status || client != c.client {
			t.Errorf("%s -> %d %q, want %d %q", c.code, status, client, c.status, c.client)
		}
		if client == "REFUSED" {
			t.Errorf("%s fell back to the catch-all", c.code)
		}
	}

	families := map[int]bool{}
	for _, code := range []string{"HB266", "HB272", "HB269"} {
		s, _, _ := businessRefusal(code)
		families[s] = true
	}
	if len(families) != 3 {
		t.Errorf("state / combination / our defect collapsed to %d statuses, want 3", len(families))
	}
}
