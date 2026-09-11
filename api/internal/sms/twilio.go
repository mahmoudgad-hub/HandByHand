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
	"strconv"
	"strings"
	"time"
)

// TwilioWhatsApp delivers over WhatsApp through Twilio's Messaging API.
//
// WHY THIS IS A SEPARATE SENDER AND NOT HTTPConfig WITH DIFFERENT FIELD NAMES.
// HTTPSender puts the account in FORM FIELDS because that is what every
// Egyptian bulk-SMS provider this project looked at does. Twilio authenticates
// with HTTP Basic and puts the account id in the PATH, so there is no naming
// of fields that reaches it. The difference is the protocol, not the spelling.
//
// AND WHY WHATSAPP IS NOT JUST ANOTHER NUMBER. A business may not send a
// WhatsApp message of its own composition to somebody who has not written to
// it in the last 24 hours. Outside that window the only thing that leaves is
// an APPROVED TEMPLATE, named by a ContentSid, with its variables supplied
// separately. Every message this centre sends is business-initiated - a login
// code, a confirmed appointment - so in practice the window is always shut and
// the template path is the only one. Body is carried anyway, because a reply
// inside an open window is a real case and a sender that cannot use it would
// have to be replaced rather than extended.
//
// WHAT THIS MEANS FOR A CALLER THAT HAS ONLY RENDERED TEXT. It cannot send.
// hbh.notifications renders body_ar in PL/pgSQL - correct for SMS, and not
// enough here, because a template needs the VALUES and not the sentence they
// were put into. Such a message is refused as CONFIG rather than sent as
// freeform: freeform would be rejected by WhatsApp as error 63016 on every
// attempt outside a session, and a retry produces the identical refusal.
//
// NO CREDENTIAL IS WRITTEN DOWN HERE. The account sid, the auth token and the
// sender are process environment. The only provider fact that is persisted is
// the message sid it hands back.
type TwilioWhatsApp struct {
	cfg    TwilioConfig
	client *http.Client
}

// TwilioConfig is deployment wiring. No business value lives here: no message
// text, no retry count, no destination.
type TwilioConfig struct {
	// AccountSID identifies the account and also forms part of the URL.
	AccountSID string
	// AuthToken is the account secret. An API key sid and secret work in the
	// same positions and are the better choice, because they can be revoked
	// without changing the account.
	AuthToken string

	// From is the WhatsApp sender, as the bare number in E.164 (+20...) or
	// the shape Twilio prints (whatsapp:+20...). Either is accepted; the
	// prefix is normalised on the wire.
	From string
	// MessagingServiceSid is an alternative to From. When both are given the
	// service wins, because that is the one that carries sender selection and
	// per-country rules with it.
	MessagingServiceSid string

	// ContentSIDs maps a template_code from hbh.sms_outbox to the ContentSid
	// Meta approved for it. A code with no entry cannot be sent: guessing
	// would deliver the wrong template to a family.
	ContentSIDs map[string]string

	// StatusCallback is where Twilio reports what happened after it accepted
	// the message. Optional, and nothing in this service reads it yet.
	StatusCallback string

	// AllowFreeform sends Body when the template code has no ContentSid,
	// instead of refusing. IT IS A DEVELOPMENT AFFORDANCE AND config.Load
	// REFUSES IT OUTSIDE development, for the same reason it refuses OTPEcho
	// and SMS_PROVIDER=dev.
	//
	// WHAT IT IS FOR. Twilio's WhatsApp sandbox opens a 24-hour session the
	// moment a tester sends it the join word, and inside that window free
	// text is delivered. So a developer can see a login code arrive on a real
	// handset before Meta has approved a single template, which is otherwise
	// a wait measured in days.
	//
	// WHY IT MUST NOT LEAVE development. Outside an open session - which is
	// every message this centre actually sends, because all of them are
	// business-initiated - WhatsApp refuses free text with error 63016. The
	// refusal is identical on every attempt, so the fallback would climb the
	// whole retry ladder and the family would still receive nothing, while
	// the outbox filled with failures that name a template rather than the
	// missing approval. The CONFIG refusal this replaces is what puts that
	// in front of an operator on the first attempt instead of the fifth.
	AllowFreeform bool

	Timeout time.Duration
}

// Complete reports whether this deployment has been given enough to send.
func (c TwilioConfig) Complete() error {
	var missing []string
	if strings.TrimSpace(c.AccountSID) == "" {
		missing = append(missing, "TWILIO_ACCOUNT_SID")
	}
	if strings.TrimSpace(c.AuthToken) == "" {
		missing = append(missing, "TWILIO_AUTH_TOKEN")
	}
	if strings.TrimSpace(c.From) == "" && strings.TrimSpace(c.MessagingServiceSid) == "" {
		missing = append(missing, "TWILIO_WHATSAPP_FROM or TWILIO_MESSAGING_SERVICE_SID")
	}
	if len(missing) > 0 {
		return fmt.Errorf("SMS_PROVIDER=twilio_whatsapp needs %s", strings.Join(missing, ", "))
	}
	return nil
}

// NewTwilioWhatsApp validates the configuration at construction, so a
// deployment that cannot send says so at startup rather than at a parent's
// first login.
func NewTwilioWhatsApp(cfg TwilioConfig) (*TwilioWhatsApp, error) {
	if err := cfg.Complete(); err != nil {
		return nil, err
	}
	// An account sid that is not an account sid produces a 404 on a URL that
	// names it, which reads as "Twilio is down" rather than as a typo.
	if !strings.HasPrefix(cfg.AccountSID, "AC") {
		return nil, errors.New("TWILIO_ACCOUNT_SID must start with AC")
	}
	if cfg.MessagingServiceSid != "" && !strings.HasPrefix(cfg.MessagingServiceSid, "MG") {
		return nil, errors.New("TWILIO_MESSAGING_SERVICE_SID must start with MG")
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 10 * time.Second
	}
	if cfg.ContentSIDs == nil {
		cfg.ContentSIDs = map[string]string{}
	}
	return &TwilioWhatsApp{cfg: cfg, client: &http.Client{Timeout: cfg.Timeout}}, nil
}

func (t *TwilioWhatsApp) Code() string  { return "twilio_whatsapp" }
func (t *TwilioWhatsApp) Usable() error { return t.cfg.Complete() }

// waAddress puts the channel prefix on a number exactly once.
func waAddress(n string) string {
	n = strings.TrimSpace(n)
	if strings.HasPrefix(n, "whatsapp:") {
		return n
	}
	return "whatsapp:" + n
}

func (t *TwilioWhatsApp) Send(ctx context.Context, m Message) (Result, error) {
	to, err := E164(m.To)
	if err != nil {
		return Result{}, err
	}

	form := url.Values{}
	form.Set("To", waAddress(to))
	if t.cfg.MessagingServiceSid != "" {
		form.Set("MessagingServiceSid", t.cfg.MessagingServiceSid)
	} else {
		form.Set("From", waAddress(t.cfg.From))
	}
	if t.cfg.StatusCallback != "" {
		form.Set("StatusCallback", t.cfg.StatusCallback)
	}

	// THE TEMPLATE IS THE NORMAL PATH, and the refusal below is the whole
	// point of the check: a business-initiated WhatsApp message without one
	// is refused by WhatsApp, not by us, and refused identically every time.
	// Saying so as CONFIG puts it in front of the operator who can add the
	// mapping instead of burning SMS_MAX_ATTEMPTS against a wall.
	switch {
	case m.TemplateCode != "" && t.cfg.ContentSIDs[m.TemplateCode] == "":
		// NO TEMPLATE IS MAPPED. Refusing is the right answer everywhere the
		// 24-hour session is shut, which is everywhere this centre sends -
		// see AllowFreeform's comment for why the fallback is development
		// only and what it costs when it is not.
		if !t.cfg.AllowFreeform || m.Body == "" {
			return Result{}, Fail(ClassConfig,
				"no approved WhatsApp template is mapped to "+m.TemplateCode, nil)
		}
		form.Set("Body", m.Body)
	case m.TemplateCode != "":
		sid := t.cfg.ContentSIDs[m.TemplateCode]
		form.Set("ContentSid", sid)
		if len(m.Vars) > 0 {
			vars := make(map[string]string, len(m.Vars))
			for i, v := range m.Vars {
				// Twilio numbers template variables from 1, as Meta does.
				vars[strconv.Itoa(i+1)] = v
			}
			encoded, err := json.Marshal(vars)
			if err != nil {
				return Result{}, Fail(ClassPermanent, "template variables could not be encoded", err)
			}
			form.Set("ContentVariables", string(encoded))
		}
	case m.Body != "":
		// Only reachable inside an open 24-hour session. Left in because a
		// reply to a family who wrote first is a real case; every scheduled
		// message this service sends takes the branch above.
		form.Set("Body", m.Body)
	default:
		return Result{}, Fail(ClassPermanent, "the message has neither a template nor a body", nil)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://api.twilio.com/2010-04-01/Accounts/"+url.PathEscape(t.cfg.AccountSID)+"/Messages.json",
		strings.NewReader(form.Encode()))
	if err != nil {
		return Result{}, Fail(ClassConfig, "the provider request could not be built", err)
	}
	req.SetBasicAuth(t.cfg.AccountSID, t.cfg.AuthToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded; charset=UTF-8")
	req.Header.Set("Accept", "application/json")

	resp, err := t.client.Do(req)
	if err != nil {
		var nerr net.Error
		if errors.As(err, &nerr) && nerr.Timeout() {
			return Result{}, Fail(ClassTransient, "the provider did not answer in time", err)
		}
		return Result{}, Fail(ClassTransient, "the provider could not be reached", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 64*1024))

	if resp.StatusCode >= 200 && resp.StatusCode < 300 {
		return parseTwilioAccepted(body), nil
	}
	return Result{}, classifyTwilio(resp.StatusCode, resp.Status, body)
}

// twilioAccepted is the subset of Twilio's reply this service reads.
type twilioAccepted struct {
	SID         string `json:"sid"`
	NumSegments string `json:"num_segments"`
}

func parseTwilioAccepted(body []byte) Result {
	var a twilioAccepted
	if err := json.Unmarshal(body, &a); err != nil {
		// Accepted is accepted. Losing the sid costs an operator one question
		// they have to ask by hand; treating it as a failure would send the
		// message a second time.
		return Result{}
	}
	r := Result{ProviderMessageID: a.SID}
	if n, err := strconv.Atoi(a.NumSegments); err == nil {
		r.Segments = n
	}
	return r
}

// twilioError is the shape Twilio uses for every failure.
type twilioError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// twilioClasses maps the codes worth distinguishing to what a retry would do.
//
// ONLY CODES THAT HAVE BEEN REASONED ABOUT ARE HERE. Anything else falls to
// the status-code rule below, and an unclassified failure defaults TRANSIENT -
// which costs at most SMS_MAX_ATTEMPTS against a ceiling the database already
// enforces, where the opposite silently drops a message a family was owed.
var twilioClasses = map[int]Class{
	20003: ClassConfig,    // authenticate - the deployment's credentials
	20404: ClassConfig,    // not found - usually a wrong account sid
	20429: ClassTransient, // too many requests
	21211: ClassPermanent, // To is not a valid phone number
	21408: ClassConfig,    // no permission to send to this region
	21606: ClassConfig,    // the From number is not a valid WhatsApp sender
	21610: ClassPermanent, // the recipient has unsubscribed
	21612: ClassConfig,    // this From cannot reach this To
	63007: ClassConfig,    // no WhatsApp channel for this From
	63016: ClassConfig,    // freeform outside the session window - needs a template
	63018: ClassTransient, // WhatsApp rate limit
	63024: ClassPermanent, // invalid message - the body or the variables
}

func classifyTwilio(status int, statusText string, body []byte) error {
	var e twilioError
	// Twilio's own code is more precise than the HTTP status, so it decides
	// when it is present and recognised.
	if err := json.Unmarshal(body, &e); err == nil && e.Code != 0 {
		detail := fmt.Sprintf("twilio %d: %s", e.Code, truncate(e.Message, 400))
		if class, ok := twilioClasses[e.Code]; ok {
			return Fail(class, detail, nil)
		}
		if status >= 500 {
			return Fail(ClassTransient, detail, nil)
		}
		return Fail(ClassPermanent, detail, nil)
	}

	switch {
	case status == http.StatusTooManyRequests:
		return Fail(ClassTransient, "the provider is rate limiting this account", nil)
	case status == http.StatusUnauthorized || status == http.StatusForbidden:
		return Fail(ClassConfig, "the provider refused these credentials", nil)
	case status >= 500:
		return Fail(ClassTransient, "the provider answered "+statusText, nil)
	default:
		return Fail(ClassPermanent, "the provider rejected the message with "+statusText, nil)
	}
}
