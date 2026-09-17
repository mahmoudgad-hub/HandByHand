package sms

import (
	"context"
	"log/slog"
	"os"
	"strconv"
	"time"
)

// Queue is what the worker needs from the database. It is an interface rather
// than *store.DB so this package does not import the store and the store does
// not import this package - and so a test can drive the loop without one.
type Queue interface {
	ClaimSMS(ctx context.Context, limit int, worker string) ([]Claimed, error)
	RecordSMSSent(ctx context.Context, id int64, provider, msgID string) (bool, error)
	RecordSMSFailed(ctx context.Context, id int64, class, detail string) (string, error)
	// TemplateSID is the ContentSid this message's template was approved
	// under in its centre, or "" when there is none (migration 0153).
	TemplateSID(ctx context.Context, id int64) (string, error)
}

// Claimed mirrors store.Pending. The duplication is one small struct and it
// buys a package boundary with no cycle in it.
type Claimed struct {
	ID           int64
	Purpose      string
	TemplateCode string
	Destination  string
	Body         string
	Vars         []string
	Attempts     int
}

// Worker drains the outbox.
//
// HOW IT STARTS. cmd/hbhd starts one goroutine after the HTTP listener, and it
// stops on the same context the server shuts down on. There is no separate
// process and no separate deployment unit, on purpose: the periodic work this
// project already has - hbh.run_maintenance - is driven by cron on the host
// (deploy/server/cron-install.sh) because it is pure SQL. This is not: it
// makes an HTTPS call, so it has to live somewhere that can, and the API
// process is the only thing in this stack that qualifies. A second binary to
// deploy, monitor and version for one loop would be infrastructure nobody
// asked for.
//
// HOW OFTEN IT POLLS. Interval, default five seconds. Long enough that an idle
// centre is not running a query every second all night; short enough that a
// family told about a cancelled appointment hears within a few seconds. The
// claim query is a partial-index lookup returning nothing on an empty queue.
//
// HOW TWO WORKERS AVOID SENDING THE SAME MESSAGE. They cannot: hbh.claim_sms
// marks rows SENDING inside a FOR UPDATE SKIP LOCKED statement that commits
// before anything is sent, so a row is claimed by exactly one caller. Running
// two API instances is therefore safe without any coordination between them -
// which is more than can be said for the login rate limiter, and the reason
// this was done in the database rather than in memory.
//
// WHAT HAPPENS TO A MESSAGE THAT KEEPS FAILING. hbh.record_sms_failed counts
// the attempt, applies exponential backoff, and moves the row to DEAD at
// SMS_MAX_ATTEMPTS. A PERMANENT or CONFIG classification skips the counting
// and is DEAD at once. Nothing loops for ever, and nothing is deleted -
// v_sms_delivery still shows it, with the reason.
type Worker struct {
	Queue    Queue
	Sender   Sender
	Log      *slog.Logger
	Interval time.Duration
	Batch    int

	// Name identifies this worker in sms_outbox.claimed_by, so a stuck row
	// says which process was holding it.
	Name string
}

// NewWorker fills in the defaults and names the worker after the host.
func NewWorker(q Queue, s Sender, log *slog.Logger, interval time.Duration, batch int) *Worker {
	if interval <= 0 {
		interval = 5 * time.Second
	}
	if batch <= 0 {
		batch = 20
	}
	host, err := os.Hostname()
	if err != nil || host == "" {
		host = "hbhd"
	}
	return &Worker{
		Queue: q, Sender: s, Log: log,
		Interval: interval, Batch: batch,
		Name: host + ":" + strconv.Itoa(os.Getpid()),
	}
}

// Run polls until ctx is done.
func (w *Worker) Run(ctx context.Context) {
	t := time.NewTicker(w.Interval)
	defer t.Stop()

	w.Log.Info("sms worker started",
		"provider", w.Sender.Code(), "interval", w.Interval.String(), "batch", w.Batch)

	for {
		select {
		case <-ctx.Done():
			w.Log.Info("sms worker stopped")
			return
		case <-t.C:
			w.drain(ctx)
		}
	}
}

// drain does one pass. It is separate from Run so a test can call it directly
// and assert on one batch rather than racing a ticker.
func (w *Worker) drain(ctx context.Context) {
	batch, err := w.Queue.ClaimSMS(ctx, w.Batch, w.Name)
	if err != nil {
		// Not fatal and not retried here: the next tick tries again, and the
		// rows are untouched because the claim never committed.
		w.Log.WarnContext(ctx, "sms worker could not claim", "err", err)
		return
	}
	for _, m := range batch {
		select {
		case <-ctx.Done():
			// The rows stay SENDING and hbh.reap_stuck_sms brings them back
			// after SMS_STUCK_MINUTES. Returning them here would need a write
			// on a context that is already cancelled.
			return
		default:
		}
		w.send(ctx, m)
	}
}

func (w *Worker) send(ctx context.Context, m Claimed) {
	// A per-message deadline, independent of the loop's. One unresponsive
	// provider call must not hold the whole batch.
	sendCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()

	// BOTH SHAPES GO, AND THE TRANSPORT PICKS. Body is the Arabic sentence
	// PL/pgSQL rendered, which is what an SMS provider wants; Vars is the
	// same information taken apart, which is the only thing WhatsApp will
	// accept for a message the centre started. Neither this loop nor the
	// database knows which one is in use - see migration 0106.
	//
	// THE ContentSid IS READ PER MESSAGE, not once at startup: the owner
	// approves a template in the console and the next message uses it. A
	// failed lookup is a database that did not answer, not a message that
	// cannot be sent, so it goes back on the queue as TRANSIENT. Sending on
	// without it would make a WhatsApp sender refuse the message as CONFIG -
	// DEAD on the first attempt, for a fault that was ours and momentary.
	sid, err := w.Queue.TemplateSID(ctx, m.ID)
	if err != nil {
		status, rerr := w.Queue.RecordSMSFailed(ctx, m.ID, string(ClassTransient),
			"the approved template could not be looked up")
		if rerr != nil {
			w.Log.ErrorContext(ctx, "sms failure could not be recorded",
				"sms_id", m.ID, "err", rerr)
			return
		}
		w.Log.WarnContext(ctx, "sms not sent - template lookup failed",
			"sms_id", m.ID, "template", m.TemplateCode, "status", status, "err", err)
		return
	}

	res, err := w.Sender.Send(sendCtx, Message{
		To:           m.Destination,
		Body:         m.Body,
		Ref:          "sms:" + strconv.FormatInt(m.ID, 10),
		TemplateCode: m.TemplateCode,
		Vars:         m.Vars,
		ContentSID:   sid,
	})
	if err != nil {
		class, detail := ClassOf(err)
		status, rerr := w.Queue.RecordSMSFailed(ctx, m.ID, string(class), detail)
		if rerr != nil {
			w.Log.ErrorContext(ctx, "sms failure could not be recorded",
				"sms_id", m.ID, "err", rerr)
			return
		}
		// EVERY FIELD HERE IS SAFE TO WRITE DOWN. The id, the event, the
		// classification, the attempt and the outcome - no body, no number,
		// no credential. 27 of the brief, and the one line of it that is
		// easiest to break by adding a helpful debug field later.
		w.Log.WarnContext(ctx, "sms not delivered",
			"sms_id", m.ID, "template", m.TemplateCode, "purpose", m.Purpose,
			"to", Mask(m.Destination), "attempt", m.Attempts,
			"class", string(class), "status", status)
		return
	}

	ok, err := w.Queue.RecordSMSSent(ctx, m.ID, w.Sender.Code(), res.ProviderMessageID)
	if err != nil {
		// THE MESSAGE WENT AND THE DATABASE DOES NOT KNOW. This is the exact
		// window that makes the guarantee at-least-once rather than exactly
		// once: the row stays SENDING, the reaper returns it, and the family
		// may receive a second copy. It is logged at error because it is the
		// one outcome an operator should be able to count.
		w.Log.ErrorContext(ctx, "sms was accepted but the result could not be recorded",
			"sms_id", m.ID, "provider_msg_id", res.ProviderMessageID, "err", err)
		return
	}
	if !ok {
		w.Log.WarnContext(ctx, "sms was accepted but the row had already been reclaimed",
			"sms_id", m.ID)
		return
	}

	w.Log.InfoContext(ctx, "sms delivered to provider",
		"sms_id", m.ID, "template", m.TemplateCode, "purpose", m.Purpose,
		"to", Mask(m.Destination), "provider", w.Sender.Code(),
		"provider_msg_id", res.ProviderMessageID, "segments", res.Segments)
}
