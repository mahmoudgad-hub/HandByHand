package http

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func win(t *testing.T, query string) (w windowResult) {
	t.Helper()
	r := httptest.NewRequest(http.MethodGet, "/x?"+query, nil)
	got, ok := window(r)
	return windowResult{got.From, got.To, got.Limit, ok}
}

type windowResult struct {
	from  *string
	to    *string
	limit int
	ok    bool
}

func TestWindowDefaults(t *testing.T) {
	got := win(t, "")
	if !got.ok {
		t.Fatal("an empty query was refused")
	}
	if got.from != nil || got.to != nil {
		t.Fatal("an empty query invented a bound")
	}
	if got.limit != defaultLimit {
		t.Fatalf("limit %d, want %d", got.limit, defaultLimit)
	}
}

// A bare date is refused rather than guessed at. Accepting "2026-09-03" would
// force this layer to decide whether it meant midnight in Cairo or midnight in
// UTC - two hours apart, and a business rule either way.
func TestWindowRefusesBareDate(t *testing.T) {
	if win(t, "from=2026-09-03").ok {
		t.Fatal("a bare date was accepted as an instant")
	}
}

func TestWindowAcceptsInstants(t *testing.T) {
	got := win(t, "from=2026-09-01T00:00:00Z&to=2026-10-01T00:00:00%2B03:00")
	if !got.ok {
		t.Fatal("valid RFC 3339 instants were refused")
	}
	if got.from == nil || got.to == nil {
		t.Fatal("the bounds were dropped")
	}
}

func TestWindowLimitBounds(t *testing.T) {
	for _, bad := range []string{"limit=0", "limit=-1", "limit=abc", "limit=501"} {
		if win(t, bad).ok {
			t.Errorf("%q was accepted", bad)
		}
	}
	got := win(t, "limit=50")
	if !got.ok || got.limit != 50 {
		t.Fatalf("limit=50 gave %d (ok=%v)", got.limit, got.ok)
	}
}
