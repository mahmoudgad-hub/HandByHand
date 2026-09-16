package http

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestAnalyticsRange(t *testing.T) {
	for _, tc := range []struct {
		from, to string
		valid    bool
	}{
		{"2026-09-14", "2026-09-14", true},
		{"2026-02-29", "2026-03-01", false},
		{"2026-09-15", "2026-09-14", false},
		{"2025-01-01", "2026-01-02", false},
		{"", "2026-09-14", false},
	} {
		if validAnalyticsRange(tc.from, tc.to) != tc.valid {
			t.Errorf("range %s %s", tc.from, tc.to)
		}
	}
}

func TestAnalyticsRejectsInvalidQueryBeforeDB(t *testing.T) {
	s := &Server{}
	for _, query := range []string{"from=2026-09-15&to=2026-09-14", "from=2026-09-14&to=2026-09-14&offset=-1", "from=2026-09-14&to=2026-09-14&offset=no"} {
		w := httptest.NewRecorder()
		s.handleOpsAnalytics(w, httptest.NewRequest(http.MethodGet, "/api/v1/ops/analytics?"+query, nil))
		if w.Code != http.StatusBadRequest {
			t.Fatalf("status %d", w.Code)
		}
	}
}

func TestUsageRejectsUnsafePayload(t *testing.T) {
	s := &Server{}
	for _, body := range []string{
		`{"app":"portal","feature":"/children/42?name=private","kind":"page","action":"view"}`,
		`{"app":"portal","feature":"portal.nav.home","kind":"action","action":"view"}`,
		`{"app":"other","feature":"portal.nav.home","kind":"page","action":"view"}`,
	} {
		w := httptest.NewRecorder()
		s.handleUsageEvent(w, httptest.NewRequest(http.MethodPost, "/api/v1/usage-events", strings.NewReader(body)))
		if w.Code != http.StatusBadRequest {
			t.Fatalf("status %d", w.Code)
		}
	}
}
