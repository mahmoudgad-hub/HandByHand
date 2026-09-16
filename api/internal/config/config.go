// Package config loads the service configuration from the environment.
//
// No business value is written in this package. Anything a centre could
// reasonably want to change - the accepted mobile pattern, the length of a
// one-time code, how long a session lives - is a row in hbh.sys_params and is
// read at runtime through store.Params. What lives here is deployment wiring
// only: where to listen, which database to reach, how loudly to log.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strconv"
	"strings"
	"time"
)

// Config is the fully resolved configuration for one process.
type Config struct {
	// Env is "development" or "production". It gates the developer-only
	// affordances below; nothing else branches on it.
	Env string

	Listen      string
	DatabaseURL string
	DBMaxConns  int32

	LogLevel slog.Level

	// CORSOrigins is the exact allow list. Empty means no cross-origin
	// request is answered at all, which is the correct production value
	// once the Angular bundle is served from the same origin.
	CORSOrigins []string

	// TrustProxy decides whether X-Forwarded-For is believed. It must stay
	// false unless a proxy we control actually sets that header: the value
	// ends up in the audit log as the client address, and a header a client
	// can write is a client-controlled audit trail.
	TrustProxy bool

	// OTPEcho returns the generated one-time code in the HTTP response.
	// There is no SMS gateway yet, and the acceptance suite has no other way
	// to learn the code, so this exists - but Load refuses to start a
	// non-development process with it on.
	OTPEcho bool

	AuthRatePerMinute int
	ParamCacheTTL     time.Duration
	ShutdownGrace     time.Duration

	// RequestLog writes one row per finished request to hbh.api_request_log,
	// which is what the operations screen reads.
	//
	// It defaults to ON and there is a switch only because it costs a
	// database round trip per request: an operator watching a service under
	// load must be able to turn off the thing that is measuring it. It is not
	// a privacy switch - the row carries a route template, a status and a
	// duration, never a body and never a query string.
	RequestLog bool

	// SiteAssetsDir is where an uploaded photograph or introduction film is
	// written. Empty disables uploading entirely, and that is the default:
	// a service with nowhere safe to put a file should refuse to take one
	// rather than invent a directory.
	//
	// The database stores the PATH and never the bytes. A film in a bytea
	// column would land in every pg_dump, and this project has already been
	// bitten once by what its backups quietly contained.
	SiteAssetsDir string

	// StaffDocsDir is where a member of staff's scanned documents are
	// written. It is a DIFFERENT directory from SiteAssetsDir and that is
	// the point: the site's media is served by an unauthenticated route,
	// because it is bound for a public page. A scan of somebody's identity
	// card is the opposite of that, and the surest way to leak one is to
	// put it in a directory an open route already serves.
	//
	// Empty disables staff document upload entirely, which is the default:
	// a service with nowhere safe to put a file should refuse to take one.
	StaffDocsDir string

	// SMSProvider selects the delivery implementation: "dev", "http" or
	// "twilio_whatsapp".
	//
	// "dev" accepts every message and sends nothing, which is right on a
	// laptop and catastrophic in production - a centre whose parents cannot
	// receive a login code, reporting a healthy service. Load refuses it
	// outside development for exactly the reason it refuses OTPEcho, and the
	// two rules together are the whole of the production fail-closed
	// guarantee: a production process either has a real provider or does not
	// start.
	SMSProvider string

	// SMSHTTP is the provider account. Every field is a secret or an address
	// and none of them is written to the database, to a log, or to an error
	// detail - hbh.sms_outbox records only the message id the provider
	// hands back.
	SMSHTTPURL      string
	SMSHTTPUsername string
	SMSHTTPPassword string
	SMSHTTPSenderID string

	// Field names differ between Egyptian bulk providers and are the
	// difference between supporting one and supporting the next. Empty means
	// the common defaults; see sms.withFieldDefaults.
	SMSHTTPFieldUsername string
	SMSHTTPFieldPassword string
	SMSHTTPFieldSender   string
	SMSHTTPFieldTo       string
	SMSHTTPFieldBody     string

	// Twilio, when SMS_PROVIDER is twilio_whatsapp. The account sid and token
	// are secrets on the same terms as the bulk-provider account above.
	//
	// TwilioContentSIDs maps a template_code to the ContentSid Meta approved
	// for it, read from TWILIO_CONTENT_<CODE>. It is a map and not four named
	// fields because the set of templates grows with the centre's messages
	// and a new one should be an environment line, not a build.
	TwilioAccountSID     string
	TwilioAuthToken      string
	TwilioWhatsAppFrom   string
	TwilioMessagingSvc   string
	TwilioStatusCallback string
	TwilioContentSIDs    map[string]string

	// TwilioAllowFreeform sends the rendered Arabic when a template code has
	// no approved ContentSid, instead of refusing. It exists so a developer
	// can watch a login code arrive on a real handset inside Twilio's WhatsApp
	// sandbox, which opens a 24-hour session, before Meta has approved
	// anything. Load refuses it outside development for the same reason it
	// refuses OTPEcho: outside that window WhatsApp rejects free text every
	// time, so in production it would retry an identical refusal to the end of
	// the ladder and deliver nothing.
	TwilioAllowFreeform bool

	// SMSWorkerInterval is how often the outbox is polled, and SMSWorkerBatch
	// how many messages one pass claims. Neither is a business value: what to
	// send and when to give up are decided in PL/pgSQL.
	SMSWorkerInterval time.Duration
	SMSWorkerBatch    int
}

// Fixed transport limits. These are not business values and are not worth an
// environment variable; they exist so a slow or hostile client cannot hold a
// connection open indefinitely.
const (
	ReadHeaderTimeout = 5 * time.Second
	ReadTimeout       = 15 * time.Second
	WriteTimeout      = 30 * time.Second
	IdleTimeout       = 60 * time.Second
	MaxRequestBody    = 64 * 1024

	// Uploads have their own ceilings, because MaxRequestBody is sized for a
	// JSON body and would refuse every photograph. They are applied by the
	// upload handler alone - no other route reads them.
	MaxImageUpload = 6 * 1024 * 1024
	MaxVideoUpload = 120 * 1024 * 1024
)

// Load reads the process environment.
func Load() (Config, error) {
	return loadFrom(os.Getenv)
}

func loadFrom(getenv func(string) string) (Config, error) {
	cfg := Config{
		Env:               str(getenv, "APP_ENV", "development"),
		Listen:            str(getenv, "API_LISTEN", ":8090"),
		DatabaseURL:       getenv("DATABASE_URL"),
		DBMaxConns:        8,
		AuthRatePerMinute: 10,
		ParamCacheTTL:     60 * time.Second,
		ShutdownGrace:     15 * time.Second,
		SMSWorkerInterval: 5 * time.Second,
		SMSWorkerBatch:    20,
	}

	var errs []error

	if cfg.DatabaseURL == "" {
		errs = append(errs, errors.New("DATABASE_URL is required"))
	}
	if cfg.Env != "development" && cfg.Env != "production" {
		errs = append(errs, fmt.Errorf("APP_ENV must be development or production, got %q", cfg.Env))
	}

	lvl, err := level(str(getenv, "LOG_LEVEL", "info"))
	if err != nil {
		errs = append(errs, err)
	}
	cfg.LogLevel = lvl

	if v := strings.TrimSpace(getenv("CORS_ORIGINS")); v != "" {
		for _, o := range strings.Split(v, ",") {
			if o = strings.TrimSpace(o); o != "" {
				cfg.CORSOrigins = append(cfg.CORSOrigins, o)
			}
		}
	}

	if cfg.TrustProxy, err = boolean(getenv, "TRUST_PROXY", false); err != nil {
		errs = append(errs, err)
	}
	if cfg.OTPEcho, err = boolean(getenv, "OTP_ECHO", false); err != nil {
		errs = append(errs, err)
	}
	if cfg.RequestLog, err = boolean(getenv, "REQUEST_LOG", true); err != nil {
		errs = append(errs, err)
	}
	cfg.SiteAssetsDir = strings.TrimSpace(getenv("SITE_ASSETS_DIR"))
	cfg.StaffDocsDir = strings.TrimSpace(getenv("STAFF_DOCS_DIR"))

	cfg.SMSProvider = strings.ToLower(str(getenv, "SMS_PROVIDER", "dev"))
	cfg.SMSHTTPURL = strings.TrimSpace(getenv("SMS_HTTP_URL"))
	cfg.SMSHTTPUsername = strings.TrimSpace(getenv("SMS_HTTP_USERNAME"))
	cfg.SMSHTTPPassword = getenv("SMS_HTTP_PASSWORD")
	cfg.SMSHTTPSenderID = strings.TrimSpace(getenv("SMS_HTTP_SENDER_ID"))
	cfg.SMSHTTPFieldUsername = strings.TrimSpace(getenv("SMS_HTTP_FIELD_USERNAME"))
	cfg.SMSHTTPFieldPassword = strings.TrimSpace(getenv("SMS_HTTP_FIELD_PASSWORD"))
	cfg.SMSHTTPFieldSender = strings.TrimSpace(getenv("SMS_HTTP_FIELD_SENDER"))
	cfg.SMSHTTPFieldTo = strings.TrimSpace(getenv("SMS_HTTP_FIELD_TO"))
	cfg.SMSHTTPFieldBody = strings.TrimSpace(getenv("SMS_HTTP_FIELD_BODY"))
	cfg.TwilioAccountSID = strings.TrimSpace(getenv("TWILIO_ACCOUNT_SID"))
	cfg.TwilioAuthToken = getenv("TWILIO_AUTH_TOKEN")
	cfg.TwilioWhatsAppFrom = strings.TrimSpace(getenv("TWILIO_WHATSAPP_FROM"))
	cfg.TwilioMessagingSvc = strings.TrimSpace(getenv("TWILIO_MESSAGING_SERVICE_SID"))
	cfg.TwilioStatusCallback = strings.TrimSpace(getenv("TWILIO_STATUS_CALLBACK"))
	if cfg.TwilioContentSIDs, err = contentSIDs(getenv("TWILIO_CONTENT_SIDS")); err != nil {
		errs = append(errs, err)
	}
	if cfg.TwilioAllowFreeform, err = boolean(getenv, "TWILIO_ALLOW_FREEFORM", false); err != nil {
		errs = append(errs, err)
	}
	if cfg.SMSWorkerInterval, err = seconds(getenv, "SMS_WORKER_SECONDS", cfg.SMSWorkerInterval); err != nil {
		errs = append(errs, err)
	}
	if cfg.SMSWorkerBatch, err = integer(getenv, "SMS_WORKER_BATCH", cfg.SMSWorkerBatch); err != nil {
		errs = append(errs, err)
	}
	if cfg.DBMaxConns, err = integer32(getenv, "DB_MAX_CONNS", cfg.DBMaxConns); err != nil {
		errs = append(errs, err)
	}
	if cfg.AuthRatePerMinute, err = integer(getenv, "AUTH_RATE_PER_MINUTE", cfg.AuthRatePerMinute); err != nil {
		errs = append(errs, err)
	}
	if cfg.ParamCacheTTL, err = seconds(getenv, "PARAM_CACHE_SECONDS", cfg.ParamCacheTTL); err != nil {
		errs = append(errs, err)
	}
	if cfg.ShutdownGrace, err = seconds(getenv, "SHUTDOWN_GRACE_SECONDS", cfg.ShutdownGrace); err != nil {
		errs = append(errs, err)
	}

	// THE CROSS-FIELD RULES, and the reason this function returns an error at
	// all. Both are about the same door.
	//
	// A production process that echoes one-time codes has published every
	// account on it; refusing to start is the only safe response, because a
	// warning in a log nobody reads is not a control.
	if cfg.OTPEcho && cfg.Env != "development" {
		errs = append(errs, errors.New("OTP_ECHO is a development-only affordance and must not be set when APP_ENV is not development"))
	}

	// THE THIRD AFFORDANCE OF THE SAME FAMILY, and it fails the same way if
	// it escapes: quietly. A WhatsApp message the centre starts is refused as
	// free text with error 63016 outside a 24-hour session, and every message
	// this centre starts is outside one. So in production this setting does
	// not send the message a different way - it sends nothing, five times,
	// and writes failures that name a template rather than the approval
	// nobody asked for. Refusing to start is the only honest response.
	if cfg.TwilioAllowFreeform && cfg.Env != "development" {
		errs = append(errs, errors.New("TWILIO_ALLOW_FREEFORM is a development-only affordance and must not be set when APP_ENV is not development"))
	}

	// And the half that was missing until C5. Turning OTP_ECHO off without a
	// provider does not make production safe, it makes production UNUSABLE -
	// quietly. Every login would be accepted, every code generated and
	// discarded, and the service would report itself healthy while no parent
	// could sign in. There is no message in any log that says "nobody can
	// authenticate"; there is only silence and a support call weeks later.
	//
	// The two rules together are the guarantee: a production process has a
	// real delivery channel, or it does not start. Neither can be satisfied
	// by remembering to set something.
	if cfg.Env != "development" {
		switch cfg.SMSProvider {
		case "dev", "":
			errs = append(errs, errors.New("SMS_PROVIDER=dev delivers nothing - a production process must be given a real provider (SMS_PROVIDER=http or twilio_whatsapp)"))
		case "http":
			// The presence of every credential is checked here rather than at
			// the first login, for the same reason MobilePattern is read at
			// startup: a missing setting should stop the service, not produce
			// a puzzling refusal at the login screen.
			for _, p := range []struct {
				name, value string
			}{
				{"SMS_HTTP_URL", cfg.SMSHTTPURL},
				{"SMS_HTTP_USERNAME", cfg.SMSHTTPUsername},
				{"SMS_HTTP_PASSWORD", cfg.SMSHTTPPassword},
				{"SMS_HTTP_SENDER_ID", cfg.SMSHTTPSenderID},
			} {
				if strings.TrimSpace(p.value) == "" {
					errs = append(errs, fmt.Errorf("SMS_PROVIDER=http needs %s", p.name))
				}
			}
		case "twilio_whatsapp":
			for _, p := range []struct {
				name, value string
			}{
				{"TWILIO_ACCOUNT_SID", cfg.TwilioAccountSID},
				{"TWILIO_AUTH_TOKEN", cfg.TwilioAuthToken},
			} {
				if strings.TrimSpace(p.value) == "" {
					errs = append(errs, fmt.Errorf("SMS_PROVIDER=twilio_whatsapp needs %s", p.name))
				}
			}
			if strings.TrimSpace(cfg.TwilioWhatsAppFrom) == "" &&
				strings.TrimSpace(cfg.TwilioMessagingSvc) == "" {
				errs = append(errs, errors.New(
					"SMS_PROVIDER=twilio_whatsapp needs TWILIO_WHATSAPP_FROM or TWILIO_MESSAGING_SERVICE_SID"))
			}
			// A login code is the one message whose absence closes the front
			// door, so its template is required rather than discovered at the
			// first attempt. Every other template fails one message; this one
			// fails every sign-in.
			if _, ok := cfg.TwilioContentSIDs["OTP_LOGIN"]; !ok {
				errs = append(errs, errors.New(
					"SMS_PROVIDER=twilio_whatsapp needs TWILIO_CONTENT_SIDS to map OTP_LOGIN - "+
						"without it no parent can receive a login code"))
			}
		default:
			errs = append(errs, fmt.Errorf("SMS_PROVIDER must be dev, http or twilio_whatsapp, got %q", cfg.SMSProvider))
		}
	}

	if len(errs) > 0 {
		return Config{}, errors.Join(errs...)
	}
	return cfg, nil
}

// contentSIDs parses TWILIO_CONTENT_SIDS: CODE=SID pairs, comma separated.
//
// A MALFORMED ENTRY IS AN ERROR AND NOT A SKIP. Dropping the pair somebody
// mistyped leaves a template unmapped, and an unmapped template is a CONFIG
// failure at the moment a family was owed a message rather than at startup -
// the same shape as every other setting this file refuses to guess at.
func contentSIDs(raw string) (map[string]string, error) {
	out := map[string]string{}
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return out, nil
	}
	for _, pair := range strings.Split(raw, ",") {
		pair = strings.TrimSpace(pair)
		if pair == "" {
			continue
		}
		code, sid, ok := strings.Cut(pair, "=")
		code, sid = strings.TrimSpace(code), strings.TrimSpace(sid)
		if !ok || code == "" || sid == "" {
			return nil, fmt.Errorf("TWILIO_CONTENT_SIDS entry %q is not CODE=SID", pair)
		}
		if _, dup := out[code]; dup {
			// Last-wins would make which template a family receives depend on
			// the order of an environment string.
			return nil, fmt.Errorf("TWILIO_CONTENT_SIDS names %q twice", code)
		}
		out[code] = sid
	}
	return out, nil
}

func str(getenv func(string) string, key, def string) string {
	if v := strings.TrimSpace(getenv(key)); v != "" {
		return v
	}
	return def
}

func boolean(getenv func(string) string, key string, def bool) (bool, error) {
	v := strings.TrimSpace(getenv(key))
	if v == "" {
		return def, nil
	}
	b, err := strconv.ParseBool(v)
	if err != nil {
		return def, fmt.Errorf("%s: %q is not a boolean", key, v)
	}
	return b, nil
}

func integer(getenv func(string) string, key string, def int) (int, error) {
	v := strings.TrimSpace(getenv(key))
	if v == "" {
		return def, nil
	}
	n, err := strconv.Atoi(v)
	if err != nil || n <= 0 {
		return def, fmt.Errorf("%s: %q is not a positive integer", key, v)
	}
	return n, nil
}

func integer32(getenv func(string) string, key string, def int32) (int32, error) {
	n, err := integer(getenv, key, int(def))
	if err != nil {
		return def, err
	}
	return int32(n), nil
}

func seconds(getenv func(string) string, key string, def time.Duration) (time.Duration, error) {
	n, err := integer(getenv, key, int(def/time.Second))
	if err != nil {
		return def, err
	}
	return time.Duration(n) * time.Second, nil
}

func level(s string) (slog.Level, error) {
	switch strings.ToLower(s) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return slog.LevelInfo, fmt.Errorf("LOG_LEVEL: %q is not one of debug, info, warn, error", s)
	}
}
