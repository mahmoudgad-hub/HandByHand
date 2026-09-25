package http

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/sms"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The login flow is two requests: ask for a code, then exchange it for a
// session token. Neither of them decides anything. hbh.request_otp and
// hbh.verify_otp hold the whole policy - lifetime, resend window, attempt
// ceiling, what happens on the last wrong guess - and these handlers translate
// the answer into HTTP.

type otpRequestIn struct {
	Mobile string `json:"mobile"`
}

// otpRequestOut DOES distinguish a registered number from an unregistered one,
// by the owner's explicit decision on 2026-09-05.
//
// It used to be identical for both, and the reason is worth keeping written
// down rather than deleted, because it has not stopped being true: passing on
// hbh.request_otp's NOT_REGISTERED turns this endpoint into a way to ask "is
// this person a customer of this children's therapy centre?" - two calls, no
// account, no token. The answer is about a family and a disability, and it is
// the kind of thing that is not supposed to be answerable by a stranger.
//
// WHAT WAS TRADED FOR IT. The old behaviour sent a parent whose number is not
// on any child's file to a code screen to wait for an SMS that was never going
// to arrive, with nothing on the screen to tell them why or what to do. That
// is a real family, blocked at the front door, every time - against a leak
// that is real but conditional on somebody choosing to probe. The owner
// weighed the two and chose the parent. Recorded here, not argued again.
//
// AND A SECOND CASE, added by the owner on 2026-09-10 after walking into it:
// a family who filled in the enrolment form and has not been called back yet
// got the same code screen and the same silence. They are not strangers - the
// centre has their application open on a desk - and telling them "your
// application is still being reviewed" is the difference between waiting and
// giving up. ENROLMENT_PENDING is that answer, and hbh.request_otp decides
// when it applies (migration 0082), not this layer.
//
// A REJECTED APPLICATION IS NOT ONE OF THEM. REJECTED and DUPLICATE answer
// NOT_REGISTERED like any stranger: "the centre considered you and said no"
// is a decision about a family, it helps nobody standing at a login screen,
// and nobody asked for it.
//
// WHAT IS STILL WITHHELD. A locked account still answers SENT, because "this
// number exists but is locked" is a second, sharper fact about a named family
// and nobody asked for it either. The two durations still come from
// sys_params and still do not vary with the caller - except on the two
// answers above, where nothing was sent and a countdown would be counting
// down to nothing.
//
// AND IT WAS ALREADY ANSWERABLE. Before this change, asking for a code and
// then verifying any six digits told you the same thing: a registered number
// answered WRONG_CODE with an attempt count, an unregistered one
// NO_PENDING_CODE. So this makes an existing leak honest and visible rather
// than opening a closed one - but it does not close it either, and the verify
// path is where a real fix has to go.
type otpRequestOut struct {
	Status           string `json:"status"`
	ExpiresInSeconds int    `json:"expires_in_seconds"`
	ResendInSeconds  int    `json:"resend_in_seconds"`

	// DevCode is present only when OTP_ECHO is on, which config.Load permits
	// only outside production. There is no SMS gateway yet and the acceptance
	// suite has no other way to learn the code.
	DevCode *string `json:"dev_code,omitempty"`
}

func (s *Server) handleRequestOTP(w http.ResponseWriter, r *http.Request) {
	var in otpRequestIn
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	mobile := strings.TrimSpace(in.Mobile)
	pattern, err := s.params.MobilePattern(r.Context())
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if !pattern.MatchString(mobile) {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation, map[string]any{"mobile": "FORMAT"})
		return
	}

	res, err := s.db.RequestOTP(r.Context(), mobile)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	action := audit.ActionLogin
	if !res.OK {
		action = audit.ActionDeny
	}
	s.audit.Record(r.Context(), audit.Event{
		Action:   action,
		Actor:    maskMobile(mobile),
		Detail:   "OTP_REQUEST " + res.Reason,
		ClientIP: s.clientIP(r),
	})

	ttlMinutes := s.intParam(r, "OTP_TTL_MINUTES", 0)
	resend := s.intParam(r, "OTP_RESEND_SECONDS", 0)

	// TWO OUTCOMES NOW REACH THE SCREEN. Everything else still collapses
	// into SENT. The header of otpRequestOut carries the reasoning and what
	// it costs; this is the mapping only.
	//
	// The comment that stood here said the opposite of the one above the
	// type, and the CODE obeyed this one - so the decision of 2026-09-05
	// was written down and never carried out, and whichever half a reader
	// reached first is what they believed. It is carried out now, extended
	// by the owner on 2026-09-10 to cover a family who has applied and is
	// waiting to be called back.
	//
	// RESEND_TOO_SOON means a code IS outstanding, so "sent" is the useful
	// thing to say. USER_LOCKED stays withheld: "this number exists but is
	// locked" is a sharper fact than "this number exists", nobody asked for
	// it, and a locked family is one the centre is already speaking to.
	out := otpRequestOut{
		Status:           "SENT",
		ExpiresInSeconds: ttlMinutes * 60,
		ResendInSeconds:  resend,
	}
	switch res.Reason {
	case "NOT_REGISTERED", "ENROLMENT_PENDING":
		// Nothing was sent, so neither duration means anything. Leaving them
		// in puts a resend countdown on a screen with nothing to resend.
		out.Status = res.Reason
		out.ExpiresInSeconds = 0
		out.ResendInSeconds = 0
	}
	// DELIVERY. The code goes to the provider here, inside the request that
	// asked for it, and the plaintext is never written down on the way: it
	// exists in res.Code and in the rendered body, both of which live for the
	// length of this function. hbh.sms_outbox records the ATTEMPT - who,
	// when, which provider, what came back - with body_ar NULL, which
	// ck_sms_body makes structural rather than a habit.
	//
	// WHY THIS IS NOT QUEUED like every other message. A login code has a
	// fifteen-minute life and a parent watching a screen, so a worker polling
	// every five seconds is latency in the one flow where latency is the
	// product. And a queued code is a live credential sitting in a table
	// waiting to be picked up, which is the thing hbh.otp_codes stores only a
	// bcrypt hash to avoid.
	//
	// WHY A FAILURE DOES NOT CHANGE THE ANSWER. The response is already
	// SENT for a locked account and for a code that is still outstanding;
	// adding "the gateway is down" to the list would tell an outsider
	// something about this deployment and tell the parent nothing they can
	// act on. It is recorded, it is logged, and the screen says what it says.
	// THE NUMBER DELIVERED TO IS THE ONE THE DATABASE READ, NOT THE ONE THAT
	// WAS TYPED. They find the same account and are not the same string:
	// 00201225283838 was issued a code, answered SENT, and went to the
	// provider as typed, where it was refused as PERMANENT. The typed form is
	// still what the audit line above and the echo warning below mask, because
	// those describe the request; delivery describes where the code went.
	if res.OK && res.Code != nil && res.CenterID != nil && res.MobileE164 != nil {
		s.deliverOTP(r, *res.MobileE164, *res.Code, *res.CenterID, ttlMinutes)
	}

	if s.cfg.OTPEcho && res.Code != nil {
		out.DevCode = res.Code
		s.log.WarnContext(r.Context(), "one-time code echoed to the client - development only",
			"mobile", maskMobile(mobile))
	}

	// 202: the code was accepted for delivery. It is not 200, because on this
	// path nothing was returned to act on.
	writeJSON(w, http.StatusAccepted, out)
}

type otpVerifyIn struct {
	Mobile string `json:"mobile"`
	Code   string `json:"code"`
}

type otpVerifyOut struct {
	TokenType string    `json:"token_type"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}

func (s *Server) handleVerifyOTP(w http.ResponseWriter, r *http.Request) {
	var in otpVerifyIn
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	mobile := strings.TrimSpace(in.Mobile)
	code := strings.TrimSpace(in.Code)

	pattern, err := s.params.MobilePattern(r.Context())
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	// The code is checked for shape only - digits, non-empty. Its length is
	// OTP_LENGTH, a parameter that can change while a code is outstanding, so
	// enforcing it here would refuse a code the database would have accepted.
	if !pattern.MatchString(mobile) || code == "" || !isDigits(code) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	res, err := s.db.VerifyOTP(r.Context(), mobile, code)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	if !res.OK {
		s.audit.Record(r.Context(), audit.Event{
			Action:   audit.ActionDeny,
			Actor:    maskMobile(mobile),
			Detail:   "OTP_VERIFY " + res.Reason,
			ClientIP: s.clientIP(r),
		})
		status, code := verifyFailure(res.Reason)
		if res.AttemptsLeft != nil {
			writeErrorFields(w, r, status, code, map[string]any{"attempts_left": *res.AttemptsLeft})
			return
		}
		writeError(w, r, status, code)
		return
	}

	if res.UserID == nil {
		writeInternal(w, r, s.log, fmt.Errorf("verify_otp reported success with no user_id"))
		return
	}

	token, err := auth.NewToken()
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	session, err := s.db.CreateSession(r.Context(), *res.UserID, token, s.clientIP(r), r.UserAgent())
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionLogin,
		Actor:    "user:" + strconv.Itoa(*res.UserID),
		Detail:   "OTP_VERIFY OK session=" + strconv.FormatInt(session.ID, 10),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, otpVerifyOut{
		TokenType: "Bearer",
		Token:     token,
		ExpiresAt: session.ExpiresAt,
	})
}

// verifyFailure maps a database reason to a status and a client code.
//
// Every reason here is one a legitimate user needs to act on: try again, ask
// for a new code, call the centre. NOT_REGISTERED is not among them, and
// cannot be: hbh.verify_otp reports an unknown number as NO_PENDING_CODE,
// which is exactly what a known number with no live code reports.
func verifyFailure(reason string) (int, string) {
	switch reason {
	case store.ReasonWrongCode:
		return http.StatusUnauthorized, store.ReasonWrongCode
	case store.ReasonExpired:
		return http.StatusUnauthorized, store.ReasonExpired
	case store.ReasonNoPendingCode:
		return http.StatusUnauthorized, store.ReasonNoPendingCode
	case store.ReasonTooManyAttempts:
		// 423: the account is locked, and no repetition of this request will
		// change that. It is not 401, which invites the client to retry.
		return http.StatusLocked, store.ReasonTooManyAttempts
	case store.ReasonUserLocked:
		return http.StatusLocked, store.ReasonUserLocked
	default:
		return http.StatusUnauthorized, CodeUnauthenticated
	}
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	// Revoking a token that was already dead is not a failure - a client that
	// logs out twice has done nothing wrong - so the result is recorded and
	// not returned.
	revoked, err := s.db.RevokeSession(r.Context(), bearerToken(r), "LOGOUT")
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionLogin,
		Actor:    ident.Username,
		CenterID: &ident.CenterID,
		Detail:   "LOGOUT revoked=" + strconv.FormatBool(revoked),
		ClientIP: s.clientIP(r),
	})

	w.WriteHeader(http.StatusNoContent)
}

// intParam reads a numeric system parameter, falling back to def.
//
// A parameter that is missing or unreadable must not fail a login: these two
// values are hints for a countdown on the screen, not rules. The rules were
// applied inside the database before this handler saw the answer.
func (s *Server) intParam(r *http.Request, code string, def int) int {
	raw, err := s.params.Get(r.Context(), code, "")
	if err != nil || raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 0 {
		s.log.WarnContext(r.Context(), "system parameter is not a number", "param", code, "value", raw)
		return def
	}
	return n
}

func isDigits(s string) bool {
	for _, c := range s {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

// maskMobile keeps the last four digits and hides the rest.
//
// The audit trail has to identify the attempt or it proves nothing, and it is
// read by more people than the row it describes. Four digits distinguish the
// attempts of one afternoon without publishing anybody's phone number.
// deliverOTP hands a login code to the provider and records the attempt.
//
// EVERY ARGUMENT AND RETURN IS CHOSEN SO THE CODE CANNOT ESCAPE. It is not
// returned, not put in an error, not put in a log line, and not written to the
// outbox - the only place it lands is the provider's request body. The two
// things that DO get recorded are the destination and the outcome, which is
// what an operator needs to answer "did the code go out" and what an attacker
// cannot use.
//
// The message itself comes from sys_params.SMS_TEMPLATE_OTP, not from a string
// in this file: rule 2 of this project, and the practical half of it is that a
// centre changing its wording should not need a build. Placeholders are
// {code} and {minutes}, and a template missing them is refused rather than
// sent - a code nobody can read is worse than a failure somebody can see.
// The centre comes from hbh.request_otp and NOT from a query here. A code is
// issued before there is a session, so this connection carries no identity and
// the policy on hbh.users matches nothing - RLS failing closed, as designed.
// The first version of this function did the obvious lookup, got zero rows
// every time, and delivered nothing while returning 202. See migration 0095.
func (s *Server) deliverOTP(r *http.Request, mobile, code string, centerID, ttlMinutes int) {
	ctx := r.Context()

	body, terr := s.otpMessage(ctx, code, ttlMinutes)
	if terr != nil {
		s.log.ErrorContext(ctx, "the one-time code template is unusable", "err", terr)
		s.recordOTPDelivery(ctx, centerID, mobile, "", "", string(sms.ClassConfig),
			"SMS_TEMPLATE_OTP is missing or has no {code} placeholder")
		return
	}

	// The approved WhatsApp template for a login code in THIS centre, read
	// from hbh.message_templates (migration 0153). A code is sent inside the
	// request that asked for it, so there is no retry to fall back on: a
	// lookup that fails is recorded as TRANSIENT and not sent, which is
	// honest about whose fault it was, and the parent can ask again once the
	// resend window passes.
	tpl, lerr := s.db.TemplateRef(ctx, centerID, "OTP_LOGIN")
	if lerr != nil {
		s.log.ErrorContext(ctx, "the login-code template could not be looked up", "err", lerr)
		s.recordOTPDelivery(ctx, centerID, mobile, "", "", string(sms.ClassTransient),
			"the approved template could not be looked up")
		return
	}

	res, serr := s.sender.Send(ctx, sms.Message{
		TemplateName: tpl.Name,
		TemplateLang: tpl.Lang,
		TemplateAuth: tpl.Auth,
		To:           mobile,
		Body:         body,
		// THE SAME CODE, TWICE, IN TWO SHAPES, because the two transports ask
		// for different things and neither can use the other's. An SMS
		// provider takes the sentence SMS_TEMPLATE_OTP produced; WhatsApp
		// takes an approved template and the VALUES that go into it, and
		// refuses a sentence this service composed. Body is still the one
		// the centre edits, and it still comes from sys_params.
		//
		// ONE VARIABLE, AND THE MINUTES ARE NOT IT. A Meta AUTHENTICATION
		// template - the category an OTP must use - has a fixed body taking
		// {{1}} and nothing else; its expiry is a PROPERTY of the template,
		// set once at approval, not a value supplied per message. Passing the
		// minutes as {{2}} is rejected for a variable the template does not
		// have, and the refusal names the count rather than the cause.
		//
		// ttlMinutes therefore still reaches the family - through Body, on
		// the SMS path, from SMS_TEMPLATE_OTP - and reaches a WhatsApp reader
		// through the approved template's own expiry line.
		// OTP_LOGIN, WHICH IS WHAT THE OUTBOX ALREADY CALLS IT. This said
		// "OTP" until a real send was watched end to end: hbh.record_otp_delivery
		// writes template_code = 'OTP_LOGIN', so that is the name on the
		// operations screen and the only name an operator has to go on when
		// approving the template. Approving it as OTP_LOGIN - the sensible
		// reading - left the code looking for "OTP" and refusing every login
		// code with a CONFIG error naming a template nobody had heard of.
		TemplateCode: "OTP_LOGIN",
		Vars:         []string{code},
		// The reference is per code, not per request: a resend issues a new
		// code and gets a new row, which is what makes the outbox a history
		// of codes sent rather than of buttons pressed.
		Ref: "otp:" + strconv.FormatInt(time.Now().UTC().UnixNano(), 10),
	})
	if serr != nil {
		class, detail := sms.ClassOf(serr)
		s.recordOTPDelivery(ctx, centerID, mobile, "", "", string(class), detail)
		s.log.WarnContext(ctx, "a login code was not delivered",
			"mobile", maskMobile(mobile), "provider", s.sender.Code(),
			"class", string(class))
		return
	}

	s.recordOTPDelivery(ctx, centerID, mobile, s.sender.Code(), res.ProviderMessageID, "", "")
}

func (s *Server) recordOTPDelivery(ctx context.Context, centerID int, mobile,
	provider, providerMsg, errClass, errDetail string) {
	if provider == "" {
		provider = s.sender.Code()
	}
	if err := s.db.EnqueueOTPDelivery(ctx, centerID, mobile,
		provider, providerMsg, errClass, errDetail); err != nil {
		// The code was sent or it was not; failing to write the RECORD of it
		// must not fail the login. It is logged so the gap is visible.
		s.log.ErrorContext(ctx, "a login code delivery could not be recorded", "err", err)
	}
}

// otpMessage renders the template.
//
// 26 of the brief asks for the code, the expiry and a warning not to share it,
// and nothing else - no name, no child, no centre address. The whole of that
// is the centre's to word, so it is a parameter; what is enforced here is only
// that the result actually contains the code.
func (s *Server) otpMessage(ctx context.Context, code string, ttlMinutes int) (string, error) {
	tpl, err := s.params.Get(ctx, "SMS_TEMPLATE_OTP", "")
	if err != nil {
		return "", err
	}
	if !strings.Contains(tpl, "{code}") {
		return "", errors.New("SMS_TEMPLATE_OTP has no {code} placeholder")
	}
	out := strings.ReplaceAll(tpl, "{code}", code)
	out = strings.ReplaceAll(out, "{minutes}", strconv.Itoa(ttlMinutes))
	return out, nil
}

func maskMobile(m string) string {
	if len(m) <= 4 {
		return "mobile:****"
	}
	return "mobile:****" + m[len(m)-4:]
}

type staffLoginIn struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// handleStaffLogin signs in a member of staff.
//
// The operations app needs this because its users are not families: a parent
// proves a phone, a therapist proves a password, and hbh.verify_password
// refuses to let the two paths cross - a GUARDIAN account is turned away with
// NOT_PASSWORD_USER however good the password is.
//
// Every failure answers 401 with the same code. BAD_CREDENTIALS and
// NOT_PASSWORD_USER are deliberately collapsed: telling an outsider that a
// username exists but signs in another way is telling them the username
// exists.
func (s *Server) handleStaffLogin(w http.ResponseWriter, r *http.Request) {
	var in staffLoginIn
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	username := strings.TrimSpace(in.Username)
	if username == "" || in.Password == "" {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	res, err := s.db.VerifyPassword(r.Context(), username, in.Password)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	if !res.OK {
		s.audit.Record(r.Context(), audit.Event{
			Action:   audit.ActionDeny,
			Actor:    username,
			Detail:   "STAFF_LOGIN " + res.Reason,
			ClientIP: s.clientIP(r),
		})
		status, code := http.StatusUnauthorized, CodeUnauthenticated
		if res.Reason == "TEMPORARILY_LOCKED" || res.Reason == store.ReasonUserLocked {
			// 423, not 401: repeating the request will not help, and a client
			// that keeps retrying only deepens the lockout.
			status, code = http.StatusLocked, res.Reason
		}
		writeError(w, r, status, code)
		return
	}

	if res.UserID == nil {
		writeInternal(w, r, s.log, fmt.Errorf("verify_password reported success with no user_id"))
		return
	}

	token, err := auth.NewToken()
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	session, err := s.db.CreateSession(r.Context(), *res.UserID, token, s.clientIP(r), r.UserAgent())
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionLogin,
		Actor:    "user:" + strconv.Itoa(*res.UserID),
		Detail:   "STAFF_LOGIN OK session=" + strconv.FormatInt(session.ID, 10),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, otpVerifyOut{
		TokenType: "Bearer",
		Token:     token,
		ExpiresAt: session.ExpiresAt,
	})
}
