package http

import (
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"

	"github.com/handbyhand/hbh/api/internal/config"
)

// Every error this service returns is a CODE, never a sentence.
//
// The interface speaks Arabic; this layer does not speak at all. Arabic
// wording lives in the Angular translation files, for the same reason it does
// not live in an Angular template: a message written where it is displayed
// gets copied, then edited in one copy only. A code also survives a second
// language without a release. See CLAUDE.md, and docs/01-stack-decisions.md
// D-11.
const (
	CodeValidation       = "VALIDATION"
	CodeUnauthenticated  = "UNAUTHENTICATED"
	CodeForbidden        = "FORBIDDEN"
	CodeNotFound         = "NOT_FOUND"
	CodeMethodNotAllowed = "METHOD_NOT_ALLOWED"
	CodeRateLimited      = "RATE_LIMITED"
	CodeInternal         = "INTERNAL"
	CodeUnavailable      = "UNAVAILABLE"

	// The file is bigger than the ceiling for its kind. Distinct from
	// VALIDATION: nothing about the file is wrong, there is simply a limit,
	// and a screen that says "check the values you entered" over a
	// photograph sends somebody looking for a typo in a picture.
	CodeTooLarge = "TOO_LARGE"

	// The family already recorded that day. Not a fault - the database
	// refuses rather than overwriting, because a second tap is far more
	// likely than a genuine change of mind, and replacing what somebody
	// said the first time loses a real answer.
	CodeAlreadyLogged = "ALREADY_LOGGED"

	// The session is not running. Distinct from NOT_FOUND: the caller can
	// see this session, there is simply nothing live in it.
	CodeNotLive = "NOT_LIVE"

	// No media gateway, or one that must not serve a family - unconfigured,
	// still marked temporary, or a quick tunnel. A fresh install is all
	// three, so this is the DEFAULT answer until somebody deliberately
	// configures a named tunnel on a domain the centre owns.
	CodeStreamUnavailable = "STREAM_UNAVAILABLE"

	// Two callers raced for one appointment slot and the exclusion
	// constraint picked a winner. Not a fault - the diary is simply fuller
	// than the caller thought a moment ago.
	CodeSlotTaken = "SLOT_TAKEN"
)

type errorBody struct {
	Error errorDetail `json:"error"`
}

type errorDetail struct {
	Code      string         `json:"code"`
	RequestID string         `json:"request_id,omitempty"`
	Fields    map[string]any `json:"fields,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	// The portal answers with a person's data. No cache anywhere holds it.
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	if body != nil {
		_ = json.NewEncoder(w).Encode(body)
	}
}

func writeError(w http.ResponseWriter, r *http.Request, status int, code string) {
	writeErrorFields(w, r, status, code, nil)
}

// writeErrorFields is the single place a refusal leaves this service, which is
// why the request log is stamped here rather than in each handler.
//
// The schema refuses a logged row of 400 or more that carries no error code,
// and rightly: an error nobody named is an error nobody can count. Recording
// the code where it is decided means no handler can forget to.
//
// Fields names WHICH field was refused - "limit", "score", a constraint's
// class - and never the value that was sent. That is what makes it safe to
// keep on a row an operator reads.
func writeErrorFields(w http.ResponseWriter, r *http.Request, status int, code string, fields map[string]any) {
	if t := traceFrom(r.Context()); t != nil {
		t.errCode = code
		t.errFields = fields
	}
	writeJSON(w, status, errorBody{Error: errorDetail{Code: code, RequestID: RequestIDFrom(r.Context()), Fields: fields}})
}

// writeInternal answers 500 without saying anything about why.
//
// The cause goes to the log with the request id attached, so an operator can
// find it; the client gets the id and nothing else. A database error text
// forwarded to a browser is a schema disclosure.
func writeInternal(w http.ResponseWriter, r *http.Request, log *slog.Logger, err error) {
	log.ErrorContext(r.Context(), "request failed",
		"method", r.Method, "path", r.URL.Path,
		"request_id", RequestIDFrom(r.Context()), "err", err)
	writeError(w, r, http.StatusInternalServerError, CodeInternal)
}

// decodeJSON reads a bounded request body into dst.
//
// Unknown fields are refused rather than ignored. A client sending
// {"mobil": "..."} because of a typo would otherwise be told its number failed
// validation, which sends the reader looking in exactly the wrong place.
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) error {
	if ct := r.Header.Get("Content-Type"); ct != "" {
		if mt := strings.TrimSpace(strings.Split(ct, ";")[0]); mt != "application/json" {
			return errors.New("content type must be application/json")
		}
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, config.MaxRequestBody))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	// Exactly one JSON value, not a stream.
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("body must contain a single JSON object")
	}
	return nil
}
