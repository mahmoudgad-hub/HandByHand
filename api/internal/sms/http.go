package sms

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// HTTPSender is the integration boundary for an Egyptian bulk-SMS provider.
//
// WHAT THIS IS AND IS NOT. It is a complete, tested transport: it builds the
// request, sends UTF-8, reads the answer, classifies the failure and reports
// the provider's message id. It is NOT a verified integration with a named
// company, because no provider has been contracted and no credentials exist in
// this environment - docs/architect/01-proposals.md 0.2 names Vodafone Bulk
// and SMSMisr as candidates and says the contract is longer than the code.
// The report for this phase states those as two separate facts and does not
// blur them.
//
// WHY A FORM POST AND NOT A VENDOR SDK. Every Egyptian bulk provider this
// project has looked at exposes the same shape: an HTTP endpoint taking a
// username, a password or token, a sender id, a destination and a body, and
// answering with a status and a message id. Naming the fields in configuration
// rather than in code means the next provider is an environment change, which
// is precisely what 0.2 asks for - "one interface in Go replaced by a line of
// configuration".
//
// NO CREDENTIAL IS WRITTEN DOWN HERE. Username, password and sender id come
// from the process environment, are never logged, never put in an error
// detail, and never reach hbh.sms_outbox. The only provider fact that is
// persisted is the message id it hands back.
type HTTPSender struct {
	cfg    HTTPConfig
	client *http.Client
}

// HTTPConfig is deployment wiring. Every field is an environment variable and
// none of them is a business value - no message text, no retry count, no
// destination lives here.
type HTTPConfig struct {
	// BaseURL is the provider's send endpoint.
	BaseURL string
	// Username and Password are the provider account. They are secrets.
	Username string
	Password string
	// SenderID is the alphanumeric originator the provider registered for
	// this centre. Providers refuse a message with an unregistered one, which
	// is a CONFIG failure and not the family's problem.
	SenderID string

	// Field names, because providers disagree about them and this is the
	// difference between supporting one and supporting the next.
	FieldUsername string
	FieldPassword string
	FieldSender   string
	FieldTo       string
	FieldBody     string

	Timeout time.Duration
}

// Complete reports whether this deployment has been given enough to send.
func (c HTTPConfig) Complete() error {
	var missing []string
	if strings.TrimSpace(c.BaseURL) == "" {
		missing = append(missing, "SMS_HTTP_URL")
	}
	if strings.TrimSpace(c.Username) == "" {
		missing = append(missing, "SMS_HTTP_USERNAME")
	}
	if strings.TrimSpace(c.Password) == "" {
		missing = append(missing, "SMS_HTTP_PASSWORD")
	}
	if strings.TrimSpace(c.SenderID) == "" {
		missing = append(missing, "SMS_HTTP_SENDER_ID")
	}
	if len(missing) > 0 {
		return fmt.Errorf("SMS_PROVIDER=http needs %s", strings.Join(missing, ", "))
	}
	return nil
}

// NewHTTPSender validates the configuration at construction, so a deployment
// that cannot send says so at startup rather than on somebody's first login.
func NewHTTPSender(cfg HTTPConfig) (*HTTPSender, error) {
	if err := cfg.Complete(); err != nil {
		return nil, err
	}
	u, err := url.Parse(strings.TrimSpace(cfg.BaseURL))
	if err != nil {
		return nil, fmt.Errorf("SMS_HTTP_URL is not a URL: %w", err)
	}
	if u.Scheme != "https" {
		// A login code and a family's number crossing the open internet in
		// clear text is the same class of defect as the API on plain HTTP,
		// and there is no provider worth using that requires it.
		return nil, errors.New("SMS_HTTP_URL must be https")
	}
	if u.Host == "" {
		return nil, errors.New("SMS_HTTP_URL has no host")
	}

	cfg = withFieldDefaults(cfg)
	if cfg.Timeout <= 0 {
		cfg.Timeout = 10 * time.Second
	}
	return &HTTPSender{cfg: cfg, client: &http.Client{Timeout: cfg.Timeout}}, nil
}

func withFieldDefaults(c HTTPConfig) HTTPConfig {
	if c.FieldUsername == "" {
		c.FieldUsername = "username"
	}
	if c.FieldPassword == "" {
		c.FieldPassword = "password"
	}
	if c.FieldSender == "" {
		c.FieldSender = "sender"
	}
	if c.FieldTo == "" {
		c.FieldTo = "mobile"
	}
	if c.FieldBody == "" {
		c.FieldBody = "message"
	}
	return c
}

func (h *HTTPSender) Code() string  { return "http" }
func (h *HTTPSender) Usable() error { return h.cfg.Complete() }

func (h *HTTPSender) Send(ctx context.Context, m Message) (Result, error) {
	to, err := E164(m.To)
	if err != nil {
		return Result{}, err
	}

	form := url.Values{}
	form.Set(h.cfg.FieldUsername, h.cfg.Username)
	form.Set(h.cfg.FieldPassword, h.cfg.Password)
	form.Set(h.cfg.FieldSender, h.cfg.SenderID)
	form.Set(h.cfg.FieldTo, to)
	// UTF-8 on the wire. Arabic is transcoded to UCS-2 by the provider, and
	// splitting a long message into segments is theirs to do - a client that
	// splits as well produces two messages where the provider would have sent
	// one concatenated one, and the family sees the seam.
	form.Set(h.cfg.FieldBody, m.Body)
	if m.Ref != "" {
		form.Set("reference", m.Ref)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, h.cfg.BaseURL,
		strings.NewReader(form.Encode()))
	if err != nil {
		return Result{}, Fail(ClassConfig, "the provider request could not be built", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
	req.Header.Set("Accept", "application/json")

	resp, err := h.client.Do(req)
	if err != nil {
		// A dial or DNS failure names the provider's host, which is not a
		// secret, but a redirect chain or a proxy error can name more. The
		// detail is deliberately short and fixed.
		var nerr net.Error
		if errors.As(err, &nerr) && nerr.Timeout() {
			return Result{}, Fail(ClassTransient, "the provider did not answer in time", err)
		}
		return Result{}, Fail(ClassTransient, "the provider could not be reached", err)
	}
	defer resp.Body.Close()

	// Bounded. A provider answering with a megabyte of HTML must not become
	// this process's memory problem, and nothing useful is past 64KB.
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))

	switch {
	case resp.StatusCode >= 200 && resp.StatusCode < 300:
		return parseAccepted(body), nil
	case resp.StatusCode == http.StatusTooManyRequests:
		return Result{}, Fail(ClassTransient, "the provider is rate limiting this account", nil)
	case resp.StatusCode == http.StatusUnauthorized || resp.StatusCode == http.StatusForbidden:
		// Not PERMANENT: the message is fine, the deployment is not, and
		// every other message will fail identically until somebody fixes it.
		return Result{}, Fail(ClassConfig, "the provider refused these credentials", nil)
	case resp.StatusCode >= 500:
		return Result{}, Fail(ClassTransient,
			"the provider answered "+resp.Status, nil)
	default:
		// 4xx that is not auth and not rate limiting is about this message -
		// most often the destination.
		return Result{}, Fail(ClassPermanent,
			"the provider rejected the message with "+resp.Status, nil)
	}
}

// parseAccepted pulls a message id out of whatever shape came back.
//
// A provider that accepts and returns nothing recognisable is still an accept:
// losing the id costs an operator one question they have to ask by hand, and
// treating it as a failure would send the message a second time.
func parseAccepted(body []byte) Result {
	var generic map[string]any
	if err := json.Unmarshal(body, &generic); err != nil {
		return Result{}
	}
	var r Result
	for _, k := range []string{"message_id", "messageId", "id", "msg_id", "MessageId"} {
		if v, ok := generic[k]; ok {
			if s := asString(v); s != "" {
				r.ProviderMessageID = s
				break
			}
		}
	}
	for _, k := range []string{"segments", "parts", "message_count"} {
		if v, ok := generic[k]; ok {
			if n, ok := v.(float64); ok {
				r.Segments = int(n)
				break
			}
		}
	}
	return r
}

func asString(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return fmt.Sprintf("%.0f", t)
	default:
		return ""
	}
}
