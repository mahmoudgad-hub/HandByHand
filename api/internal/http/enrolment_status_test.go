package http

import (
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestEnrolmentUpdateDateValidation(t *testing.T) {
	for _, tc := range []struct{ name, body, field string }{
		{"missing", `{"status":"ASSESSMENT_BOOKED"}`, "assessment_at"},
		{"null", `{"status":"ASSESSMENT_BOOKED","assessment_at":null}`, "assessment_at"},
		{"empty", `{"status":"ASSESSMENT_BOOKED","assessment_at":""}`, "assessment_at"},
		{"no zone", `{"status":"ASSESSMENT_BOOKED","assessment_at":"2026-09-15T10:00:00"}`, "assessment_at"},
		{"bad date", `{"status":"ASSESSMENT_BOOKED","assessment_at":"2026-02-30T10:00:00Z"}`, "assessment_at"},
		{"wrong type", `{"status":"ASSESSMENT_BOOKED","assessment_at":42}`, "assessment_at"},
		{"zero", `{"status":"ASSESSMENT_BOOKED","assessment_at":"0001-01-01T00:00:00Z"}`, "assessment_at"},
		{"unrelated date", `{"status":"CONTACTED","assessment_at":"2026-09-15T10:00:00Z"}`, "assessment_at"},
		{"unknown field", `{"status":"CONTACTED","unexpected":true}`, "body"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r := httptest.NewRequest("PATCH", "/", strings.NewReader(tc.body))
			_, fields := decodeEnrolmentUpdate(httptest.NewRecorder(), r)
			if fields[tc.field] == nil {
				t.Fatalf("want field %s, got %v", tc.field, fields)
			}
		})
	}
}

func TestEnrolmentUpdateAcceptsExplicitInstantAndLegacyContact(t *testing.T) {
	r := httptest.NewRequest("PATCH", "/", strings.NewReader(`{"status":"ASSESSMENT_BOOKED","assessment_at":"2026-09-15T10:00:00+03:00"}`))
	in, fields := decodeEnrolmentUpdate(httptest.NewRecorder(), r)
	if fields != nil || in.AssessmentAt == nil || !in.AssessmentAt.Equal(time.Date(2026, 9, 15, 7, 0, 0, 0, time.UTC)) || in.AssessmentAt.Location() != time.UTC {
		t.Fatalf("wrong instant: %+v, errors %v", in, fields)
	}
	r = httptest.NewRequest("PATCH", "/", strings.NewReader(`{"status":"CONTACTED","note_ar":"Called"}`))
	in, fields = decodeEnrolmentUpdate(httptest.NewRecorder(), r)
	if fields != nil || in.AssessmentAt != nil || in.NoteAr != "Called" {
		t.Fatalf("legacy update changed: %+v %v", in, fields)
	}
}

func TestEnrolmentMissingDateReturns400BeforeDatabase(t *testing.T) {
	r := httptest.NewRequest("PATCH", "/api/v1/enrolments/116", strings.NewReader(`{"status":"ASSESSMENT_BOOKED"}`))
	r.SetPathValue("application_id", "116")
	w := httptest.NewRecorder()
	// No database is configured: invalid input must never reach the store.
	(&Server{}).handleEnrolmentStatus(w, r)
	if w.Code != 400 || !strings.Contains(w.Body.String(), `"assessment_at"`) {
		t.Fatalf("unexpected response: %d %s", w.Code, w.Body.String())
	}
}
