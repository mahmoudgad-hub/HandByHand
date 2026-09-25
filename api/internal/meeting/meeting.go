// Package meeting is the boundary between this service and whatever company
// carries the video for an online consultation.
//
// WHAT IS IN HERE AND WHAT IS DELIBERATELY NOT.
//
// In here: how to turn a decision the database already made into the two or
// three strings a browser needs to open a room. That is transport.
//
// NOT in here: whether this person may enter, whose appointment it is, whether
// it was paid for, or when the door opens. Every one of those is
// hbh.authorize_meeting_entry, in PL/pgSQL, and this package cannot reach any
// of them - it is handed a Grant and it signs it. Rule 2 of this project, and
// the reason nothing below knows what a child is.
//
// AND NOT: a way to mint a pass for an arbitrary room. Mint takes a Grant, and
// the only thing that builds one is the store method that calls the database.
// There is no exported way to say "give me a token for room X" - that would be
// a second door beside the one with all the checks on it.
//
// WHY THE TOKEN REACHES THE BROWSER AT ALL, when the live-stream path is so
// careful that it does not: a stream is HTTP and can be proxied, so
// live_handlers.go keeps the credential in an HttpOnly cookie and relays the
// bytes. Real-time media is not HTTP. The family's browser negotiates directly
// with the provider, so it must authenticate directly, and there is nothing to
// proxy. Migration 0120 carries the full decision and the owner's part in it.
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
	"errors"
	"fmt"
	"strings"
	"time"
)

// Provider codes, as hbh.meetings.provider stores them.
const (
	ProviderJaaS   = "JITSI_JAAS"
	ProviderPublic = "JITSI_PUBLIC"
)

// Grant is what hbh.authorize_meeting_entry decided, plus who is joining.
//
// Every field comes from the database or from the authenticated session. None
// of it is taken from the request body: a caller who could name the room would
// not need the door.
type Grant struct {
	MeetingID int64
	RoomRef   string
	Provider  string
	Moderator bool
	ExpiresAt time.Time

	// UserRef identifies the joiner to the provider so two tabs are one
	// person. It is the account id as a string and nothing else - not a
	// mobile, not a national id, not anything that means something outside
	// this system.
	UserRef string

	// DisplayName is shown in the provider's waiting room, and it exists
	// because of the rule that the therapist admits people BY NAME. It is
	// the adult's own name. The child is never named to the provider: the
	// consultation is about them and they are not in it.
	DisplayName string
}

// Pass is the whole answer a browser gets.
type Pass struct {
	// Domain is the host the embedded client loads from, so the page does
	// not carry it as a constant and a change of provider is a change of
	// row rather than a release.
	Domain string
	// Room is the name AT THE PROVIDER, which is not always the room_ref:
	// JaaS namespaces every room under the application id.
	Room string
	// Token is empty for a provider that has none. A caller must not read
	// "" as "not allowed" - the Grant is what says allowed.
	Token string
}

// Provider mints one pass for one grant.
//
// It is one method on purpose. Recording, transcription, dial-in and the rest
// are things providers sell; this centre does not use them, and one of them -
// recording - is refused permanently by CLAUDE.md. Every method added here is
// a method the next provider has to answer and a reason it does not fit.
type Provider interface {
	Mint(g Grant) (Pass, error)
	// Code names this provider in hbh.meetings.provider.
	Code() string
	// Usable reports whether this provider can mint at all, asked at
	// startup rather than at a family's first attempt.
	Usable() error
}

// New builds the provider named by the environment.
func New(provider, env string, jaas JaaSConfig) (Provider, error) {
	switch strings.ToUpper(strings.TrimSpace(provider)) {
	case "", ProviderPublic:
		return &PublicProvider{Env: env}, nil
	case ProviderJaaS:
		return NewJaaS(jaas)
	default:
		return nil, fmt.Errorf("MEETING_PROVIDER %q is not one of %s, %s",
			provider, ProviderPublic, ProviderJaaS)
	}
}

// =====================================================================
// The development provider
// =====================================================================

// PublicProvider is meet.jit.si, and it has no tokens at all.
//
// THE ROOM NAME IS THE ONLY CREDENTIAL. Anybody who learns it can walk in, and
// nothing expires. That is survivable on a laptop with fixture data and it is
// not survivable for a family's consultation, so Usable refuses outside
// development - the same fail-closed shape as sms.DevSender, and for the same
// reason: the guarantee has to survive somebody building this without going
// through config.Load.
type PublicProvider struct{ Env string }

func (p *PublicProvider) Code() string { return ProviderPublic }

func (p *PublicProvider) Usable() error {
	if strings.EqualFold(strings.TrimSpace(p.Env), "production") {
		return errors.New("MEETING_PROVIDER=JITSI_PUBLIC has no access control at all: " +
			"the room name is the only credential, it never expires, and anyone " +
			"who is forwarded it can join a family's consultation")
	}
	return nil
}

func (p *PublicProvider) Mint(g Grant) (Pass, error) {
	if err := p.Usable(); err != nil {
		return Pass{}, err
	}
	if g.RoomRef == "" {
		return Pass{}, errors.New("the grant names no room")
	}
	// Prefixed so a name that escapes is recognisable as ours in a support
	// conversation. It adds nothing to the security of it, and pretending
	// otherwise is how a development shortcut ends up in production.
	return Pass{Domain: "meet.jit.si", Room: "hbh-" + g.RoomRef}, nil
}

// =====================================================================
// JaaS
// =====================================================================

// JaaSConfig is the account. Every field is a secret or an address, and none of
// them is written to the database, to a log, or to an error detail.
type JaaSConfig struct {
	// AppID is the tenant, shown in the JaaS console as the App ID.
	AppID string
	// KeyID is the identifier of the key pair, which travels in the JWT
	// header so the provider knows which public key to check against.
	KeyID string
	// PrivateKeyPEM is the RSA private key, in PEM. It is read from the
	// environment and never leaves this process.
	PrivateKeyPEM string
}

// JaaSProvider mints an RS256 JWT for one room and one person.
type JaaSProvider struct {
	appID string
	keyID string
	key   *rsa.PrivateKey
}

// NewJaaS parses the key once, at startup.
//
// A key that cannot be parsed is a deployment that cannot hold a consultation,
// and the place to find that out is the first second of the process rather
// than the moment a parent presses a button.
func NewJaaS(cfg JaaSConfig) (*JaaSProvider, error) {
	appID := strings.TrimSpace(cfg.AppID)
	keyID := strings.TrimSpace(cfg.KeyID)
	if appID == "" || keyID == "" {
		return nil, errors.New("MEETING_JAAS_APP_ID and MEETING_JAAS_KEY_ID are both required")
	}
	if strings.TrimSpace(cfg.PrivateKeyPEM) == "" {
		return nil, errors.New("MEETING_JAAS_PRIVATE_KEY is required")
	}

	block, _ := pem.Decode([]byte(cfg.PrivateKeyPEM))
	if block == nil {
		return nil, errors.New("MEETING_JAAS_PRIVATE_KEY is not PEM")
	}

	// Both encodings are accepted because both are handed out: the console
	// gives PKCS#8 ("BEGIN PRIVATE KEY") and older tooling gives PKCS#1
	// ("BEGIN RSA PRIVATE KEY"). Refusing one of them would be a startup
	// failure whose message says nothing about what to do.
	var key *rsa.PrivateKey
	switch {
	case block.Type == "RSA PRIVATE KEY":
		k, err := x509.ParsePKCS1PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("MEETING_JAAS_PRIVATE_KEY is not a usable RSA key: %w", err)
		}
		key = k
	default:
		any, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return nil, fmt.Errorf("MEETING_JAAS_PRIVATE_KEY is not a usable key: %w", err)
		}
		k, ok := any.(*rsa.PrivateKey)
		if !ok {
			return nil, fmt.Errorf("MEETING_JAAS_PRIVATE_KEY is %T, and JaaS signs with RSA", any)
		}
		key = k
	}

	return &JaaSProvider{appID: appID, keyID: keyID, key: key}, nil
}

func (p *JaaSProvider) Code() string { return ProviderJaaS }

func (p *JaaSProvider) Usable() error {
	if p == nil || p.key == nil {
		return errors.New("the JaaS signing key is not loaded")
	}
	return nil
}

// Mint signs the pass.
//
// THE WINDOW IS THE GRANT'S, NOT A CONSTANT HERE. The database decided when
// this pass dies - never past the end of the consultation, and never more than
// MEETING_TOKEN_TTL_MIN, which is a CHECK on the row rather than an argument.
// Recomputing it here would be a second opinion, and the weaker one would win.
func (p *JaaSProvider) Mint(g Grant) (Pass, error) {
	if err := p.Usable(); err != nil {
		return Pass{}, err
	}
	if g.RoomRef == "" {
		return Pass{}, errors.New("the grant names no room")
	}
	if g.ExpiresAt.IsZero() || !g.ExpiresAt.After(time.Now()) {
		// Fails closed. A zero time would otherwise sign a pass that
		// expired in 1970 - or, with the wrong arithmetic, one that never
		// does.
		return Pass{}, errors.New("the grant has no future expiry")
	}

	now := time.Now()
	claims := map[string]any{
		"aud":  "jitsi",
		"iss":  "chat",
		"sub":  p.appID,
		"room": g.RoomRef,
		"exp":  g.ExpiresAt.Unix(),
		// Backdated by a minute so a clock a few seconds behind the
		// provider's does not reject a pass that is genuinely valid.
		"nbf": now.Add(-1 * time.Minute).Unix(),
		"context": map[string]any{
			"user": map[string]any{
				"id":        g.UserRef,
				"name":      g.DisplayName,
				"moderator": boolString(g.Moderator),
			},
			// EVERY ONE OF THESE IS OFF, AND recording IS NOT A SETTING.
			//
			// "بث مباشر فقط — ولا تسجيل، أبدًا" is permanent in CLAUDE.md
			// and has nothing to do with storage. Turning it off in the
			// token is how the rule is enforced at the one place that could
			// break it: the provider. A moderator who found the button
			// would otherwise be one click from a clinical recording that
			// lives outside every control in this system.
			"features": map[string]any{
				"recording":         "false",
				"livestreaming":     "false",
				"transcription":     "false",
				"outbound-call":     "false",
				"sip-outbound-call": "false",
			},
		},
	}

	header := map[string]any{"alg": "RS256", "typ": "JWT", "kid": p.keyID}

	signed, err := signRS256(header, claims, p.key)
	if err != nil {
		return Pass{}, err
	}

	return Pass{
		Domain: "8x8.vc",
		// JaaS namespaces every room under the tenant, and a room name
		// without it is a room at somebody else's.
		Room:  p.appID + "/" + g.RoomRef,
		Token: signed,
	}, nil
}

// signRS256 builds a JWT with the standard library.
//
// NO DEPENDENCY FOR FORTY LINES. This module has exactly one direct
// requirement - pgx - and a JWT is three base64url segments and one signature.
// A library here would be a supply chain, a version to track and an upgrade to
// schedule, in exchange for code that is shorter than its own configuration.
func signRS256(header, claims map[string]any, key *rsa.PrivateKey) (string, error) {
	h, err := json.Marshal(header)
	if err != nil {
		return "", fmt.Errorf("meeting: encoding the token header: %w", err)
	}
	c, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("meeting: encoding the token claims: %w", err)
	}

	enc := base64.RawURLEncoding
	signing := enc.EncodeToString(h) + "." + enc.EncodeToString(c)

	sum := sha256.Sum256([]byte(signing))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, sum[:])
	if err != nil {
		return "", fmt.Errorf("meeting: signing the token: %w", err)
	}

	return signing + "." + enc.EncodeToString(sig), nil
}

// boolString is what JaaS reads: the moderator claim is the STRING "true",
// not the boolean. A real boolean is accepted by the parser and ignored by the
// permission check, which is a guest who believes they are a host and a host
// who is quietly a guest.
func boolString(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// Fingerprint is the hash written to hbh.meeting_tokens.
//
// The pass itself is never stored - the same rule as hbh.otp_codes and
// hbh.stream_tokens. What is kept is enough to recognise a pass somebody
// produces later and nothing that would let anybody produce one.
//
// WHEN THERE IS NO TOKEN, IT HASHES THE OCCASION INSTEAD, and that is not
// tidiness. hbh.meeting_tokens has a UNIQUE on the hash, so hashing the empty
// string would make the FIRST development entry succeed and every one after it
// collide - an evidence table that silently stops recording, on the provider
// where nothing else is watching either.
//
// What it hashes then is what actually happened: this room, this person, this
// instant. It is still a record of a pass being issued; it simply says so about
// an occasion rather than about a credential, because there was no credential.
func Fingerprint(p Pass, g Grant, at time.Time) []byte {
	var material string
	if p.Token != "" {
		material = "jwt\x00" + p.Token
	} else {
		material = "no-token\x00" + p.Room + "\x00" + g.UserRef + "\x00" +
			at.UTC().Format(time.RFC3339Nano)
	}
	sum := sha256.Sum256([]byte(material))
	return sum[:]
}
