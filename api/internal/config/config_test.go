package config

import (
	"net/netip"
	"slices"
	"strings"
	"testing"
)

func env(m map[string]string) func(string) string {
	return func(k string) string { return m[k] }
}

func TestLoadRequiresDatabaseURL(t *testing.T) {
	_, err := loadFrom(env(map[string]string{}))
	if err == nil || !strings.Contains(err.Error(), "DATABASE_URL") {
		t.Fatalf("want a DATABASE_URL error, got %v", err)
	}
}

// The rule this file exists for. An echoing production process has handed out
// every account's one-time code, so it must not be able to start at all.
func TestOTPEchoIsRefusedOutsideDevelopment(t *testing.T) {
	_, err := loadFrom(env(map[string]string{
		"DATABASE_URL": "postgres://x/y",
		"APP_ENV":      "production",
		"OTP_ECHO":     "true",
	}))
	if err == nil || !strings.Contains(err.Error(), "OTP_ECHO") {
		t.Fatalf("want an OTP_ECHO refusal, got %v", err)
	}
}

func TestOTPEchoIsAllowedInDevelopment(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{
		"DATABASE_URL": "postgres://x/y",
		"APP_ENV":      "development",
		"OTP_ECHO":     "true",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !cfg.OTPEcho {
		t.Fatal("OTP_ECHO was not applied")
	}
}

// X-Forwarded-For reaches the audit log as the client address. Believing it by
// default would let any caller write their own audit trail.
func TestTrustProxyDefaultsOff(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{"DATABASE_URL": "postgres://x/y"}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if cfg.TrustProxy {
		t.Fatal("TRUST_PROXY must default to false")
	}
	if len(cfg.TrustedProxies) != 0 {
		t.Fatalf("with the flag off nothing is trusted, got %v", cfg.TrustedProxies)
	}
}

// TRUST_PROXY=true with no list names the deployment it was written for:
// nginx reaching this service over loopback (deploy/server). Leaving the list
// empty instead would read as "trusting" and behave as "off".
func TestTrustedProxiesDefaultToLoopbackWhenTrusting(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{
		"DATABASE_URL": "postgres://x/y",
		"TRUST_PROXY":  "true",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !cfg.TrustedProxies[0].Contains(netip.MustParseAddr("127.0.0.1")) {
		t.Fatalf("loopback is not trusted by default: %v", cfg.TrustedProxies)
	}
	if slices.ContainsFunc(cfg.TrustedProxies, func(p netip.Prefix) bool {
		return p.Contains(netip.MustParseAddr("10.0.0.9"))
	}) {
		t.Fatalf("the default trusts more than loopback: %v", cfg.TrustedProxies)
	}
}

// A CIDR and a bare address are both accepted; a bare address means that
// host alone and must not widen to its network.
func TestTrustedProxiesAcceptCIDRAndBareAddress(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{
		"DATABASE_URL":    "postgres://x/y",
		"TRUST_PROXY":     "true",
		"TRUSTED_PROXIES": "10.1.0.0/16, 192.168.4.7",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	in := func(s string) bool {
		return slices.ContainsFunc(cfg.TrustedProxies, func(p netip.Prefix) bool {
			return p.Contains(netip.MustParseAddr(s))
		})
	}
	if !in("10.1.9.9") || !in("192.168.4.7") {
		t.Fatalf("a named proxy is not trusted: %v", cfg.TrustedProxies)
	}
	if in("192.168.4.8") {
		t.Fatal("a bare address widened to its network")
	}
}

// A typo that silently narrows the trust list fails closed - which sounds
// safe, and is also invisible: the operator who wrote it believes the
// opposite. It is an error instead.
func TestTrustedProxiesRejectGarbage(t *testing.T) {
	_, err := loadFrom(env(map[string]string{
		"DATABASE_URL":    "postgres://x/y",
		"TRUST_PROXY":     "true",
		"TRUSTED_PROXIES": "10.1.0.0/16, not-an-address",
	}))
	if err == nil || !strings.Contains(err.Error(), "TRUSTED_PROXIES") {
		t.Fatalf("a bad entry was accepted: %v", err)
	}
}

func TestCORSOriginsAreSplitAndTrimmed(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{
		"DATABASE_URL": "postgres://x/y",
		"CORS_ORIGINS": " http://localhost:4200 , https://portal.example ,",
	}))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []string{"http://localhost:4200", "https://portal.example"}
	if len(cfg.CORSOrigins) != len(want) {
		t.Fatalf("got %v, want %v", cfg.CORSOrigins, want)
	}
	for i := range want {
		if cfg.CORSOrigins[i] != want[i] {
			t.Fatalf("got %v, want %v", cfg.CORSOrigins, want)
		}
	}
}

func TestBadNumberIsReported(t *testing.T) {
	_, err := loadFrom(env(map[string]string{
		"DATABASE_URL":         "postgres://x/y",
		"AUTH_RATE_PER_MINUTE": "0",
	}))
	if err == nil || !strings.Contains(err.Error(), "AUTH_RATE_PER_MINUTE") {
		t.Fatalf("want an AUTH_RATE_PER_MINUTE error, got %v", err)
	}
}

// THE PRODUCTION FAIL-CLOSED RULE.
//
// Turning OTP_ECHO off does not make production safe on its own - it makes it
// UNUSABLE and quiet: every login accepted, every code generated and thrown
// away by the development sender, and a service reporting itself healthy while
// no parent can sign in. There is no log line for "nobody can authenticate".
// So the two rules are tested together: production has a real delivery
// channel, or it does not start.
func TestProductionRefusesTheDevelopmentSMSProvider(t *testing.T) {
	for _, provider := range []string{"", "dev"} {
		_, err := loadFrom(env(map[string]string{
			"APP_ENV":      "production",
			"DATABASE_URL": "postgres://x",
			"SMS_PROVIDER": provider,
		}))
		if err == nil || !strings.Contains(err.Error(), "SMS_PROVIDER") {
			t.Fatalf("provider %q: want an SMS_PROVIDER refusal, got %v", provider, err)
		}
	}
}

func TestProductionRefusesAnHTTPProviderWithMissingCredentials(t *testing.T) {
	base := map[string]string{
		"APP_ENV":            "production",
		"DATABASE_URL":       "postgres://x",
		"SMS_PROVIDER":       "http",
		"SMS_HTTP_URL":       "https://gateway.example.eg/send",
		"SMS_HTTP_USERNAME":  "u",
		"SMS_HTTP_PASSWORD":  "p",
		"SMS_HTTP_SENDER_ID": "HBH",
	}
	if _, err := loadFrom(env(base)); err != nil {
		t.Fatalf("a complete production configuration must start: %v", err)
	}

	for _, key := range []string{
		"SMS_HTTP_URL", "SMS_HTTP_USERNAME", "SMS_HTTP_PASSWORD", "SMS_HTTP_SENDER_ID",
	} {
		cut := make(map[string]string, len(base))
		for k, v := range base {
			cut[k] = v
		}
		delete(cut, key)
		_, err := loadFrom(env(cut))
		if err == nil || !strings.Contains(err.Error(), key) {
			t.Fatalf("missing %s: want a refusal naming it, got %v", key, err)
		}
	}
}

// Development is left alone. A laptop with no provider contract must still
// run the portal, and the acceptance suites depend on it.
func TestDevelopmentAllowsTheDevelopmentSMSProvider(t *testing.T) {
	cfg, err := loadFrom(env(map[string]string{
		"APP_ENV":      "development",
		"DATABASE_URL": "postgres://x",
	}))
	if err != nil {
		t.Fatalf("development must not need a provider: %v", err)
	}
	if cfg.SMSProvider != "dev" {
		t.Fatalf("want the default dev provider, got %q", cfg.SMSProvider)
	}
}

func TestContentSIDsParsing(t *testing.T) {
	got, err := contentSIDs(" OTP = HX1 , APPOINTMENT_CONFIRMED=HX2 ")
	if err != nil {
		t.Fatalf("a well-formed list should parse: %v", err)
	}
	if got["OTP"] != "HX1" || got["APPOINTMENT_CONFIRMED"] != "HX2" {
		t.Fatalf("got %v", got)
	}
	if empty, err := contentSIDs(""); err != nil || len(empty) != 0 {
		t.Fatalf("an empty list is not an error: %v %v", empty, err)
	}

	// A MALFORMED ENTRY IS AN ERROR, NOT A SKIP. Dropping the pair somebody
	// mistyped turns a typo into a CONFIG failure at the moment a family was
	// owed a message, instead of at startup where it can be read.
	for _, bad := range []string{"OTP", "=HX1", "OTP=", "OTP=HX1,OTP=HX2"} {
		if _, err := contentSIDs(bad); err == nil {
			t.Fatalf("%q must be refused at startup", bad)
		}
	}
}

func TestProductionRefusesTwilioWithoutAnOTPTemplate(t *testing.T) {
	base := map[string]string{
		"DATABASE_URL":         "postgres://x/y",
		"APP_ENV":              "production",
		"SESSION_SECRET":       "0123456789abcdef0123456789abcdef",
		"SMS_PROVIDER":         "twilio_whatsapp",
		"TWILIO_ACCOUNT_SID":   "AC00000000000000000000000000000000",
		"TWILIO_AUTH_TOKEN":    "secret",
		"TWILIO_WHATSAPP_FROM": "+201000000000",
		"TWILIO_CONTENT_SIDS":  "OTP_LOGIN=HX1",
	}
	if _, err := loadFrom(env(base)); err != nil {
		t.Fatalf("a complete twilio configuration should load: %v", err)
	}

	// A login code is the one message whose absence closes the front door, so
	// a deployment without its template must not start. Every other missing
	// template costs one message; this one costs every sign-in.
	noOTP := make(map[string]string, len(base))
	for k, v := range base {
		noOTP[k] = v
	}
	noOTP["TWILIO_CONTENT_SIDS"] = "APPOINTMENT_CONFIRMED=HX2"
	if _, err := loadFrom(env(noOTP)); err == nil {
		t.Fatal("a production process with no OTP template must not start")
	}

	for _, cut := range []string{"TWILIO_ACCOUNT_SID", "TWILIO_AUTH_TOKEN"} {
		short := make(map[string]string, len(base))
		for k, v := range base {
			short[k] = v
		}
		delete(short, cut)
		if _, err := loadFrom(env(short)); err == nil {
			t.Fatalf("production without %s must not start", cut)
		}
	}

	// A sender is required, and either kind counts.
	noSender := make(map[string]string, len(base))
	for k, v := range base {
		noSender[k] = v
	}
	delete(noSender, "TWILIO_WHATSAPP_FROM")
	if _, err := loadFrom(env(noSender)); err == nil {
		t.Fatal("production with no sender at all must not start")
	}
	noSender["TWILIO_MESSAGING_SERVICE_SID"] = "MG00000000000000000000000000000000"
	if _, err := loadFrom(env(noSender)); err != nil {
		t.Fatalf("a messaging service is a sender: %v", err)
	}
}

// The third development-only affordance, refused outside development exactly
// as OTP_ECHO and SMS_PROVIDER=dev are. It fails the same way if it escapes:
// quietly, by sending nothing at all in a channel that refuses free text.
func TestFreeformFallbackIsRefusedOutsideDevelopment(t *testing.T) {
	base := map[string]string{
		"DATABASE_URL":          "postgres://x/y",
		"SESSION_SECRET":        "0123456789abcdef0123456789abcdef",
		"TWILIO_ALLOW_FREEFORM": "true",
		"SMS_PROVIDER":          "twilio_whatsapp",
		"TWILIO_ACCOUNT_SID":    "AC00000000000000000000000000000000",
		"TWILIO_AUTH_TOKEN":     "secret",
		"TWILIO_WHATSAPP_FROM":  "+201000000000",
		"TWILIO_CONTENT_SIDS":   "OTP_LOGIN=HX1",
	}

	dev := make(map[string]string, len(base))
	for k, v := range base {
		dev[k] = v
	}
	dev["APP_ENV"] = "development"
	cfg, err := loadFrom(env(dev))
	if err != nil {
		t.Fatalf("development may turn it on: %v", err)
	}
	if !cfg.TwilioAllowFreeform {
		t.Fatal("the setting did not survive loading")
	}

	prod := make(map[string]string, len(base))
	for k, v := range base {
		prod[k] = v
	}
	prod["APP_ENV"] = "production"
	if _, err := loadFrom(env(prod)); err == nil {
		t.Fatal("a production process must not start with the freeform fallback on")
	}

	// And off, production still starts - so the test above is about the flag
	// and not about the rest of this configuration being wrong.
	prod["TWILIO_ALLOW_FREEFORM"] = "false"
	if _, err := loadFrom(env(prod)); err != nil {
		t.Fatalf("production with the flag off should load: %v", err)
	}
}
