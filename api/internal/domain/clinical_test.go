package domain

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

// A day must serialise as a day. Rendering a birth date as an instant is how a
// client in Cairo reads 2020-03-15T00:00:00Z back as local time and shows the
// 14th - the same two-hour class of defect D-5 exists to remove.
func TestDateMarshalsAsCalendarDay(t *testing.T) {
	var d Date
	if err := d.Scan(time.Date(2020, 3, 15, 0, 0, 0, 0, time.UTC)); err != nil {
		t.Fatalf("Scan: %v", err)
	}
	b, err := json.Marshal(d)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if string(b) != `"2020-03-15"` {
		t.Fatalf("got %s, want \"2020-03-15\"", b)
	}
}

func TestDateNullMarshalsAsNull(t *testing.T) {
	var d Date
	if err := d.Scan(nil); err != nil {
		t.Fatalf("Scan(nil): %v", err)
	}
	if d.Valid {
		t.Fatal("a NULL date reported itself valid")
	}
	b, err := json.Marshal(d)
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if string(b) != "null" {
		t.Fatalf("got %s, want null", b)
	}
}

func TestDateRefusesWrongType(t *testing.T) {
	var d Date
	if err := d.Scan("2020-03-15"); err == nil {
		t.Fatal("a string was scanned into a Date without complaint")
	}
}

// An empty plan must serialise its goals as [] and not null, so a client
// testing "no goals" and a client testing "field missing" cannot disagree.
func TestPlanGoalsAreAlwaysAnArray(t *testing.T) {
	b, err := json.Marshal(Plan{Goals: []Goal{}})
	if err != nil {
		t.Fatalf("Marshal: %v", err)
	}
	if !strings.Contains(string(b), `"goals":[]`) {
		t.Fatalf("got %s", b)
	}
}
