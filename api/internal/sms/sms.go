// Package sms is the boundary between this service and whatever company
// actually puts a text message on a phone.
//
// WHAT IS IN HERE AND WHAT IS DELIBERATELY NOT.
//
// In here: how to reach a provider, how to classify what it answers, and a
// last check that a destination is in the shape a provider expects. That is
// transport, and transport is this layer's job.
//
// NOT in here, since 0112: which country a number belongs to. That was a
// hard-coded "+20" in E164 below, and it refused every foreign number as
// permanently undeliverable. The dialling codes live in
// hbh.country_dial_codes and hbh.canonical_mobile applies them - rule 2, and
// the reason a family in the Gulf can be reached at all.
//
// NOT in here: who gets told, about what, and whether they agreed to be told.
// Every one of those is decided in PL/pgSQL - hbh.notify_guardians reads the
// guardian's own SMS_NOTIFY consent, hbh.record_sms_failed owns the attempt
// ceiling and the backoff, hbh.queue_appointment_reminders owns when a
// reminder is due. Rule 2 of this project, and the reason this package has no
// idea what a child is.
//
// AND NOT: a way to send an arbitrary message to an arbitrary number. Sender
// is reached by the outbox worker and by the login handler, and nothing else
// calls it. There is no route, no handler and no store method that would let
// a signed-in member of staff type a number and a body - that is a different
// product with different abuse rules, and building it by accident here is
// exactly what the brief refuses.
package sms

import (
	"context"
	"errors"
	"fmt"
	"strings"
)

// Class says what a failure means for a retry, and it is the only thing the
// database needs from a provider error. hbh.record_sms_failed turns it into a
// status: TRANSIENT goes back on the queue with a longer delay, the other two
// are dead on arrival because retrying them produces the identical refusal.
type Class string

const (
	// ClassTransient is a timeout, a 5xx, a rate limit - something that was
	// true for this attempt and may not be true for the next.
	ClassTransient Class = "TRANSIENT"
	// ClassPermanent is the number, the body or the account: no number of
	// retries makes an invalid destination valid.
	ClassPermanent Class = "PERMANENT"
	// ClassConfig is this deployment. Missing credentials, an unreachable
	// base URL, a sender id the provider does not recognise. It is separate
	// from PERMANENT because it is the operator's to fix and not the
	// family's, and because it is the one that means EVERY message will fail
	// rather than this one.
	ClassConfig Class = "CONFIG"
)

// Message is one text to send. It carries a Ref so that a provider that
// supports client-side references can be given ours, which is what makes a
// duplicate visible on their side as well as ours.
type Message struct {
	// To is the number as this domain stores it, which since 0112 is E.164:
	// +201500000093, +966501234567. Checking it against what a provider will
	// take is the sender's job, not the caller's, so there is exactly one
	// place that knows what shape a provider wants.
	To   string
	Body string
	// Ref is hbh.sms_outbox.dedupe_key. Opaque, stable across retries.
	Ref string

	// TemplateCode and Vars exist because WhatsApp will not carry a sentence
	// this service composed. A business-initiated WhatsApp message is an
	// APPROVED TEMPLATE named by a code, with its values supplied apart from
	// it; the rendered Arabic in Body is what an SMS provider wants and is
	// unusable there. Both are carried so each transport takes what it needs
	// and neither caller has to know which one it is talking to.
	//
	// Vars is POSITIONAL, matching {{1}}, {{2}} in the approved template.
	// Keeping it ordered rather than named is what stops this struct from
	// becoming a place where a provider's variable names are written down.
	TemplateCode string
	Vars         []string

	// TemplateName and TemplateLang identify the template Meta approved for
	// this code IN THIS CENTRE, looked up in hbh.message_templates by whoever
	// builds the Message (migration 0167). An empty name means no approved
	// template exists there yet - which a WhatsApp sender refuses as CONFIG,
	// because WhatsApp refuses the same message identically every time.
	//
	// THE NAME AND THE LANGUAGE ARE ONE ANSWER, NOT TWO. Meta approves a
	// template per language, and asking for a name in a language it was not
	// approved in is answered as if the template did not exist at all. They
	// are looked up together and travel together for that reason.
	//
	// They travel on the message rather than living in the sender because the
	// answer is per centre and changes while the process runs: the owner
	// approves a template in the console and the next message uses it, with
	// no deploy and no restart. It used to be a Twilio ContentSid, which is
	// the same idea with a reseller's name on it.
	TemplateName string
	TemplateLang string

	// TemplateAuth says this is an AUTHENTICATION template, which Meta builds
	// with a copy-the-code button whose value must be sent alongside the body
	// - see the button component in meta.go for what happens when it is not.
	// It is the template's category as the database records it, not something
	// this package decides.
	TemplateAuth bool
}

// Result is what came back when the provider accepted it.
type Result struct {
	// ProviderMessageID is what the provider calls this message. It is the
	// only handle an operator has when asking them what happened to it, so
	// it is recorded even though nothing in this service reads it.
	ProviderMessageID string
	// Segments is what the provider says it will bill, when it says. Arabic
	// goes out as UCS-2 and a UCS-2 segment is 70 characters rather than
	// 160, so one sentence can be three segments. Recorded when offered and
	// never computed here: guessing at a provider's own arithmetic produces
	// a number that disagrees with the invoice.
	Segments int
}

// Error is a provider failure with its classification attached.
type Error struct {
	Class  Class
	Detail string
	err    error
}

func (e *Error) Error() string {
	if e.Detail == "" {
		return string(e.Class)
	}
	return string(e.Class) + ": " + e.Detail
}

func (e *Error) Unwrap() error { return e.err }

// Fail builds a classified error. Detail is written to sms_outbox.error_detail
// and shown to operations, so it must never carry a credential or a body.
func Fail(class Class, detail string, err error) *Error {
	return &Error{Class: class, Detail: detail, err: err}
}

// ClassOf reads the classification out of an error, defaulting to TRANSIENT.
//
// The default is deliberate and it is the safer of the two: an unclassified
// failure treated as permanent silently drops a message a family was owed,
// and treated as transient costs at most SMS_MAX_ATTEMPTS retries against a
// ceiling the database already enforces.
func ClassOf(err error) (Class, string) {
	var e *Error
	if errors.As(err, &e) {
		return e.Class, e.Detail
	}
	return ClassTransient, truncate(err.Error(), 500)
}

// Sender puts one message on one phone.
//
// It is one method on purpose. Delivery receipts, balance queries, campaign
// scheduling and the rest are things providers sell and this centre does not
// use; every one of them added here is a method three implementations have to
// answer and a reason the next provider does not fit.
type Sender interface {
	// Send returns an *Error on failure. A nil error means the provider
	// ACCEPTED the message, which is not the same as a phone having received
	// it - no provider tells you that synchronously and this service does not
	// pretend otherwise.
	Send(ctx context.Context, m Message) (Result, error)

	// Code names this sender in hbh.sms_outbox.provider_code, so a row says
	// which implementation handled it. A database where some rows went to a
	// real gateway and some to the development sender is exactly the state an
	// operator needs to be able to see.
	Code() string

	// Usable reports whether this sender can send at all. It is asked at
	// startup, before anything is queued, because a service that cannot
	// deliver a login code has no working front door and should say so then
	// rather than at a parent's first attempt.
	Usable() error
}

// E164 checks that a destination is in the international form providers ask
// for, and returns it.
//
// IT USED TO CONVERT, AND THAT IS THE BUG THIS REPLACES. The old body hard-
// coded "+20", so anything that was not an Egyptian national number was
// refused as ClassPermanent - no retry, no queue, nothing to notice. A family
// in Riyadh had their login code marked failed and sat waiting for a message
// that was never going to be sent. And a dialling code living in Go is against
// the rule in CLAUDE.md that Egypt's specifics are parameters, never code.
//
// Migration 0112 moved the decision into the database, where it belongs: a
// mobile is stored in E.164 and hbh.canonical_mobile is the one place a typed
// number becomes a stored one, reading the dialling code from
// hbh.country_dial_codes. By the time a destination reaches this function it
// has already been through that. So this is a check, not a conversion - the
// wire's own last look at the value, in the one place that can still classify
// a bad one as PERMANENT rather than retrying it forever.
//
// THERE WAS A TRANSITIONAL 01XXXXXXXXX BRANCH HERE, AND IT HAS REACHED THE
// END IT WAS WRITTEN WITH. It converted the national form to +20 so the login
// handler could pass on what a person typed while columns still held that
// form. The handler now sends request_otp's mobile_e164, and every destination
// in hbh.sms_outbox is canonicalised on write (0114) - checked before this was
// removed: no row of any status held anything but +. So the only thing the
// branch still did was hide the next caller that forgets to canonicalise, and
// hide it for Egyptian numbers only, which is the worst subset to hide it for.
func E164(mobile string) (string, error) {
	m := stripSeparators(mobile)

	if strings.HasPrefix(m, "+") {
		if !isE164(m) {
			return "", Fail(ClassPermanent, "destination is not a valid international number", nil)
		}
		return m, nil
	}

	return "", Fail(ClassPermanent, "destination is not in international form", nil)
}

// stripSeparators removes the spaces, dashes and brackets a person puts in a
// phone number.
//
// IT IS HERE BECAUSE THE LOGIN PATH SENDS WHAT WAS TYPED. The handler passes
// the raw field to the sender - it has no reason to have read the number back
// from anywhere - and sys_params.MOBILE_PATTERN deliberately accepts "+966 50
// 123 4567", which is how a Gulf number is written. Without this, that number
// passes the edge check, is stored correctly by the database, and is then
// refused HERE as permanently undeliverable: the message never goes, and the
// row says the destination was invalid when it was not.
//
// THIS IS NOT THE COUNTRY RULE SNEAKING BACK INTO GO. Which country a number
// belongs to, what a mobile looks like there, and what the stored form is are
// all hbh.canonical_mobile's and hbh.country_dial_codes' business - that is
// the rule CLAUDE.md states and the reason the "+20" that used to be here is
// gone. Taking a space out of a string is not a business rule about Egypt.
//
// IT DROPS SEPARATORS AND NOTHING ELSE. The database's own canonicaliser
// strips everything that is not a digit, which would turn "0150000009a" into
// a ten-digit number and "+20150000009a" into a number that is almost right -
// and silently deleting a letter from a phone number is a guess, in the one
// place where guessing wrong means a code sent to a stranger. Anything that
// is not a digit, a plus or a separator survives to be refused by name.
func stripSeparators(mobile string) string {
	var b strings.Builder
	b.Grow(len(mobile))
	for _, r := range mobile {
		switch {
		case r == ' ', r == '\t', r == '\n', r == '\r', r == ' ',
			r == '-', r == '.', r == '(', r == ')':
			// a separator a person types; drop it
		case r >= '٠' && r <= '٩':
			// Arabic-Indic digit, as an Arabic keyboard produces it
			b.WriteRune('0' + (r - '٠'))
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}

// isE164 reports whether m is a plus, a non-zero country code, and between 8
// and 15 digits in total - the shape E.164 allows and the same expression the
// schema holds the stored column to.
func isE164(m string) bool {
	if len(m) < 9 || len(m) > 16 || m[0] != '+' || m[1] == '0' {
		return false
	}
	return allDigits(m[1:])
}

func allDigits(s string) bool {
	for _, r := range s {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// Mask is what may appear in a log or on an operations screen. The last four
// digits are enough for somebody holding the phone to recognise it and not
// enough for anybody else to dial it.
func Mask(mobile string) string {
	if len(mobile) <= 4 {
		return "****"
	}
	return "****" + mobile[len(mobile)-4:]
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// New builds the sender named by provider.
//
// "dev" is the only one that needs no configuration, and Usable refuses it
// outside development - see dev.go. An unknown name is a configuration error
// at startup rather than a surprise at the first login.
func New(provider string, cfg HTTPConfig, meta MetaConfig, env string) (Sender, error) {
	switch strings.ToLower(strings.TrimSpace(provider)) {
	case "", "dev":
		return &DevSender{Env: env}, nil
	case "http":
		return NewHTTPSender(cfg)
	case "meta_whatsapp":
		return NewMetaWhatsApp(meta)
	default:
		return nil, fmt.Errorf("SMS_PROVIDER %q is not one of dev, http, meta_whatsapp", provider)
	}
}
