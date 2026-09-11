package sms

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// THE CASE THE OLD BODY GOT WRONG, and the reason 0112 exists: a number that
// is not Egyptian has to pass. It used to be refused as PERMANENT, which meant
// a family in the Gulf had their login code marked dead on arrival - no retry,
// no queue, and nothing anywhere that said why.
func TestE164AcceptsAnyInternationalNumber(t *testing.T) {
	for _, in := range []string{
		"+201500000093", // Egypt, as 0112 now stores it
		"+966501234567", // Saudi Arabia
		"+971501234567", // United Arab Emirates
		"+96550123456",  // Kuwait - shorter, and still valid
		"+97433123456",  // Qatar
	} {
		got, err := E164(in)
		if err != nil {
			t.Fatalf("%q was refused: %v", in, err)
		}
		if got != in {
			t.Fatalf("%q came back as %q - this function checks, it does not convert", in, got)
		}
	}
}

// THE SHAPE A GULF NUMBER IS ACTUALLY WRITTEN IN. MOBILE_PATTERN accepts
// separators on purpose - a person types them - and the login handler passes
// the raw field straight here. Refuse these and the number passes the edge
// check, is stored correctly, and then never receives anything.
func TestE164DropsTheSeparatorsAPersonTypes(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"+966 50 123 4567", "+966501234567"},
		{"+966-50-123-4567", "+966501234567"},
		{"(+966) 50 123 4567", "+966501234567"},
		{" +201500000093 ", "+201500000093"},
		{"0150 000 0093", "+201500000093"},
		{"٠١٥٠٠٠٠٠٠٩٣", "+201500000093"},
	} {
		got, err := E164(c.in)
		if err != nil {
			t.Fatalf("%q was refused: %v", c.in, err)
		}
		if got != c.want {
			t.Fatalf("%q -> %q, want %q", c.in, got, c.want)
		}
	}
}

// A letter is not a separator. The database's canonicaliser strips everything
// that is not a digit, and this one deliberately does not: "+20150000009a"
// with the letter removed is a number that is almost right, and almost right
// is how a code reaches a stranger.
func TestE164DoesNotSilentlyDropALetter(t *testing.T) {
	for _, in := range []string{"0150000009a", "+20150000009a", "+2015000000 9a"} {
		if _, err := E164(in); err == nil {
			t.Fatalf("%q was accepted - a letter was dropped rather than refused", in)
		}
	}
}

// TRANSITIONAL, and it is a test so that removing the branch is a deliberate
// act rather than a silent one. The API ships before 0112, so for one deploy
// this build reads columns that still hold the national form. When the handler
// starts sending request_otp's mobile_e164, this test and that branch go
// together.
func TestE164StillConvertsTheNationalFormWhileTheColumnHoldsIt(t *testing.T) {
	got, err := E164(" 01500000093  ")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got != "+201500000093" {
		t.Fatalf("want +201500000093, got %q", got)
	}
}

// A destination the provider would reject must be refused HERE, and refused as
// PERMANENT - so hbh.record_sms_failed marks it DEAD instead of retrying an
// invalid number five times and billing for none of them.
func TestE164RefusesAnythingElseAsPermanent(t *testing.T) {
	for _, in := range []string{
		"",
		"0150000009",        // ten digits, and no country code to save it
		"015000000931",      // twelve
		"0150000009a",       // not digits
		"02150000009",       // a landline
		"201500000093",      // bare digits: ambiguous, and never guessed at
		"+0201500000093",    // a country code may not start with zero
		"+20150000009a",     // not digits after the plus
		"+2015000000931234", // longer than E.164 allows
		"+2015",             // shorter than E.164 allows
	} {
		_, err := E164(in)
		if err == nil {
			t.Fatalf("%q was accepted as a mobile number", in)
		}
		class, _ := ClassOf(err)
		if class != ClassPermanent {
			t.Fatalf("%q classified %s, want PERMANENT", in, class)
		}
	}
}

func TestMaskKeepsOnlyTheLastFour(t *testing.T) {
	if got := Mask("01500000093"); got != "****0093" {
		t.Fatalf("got %q", got)
	}
	if got := Mask("12"); got != "****" {
		t.Fatalf("a short number must not be returned whole, got %q", got)
	}
}

// An unclassified error is TRANSIENT, and that default is the safer of the
// two: a permanent classification would silently drop a message a family was
// owed, while a transient one costs at most SMS_MAX_ATTEMPTS retries against a
// ceiling the database already enforces.
func TestClassOfDefaultsToTransient(t *testing.T) {
	class, detail := ClassOf(errors.New("something nobody classified"))
	if class != ClassTransient {
		t.Fatalf("want TRANSIENT, got %s", class)
	}
	if detail == "" {
		t.Fatal("the detail must survive so an operator can read it")
	}
}

// THE PRODUCTION FAIL-CLOSED RULE, half of it.
//
// config.Load refuses a production process configured with SMS_PROVIDER=dev;
// this is the sender itself refusing, so the guarantee survives a future
// caller that builds one without going through Load.
func TestDevSenderIsRefusedOutsideDevelopment(t *testing.T) {
	if err := (&DevSender{Env: "production"}).Usable(); err == nil {
		t.Fatal("the development sender must not be usable in production")
	}
	if err := (&DevSender{Env: "development"}).Usable(); err != nil {
		t.Fatalf("it must be usable in development: %v", err)
	}
}

// What the acceptance suite relies on, and the line the brief draws twice: the
// development sender records that a message was ATTEMPTED, to a masked number,
// and never keeps the body. A one-time code passes through Message.Body, so a
// Record that held it would put live credentials wherever the record goes.
func TestDevSenderRecordsTheAttemptAndNotTheBody(t *testing.T) {
	d := &DevSender{Env: "development"}
	res, err := d.Send(context.Background(), Message{
		To:   "01500000093",
		Body: "code 123456 inside",
		Ref:  "otp:1",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.ProviderMessageID == "" {
		t.Fatal("an accepted message must come back with an id to ask the provider about")
	}
	sent := d.Sent()
	if len(sent) != 1 {
		t.Fatalf("want one record, got %d", len(sent))
	}
	if sent[0].To != "****0093" {
		t.Fatalf("the destination must be masked, got %q", sent[0].To)
	}
	if sent[0].Size != len([]rune("code 123456 inside")) {
		t.Fatalf("the length should be recorded, got %d", sent[0].Size)
	}
	// The whole point: nothing on the record is the body.
	if strings.Contains(sent[0].Ref+sent[0].To, "123456") {
		t.Fatal("the code reached a stored field")
	}
}

func TestDevSenderStillRefusesAMalformedNumber(t *testing.T) {
	d := &DevSender{Env: "development"}
	if _, err := d.Send(context.Background(), Message{To: "nope", Body: "x"}); err == nil {
		t.Fatal("the development path must reject what a provider would reject, or it proves nothing")
	}
}

// Arabic goes out as UCS-2, where a segment is 70 characters rather than 160.
// This is reported so a suite can see a template would cost three messages
// before a centre pays for it; it is never used to split anything.
func TestSegmentsUCS2(t *testing.T) {
	for _, c := range []struct{ runes, want int }{
		{0, 0}, {1, 1}, {70, 1}, {71, 2}, {134, 2}, {135, 3},
	} {
		if got := segmentsUCS2(c.runes); got != c.want {
			t.Fatalf("%d runes: got %d segments, want %d", c.runes, got, c.want)
		}
	}
}

func TestNewRefusesAnUnknownProvider(t *testing.T) {
	// "twilio" rather than "twilio_whatsapp" on purpose: a name that is ALMOST
	// a real provider is the one somebody types, and answering it with a
	// working sender would pick a channel the deployment did not ask for.
	if _, err := New("twilio", HTTPConfig{}, TwilioConfig{}, "development"); err == nil {
		t.Fatal("an unknown provider must fail at startup, not at the first login")
	}
	if _, err := New("vodafone", HTTPConfig{}, TwilioConfig{}, "development"); err == nil {
		t.Fatal("an unknown provider must fail at startup, not at the first login")
	}
}

func TestHTTPSenderRefusesIncompleteOrPlainHTTPConfiguration(t *testing.T) {
	full := HTTPConfig{
		BaseURL: "https://gateway.example.eg/send", Username: "u",
		Password: "p", SenderID: "HBH", Timeout: time.Second,
	}
	if _, err := NewHTTPSender(full); err != nil {
		t.Fatalf("a complete configuration should build: %v", err)
	}

	plain := full
	plain.BaseURL = "http://gateway.example.eg/send"
	if _, err := NewHTTPSender(plain); err == nil {
		t.Fatal("a login code must not cross the internet in clear text")
	}

	for _, strip := range []func(*HTTPConfig){
		func(c *HTTPConfig) { c.BaseURL = "" },
		func(c *HTTPConfig) { c.Username = "" },
		func(c *HTTPConfig) { c.Password = "" },
		func(c *HTTPConfig) { c.SenderID = "" },
	} {
		c := full
		strip(&c)
		if _, err := NewHTTPSender(c); err == nil {
			t.Fatalf("an incomplete configuration built a sender: %+v", c)
		}
	}
}

func TestFailingSenderProducesEachClass(t *testing.T) {
	for _, class := range []Class{ClassTransient, ClassPermanent, ClassConfig} {
		f := &FailingSender{Class: class, Detail: "simulated"}
		_, err := f.Send(context.Background(), Message{To: "01500000093", Body: "x"})
		if err == nil {
			t.Fatalf("%s: expected a failure", class)
		}
		got, _ := ClassOf(err)
		if got != class {
			t.Fatalf("want %s, got %s", class, got)
		}
	}
}
