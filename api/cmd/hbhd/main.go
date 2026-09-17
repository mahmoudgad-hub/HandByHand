// Command hbhd serves the Hand By Hand parent portal API.
//
// Scope: the parent portal only. The centre application is APEX 115 and stays
// there. Oracle remains production and the source of truth; this service reads
// PostgreSQL through row level security and writes no business rule of its own.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/config"
	httpapi "github.com/handbyhand/hbh/api/internal/http"
	"github.com/handbyhand/hbh/api/internal/meeting"
	"github.com/handbyhand/hbh/api/internal/sms"
	"github.com/handbyhand/hbh/api/internal/store"
)

// migrations this build requires. A database that is reachable but older than
// the code fails at boot instead of on somebody's first login.
var requiredMigrations = []string{"0001", "0002", "0003", "0004", "0005", "0006", "0007", "0008", "0009", "0012", "0013", "0014", "0016", "0017", "0018", "0019", "0020", "0021", "0026", "0027", "0028", "0031", "0032", "0033", "0034", "0035", "0036", "0037"}

func main() {
	if err := run(); err != nil {
		slog.New(slog.NewJSONHandler(os.Stderr, nil)).Error("hbhd did not start", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: cfg.LogLevel}))
	slog.SetDefault(log)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	startCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()

	db, err := store.Open(startCtx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		return err
	}
	defer db.Close()

	// The two checks that decide whether this process is allowed to exist.
	//
	// AssertSafeRole is the important one. Postgres bypasses row level
	// security for a superuser and for the owner of the table, so a service
	// that connected as hbh_owner would make every policy in the schema
	// decorative - silently, with no error and nothing in any log. There is no
	// safe way to run in that state and no way to notice it later, so the
	// process refuses to start. See docs/01-stack-decisions.md, D-2.
	if err := db.AssertSafeRole(startCtx); err != nil {
		return err
	}
	if err := db.AssertMigrated(startCtx, requiredMigrations...); err != nil {
		return err
	}

	params := store.NewParams(db, cfg.ParamCacheTTL)
	// Read the one parameter every login depends on, now rather than on the
	// first request. A seed that never ran should stop the service, not
	// produce a puzzling refusal at the login screen.
	if _, err := params.MobilePattern(startCtx); err != nil {
		return err
	}

	// THE DELIVERY CHANNEL, DECIDED BEFORE THE DOOR OPENS.
	//
	// config.Load has already refused a production process with SMS_PROVIDER
	// unset or dev; this is the second half of the same rule, and it catches
	// what configuration cannot: an https URL that does not parse, a base
	// with no host. Usable() is asked HERE rather than at the first login for
	// the reason MobilePattern is read here - a deployment that cannot
	// deliver a login code has no working front door, and it should say so
	// now rather than in front of a parent.
	sender, err := sms.New(cfg.SMSProvider, sms.HTTPConfig{
		BaseURL:       cfg.SMSHTTPURL,
		Username:      cfg.SMSHTTPUsername,
		Password:      cfg.SMSHTTPPassword,
		SenderID:      cfg.SMSHTTPSenderID,
		FieldUsername: cfg.SMSHTTPFieldUsername,
		FieldPassword: cfg.SMSHTTPFieldPassword,
		FieldSender:   cfg.SMSHTTPFieldSender,
		FieldTo:       cfg.SMSHTTPFieldTo,
		FieldBody:     cfg.SMSHTTPFieldBody,
	}, sms.TwilioConfig{
		AccountSID:          cfg.TwilioAccountSID,
		AuthToken:           cfg.TwilioAuthToken,
		From:                cfg.TwilioWhatsAppFrom,
		MessagingServiceSid: cfg.TwilioMessagingSvc,
		StatusCallback:      cfg.TwilioStatusCallback,
		AllowFreeform:       cfg.TwilioAllowFreeform,
	}, cfg.Env)
	if err != nil {
		return err
	}
	if err := sender.Usable(); err != nil {
		return err
	}
	// SAID ONCE, AT STARTUP, because nothing downstream can say it. The
	// sender has no logger and the worker cannot tell a template send from a
	// fallback, so without this line a deployment quietly sending free text
	// looks exactly like one sending approved templates. config.Load has
	// already refused this outside development; this is so the developer who
	// turned it on can see that they did.
	if cfg.TwilioAllowFreeform {
		log.Warn("TWILIO_ALLOW_FREEFORM is on - an unmapped template sends its rendered text instead of refusing",
			"note", "delivered only inside an open 24-hour WhatsApp session, such as the sandbox")
	}

	// THE LOGIN-CODE TEMPLATE, BEFORE PRODUCTION OPENS THE DOOR. It used to be
	// checked in config.Load against TWILIO_CONTENT_SIDS; the ContentSid now
	// lives in hbh.message_templates (migration 0153), so the check waits for
	// the database. A centre with no approved OTP_LOGIN template cannot send a
	// parent a login code on WhatsApp - every sign-in there fails - so the
	// process refuses to start rather than find out at a parent's first try.
	//
	// Production only. In development the sandbox and TWILIO_ALLOW_FREEFORM
	// deliver without an approved template, and a database without 0153 is
	// the normal state of a developer machine while the migration is held.
	if cfg.SMSProvider == "twilio_whatsapp" && cfg.Env != "development" {
		n, err := db.CentresWithoutTemplateSID(startCtx, "OTP_LOGIN")
		if err != nil {
			return err
		}
		if n > 0 {
			return errors.New("SMS_PROVIDER=twilio_whatsapp: " +
				"an active centre has no approved OTP_LOGIN template in hbh.message_templates - " +
				"no parent there could receive a login code")
		}
	}

	// The consultation provider, asked to prove itself at startup for the
	// same reason the sender is: a key that will not parse is a deployment
	// that cannot hold a consultation, and the place to find that out is the
	// first second of the process rather than the moment a parent presses a
	// button. meeting.PublicProvider.Usable refuses outside development.
	meetings, err := meeting.New(cfg.MeetingProvider, cfg.Env, meeting.JaaSConfig{
		AppID:         cfg.MeetingJaaSAppID,
		KeyID:         cfg.MeetingJaaSKeyID,
		PrivateKeyPEM: cfg.MeetingJaaSPrivateKey,
	})
	if err != nil {
		return err
	}
	// SAID, NOT ENFORCED, and the difference matters.
	//
	// The sender above is fatal because every deployment needs to deliver a
	// login code. Not every centre holds online consultations, and refusing
	// to start over a feature a centre does not use would be this process
	// having an opinion about their business.
	//
	// So the refusal is at the point of use - meeting_handlers.go asks
	// Usable() on every entry and answers 503, so nobody is handed a room
	// with no access control - and this is here so that a deployment which
	// DOES intend to hold consultations finds out now rather than in front
	// of a family.
	if err := meetings.Usable(); err != nil {
		log.Warn("no consultation can be held with this configuration",
			"provider", meetings.Code(), "reason", err.Error(),
			"effect", "every attempt to enter a consultation answers 503")
	} else {
		log.Info("consultation video provider", "provider", meetings.Code())
	}

	srv := &http.Server{
		Addr:              cfg.Listen,
		Handler:           httpapi.NewServer(cfg, db, params, audit.New(db.Pool(), log), log, sender, meetings).Handler(),
		ReadHeaderTimeout: config.ReadHeaderTimeout,
		ReadTimeout:       config.ReadTimeout,
		WriteTimeout:      config.WriteTimeout,
		IdleTimeout:       config.IdleTimeout,
		ErrorLog:          slog.NewLogLogger(log.Handler(), slog.LevelWarn),
	}

	// The outbox worker. One goroutine, started after the pool is proven and
	// stopped by the same signal the server is. It lives in this process
	// because it makes an HTTPS call and the API is the only thing in this
	// stack that can - hbh.run_maintenance is cron'd on the host precisely
	// because it is pure SQL. See sms.Worker's header.
	go sms.NewWorker(smsQueue{db}, sender, log,
		cfg.SMSWorkerInterval, cfg.SMSWorkerBatch).Run(ctx)

	errc := make(chan error, 1)
	go func() {
		log.Info("hbhd listening", "addr", cfg.Listen, "env", cfg.Env)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errc <- err
		}
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		log.Info("shutting down")
	}

	// Let in-flight requests finish. An audit write started by a request is
	// on its own context and completes regardless.
	shutdownCtx, cancelShutdown := context.WithTimeout(context.Background(), cfg.ShutdownGrace)
	defer cancelShutdown()
	return srv.Shutdown(shutdownCtx)
}

// smsQueue adapts *store.DB to sms.Queue.
//
// The two structs it converts between are identical, and the duplication is
// the price of a package boundary with no cycle in it: internal/sms must not
// import internal/store, because the store already imports nothing above it
// and a delivery package that reaches into the data layer is one refactor away
// from putting a retry rule there. Twelve lines, once, in the composition root
// - which is where wiring belongs.
type smsQueue struct{ db *store.DB }

func (q smsQueue) ClaimSMS(ctx context.Context, limit int, worker string) ([]sms.Claimed, error) {
	rows, err := q.db.ClaimSMS(ctx, limit, worker)
	if err != nil {
		return nil, err
	}
	out := make([]sms.Claimed, 0, len(rows))
	for _, r := range rows {
		out = append(out, sms.Claimed{
			ID: r.ID, Purpose: r.Purpose, TemplateCode: r.TemplateCode,
			Destination: r.Destination, Body: r.Body, Vars: r.Vars,
			Attempts: r.Attempts,
		})
	}
	return out, nil
}

func (q smsQueue) RecordSMSSent(ctx context.Context, id int64, provider, msgID string) (bool, error) {
	return q.db.RecordSMSSent(ctx, id, provider, msgID)
}

func (q smsQueue) RecordSMSFailed(ctx context.Context, id int64, class, detail string) (string, error) {
	return q.db.RecordSMSFailed(ctx, id, class, detail)
}

func (q smsQueue) TemplateSID(ctx context.Context, id int64) (string, error) {
	return q.db.SMSTemplateSID(ctx, id)
}
