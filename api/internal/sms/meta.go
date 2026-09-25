package sms

import (
	"bytes"
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

// MetaWhatsApp delivers over WhatsApp through Meta's own Cloud API.
//
// WHY META DIRECTLY AND NOT A RESELLER. This service used to reach WhatsApp
// through Twilio, which meant a company in the middle of every login code: a
// second account to keep alive, a second bill, a second set of error codes to
// translate, and templates identified by a Twilio id rather than by the name
// Meta approved. The owner moved the centre onto Meta on 2026-09-18 and the
// Twilio sender was removed in the same change - it is in git history if a
// reseller is ever wanted again.
//
// WHAT WHATSAPP WILL AND WILL NOT CARRY. A business may only send a message
// of its own composition to somebody who has written to it in the last 24
// hours. Every message this centre sends is business-initiated - a login
// code, a reminder, a published report - so that window is always shut, and
// the only thing that leaves is an APPROVED TEMPLATE: its name, its language,
// and its values supplied apart from the sentence. Free text outside the
// window is refused by WhatsApp itself (error 131047), identically on every
// attempt, which is why a message with no approved template is refused here
// as CONFIG rather than retried.
//
// THE TEMPLATE IS NAMED PER MESSAGE, not configured per process. The name and
// language come on the Message, read from hbh.message_templates by whoever
// built it, so the owner approving a template in the console changes what the
// next message sends with no deploy and no restart.
//
// NO CREDENTIAL IS WRITTEN DOWN HERE. The access token and the phone number
// id are process environment, and the only provider fact persisted is the
// message id Meta hands back.
type MetaWhatsApp struct {
	cfg    MetaConfig
	client *http.Client
}

// MetaConfig is deployment wiring. No business value lives here: no message
// text, no retry count, no destination.
type MetaConfig struct {
	// PhoneNumberID is the centre's WhatsApp sender, as Meta's own id rather
	// than as a number - it forms the path the message is posted to. The
	// number itself never appears on the wire.
	PhoneNumberID string

	// AccessToken authenticates as the system user the token was generated
	// for. A system user's token does not expire and can be revoked on its
	// own, which is why the setup notes ask for one rather than for a token
	// tied to a person's login.
	AccessToken string

	// APIVersion is the Graph API version, "v21.0" by default. Named because
	// Meta retires versions on a published schedule and a deployment must be
	// able to move without a build.
	APIVersion string

	// BaseURL is https://graph.facebook.com by default. It exists so a test
	// can point this sender at a local server; nothing in production sets it.
	BaseURL string

	Timeout time.Duration
}

// Complete reports whether this deployment has been given enough to send.
func (c MetaConfig) Complete() error {
	var missing []string
	if strings.TrimSpace(c.PhoneNumberID) == "" {
		missing = append(missing, "META_PHONE_NUMBER_ID")
	}
	if strings.TrimSpace(c.AccessToken) == "" {
		missing = append(missing, "META_ACCESS_TOKEN")
	}
	if len(missing) > 0 {
		return fmt.Errorf("SMS_PROVIDER=meta_whatsapp needs %s", strings.Join(missing, ", "))
	}
	return nil
}

// NewMetaWhatsApp validates the configuration at construction, so a
// deployment that cannot send says so at startup rather than at a parent's
// first login.
func NewMetaWhatsApp(cfg MetaConfig) (*MetaWhatsApp, error) {
	if err := cfg.Complete(); err != nil {
		return nil, err
	}
	if strings.TrimSpace(cfg.BaseURL) == "" {
		cfg.BaseURL = "https://graph.facebook.com"
	}
	u, err := url.Parse(strings.TrimRight(cfg.BaseURL, "/"))
	if err != nil || u.Host == "" {
		return nil, errors.New("META_API_BASE must be an absolute URL")
	}
	cfg.BaseURL = u.String()
	if strings.TrimSpace(cfg.APIVersion) == "" {
		cfg.APIVersion = "v21.0"
	}
	// A version that is not a version produces a 404 on a URL that names it,
	// which reads as "Meta is down" rather than as a typo.
	if !strings.HasPrefix(cfg.APIVersion, "v") {
		return nil, errors.New("META_API_VERSION must look like v21.0")
	}
	if cfg.Timeout <= 0 {
		cfg.Timeout = 10 * time.Second
	}
	return &MetaWhatsApp{cfg: cfg, client: &http.Client{Timeout: cfg.Timeout}}, nil
}

func (m *MetaWhatsApp) Code() string  { return "meta_whatsapp" }
func (m *MetaWhatsApp) Usable() error { return m.cfg.Complete() }

// metaRequest is the message as Meta's Cloud API takes it.
type metaRequest struct {
	MessagingProduct string        `json:"messaging_product"`
	RecipientType    string        `json:"recipient_type,omitempty"`
	To               string        `json:"to"`
	Type             string        `json:"type"`
	Template         *metaTemplate `json:"template,omitempty"`
	Text             *metaTextBody `json:"text,omitempty"`
}

type metaTextBody struct {
	Body       string `json:"body"`
	PreviewURL bool   `json:"preview_url"`
}

type metaTemplate struct {
	Name       string          `json:"name"`
	Language   metaLanguage    `json:"language"`
	Components []metaComponent `json:"components,omitempty"`
}

type metaLanguage struct {
	Code string `json:"code"`
}

type metaComponent struct {
	Type       string          `json:"type"`
	SubType    string          `json:"sub_type,omitempty"`
	Index      string          `json:"index,omitempty"`
	Parameters []metaParameter `json:"parameters,omitempty"`
}

type metaParameter struct {
	Type string `json:"type"`
	Text string `json:"text"`
}

func (m *MetaWhatsApp) Send(ctx context.Context, msg Message) (Result, error) {
	to, err := E164(msg.To)
	if err != nil {
		return Result{}, err
	}

	req := metaRequest{MessagingProduct: "whatsapp", RecipientType: "individual", To: to}

	switch {
	case msg.TemplateName != "":
		req.Type = "template"
		req.Template = &metaTemplate{
			Name:     msg.TemplateName,
			Language: metaLanguage{Code: templateLang(msg.TemplateLang)},
		}
		if len(msg.Vars) > 0 {
			params := make([]metaParameter, 0, len(msg.Vars))
			for _, v := range msg.Vars {
				params = append(params, metaParameter{Type: "text", Text: v})
			}
			req.Template.Components = append(req.Template.Components,
				metaComponent{Type: "body", Parameters: params})

			// THE BUTTON AN AUTHENTICATION TEMPLATE CARRIES, AND THE TRAP IT
			// IS. Meta builds every authentication template with a button
			// that copies the code, and it will not accept the message unless
			// the VALUE for that button is sent as well - the same code, a
			// second time, as a url/copy_code button parameter. Leaving it out
			// is answered with 132000 "number of parameters does not match",
			// which reads as a fault in the body and is not one.
			//
			// Only the login code takes this branch: hbh.message_templates
			// marks exactly one template per centre AUTHENTICATION, and its
			// var_count is 1.
			if msg.TemplateAuth {
				req.Template.Components = append(req.Template.Components, metaComponent{
					Type:       "button",
					SubType:    "url",
					Index:      "0",
					Parameters: []metaParameter{{Type: "text", Text: msg.Vars[0]}},
				})
			}
		}
	case msg.TemplateCode != "":
		// NO APPROVED TEMPLATE for this code in this centre. Refusing is the
		// right answer everywhere the 24-hour window is shut, which is
		// everywhere this centre sends. CONFIG puts it in front of the
		// operator who can approve the template instead of burning
		// SMS_MAX_ATTEMPTS against a wall that answers the same every time.
		return Result{}, Fail(ClassConfig,
			"no approved WhatsApp template for "+msg.TemplateCode, nil)
	case msg.Body != "":
		// Only reachable inside an open 24-hour window - a reply to a family
		// who wrote first. Every scheduled message this service sends takes
		// the template branch above.
		req.Type = "text"
		req.Text = &metaTextBody{Body: msg.Body}
	default:
		return Result{}, Fail(ClassPermanent, "the message has neither a template nor a body", nil)
	}

	payload, err := json.Marshal(req)
	if err != nil {
		return Result{}, Fail(ClassPermanent, "the message could not be encoded", err)
	}

	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost,
		m.cfg.BaseURL+"/"+m.cfg.APIVersion+"/"+url.PathEscape(m.cfg.PhoneNumberID)+"/messages",
		bytes.NewReader(payload))
	if err != nil {
		return Result{}, Fail(ClassConfig, "the provider request could not be built", err)
	}
	httpReq.Header.Set("Authorization", "Bearer "+m.cfg.AccessToken)
	httpReq.Header.Set("Content-Type", "application/json")
	httpReq.Header.Set("Accept", "application/json")

	resp, err := m.client.Do(httpReq)
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
		return parseMetaAccepted(body), nil
	}
	return Result{}, classifyMeta(resp.StatusCode, resp.Status, body)
}

// templateLang defaults the language rather than sending an empty one, which
// Meta answers with "template name does not exist in the translation" - a
// message that names the template and not the missing language.
func templateLang(code string) string {
	if c := strings.TrimSpace(code); c != "" {
		return c
	}
	return "ar"
}

// metaAccepted is the subset of Meta's reply this service reads.
type metaAccepted struct {
	Messages []struct {
		ID string `json:"id"`
	} `json:"messages"`
}

func parseMetaAccepted(body []byte) Result {
	var a metaAccepted
	if err := json.Unmarshal(body, &a); err != nil || len(a.Messages) == 0 {
		// Accepted is accepted. Losing the id costs an operator one question
		// they have to ask by hand; treating it as a failure would send the
		// message a second time.
		return Result{}
	}
	// SEGMENTS ARE NOT REPORTED AND ARE NOT GUESSED. Meta bills WhatsApp by
	// conversation, not by the 70-character UCS-2 segment an SMS gateway
	// counts, so there is no number here that would mean anything. Zero says
	// "not offered", which is the truth.
	return Result{ProviderMessageID: a.Messages[0].ID}
}

// metaError is the shape Meta uses for every failure.
type metaError struct {
	Error struct {
		Message   string `json:"message"`
		Type      string `json:"type"`
		Code      int    `json:"code"`
		Subcode   int    `json:"error_subcode"`
		FBTraceID string `json:"fbtrace_id"`
	} `json:"error"`
}

// metaClasses maps the codes worth distinguishing to what a retry would do.
//
// ONLY CODES THAT HAVE BEEN REASONED ABOUT ARE HERE. Anything else falls to
// the status-code rule below, and an unclassified failure defaults TRANSIENT -
// which costs at most SMS_MAX_ATTEMPTS against a ceiling the database already
// enforces, where the opposite silently drops a message a family was owed.
//
// THE LINE BETWEEN CONFIG AND PERMANENT IS "WHOSE FAULT, AND WHAT FIXES IT".
// A paused template, a spent token, an unregistered sender: every message
// fails until an operator acts, so they are CONFIG and dead on the first
// attempt with a reason that names the fix. A number that is not on WhatsApp
// or a value too long for the template is this message only - PERMANENT.
var metaClasses = map[int]Class{
	0:      ClassTransient, // Meta's own "unknown error", their advice is to retry
	4:      ClassTransient, // application request limit
	80007:  ClassTransient, // rate limit on this business account
	130429: ClassTransient, // cloud API message throughput limit
	131048: ClassTransient, // spam rate limit - the account is sending too fast
	131049: ClassTransient, // healthy-ecosystem limit - this recipient, right now
	131000: ClassTransient, // something went wrong on Meta's side
	131053: ClassPermanent, // media upload error - this message's own content
	131026: ClassPermanent, // undeliverable: the number is not on WhatsApp
	132000: ClassPermanent, // parameter count does not match the template
	132005: ClassPermanent, // the filled-in template is longer than allowed
	132007: ClassPermanent, // the filled-in text violates the template's format
	132012: ClassPermanent, // a parameter's format does not match the template
	131047: ClassConfig,    // re-engagement: free text outside the 24-hour window
	131031: ClassConfig,    // the business account is restricted or locked
	131042: ClassConfig,    // billing: no payment method on the account
	132001: ClassConfig,    // the template does not exist in this language
	132015: ClassConfig,    // the template is paused for quality
	132016: ClassConfig,    // the template is disabled
	133010: ClassConfig,    // the sender is not registered on the Cloud API
	133015: ClassConfig,    // the sender is being deregistered
	190:    ClassConfig,    // the access token is invalid or expired
	200:    ClassConfig,    // the token lacks whatsapp_business_messaging
	368:    ClassConfig,    // temporarily blocked for policy violations
}

func classifyMeta(status int, statusText string, body []byte) error {
	var e metaError
	// Meta's own code is more precise than the HTTP status, so it decides
	// when it is present and recognised.
	if err := json.Unmarshal(body, &e); err == nil && (e.Error.Code != 0 || e.Error.Message != "") {
		// THE TRACE ID IS KEPT AND THE MESSAGE IS TRUNCATED. fbtrace_id is
		// the only handle Meta's own support asks for, and it is not a
		// credential; the message can be long and is written to
		// sms_outbox.error_detail, which operations reads.
		detail := fmt.Sprintf("meta %d", e.Error.Code)
		if e.Error.Subcode != 0 {
			detail += fmt.Sprintf("/%d", e.Error.Subcode)
		}
		detail += ": " + truncate(e.Error.Message, 360)
		if e.Error.FBTraceID != "" {
			detail += " [" + truncate(e.Error.FBTraceID, 40) + "]"
		}
		if class, ok := metaClasses[e.Error.Code]; ok {
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
