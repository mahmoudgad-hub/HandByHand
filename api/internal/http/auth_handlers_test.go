package http

import (
	"net/http"
	"net/http/httptest"
	"net/netip"
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

// loopbackTrust is what config.Load produces for TRUST_PROXY=true with no
// TRUSTED_PROXIES set: nginx talks to this service over loopback.
func loopbackTrust() []netip.Prefix {
	return []netip.Prefix{
		netip.MustParsePrefix("127.0.0.0/8"),
		netip.MustParsePrefix("::1/128"),
	}
}

// X-Forwarded-For reaches the audit log as the client address, and is the
// rate limiter's bucket key. Believed without a proxy in front, it lets a
// caller write their own audit trail and rotate past the limiter.
//
// THIS TEST ASSERTED THE OPPOSITE UNTIL HBH-005, and it was the test that
// was wrong, not the code it passed against: it set a peer of 10.0.0.9 - no
// proxy of ours - and required the forwarded value to be believed merely
// because the flag was on. It encoded "trust the header from anyone", which
// is the defect the card's fourth criterion names.
func TestClientIPBelievesForwardedOnlyFromATrustedPeer(t *testing.T) {
	newReq := func(peer, fwd string) *http.Request {
		r := httptest.NewRequest(http.MethodGet, "/", nil)
		r.RemoteAddr = peer
		r.Header.Set("X-Forwarded-For", fwd)
		return r
	}

	// The flag off: the header is inert whoever sends it.
	untrusting := &Server{cfg: config.Config{TrustProxy: false}}
	if ip := untrusting.clientIP(newReq("127.0.0.1:5555", "203.0.113.7")); ip == nil || *ip != "127.0.0.1" {
		t.Fatalf("flag off: got %v, want the socket address", derefOr(ip))
	}

	// The flag on and the peer IS the proxy: believed.
	trusting := &Server{cfg: config.Config{
		TrustProxy: true, TrustedProxies: loopbackTrust(),
	}}
	if ip := trusting.clientIP(newReq("127.0.0.1:5555", "203.0.113.7")); ip == nil || *ip != "203.0.113.7" {
		t.Fatalf("via proxy: got %v, want the forwarded address", derefOr(ip))
	}

	// The flag on and the peer is NOT the proxy - a direct caller carrying a
	// header it wrote itself. The card's fourth criterion.
	if ip := trusting.clientIP(newReq("10.0.0.9:5555", "203.0.113.7")); ip == nil || *ip != "10.0.0.9" {
		t.Fatalf("forged by a direct caller: got %v, want the socket address", derefOr(ip))
	}
}

// The half that every other check passes through.
//
// nginx sets the header with $proxy_add_x_forwarded_for, which APPENDS the
// peer it saw to whatever arrived. A caller who sends "X-Forwarded-For:
// 1.2.3.4" therefore reaches the service as "1.2.3.4, <their real address>":
// flag on, peer genuinely the proxy, header genuinely written by nginx - and
// the first entry is still the caller's own claim.
func TestClientIPTakesTheEntryTheProxyAppended(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "127.0.0.1:5555"
	r.Header.Set("X-Forwarded-For", "1.2.3.4, 198.51.100.22")

	s := &Server{cfg: config.Config{TrustProxy: true, TrustedProxies: loopbackTrust()}}
	if ip := s.clientIP(r); ip == nil || *ip != "198.51.100.22" {
		t.Fatalf("got %v, want the rightmost entry (the one nginx wrote)", derefOr(ip))
	}
}

// A trust list that names nobody trusts nobody. TRUST_PROXY=true with an
// empty TRUSTED_PROXIES must not read as "trust everything" - the one
// direction this schema never fails in.
func TestClientIPWithNoTrustedProxiesBelievesNobody(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "127.0.0.1:5555"
	r.Header.Set("X-Forwarded-For", "203.0.113.7")

	s := &Server{cfg: config.Config{TrustProxy: true}}
	if ip := s.clientIP(r); ip == nil || *ip != "127.0.0.1" {
		t.Fatalf("got %v, want the socket address", derefOr(ip))
	}
}

// A forged header must not become a null-shaped hole in the audit row either:
// an unparseable value falls back to the socket.
// THE PEER HERE IS THE PROXY, deliberately. With an untrusted peer this
// check passes without ever reaching the parsing it claims to test - the
// header is discarded for being unsigned, not for being garbage - and a
// refusal for the wrong reason proves nothing.
func TestClientIPRejectsGarbageForwardedValue(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.RemoteAddr = "127.0.0.1:5555"
	r.Header.Set("X-Forwarded-For", "not-an-address")

	s := &Server{cfg: config.Config{TrustProxy: true, TrustedProxies: loopbackTrust()}}
	if ip := s.clientIP(r); ip == nil || *ip != "127.0.0.1" {
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
