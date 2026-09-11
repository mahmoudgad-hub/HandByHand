package http

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/handbyhand/hbh/api/internal/config"
)

func TestGatewayURLJoinsBaseAndPath(t *testing.T) {
	u, err := gatewayURL("https://media.example.eg/live", "room1/main")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got := u.String(); got != "https://media.example.eg/live/room1/main" {
		t.Fatalf("got %q", got)
	}
}

// The base must be a real http(s) URL. Everything else is a misconfiguration
// that would otherwise become a confusing proxy failure at watch time.
func TestGatewayURLRefusesBadBase(t *testing.T) {
	for _, base := range []string{
		"",
		"   ",
		"rtsp://camera.local/stream", // an address, not a gateway
		"file:///etc/passwd",
		"/just/a/path",
		"https://", // no host
	} {
		if _, err := gatewayURL(base, "room1"); err == nil {
			t.Errorf("base %q was accepted", base)
		}
	}
}

// The database constrains gateway_path to ^[A-Za-z0-9_/-]{1,120}$, so none of
// these can be stored today. They are refused here anyway: that constraint
// protects one writer, and this function should not depend on being the only
// one there will ever be.
func TestGatewayURLRefusesOddPath(t *testing.T) {
	for _, path := range []string{
		"",
		"../../etc/passwd",
		"room1?token=x",
		"room1#frag",
		`room1\..\secret`,
	} {
		if _, err := gatewayURL("https://media.example.eg", path); err == nil {
			t.Errorf("path %q was accepted", path)
		}
	}
}

// The stream cookie is a live credential. Marking it Secure on a header the
// client itself wrote would let a caller decide it may travel in clear text.
func TestIsTLSIgnoresForwardedProtoUnlessTrusted(t *testing.T) {
	r := httptest.NewRequest(http.MethodGet, "/", nil)
	r.Header.Set("X-Forwarded-Proto", "https")

	untrusting := &Server{cfg: config.Config{TrustProxy: false}}
	if untrusting.isTLS(r) {
		t.Fatal("a client-written header was believed")
	}

	trusting := &Server{cfg: config.Config{TrustProxy: true}}
	if !trusting.isTLS(r) {
		t.Fatal("a declared proxy was not believed")
	}
}

// The playback path is a fixed string, identical for every viewer and every
// session. If it ever carried a session or a token, it would be in every proxy
// log and every browser history.
func TestPlaybackPathIdentifiesNothing(t *testing.T) {
	if playbackPath != "/api/v1/stream/media" {
		t.Fatalf("playback path changed to %q - it must stay constant", playbackPath)
	}
	for _, bad := range []string{"{", "}", "?", "="} {
		if strings.Contains(playbackPath, bad) {
			t.Fatalf("the playback path has become parameterised: %q", playbackPath)
		}
	}
}
