package meeting

import (
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"strings"
	"testing"
	"time"
)

// testProvider builds a JaaS provider on a throwaway key.
//
// 2048 bits and generated per call: the key never leaves the test binary, and a
// fixture key checked into the repository is a key somebody eventually pastes
// into a deployment.
func testProvider(t *testing.T) (*JaaSProvider, *rsa.PrivateKey) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generating a key: %v", err)
	}
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		t.Fatalf("marshalling the key: %v", err)
	}
	block := pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der})

	p, err := NewJaaS(JaaSConfig{AppID: "vpaas-magic-cookie-abc", KeyID: "abc/def", PrivateKeyPEM: string(block)})
	if err != nil {
		t.Fatalf("building the provider: %v", err)
	}
	return p, key
}

func claimsOf(t *testing.T, token string) map[string]any {
	t.Helper()
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("a JWT has three segments, this has %d", len(parts))
	}
	raw, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		t.Fatalf("decoding the claims: %v", err)
	}
	var m map[string]any
	if err := json.Unmarshal(raw, &m); err != nil {
		t.Fatalf("parsing the claims: %v", err)
	}
	return m
}

func aGrant() Grant {
	return Grant{
		MeetingID:   7,
		RoomRef:     "0123456789abcdef0123456789abcdef",
		Provider:    ProviderJaaS,
		ExpiresAt:   time.Now().Add(15 * time.Minute),
		UserRef:     "935",
		DisplayName: "وليّ الأمر",
	}
}

// THE PERMANENT RULE, ASSERTED WHERE IT IS ENFORCED.
//
// "بث مباشر فقط - ولا تسجيل، أبدًا" is in CLAUDE.md and has nothing to do with
// storage. The provider is the one place that could break it, and the token is
// the only thing that tells the provider. A moderator who found the button
// would otherwise be one click from a clinical recording living outside every
// control in this system.
func TestTheTokenForbidsRecording(t *testing.T) {
	p, _ := testProvider(t)
	pass, err := p.Mint(aGrant())
	if err != nil {
		t.Fatalf("minting: %v", err)
	}

	ctx, _ := claimsOf(t, pass.Token)["context"].(map[string]any)
	features, _ := ctx["features"].(map[string]any)
	if features == nil {
		t.Fatal("the token carries no features block, so nothing is switched off")
	}
	for _, f := range []string{"recording", "livestreaming", "transcription"} {
		if features[f] != "false" {
			t.Fatalf("feature %q is %v, and it must be the string \"false\"", f, features[f])
		}
	}
}

// A GUARDIAN IS NEVER A MODERATOR, and the claim is a STRING.
//
// JaaS reads "moderator" as text. A real JSON boolean parses and is then
// ignored by the permission check - which is a guest who believes they are a
// host, and a host who is quietly a guest.
func TestModeratorIsAStringAndFollowsTheGrant(t *testing.T) {
	p, _ := testProvider(t)

	for _, moderator := range []bool{false, true} {
		g := aGrant()
		g.Moderator = moderator
		pass, err := p.Mint(g)
		if err != nil {
			t.Fatalf("minting: %v", err)
		}
		ctx, _ := claimsOf(t, pass.Token)["context"].(map[string]any)
		user, _ := ctx["user"].(map[string]any)

		want := "false"
		if moderator {
			want = "true"
		}
		got, ok := user["moderator"].(string)
		if !ok {
			t.Fatalf("moderator came out as %T, and JaaS reads a string", user["moderator"])
		}
		if got != want {
			t.Fatalf("moderator = %q, want %q", got, want)
		}
	}
}

// THE WINDOW IS THE DATABASE'S, NOT THIS PACKAGE'S. hbh.authorize_meeting_entry
// caps it at MEETING_TOKEN_TTL_MIN and never past the end of the consultation,
// with a CHECK on the row underneath. Recomputing it here would be a second
// opinion, and nothing can call a pass back once it is signed.
func TestTheExpiryIsTheGrantsOwn(t *testing.T) {
	p, _ := testProvider(t)
	g := aGrant()
	g.ExpiresAt = time.Now().Add(3 * time.Minute).Truncate(time.Second)

	pass, err := p.Mint(g)
	if err != nil {
		t.Fatalf("minting: %v", err)
	}
	claims := claimsOf(t, pass.Token)
	exp, ok := claims["exp"].(float64)
	if !ok {
		t.Fatalf("exp is %T", claims["exp"])
	}
	if int64(exp) != g.ExpiresAt.Unix() {
		t.Fatalf("exp = %d, want the grant's %d", int64(exp), g.ExpiresAt.Unix())
	}
}

// FAILS CLOSED. A zero time is not "no expiry"; it is 1970, and the arithmetic
// that would have produced a pass with no end is exactly the arithmetic worth
// refusing outright.
func TestMintRefusesAGrantWithNoFutureExpiry(t *testing.T) {
	p, _ := testProvider(t)

	for _, c := range []struct {
		name string
		g    Grant
	}{
		{"zero time", func() Grant { g := aGrant(); g.ExpiresAt = time.Time{}; return g }()},
		{"already past", func() Grant { g := aGrant(); g.ExpiresAt = time.Now().Add(-time.Second); return g }()},
		{"no room", func() Grant { g := aGrant(); g.RoomRef = ""; return g }()},
	} {
		if _, err := p.Mint(c.g); err == nil {
			t.Fatalf("%s was minted", c.name)
		}
	}
}

// The signature is real, and the test checks it the way the provider will:
// against the public half, over the first two segments.
func TestTheSignatureVerifies(t *testing.T) {
	p, key := testProvider(t)
	pass, err := p.Mint(aGrant())
	if err != nil {
		t.Fatalf("minting: %v", err)
	}

	parts := strings.Split(pass.Token, ".")
	sig, err := base64.RawURLEncoding.DecodeString(parts[2])
	if err != nil {
		t.Fatalf("decoding the signature: %v", err)
	}
	sum := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(&key.PublicKey, crypto.SHA256, sum[:], sig); err != nil {
		t.Fatalf("the signature does not verify: %v", err)
	}
}

// The room is namespaced under the tenant, and a name without it is a room at
// somebody else's.
func TestTheRoomIsNamespacedUnderTheTenant(t *testing.T) {
	p, _ := testProvider(t)
	pass, err := p.Mint(aGrant())
	if err != nil {
		t.Fatalf("minting: %v", err)
	}
	if pass.Room != "vpaas-magic-cookie-abc/0123456789abcdef0123456789abcdef" {
		t.Fatalf("room = %q", pass.Room)
	}
	if pass.Domain != "8x8.vc" {
		t.Fatalf("domain = %q", pass.Domain)
	}
}

// THE PRODUCTION FAIL-CLOSED RULE, the same shape as sms.DevSender's.
//
// The public instance has no tokens at all: the room name is the only
// credential and it never expires. This is the sender itself refusing, so the
// guarantee survives a future caller that builds one without going through
// config.Load.
func TestThePublicProviderIsRefusedInProduction(t *testing.T) {
	if err := (&PublicProvider{Env: "production"}).Usable(); err == nil {
		t.Fatal("meet.jit.si must not carry a family's consultation")
	}
	if _, err := (&PublicProvider{Env: "production"}).Mint(aGrant()); err == nil {
		t.Fatal("Mint must refuse too - Usable alone is a check somebody can skip")
	}
	if err := (&PublicProvider{Env: "development"}).Usable(); err != nil {
		t.Fatalf("it must be usable on a laptop: %v", err)
	}
}

// AND IT HANDS OUT NO TOKEN, which the handler must not read as a refusal.
func TestThePublicProviderMintsNoToken(t *testing.T) {
	pass, err := (&PublicProvider{Env: "development"}).Mint(aGrant())
	if err != nil {
		t.Fatalf("minting: %v", err)
	}
	if pass.Token != "" {
		t.Fatal("the public instance has no tokens; producing one would be pretending")
	}
	if pass.Domain != "meet.jit.si" || !strings.HasPrefix(pass.Room, "hbh-") {
		t.Fatalf("domain = %q room = %q", pass.Domain, pass.Room)
	}
}

// THE ONE THAT KEEPS THE EVIDENCE TABLE HONEST.
//
// hbh.meeting_tokens has a UNIQUE on the hash. With no token to hash, a naive
// fingerprint would hash the empty string - the first development entry would
// be recorded and every one after it would collide, on the provider where
// nothing else is watching either.
func TestFingerprintIsDistinctWhenThereIsNoToken(t *testing.T) {
	g := aGrant()
	pass := Pass{Domain: "meet.jit.si", Room: "hbh-" + g.RoomRef}

	first := Fingerprint(pass, g, time.Unix(1, 0))
	second := Fingerprint(pass, g, time.Unix(2, 0))
	if string(first) == string(second) {
		t.Fatal("two passes for the same room hash the same, so the second is never recorded")
	}
	if len(first) != 32 {
		t.Fatalf("hash is %d bytes; record_meeting_token wants at least 16", len(first))
	}
}

// And with a token it is the TOKEN that is hashed, not the occasion - so the
// same pass produced later is recognisable, which is the only thing this
// column is for. It must therefore NOT depend on the instant.
func TestFingerprintHashesTheTokenWhenThereIsOne(t *testing.T) {
	p, _ := testProvider(t)
	g := aGrant()
	pass, err := p.Mint(g)
	if err != nil {
		t.Fatalf("minting: %v", err)
	}

	at := time.Now()
	if string(Fingerprint(pass, g, at)) != string(Fingerprint(pass, g, at.Add(time.Hour))) {
		t.Fatal("the same pass hashed two ways an hour apart - it could never be recognised again")
	}

	// And the pass itself is not in the hash material in any recoverable
	// form: the stored bytes are a digest, not the credential.
	if strings.Contains(string(Fingerprint(pass, g, at)), pass.Token[:16]) {
		t.Fatal("the token is recoverable from what is stored")
	}
}

func TestNewRefusesAnUnknownProvider(t *testing.T) {
	if _, err := New("ZOOM", "development", JaaSConfig{}); err == nil {
		t.Fatal("an unknown provider must fail at startup, not at a family's first attempt")
	}
	if _, err := New("JITSI_JAAS", "production", JaaSConfig{}); err == nil {
		t.Fatal("JaaS with no account must fail at startup")
	}
	if _, err := New("", "development", JaaSConfig{}); err != nil {
		t.Fatalf("the empty default should build the development provider: %v", err)
	}
}

func TestNewJaaSRefusesAKeyItCannotUse(t *testing.T) {
	full := JaaSConfig{AppID: "a", KeyID: "b", PrivateKeyPEM: "-----BEGIN PRIVATE KEY-----\nbm90IGEga2V5\n-----END PRIVATE KEY-----\n"}
	if _, err := NewJaaS(full); err == nil {
		t.Fatal("a PEM block that is not a key built a provider")
	}
	if _, err := NewJaaS(JaaSConfig{AppID: "a", KeyID: "b", PrivateKeyPEM: "not pem at all"}); err == nil {
		t.Fatal("a non-PEM string built a provider")
	}
}
