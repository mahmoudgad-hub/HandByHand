package store

import (
	"encoding/json"
	"testing"
	"time"
)

func TestEnrolmentAssessmentRequiresAnExplicitTimezone(t *testing.T) {
	for _, raw := range []string{"2026-01-15T11:30", "2026-01-15", "not-a-date"} {
		var in EnrolmentUpdate
		if err := json.Unmarshal([]byte(`{"status":"ASSESSMENT_BOOKED","assessment_at":"`+raw+`"}`), &in); err == nil {
			t.Fatalf("accepted ambiguous assessment time %q", raw)
		}
	}
	var in EnrolmentUpdate
	if err := json.Unmarshal([]byte(`{"status":"ASSESSMENT_BOOKED","assessment_at":"2026-01-15T11:30:00+02:00"}`), &in); err != nil {
		t.Fatal(err)
	}
	if in.AssessmentAt == nil || !in.AssessmentAt.Equal(time.Date(2026, 1, 15, 9, 30, 0, 0, time.UTC)) {
		t.Fatalf("lost the assessment instant: %v", in.AssessmentAt)
	}
}
