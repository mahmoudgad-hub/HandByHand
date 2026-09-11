package http

import (
	"context"
	"encoding/json"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

// Intake and the satisfaction survey.
//
// The first endpoint below is the only WRITE in this service that answers a
// caller with no token, and it is worth knowing why that is safe: it reaches
// exactly one SECURITY DEFINER function, that function decides for itself
// whether to accept the row, and the transaction it runs in still carries no
// identity - so nothing else in the schema is visible to it.

// isoDate is the calendar-day shape. A birth date is a day, not an instant.
var isoDate = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

// handleSubmitEnrolment records an application from a family with no account.
//
// WHAT THE CALLER IS TOLD, AND WHAT THEY ARE NOT. The database answers with a
// reason - REJECTED, TOO_MANY_FOR_MOBILE, TOO_MANY_FOR_IP - and none of them
// reaches the browser as written:
//
//   - REJECTED means the centre code is unknown. Passing it through would let
//     anybody enumerate which centres exist by trying codes.
//   - The two limits are told apart in the log and NOT in the answer. Saying
//     "too many for this mobile" tells a stranger that the number they typed
//     is already known to this centre, which is a fact about a family.
//
// So a refusal is one of two shapes: 429 for a limit and 400 for anything
// else, with no detail on either. The distinction is recorded where the centre
// can see it.
func (s *Server) handleSubmitEnrolment(w http.ResponseWriter, r *http.Request) {
	var in store.EnrolmentIn
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if field, ok := badEnrolment(in); !ok {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation, map[string]any{"field": field})
		return
	}

	// The address is passed even when it is uncertain, because a nil one
	// silently disables the per-address limit. An unenforced limit that looks
	// enforced is worse than no limit at all.
	ip := s.clientIP(r)

	res, err := s.db.SubmitEnrolment(r.Context(), in, ip)
	if err != nil {
		s.opsError(w, r, "SUBMIT_ENROLMENT", err)
		return
	}

	if !res.OK {
		// Recorded with the real reason. This is the only place the
		// distinction exists, and an intake queue that suddenly stops filling
		// is answered here rather than by guesswork.
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Detail: "ENROLMENT " + res.Reason, ClientIP: ip,
		})
		switch res.Reason {
		case store.EnrolmentTooManyMobil, store.EnrolmentTooManyIP:
			writeError(w, r, http.StatusTooManyRequests, CodeRateLimited)
		default:
			writeError(w, r, http.StatusBadRequest, CodeValidation)
		}
		return
	}

	// The application number is the ONE thing the family gets back. It is
	// their reference when they telephone, and it discloses nothing: it does
	// not resolve to a row for anybody who is not signed in.
	writeJSON(w, http.StatusCreated, map[string]any{"application_no": res.ApplicationNo})
}

// badEnrolment names the first missing or malformed field.
//
// It checks SHAPE only - present, a date that is a date, a gender that is one
// of two letters. Whether the centre exists, whether the family has already
// applied three times today, whether the service identifier is real: all of
// that is the database's, and asking it twice would be two answers.
func badEnrolment(in store.EnrolmentIn) (string, bool) {
	for _, f := range []struct {
		name string
		val  string
	}{
		{"center_code", in.CenterCode},
		{"parent_name_ar", in.ParentNameAr},
		{"parent_mobile", in.ParentMobile},
		{"child_name_ar", in.ChildNameAr},
	} {
		if strings.TrimSpace(f.val) == "" {
			return f.name, false
		}
	}
	if !isoDate.MatchString(in.ChildBirthDate) {
		return "child_birth_date (YYYY-MM-DD)", false
	}
	if in.ChildGender != "M" && in.ChildGender != "F" {
		return "child_gender (M|F)", false
	}
	return "", true
}

func (s *Server) handleEnrolments(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := store.EnrolmentQuery{
		Status:   strings.TrimSpace(r.URL.Query().Get("status")),
		Archived: r.URL.Query().Get("archived") == "true",
		Limit:    defaultLimit,
	}
	if raw := r.URL.Query().Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > maxLimit {
			badQuery(w, r, errBadLimit)
			return
		}
		q.Limit = n
	}
	if raw := r.URL.Query().Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			badQuery(w, r, errBadPage)
			return
		}
		q.Offset = (n - 1) * q.Limit
	}

	rows, total, err := s.db.Enrolments(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	// An application carries a name, a mobile and a paragraph about a child.
	// It is read-sensitive from the moment it is filed, so the read is
	// recorded like any other - triggers do not catch reads.
	s.recordOpsRead(r, "ENROLMENTS")
	writeJSON(w, http.StatusOK, page("enrolments", rows, total, q.Limit, q.Offset))
}

func (s *Server) handleEnrolment(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "application_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	e, err := s.db.Enrolment(r.Context(), ident.Username, id)
	if err != nil {
		s.opsError(w, r, "ENROLMENT", err)
		return
	}
	s.recordOpsRead(r, "ENROLMENT")
	writeJSON(w, http.StatusOK, e)
}

func (s *Server) handleEnrolmentStatus(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "application_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.EnrolmentUpdate
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.Status) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"status": "CONTACTED|ASSESSMENT_BOOKED|ENROLLED|REJECTED|DUPLICATE"})
		return
	}
	if err := s.db.SetEnrolmentStatus(r.Context(), ident.Username, id, in); err != nil {
		s.opsError(w, r, "ENROLMENT_STATUS", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleConvertEnrolment turns an application into a family.
//
// 201 with the identifiers, because something was created - a guardian, a
// child, and the link between them. The response is what the screen needs to
// navigate straight to the new child's file, which is what the person who just
// converted it wants to do next.
func (s *Server) handleConvertEnrolment(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "application_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		NoteAr string `json:"note_ar"`
	}
	if r.ContentLength > 0 {
		if err := decodeJSON(w, r, &in); err != nil {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
	}
	c, err := s.db.ConvertEnrolment(r.Context(), ident.Username, id, in.NoteAr)
	if err != nil {
		s.opsError(w, r, "CONVERT_ENROLMENT", err)
		return
	}
	writeJSON(w, http.StatusCreated, c)
}

// =====================================================================
// THE SATISFACTION SURVEY
// =====================================================================

// handleNPSDue answers with the question to show now, or with null.
//
// null is an ORDINARY answer, not 404: "there is nothing to ask you" is the
// usual state of this endpoint, and a screen that treated it as an error would
// log a failure on every page load.
func (s *Server) handleNPSDue(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	p, err := s.db.NPSDue(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"survey": p})
}

func (s *Server) handleSubmitNPS(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "survey_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.NPSAnswer
	if err := decodeJSON(w, r, &in); err != nil || in.Score == nil {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"score": "0..10"})
		return
	}
	if _, err := s.db.SubmitNPS(r.Context(), ident.Username, id, in, s.clientIP(r)); err != nil {
		s.opsError(w, r, "SUBMIT_NPS", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleSkipNPS records a dismissal.
//
// This endpoint exists so the question can stop. A client that shows the
// prompt and drops the dismissal turns one question into one per page load -
// the cooldown starts when something is RECORDED, and a closed dialog records
// nothing on its own.
func (s *Server) handleSkipNPS(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "survey_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.NPSAnswer
	if r.ContentLength > 0 {
		if err := decodeJSON(w, r, &in); err != nil {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
	}
	if _, err := s.db.SkipNPS(r.Context(), ident.Username, id, in.ContextKind, in.ContextID); err != nil {
		s.opsError(w, r, "SKIP_NPS", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleNPSSummary(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.NPSSummary(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	monthly, err := s.db.NPSMonthly(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"surveys": rows, "total": len(rows), "monthly": monthly})
}

// =====================================================================
// THE OPERATIONS SCREEN
// =====================================================================

// The three views behind /ops. Each needs OPS.VIEW, which only a centre
// administrator holds - and as everywhere else that is enforced by the policy,
// so a caller without it gets an empty list rather than a refusal. An empty
// list is the correct answer to "show me what I may see" when the answer is
// nothing.

func (s *Server) handleOpsHealth(w http.ResponseWriter, r *http.Request) {
	s.viewEndpoint(w, r, "OPS_HEALTH", "routes", s.db.APIHealth)
}

func (s *Server) handleOpsErrors(w http.ResponseWriter, r *http.Request) {
	s.viewEndpoint(w, r, "OPS_ERRORS", "errors", s.db.RecentErrors)
}

func (s *Server) handleOpsActivity(w http.ResponseWriter, r *http.Request) {
	s.viewEndpoint(w, r, "OPS_ACTIVITY", "users", s.db.UserActivity)
}

// viewEndpoint is the shared body of the three reporting reads.
func (s *Server) viewEndpoint(w http.ResponseWriter, r *http.Request, what, name string,
	read func(ctx context.Context, ident string) ([]json.RawMessage, error)) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := read(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, what)
	writeJSON(w, http.StatusOK, map[string]any{name: rows, "total": len(rows)})
}

func (s *Server) handleDashboardMetrics(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.DashboardMetrics(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, rows[0])
}
