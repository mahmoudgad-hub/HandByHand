package http

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/handbyhand/hbh/api/internal/config"
	"github.com/handbyhand/hbh/api/internal/store"
)

func TestMaskMobileKeepsFourDigits(t *testing.T) {
	got := maskMobile("01012345678")
	if got != "mobile:****5678" {
		t.Fatalf("got %q", got)
	}
	if strings.Contains(got, "0101234") {
		t.Fatalf("the number survived masking: %q", got)
	}
	if maskMobile("123") != "mobile:****" {
		t.Fatalf("a short value leaked: %q", maskMobile("123"))
	}
}

// A locked account must not be told to retry. 401 invites another attempt;
// 423 says the door is shut until somebody opens it.
func TestVerifyFailureStatuses(t *testing.T) {
	cases := []struct {
		reason string
		status int
		code   string
	}{
		{store.ReasonWrongCode, http.StatusUnauthorized, "WRONG_CODE"},
		{store.ReasonExpired, http.StatusUnauthorized, "EXPIRED"},
		{store.ReasonNoPendingCode, http.StatusUnauthorized, "NO_PENDING_CODE"},
		{store.ReasonTooManyAttempts, http.StatusLocked, "TOO_MANY_ATTEMPTS"},
		{store.ReasonUserLocked, http.StatusLocked, "USER_LOCKED"},
		{"SOMETHING_NEW", http.StatusUnauthorized, CodeUnauthenticated},
	}
	for _, c := range cases {
		status, code := verifyFailure(c.reason)
		if status != c.status || code != c.code {
			t.Errorf("%s: got %d/%s, want %d/%s", c.reason, status, code, c.status, c.code)
		}
	}
}

// NOT_REGISTERED must have no mapping at all. If one is ever added, this test
// is the thing that notices: the login screen would start answering "is this
// person a customer of yours?" for anyone who asked.
func TestNotRegisteredHasNoClientMapping(t *testing.T) {
	_, code := verifyFailure(store.ReasonNotRegistered)
	if code != CodeUnauthenticated {
		t.Fatalf("NOT_REGISTERED leaked to the client as %q", code)
	}
}

func TestBearerTokenParsing(t *testing.T) {
	cases := map[string]string{
		"Bearer abc123":  "abc123",
		"bearer abc123":  "abc123",
		"Bearer  abc123": "abc123",
		"Basic abc123":   "",
		"abc123":         "",
		"":               "",
		"Bearer ":        "",
	}
	for header, want := range cases {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		if header != "" {
			r.Header.Set("Authorization", header)
		}
		if got := bearerToken(r); got != want {
			t.Errorf("%q: got %q, want %q", header, got, want)
		}
	}
}

// X-Forwarded-For reaches the audit log as the client address. Believed
// without a proxy in front, it lets a caller write their own audit trail.
func TestClientIPIgnoresForwardedHeaderUnlessTrusted(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "10.0.0.9:5555"
	r.Header.Set("X-Forwarded-For", "203.0.113.7")

	untrusting := &Server{cfg: config.Config{TrustProxy: false}}
	if ip := untrusting.clientIP(r); ip == nil || *ip != "10.0.0.9" {
		t.Fatalf("got %v, want the socket address", derefOr(ip))
	}

	trusting := &Server{cfg: config.Config{TrustProxy: true}}
	if ip := trusting.clientIP(r); ip == nil || *ip != "203.0.113.7" {
		t.Fatalf("got %v, want the forwarded address", derefOr(ip))
	}
}

// A forged header must not become a null-shaped hole in the audit row either:
// an unparseable value falls back to the socket.
func TestClientIPRejectsGarbageForwardedValue(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "10.0.0.9:5555"
	r.Header.Set("X-Forwarded-For", "not-an-address")

	s := &Server{cfg: config.Config{TrustProxy: true}}
	if ip := s.clientIP(r); ip == nil || *ip != "10.0.0.9" {
		t.Fatalf("got %v, want the socket address", derefOr(ip))
	}
}

func derefOr(s *string) string {
	if s == nil {
		return "<nil>"
	}
	return *s
}

func TestIsDigits(t *testing.T) {
	for _, ok := range []string{"0", "123456"} {
		if !isDigits(ok) {
			t.Errorf("%q was refused", ok)
		}
	}
	// Arabic-Indic digits are not ASCII digits. The screen may show ٦٥٤٣٢١;
	// what arrives on the wire is normalised by the client.
	for _, bad := range []string{"12a", "12 3", "١٢٣", "-1", ""} {
		if bad != "" && isDigits(bad) {
			t.Errorf("%q was accepted", bad)
		}
	}
}
