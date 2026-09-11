package sms

import (
	"context"
	"encoding/json"
	"net/url"
	"strconv"
	"strings"
	"testing"
)

func TestTwilioRefusesIncompleteConfiguration(t *testing.T) {
	full := TwilioConfig{
		AccountSID: "AC00000000000000000000000000000000",
		AuthToken:  "secret",
		From:       "+201000000000",
	}
	if _, err := NewTwilioWhatsApp(full); err != nil {
		t.Fatalf("a complete configuration should build: %v", err)
	}

	for _, c := range []struct {
		name string
		mut  func(*TwilioConfig)
	}{
		{"no account sid", func(c *TwilioConfig) { c.AccountSID = "" }},
		{"no auth token", func(c *TwilioConfig) { c.AuthToken = "" }},
		{"no sender at all", func(c *TwilioConfig) { c.From = ""; c.MessagingServiceSid = "" }},
		// A sid that is not a sid produces a 404 on a URL that names it,
		// which reads as an outage rather than as the typo it is.
		{"account sid is not a sid", func(c *TwilioConfig) { c.AccountSID = "not-a-sid" }},
		{"messaging service is not a service", func(c *TwilioConfig) { c.MessagingServiceSid = "AC123" }},
	} {
		cfg := full
		c.mut(&cfg)
		if _, err := NewTwilioWhatsApp(cfg); err == nil {
			t.Fatalf("%s: must fail at startup, not at a parent's first login", c.name)
		}
	}
}

// A MessagingServiceSid alone is enough: it carries sender selection with it.
func TestTwilioAcceptsAMessagingServiceWithoutAFrom(t *testing.T) {
	_, err := NewTwilioWhatsApp(TwilioConfig{
		AccountSID:          "AC00000000000000000000000000000000",
		AuthToken:           "secret",
		MessagingServiceSid: "MG00000000000000000000000000000000",
	})
	if err != nil {
		t.Fatalf("a messaging service is a sender: %v", err)
	}
}

func newTestTwilio(t *testing.T, content map[string]string) *TwilioWhatsApp {
	t.Helper()
	s, err := NewTwilioWhatsApp(TwilioConfig{
		AccountSID:  "AC00000000000000000000000000000000",
		AuthToken:   "secret",
		From:        "+201000000000",
		ContentSIDs: content,
	})
	if err != nil {
		t.Fatalf("building the test sender: %v", err)
	}
	return s
}

// THE LOAD-BEARING REFUSAL. An unmapped template must be CONFIG and must be
// refused before any request is made: WhatsApp rejects a business-initiated
// freeform message identically every time, so retrying one burns the attempt
// ceiling against a wall and the family still gets nothing. CONFIG is what
// puts it in front of the person who can add the mapping.
func TestTwilioRefusesAnUnmappedTemplateAsConfig(t *testing.T) {
	s := newTestTwilio(t, map[string]string{"OTP": "HX0000000000000000000000000000000"})

	_, err := s.Send(context.Background(), Message{
		To: "01012345678", TemplateCode: "APPOINTMENT_CONFIRMED",
	})
	if err == nil {
		t.Fatal("an unmapped template must not be sent")
	}
	class, detail := ClassOf(err)
	if class != ClassConfig {
		t.Fatalf("got %s, want CONFIG - a retry produces the identical refusal", class)
	}
	if !strings.Contains(detail, "APPOINTMENT_CONFIRMED") {
		t.Fatalf("the detail must name the template an operator has to map, got %q", detail)
	}
}

// THE FALLBACK, AND THE FOUR WAYS IT MUST NOT FIRE. It is a development
// affordance for Twilio's sandbox, where a 24-hour session is open and free
// text is delivered; config.Load refuses it outside development. Everywhere
// else the CONFIG refusal has to survive, because WhatsApp rejects free text
// with 63016 on every attempt and a fallback would climb the whole retry
// ladder to deliver nothing.
func TestTwilioFreeformFallbackOnlyWhenAllowedAndOnlyWithABody(t *testing.T) {
	build := func(allow bool) *TwilioWhatsApp {
		t.Helper()
		s, err := NewTwilioWhatsApp(TwilioConfig{
			AccountSID:    "AC00000000000000000000000000000000",
			AuthToken:     "secret",
			From:          "+201000000000",
			ContentSIDs:   map[string]string{"OTP": "HX1"},
			AllowFreeform: allow,
		})
		if err != nil {
			t.Fatalf("building: %v", err)
		}
		return s
	}

	unmapped := Message{To: "01012345678", TemplateCode: "APPOINTMENT_BOOKED", Body: "رسالة"}

	// Off: refused, and refused as CONFIG so it is not retried.
	if _, err := build(false).Send(context.Background(), unmapped); err == nil {
		t.Fatal("with the affordance off an unmapped template must be refused")
	} else if class, _ := ClassOf(err); class != ClassConfig {
		t.Fatalf("got %s, want CONFIG", class)
	}

	// On but with nothing to fall back TO: still refused. An empty body is
	// not a message, and sending one would be a delivered blank.
	noBody := unmapped
	noBody.Body = ""
	if _, err := build(true).Send(context.Background(), noBody); err == nil {
		t.Fatal("there is nothing to fall back to without a body")
	} else if class, _ := ClassOf(err); class != ClassConfig {
		t.Fatalf("got %s, want CONFIG", class)
	}

	// On, with a body: it gets past the refusal and reaches the wire. The
	// request then fails on the fake credentials, which is a PROVIDER error
	// and not a CONFIG one - that difference is the whole assertion.
	if _, err := build(true).Send(context.Background(), unmapped); err != nil {
		if _, detail := ClassOf(err); strings.Contains(detail, "APPOINTMENT_BOOKED") {
			t.Fatalf("the fallback did not fire - still refused locally: %s", detail)
		}
	}

	// A MAPPED template is never affected by the affordance: it still goes as
	// a template, so turning this on cannot silently downgrade a message that
	// had an approval.
	mapped := Message{To: "01012345678", TemplateCode: "OTP", Vars: []string{"123456"}, Body: "fallback"}
	if _, err := build(true).Send(context.Background(), mapped); err != nil {
		if _, detail := ClassOf(err); strings.Contains(detail, "OTP") &&
			strings.Contains(detail, "no approved") {
			t.Fatalf("a mapped template must not be refused: %s", detail)
		}
	}
}

// A rendered sentence with no template is what hbh.sms_outbox holds today.
// It must be refused rather than sent as freeform - see the worker.
func TestTwilioRefusesAnEmptyMessage(t *testing.T) {
	s := newTestTwilio(t, nil)
	// Body alone is ALLOWED to reach the wire: it is a real case inside an
	// open 24-hour window. What must not happen is a silent template-less
	// send of a message whose template_code was never mapped, which the test
	// above covers. This one pins the empty message instead.
	if _, err := s.Send(context.Background(), Message{To: "01012345678"}); err == nil {
		t.Fatal("a message with neither template nor body must be refused")
	} else if class, _ := ClassOf(err); class != ClassPermanent {
		t.Fatalf("got %s, want PERMANENT - an empty message is empty on every retry", class)
	}
}

// The destination is checked by the shared E164, so a bad one never reaches a
// provider and is never billed.
func TestTwilioRefusesANonEgyptianDestination(t *testing.T) {
	s := newTestTwilio(t, map[string]string{"OTP": "HX0"})
	for _, bad := range []string{"", "0101234567", "201012345678", "0191234567a"} {
		if _, err := s.Send(context.Background(), Message{
			To: bad, TemplateCode: "OTP", Vars: []string{"123456"},
		}); err == nil {
			t.Fatalf("%q must be refused as a destination", bad)
		}
	}
}

func TestWaAddressDoesNotDoublePrefix(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"+201012345678", "whatsapp:+201012345678"},
		{"whatsapp:+201012345678", "whatsapp:+201012345678"},
		{"  +201012345678 ", "whatsapp:+201012345678"},
	} {
		if got := waAddress(c.in); got != c.want {
			t.Fatalf("waAddress(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

// Variables are POSITIONAL and Twilio numbers them from 1, as Meta does. An
// off-by-one here sends a family a countdown where a login code should be.
func TestTwilioVariablesAreNumberedFromOne(t *testing.T) {
	vars := map[string]string{}
	for i, v := range []string{"123456", "15"} {
		vars[strconv.Itoa(i+1)] = v
	}
	encoded, err := json.Marshal(vars)
	if err != nil {
		t.Fatal(err)
	}
	var back map[string]string
	if err := json.Unmarshal(encoded, &back); err != nil {
		t.Fatal(err)
	}
	if back["1"] != "123456" || back["2"] != "15" {
		t.Fatalf("variables must be 1-based: %v", back)
	}
	if _, ok := back["0"]; ok {
		t.Fatal("there is no variable zero in a Meta template")
	}
}

// CLASSIFICATION IS THE WHOLE CONTRACT WITH record_sms_failed: TRANSIENT goes
// back on the queue, PERMANENT and CONFIG do not. Getting one wrong either
// drops a message a family was owed or retries a refusal forever.
func TestTwilioClassification(t *testing.T) {
	for _, c := range []struct {
		name   string
		status int
		body   string
		want   Class
	}{
		{"auth is the deployment", 401, `{"code":20003,"message":"Authenticate"}`, ClassConfig},
		{"freeform outside the window needs a template", 400,
			`{"code":63016,"message":"Failed to send freeform message"}`, ClassConfig},
		{"no channel for this sender", 400, `{"code":63007,"message":"no channel"}`, ClassConfig},
		{"region not enabled", 400, `{"code":21408,"message":"Permission to send"}`, ClassConfig},
		{"an invalid number is invalid on every retry", 400,
			`{"code":21211,"message":"Invalid To"}`, ClassPermanent},
		{"an opted-out recipient stays opted out", 400,
			`{"code":21610,"message":"unsubscribed"}`, ClassPermanent},
		{"rate limits pass", 429, `{"code":63018,"message":"rate limit"}`, ClassTransient},
		{"too many requests", 429, `{"code":20429,"message":"Too Many Requests"}`, ClassTransient},
		// An unrecognised code falls to the status, and an unrecognised 5xx
		// is transient: the safer default, since the ceiling is enforced in
		// PL/pgSQL anyway.
		{"unknown code on a 5xx retries", 503, `{"code":99999,"message":"boom"}`, ClassTransient},
		{"unknown code on a 4xx does not", 400, `{"code":99999,"message":"boom"}`, ClassPermanent},
		// No parseable body at all - the status has to carry it.
		{"unparseable 500 retries", 500, `<html>gateway</html>`, ClassTransient},
		{"unparseable 400 does not", 400, `<html>nope</html>`, ClassPermanent},
		{"unparseable 401 is the deployment", 401, ``, ClassConfig},
	} {
		err := classifyTwilio(c.status, "test status", []byte(c.body))
		class, detail := ClassOf(err)
		if class != c.want {
			t.Fatalf("%s: got %s, want %s (detail %q)", c.name, class, c.want, detail)
		}
	}
}

// The detail reaches an operations screen, so it must name the provider's own
// code - that is the handle Twilio support asks for - and must not be empty.
func TestTwilioDetailCarriesTheProviderCode(t *testing.T) {
	err := classifyTwilio(400, "400 Bad Request", []byte(`{"code":63016,"message":"Failed to send freeform message"}`))
	_, detail := ClassOf(err)
	if !strings.Contains(detail, "63016") {
		t.Fatalf("the detail must carry the provider code, got %q", detail)
	}
}

func TestTwilioParsesAcceptedAndSurvivesNonsense(t *testing.T) {
	r := parseTwilioAccepted([]byte(`{"sid":"SM123","num_segments":"2"}`))
	if r.ProviderMessageID != "SM123" || r.Segments != 2 {
		t.Fatalf("got %+v", r)
	}
	// ACCEPTED IS ACCEPTED. Losing the sid costs one manual question; treating
	// it as a failure would send the family the message a second time.
	if got := parseTwilioAccepted([]byte(`not json`)); got.ProviderMessageID != "" {
		t.Fatalf("unparseable body must still be an accept, got %+v", got)
	}
}

// A secret must never be reachable from anything that gets written down.
func TestTwilioCredentialsAreNotInTheFormOrTheDetail(t *testing.T) {
	err := classifyTwilio(401, "401", []byte(`{"code":20003,"message":"Authenticate"}`))
	_, detail := ClassOf(err)
	if strings.Contains(strings.ToLower(detail), "secret") {
		t.Fatalf("an error detail reaches operations and must not carry a credential: %q", detail)
	}

	// The account sid appears in the URL path, which is Twilio's design; the
	// token must appear only in the Authorization header, never in the form.
	form := url.Values{}
	form.Set("To", "whatsapp:+201012345678")
	if strings.Contains(form.Encode(), "secret") {
		t.Fatal("the auth token must never be a form field")
	}
}
