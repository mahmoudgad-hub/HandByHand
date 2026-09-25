package sms

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// metaServer stands in for Meta's Cloud API and keeps what it was posted, so a
// test can assert on the JSON that actually went out rather than on the struct
// that was meant to produce it.
type metaServer struct {
	*httptest.Server
	path string
	auth string
	body map[string]any
}

func newMetaServer(t *testing.T, status int, reply string) *metaServer {
	t.Helper()
	ms := &metaServer{}
	ms.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ms.path = r.URL.Path
		ms.auth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		ms.body = map[string]any{}
		_ = json.Unmarshal(raw, &ms.body)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = io.WriteString(w, reply)
	}))
	t.Cleanup(ms.Close)
	return ms
}

func newTestMeta(t *testing.T, base string) *MetaWhatsApp {
	t.Helper()
	s, err := NewMetaWhatsApp(MetaConfig{
		PhoneNumberID: "1332135986649707",
		AccessToken:   "token",
		BaseURL:       base,
		Timeout:       2 * time.Second,
	})
	if err != nil {
		t.Fatalf("a complete configuration must build: %v", err)
	}
	return s
}

const metaAcceptedReply = `{"messaging_product":"whatsapp","messages":[{"id":"wamid.HBgLMjA="}]}`

// The normal path: a business-initiated message goes out as the template Meta
// approved, with the values apart from the sentence.
func TestMetaSendsTheApprovedTemplateWithItsValues(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	res, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To:           "+201500000093",
		TemplateCode: "APPOINTMENT_REMINDER",
		TemplateName: "appointment_reminder",
		TemplateLang: "ar",
		Vars:         []string{"مؤمن", "الأحد", "20/09/2026", "5:00 مساءً"},
		Body:         "the rendered sentence an SMS gateway would take",
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if res.ProviderMessageID != "wamid.HBgLMjA=" {
		t.Fatalf("the message id was not read back: %+v", res)
	}

	// THE VERSION AND THE SENDER ARE IN THE PATH, and the token is a bearer
	// header. A phone number id in the wrong position is a 404 that reads as
	// "Meta is down".
	if !strings.HasSuffix(ms.path, "/v21.0/1332135986649707/messages") {
		t.Fatalf("posted to %q", ms.path)
	}
	if ms.auth != "Bearer token" {
		t.Fatalf("the token did not travel as a bearer header: %q", ms.auth)
	}

	if ms.body["type"] != "template" {
		t.Fatalf("not sent as a template: %v", ms.body["type"])
	}
	tpl, _ := ms.body["template"].(map[string]any)
	if tpl["name"] != "appointment_reminder" {
		t.Fatalf("wrong template name: %v", tpl["name"])
	}
	lang, _ := tpl["language"].(map[string]any)
	if lang["code"] != "ar" {
		t.Fatalf("wrong language: %v", lang)
	}

	// THE RENDERED SENTENCE MUST NOT BE ON THE WIRE. It is carried on the
	// Message for the SMS transport, and a template message that also sent it
	// would be refused - and would have put a family's details somewhere the
	// template did not ask for them.
	if _, ok := ms.body["text"]; ok {
		t.Fatal("the rendered body was sent alongside the template")
	}

	comps, _ := tpl["components"].([]any)
	if len(comps) != 1 {
		t.Fatalf("want one body component, got %v", comps)
	}
	body, _ := comps[0].(map[string]any)
	params, _ := body["parameters"].([]any)
	if body["type"] != "body" || len(params) != 4 {
		t.Fatalf("the four values did not travel as body parameters: %v", comps[0])
	}
	first, _ := params[0].(map[string]any)
	if first["text"] != "مؤمن" {
		t.Fatalf("the values are out of order or altered: %v", params)
	}
}

// An authentication template carries a copy-the-code button, and Meta refuses
// the message unless the button's value is sent too. This is the assertion
// that would have caught 132000 "number of parameters does not match" before a
// parent ever failed to sign in.
func TestMetaSendsTheCodeTwiceForAnAuthenticationTemplate(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To:           "+966544452367",
		TemplateCode: "OTP_LOGIN",
		TemplateName: "otp_login",
		TemplateLang: "ar",
		TemplateAuth: true,
		Vars:         []string{"482915"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tpl, _ := ms.body["template"].(map[string]any)
	comps, _ := tpl["components"].([]any)
	if len(comps) != 2 {
		t.Fatalf("want a body and a button component, got %v", comps)
	}
	btn, _ := comps[1].(map[string]any)
	if btn["type"] != "button" || btn["sub_type"] != "url" || btn["index"] != "0" {
		t.Fatalf("the copy-code button is not addressed as Meta expects: %v", btn)
	}
	params, _ := btn["parameters"].([]any)
	p0, _ := params[0].(map[string]any)
	if len(params) != 1 || p0["text"] != "482915" {
		t.Fatalf("the button did not carry the code: %v", params)
	}

	// And an ordinary template gets no button, or Meta answers 132000 from
	// the other direction.
	ms2 := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	_, err = newTestMeta(t, ms2.URL).Send(context.Background(), Message{
		To: "+201500000093", TemplateCode: "PORTAL_UPDATE",
		TemplateName: "portal_update", TemplateLang: "ar", Vars: []string{"تقرير جديد"},
	})
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tpl2, _ := ms2.body["template"].(map[string]any)
	comps2, _ := tpl2["components"].([]any)
	if len(comps2) != 1 {
		t.Fatalf("a utility template must send the body alone, got %v", comps2)
	}
}

// NO APPROVED TEMPLATE IS A CONFIG REFUSAL, NOT A RETRY AND NOT FREE TEXT.
// WhatsApp answers free text outside the 24-hour window identically every
// time, so a retry ladder delivers nothing and buries the one fact an operator
// needs: a template is waiting for approval.
func TestMetaRefusesAMessageWithNoApprovedTemplate(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To:           "+201500000093",
		TemplateCode: "APPOINTMENT_REMINDER",
		Body:         "the rendered sentence",
	})
	class, detail := ClassOf(err)
	if err == nil || class != ClassConfig {
		t.Fatalf("want a CONFIG refusal, got %v (%s)", err, class)
	}
	if !strings.Contains(detail, "APPOINTMENT_REMINDER") {
		t.Fatalf("the refusal must name the code an operator has to approve: %q", detail)
	}
	if ms.body != nil {
		t.Fatal("the message reached the provider anyway")
	}
}

// A reply inside an open window is the one free-text case, and it is still
// reachable - a family that wrote first may be answered.
func TestMetaSendsTextWhenThereIsNoTemplateCodeAtAll(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	if _, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To: "+201500000093", Body: "شكرًا لتواصلكم.",
	}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if ms.body["type"] != "text" {
		t.Fatalf("want a text message, got %v", ms.body["type"])
	}
	text, _ := ms.body["text"].(map[string]any)
	if text["body"] != "شكرًا لتواصلكم." {
		t.Fatalf("the body did not survive: %v", text)
	}
}

func TestMetaRefusesAMessageWithNeitherTemplateNorBody(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{To: "+201500000093"})
	if class, _ := ClassOf(err); err == nil || class != ClassPermanent {
		t.Fatalf("want a PERMANENT refusal, got %v (%s)", err, class)
	}
}

// EVERY CLASS IS ASSERTED BY NAME, because the class is the whole of what the
// database does next: TRANSIENT goes back on the queue, CONFIG and PERMANENT
// are dead on arrival. A failure classified the wrong way either drops a
// message a family was owed or retries an identical refusal five times.
func TestMetaClassifiesWhatTheProviderAnswers(t *testing.T) {
	for _, tc := range []struct {
		name   string
		status int
		reply  string
		want   Class
	}{
		{"an expired token stops every message", http.StatusUnauthorized,
			`{"error":{"message":"Session has expired","code":190,"fbtrace_id":"Axb1"}}`, ClassConfig},
		{"a paused template needs the owner", http.StatusBadRequest,
			`{"error":{"message":"Template is paused","code":132015}}`, ClassConfig},
		{"free text outside the window needs a template", http.StatusBadRequest,
			`{"error":{"message":"Re-engagement message","code":131047}}`, ClassConfig},
		{"a number not on WhatsApp is this message alone", http.StatusBadRequest,
			`{"error":{"message":"Message undeliverable","code":131026}}`, ClassPermanent},
		{"a value too long for the template is this message alone", http.StatusBadRequest,
			`{"error":{"message":"Hydrated text is too long","code":132005}}`, ClassPermanent},
		{"a throughput limit is worth retrying", http.StatusTooManyRequests,
			`{"error":{"message":"Rate limit hit","code":130429}}`, ClassTransient},
		{"Meta's own outage is worth retrying", http.StatusInternalServerError,
			`{"error":{"message":"Something went wrong","code":131000}}`, ClassTransient},
		// An unrecognised code is not guessed at: a 4xx is this message's own
		// fault and a 5xx is theirs.
		{"an unknown 4xx is permanent", http.StatusBadRequest,
			`{"error":{"message":"New failure nobody has mapped","code":999999}}`, ClassPermanent},
		{"an unknown 5xx is transient", http.StatusBadGateway,
			`{"error":{"message":"New failure nobody has mapped","code":999999}}`, ClassTransient},
		// And a reply that is not JSON at all still has to be classified.
		{"a proxy's HTML error page is read by its status", http.StatusServiceUnavailable,
			`<html>503</html>`, ClassTransient},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ms := newMetaServer(t, tc.status, tc.reply)
			_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
				To: "+201500000093", TemplateCode: "PORTAL_UPDATE",
				TemplateName: "portal_update", TemplateLang: "ar", Vars: []string{"x"},
			})
			class, detail := ClassOf(err)
			if err == nil || class != tc.want {
				t.Fatalf("want %s, got %s (%v)", tc.want, class, err)
			}
			// THE DETAIL IS WRITTEN TO sms_outbox.error_detail AND READ BY
			// OPERATIONS. It must never carry the token, and it must carry
			// enough for Meta's own support to find the request.
			if strings.Contains(detail, "token") {
				t.Fatalf("the credential reached the error detail: %q", detail)
			}
		})
	}
}

// The trace id is the only handle Meta's support asks for, so it is kept.
func TestMetaKeepsTheTraceIDInTheDetail(t *testing.T) {
	ms := newMetaServer(t, http.StatusBadRequest,
		`{"error":{"message":"Template does not exist","code":132001,"error_subcode":2494010,"fbtrace_id":"Axb1cD"}}`)
	_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To: "+201500000093", TemplateCode: "PORTAL_UPDATE",
		TemplateName: "portal_update", TemplateLang: "en", Vars: []string{"x"},
	})
	_, detail := ClassOf(err)
	for _, want := range []string{"132001", "2494010", "Axb1cD"} {
		if !strings.Contains(detail, want) {
			t.Fatalf("the detail dropped %q: %q", want, detail)
		}
	}
}

// A destination that is not international is refused before any call - the
// same rule every sender in this package applies, and the reason a bad number
// is never retried.
func TestMetaRefusesADestinationThatIsNotE164(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	_, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To: "01500000093", TemplateName: "portal_update", TemplateLang: "ar",
	})
	if class, _ := ClassOf(err); err == nil || class != ClassPermanent {
		t.Fatalf("want a PERMANENT refusal, got %v (%s)", err, class)
	}
	if ms.body != nil {
		t.Fatal("a bad destination reached the provider")
	}
}

// A deployment that cannot send must say so at startup, not at a parent's
// first login.
func TestMetaRefusesAnIncompleteConfiguration(t *testing.T) {
	for _, tc := range []struct {
		name string
		cfg  MetaConfig
	}{
		{"no sender", MetaConfig{AccessToken: "t"}},
		{"no token", MetaConfig{PhoneNumberID: "1"}},
		{"a base that is not a URL", MetaConfig{PhoneNumberID: "1", AccessToken: "t", BaseURL: "graph.facebook.com"}},
		{"a version that is not one", MetaConfig{PhoneNumberID: "1", AccessToken: "t", APIVersion: "21.0"}},
	} {
		if _, err := NewMetaWhatsApp(tc.cfg); err == nil {
			t.Fatalf("%s: must not build", tc.name)
		}
	}
}

// The language is defaulted rather than sent empty: Meta answers a missing
// language by naming the template, which sends the reader looking in the
// wrong place.
func TestMetaDefaultsTheLanguage(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, metaAcceptedReply)
	if _, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To: "+201500000093", TemplateName: "portal_update", Vars: []string{"x"},
	}); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	tpl, _ := ms.body["template"].(map[string]any)
	lang, _ := tpl["language"].(map[string]any)
	if lang["code"] != "ar" {
		t.Fatalf("want the Arabic default, got %v", lang)
	}
}

// Accepted is accepted. A reply this service cannot parse must not be read as
// a failure, or the message goes a second time.
func TestMetaTreatsAnUnreadableAcceptanceAsAccepted(t *testing.T) {
	ms := newMetaServer(t, http.StatusOK, `{"messaging_product":"whatsapp"}`)
	res, err := newTestMeta(t, ms.URL).Send(context.Background(), Message{
		To: "+201500000093", TemplateName: "portal_update", TemplateLang: "ar", Vars: []string{"x"},
	})
	if err != nil {
		t.Fatalf("an accepted message with no id must not fail: %v", err)
	}
	if res.ProviderMessageID != "" {
		t.Fatalf("an id was invented: %+v", res)
	}
}
