package sms

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"sync"
	"time"
)

// DevSender accepts every message and sends nothing.
//
// WHAT IT IS FOR. The acceptance suites need a delivery path that costs
// nothing and is deterministic, and a developer needs the portal to work on a
// laptop with no provider contract. Both are real, and both are the reason the
// obvious shortcut - "no sender configured, so skip sending and mark it sent" -
// must not exist: that shortcut would look identical in production.
//
// WHAT IT DOES NOT DO, and this is the line the brief draws twice. It does not
// write the message body anywhere a log collector would find it, and it does
// not touch a one-time code at all. Message.Body for an OTP is the rendered
// template WITH THE CODE IN IT; printing that to stdout would put live
// credentials in the container log, which is the same leak as OTP_ECHO without
// the config guard in front of it. So what it records is the destination
// masked, the reference, and the length - enough to prove delivery was
// attempted and nothing that helps anybody sign in.
//
// The development affordance that DOES reveal the code is OTP_ECHO, which
// config.Load refuses outside development. One exposed path, one guard on it.
type DevSender struct {
	Env string

	mu   sync.Mutex
	sent []Record
}

// Record is what a test can ask about afterwards. It is the whole reason
// DevSender keeps anything in memory: a suite has to be able to assert that a
// message was requested, to the right number, for the right event - without
// ever seeing the body.
type Record struct {
	To   string // masked
	Ref  string
	Size int
	At   time.Time
}

func (d *DevSender) Code() string { return "dev" }

// Usable refuses outside development.
//
// This is the second half of the production fail-closed rule, and it closes
// the gap OTP_ECHO alone leaves. config.Load already refuses to start a
// production process that ECHOES codes; without this, a production process
// with no provider configured would start happily, accept a login, queue the
// code, hand it to a sender that throws it away, and report a healthy
// authentication system to which nobody can ever sign in. Silence is the worst
// of the three outcomes, so it is the one that is removed.
func (d *DevSender) Usable() error {
	if d.Env != "development" {
		return errors.New("SMS_PROVIDER=dev delivers nothing and must not be used when APP_ENV is not development - configure a real provider")
	}
	return nil
}

func (d *DevSender) Send(_ context.Context, m Message) (Result, error) {
	// The number is still validated. A test that passes a malformed
	// destination should fail here for the same reason a real provider would
	// reject it, or the dev path proves nothing about the real one.
	if _, err := E164(m.To); err != nil {
		return Result{}, err
	}

	d.mu.Lock()
	d.sent = append(d.sent, Record{
		To:   Mask(m.To),
		Ref:  m.Ref,
		Size: len([]rune(m.Body)),
		At:   time.Now().UTC(),
	})
	n := len(d.sent)
	d.mu.Unlock()

	return Result{
		ProviderMessageID: "dev-" + strconv.Itoa(n),
		// Arabic is UCS-2, so 70 runes to a segment. Reported rather than
		// billed - the point is that a suite can see a long template would
		// have cost three messages before a family pays for it.
		Segments: segmentsUCS2(len([]rune(m.Body))),
	}, nil
}

// Sent returns a copy of what was accepted, for tests.
func (d *DevSender) Sent() []Record {
	d.mu.Lock()
	defer d.mu.Unlock()
	out := make([]Record, len(d.sent))
	copy(out, d.sent)
	return out
}

func segmentsUCS2(runes int) int {
	switch {
	case runes == 0:
		return 0
	case runes <= 70:
		return 1
	default:
		// Concatenated UCS-2 spends 3 characters per part on the header.
		return (runes + 66) / 67
	}
}

// FailingSender is a Sender that refuses in a stated way.
//
// It exists so the acceptance suite can produce a timeout, a 500, a rate limit
// and an invalid number WITHOUT a provider account and without waiting for a
// real one to misbehave. Retry policy, the attempt ceiling and the dead-letter
// transition are business rules in PL/pgSQL, and a rule nothing can make fail
// is a rule nobody has tested.
type FailingSender struct {
	Class  Class
	Detail string
}

func (f *FailingSender) Code() string  { return "failing" }
func (f *FailingSender) Usable() error { return nil }

func (f *FailingSender) Send(context.Context, Message) (Result, error) {
	return Result{}, Fail(f.Class, f.Detail, fmt.Errorf("simulated %s failure", f.Class))
}
