package sms

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"sync"
	"testing"
)

// fakeQueue stands in for the database so the loop can be driven without one.
// What it does NOT do is make a decision: the status it returns for a failure
// is the one the real hbh.record_sms_failed would return, because the retry
// rule lives there and a fake that invented its own would be testing itself.
type fakeQueue struct {
	mu      sync.Mutex
	pending []Claimed
	sent    []int64
	failed  []string
	nextSt  string
	claimEr error
	sentEr  error
	sid     string
	sidEr   error
}

func (q *fakeQueue) TemplateSID(context.Context, int64) (string, error) {
	return q.sid, q.sidEr
}

// captureSender accepts every message and keeps what it was handed, so a test
// can see which ContentSid the worker put on it.
type captureSender struct {
	mu  sync.Mutex
	got []Message
}

func (c *captureSender) Send(_ context.Context, m Message) (Result, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.got = append(c.got, m)
	return Result{ProviderMessageID: "cap-1"}, nil
}
func (c *captureSender) Code() string  { return "capture" }
func (c *captureSender) Usable() error { return nil }

// The ContentSid is read per message and travels on it - the owner approves
// a template and the next message uses it, with no restart.
func TestWorkerPutsTheApprovedTemplateOnTheMessage(t *testing.T) {
	q := &fakeQueue{
		pending: []Claimed{{ID: 3, Destination: "+201500000093", TemplateCode: "APPOINTMENT_BOOKED", Body: "x"}},
		sid:     "HX00000000000000000000000000000042",
	}
	s := &captureSender{}
	NewWorker(q, s, quiet(), 0, 0).drain(context.Background())
	if len(s.got) != 1 || s.got[0].ContentSID != q.sid {
		t.Fatalf("the approved ContentSid did not reach the sender: %+v", s.got)
	}
	if len(q.sent) != 1 {
		t.Fatalf("want the message recorded as sent, got %v", q.sent)
	}
}

// A lookup that fails is our database not answering, not a message that
// cannot be sent. It must go back on the queue as TRANSIENT and must NOT
// reach the sender - which would refuse it as CONFIG and kill it on the first
// attempt for a fault that was ours.
func TestWorkerRetriesWhenTheTemplateLookupFails(t *testing.T) {
	q := &fakeQueue{
		pending: []Claimed{{ID: 4, Destination: "+201500000093", TemplateCode: "APPOINTMENT_BOOKED", Body: "x"}},
		sidEr:   errors.New("database went away"),
	}
	s := &captureSender{}
	NewWorker(q, s, quiet(), 0, 0).drain(context.Background())
	if len(s.got) != 0 {
		t.Fatal("a message whose template could not be looked up must not be sent")
	}
	if len(q.failed) != 1 || q.failed[0] != string(ClassTransient) {
		t.Fatalf("want one TRANSIENT failure recorded, got %v", q.failed)
	}
}

func (q *fakeQueue) ClaimSMS(context.Context, int, string) ([]Claimed, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.claimEr != nil {
		return nil, q.claimEr
	}
	out := q.pending
	q.pending = nil
	return out, nil
}

func (q *fakeQueue) RecordSMSSent(_ context.Context, id int64, _, _ string) (bool, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	if q.sentEr != nil {
		return false, q.sentEr
	}
	q.sent = append(q.sent, id)
	return true, nil
}

func (q *fakeQueue) RecordSMSFailed(_ context.Context, _ int64, class, _ string) (string, error) {
	q.mu.Lock()
	defer q.mu.Unlock()
	q.failed = append(q.failed, class)
	if q.nextSt == "" {
		return "PENDING", nil
	}
	return q.nextSt, nil
}

func quiet() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

func TestWorkerSendsAClaimedBatchAndRecordsEachOne(t *testing.T) {
	q := &fakeQueue{pending: []Claimed{
		{ID: 1, Purpose: "NOTIFICATION", TemplateCode: "REPORT_PUBLISHED",
			Destination: "+201500000093", Body: "x"},
		{ID: 2, Purpose: "NOTIFICATION", TemplateCode: "APPOINTMENT_BOOKED",
			Destination: "+201500000094", Body: "y"},
	}}
	d := &DevSender{Env: "development"}
	NewWorker(q, d, quiet(), 0, 0).drain(context.Background())

	if len(q.sent) != 2 {
		t.Fatalf("want two recorded sends, got %v", q.sent)
	}
	if len(d.Sent()) != 2 {
		t.Fatalf("want two provider calls, got %d", len(d.Sent()))
	}
}

// The classification reaches the database unchanged. This is the join between
// the two halves of the retry policy: Go decides WHAT KIND of failure it was
// and PL/pgSQL decides what that means for a retry. A worker that decided both
// would be a second copy of the rule.
func TestWorkerPassesTheClassificationThrough(t *testing.T) {
	for _, c := range []struct {
		class Class
		as    string
	}{
		{ClassTransient, "TRANSIENT"},
		{ClassPermanent, "PERMANENT"},
		{ClassConfig, "CONFIG"},
	} {
		q := &fakeQueue{pending: []Claimed{{ID: 7, Destination: "+201500000093", Body: "x"}}}
		NewWorker(q, &FailingSender{Class: c.class, Detail: "simulated"}, quiet(), 0, 0).
			drain(context.Background())
		if len(q.failed) != 1 || q.failed[0] != c.as {
			t.Fatalf("want %s recorded, got %v", c.as, q.failed)
		}
		if len(q.sent) != 0 {
			t.Fatal("a failed message must not be recorded as sent")
		}
	}
}

// An invalid number never reaches the provider - E164 refuses it inside the
// sender - and is recorded PERMANENT, which is what makes it DEAD at once
// rather than retried until the ceiling.
func TestWorkerRecordsAnInvalidNumberAsPermanent(t *testing.T) {
	q := &fakeQueue{
		pending: []Claimed{{ID: 9, Destination: "UNKNOWN", Body: "x"}},
		nextSt:  "DEAD",
	}
	NewWorker(q, &DevSender{Env: "development"}, quiet(), 0, 0).drain(context.Background())
	if len(q.failed) != 1 || q.failed[0] != "PERMANENT" {
		t.Fatalf("want one PERMANENT failure, got %v", q.failed)
	}
}

// A claim that fails leaves everything alone and says so. The rows were never
// marked SENDING because the claim never committed, so the next tick simply
// tries again - there is nothing to undo.
func TestWorkerSurvivesAClaimFailure(t *testing.T) {
	q := &fakeQueue{claimEr: errors.New("database went away")}
	NewWorker(q, &DevSender{Env: "development"}, quiet(), 0, 0).drain(context.Background())
	if len(q.sent) != 0 || len(q.failed) != 0 {
		t.Fatal("a claim failure must not produce a send or a failure record")
	}
}

// THE AT-LEAST-ONCE WINDOW, made explicit rather than left to a comment.
//
// The provider accepted the message and the result could not be written. The
// worker must NOT retry here: the row stays SENDING, hbh.reap_stuck_sms returns
// it after SMS_STUCK_MINUTES, and the family may get a second copy. Sending
// again immediately would turn a rare duplicate into a guaranteed one.
func TestWorkerDoesNotResendWhenTheResultCannotBeRecorded(t *testing.T) {
	d := &DevSender{Env: "development"}
	q := &fakeQueue{
		pending: []Claimed{{ID: 11, Destination: "+201500000093", Body: "x"}},
		sentEr:  errors.New("commit failed"),
	}
	NewWorker(q, d, quiet(), 0, 0).drain(context.Background())

	if len(d.Sent()) != 1 {
		t.Fatalf("the provider must have been called exactly once, got %d", len(d.Sent()))
	}
	if len(q.failed) != 0 {
		t.Fatal("a message the provider ACCEPTED must not be recorded as failed")
	}
}

// A cancelled context stops the batch without writing on it. Anything already
// claimed stays SENDING and the reaper is what brings it back.
func TestWorkerStopsOnCancellation(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	d := &DevSender{Env: "development"}
	q := &fakeQueue{pending: []Claimed{{ID: 1, Destination: "+201500000093", Body: "x"}}}
	NewWorker(q, d, quiet(), 0, 0).drain(ctx)
	if len(d.Sent()) != 0 {
		t.Fatal("nothing should have been sent after cancellation")
	}
}
