package http

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The home programme, and the first two endpoints in this service that write.
//
// A write is checked twice, and not by accident. This layer first establishes
// that the child is visible, which turns "not yours" into 404 with a recorded
// refusal. The database function then checks again, from inside, and its check
// is the narrower one: hbh.submit_request requires the caller to be an actual
// GUARDIAN of the child, which staff who may read that child are not.
//
// The first check exists for the answer, not the safety. Remove it and the
// system is still safe - the function refuses - but a caller walking
// identifiers would get 403 for a child that is not theirs, which confirms the
// child exists. The database protects; this layer decides what to say.

func (s *Server) handleActivities(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_ACTIVITIES", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Activities(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"activities": rows}, nil
	})
}

func (s *Server) handleActivityLog(w http.ResponseWriter, r *http.Request) {
	win, ok := window(r)
	if !ok {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"limit": "1.." + strconv.Itoa(maxLimit)})
		return
	}
	s.childRead(w, r, "CHILD_ACTIVITY_LOG", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.ActivityLog(ctx, ident, childID, win.Limit)
		if err != nil {
			return nil, err
		}
		return map[string]any{"log": rows}, nil
	})
}

type logActivityIn struct {
	// A calendar day, because that is what the family is reporting on. Empty
	// means today, decided by the database's current_date and not by this
	// process's clock - the server and the family are in different zones.
	LogDate string `json:"log_date"`
	Done    *bool  `json:"done"`
	NoteAr  string `json:"note_ar"`
}

func (s *Server) handleLogActivity(w http.ResponseWriter, r *http.Request) {
	var in logActivityIn
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	var day *time.Time
	if raw := strings.TrimSpace(in.LogDate); raw != "" {
		parsed, err := time.Parse("2006-01-02", raw)
		if err != nil {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"log_date": "YYYY-MM-DD"})
			return
		}
		day = &parsed
	}

	done := true
	if in.Done != nil {
		done = *in.Done
	}

	activityID, err := strconv.Atoi(r.PathValue("child_activity_id"))
	if err != nil || activityID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	s.childWrite(w, r, "ACTIVITY_LOG", func(ctx context.Context, ident string, childID int) (any, int, error) {
		logID, err := s.db.LogActivity(ctx, ident, activityID, day, done, in.NoteAr)
		if err != nil {
			return nil, 0, err
		}
		return map[string]any{"log_id": logID}, http.StatusCreated, nil
	})
}

func (s *Server) handleRequests(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_REQUESTS", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Requests(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"requests": rows}, nil
	})
}

func (s *Server) handleSubmitRequest(w http.ResponseWriter, r *http.Request) {
	var in domain.NewRequest
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	in.KindCode = strings.TrimSpace(in.KindCode)
	if in.KindCode == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"kind_code": "REQUIRED"})
		return
	}

	// The accepted kinds are lookup rows, not a Go constant. A centre that
	// stops taking callback requests deactivates a row; nothing is rebuilt.
	ident, _ := auth.FromContext(r.Context())
	kinds, err := s.db.RequestKinds(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if !slices.Contains(kinds, in.KindCode) {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"kind_code": "UNKNOWN", "accepted": kinds})
		return
	}

	s.childWrite(w, r, "REQUEST_SUBMIT", func(ctx context.Context, ident string, childID int) (any, int, error) {
		requestID, err := s.db.SubmitRequest(ctx, ident, childID, in)
		if err != nil {
			return nil, 0, err
		}
		return map[string]any{"request_id": requestID}, http.StatusCreated, nil
	})
}

// childWrite is childRead's counterpart for the two endpoints that change
// something. It adds the mapping from the database's own refusal codes.
func (s *Server) childWrite(w http.ResponseWriter, r *http.Request, what string,
	fn func(ctx context.Context, ident string, childID int) (any, int, error)) {

	ident, _ := auth.FromContext(r.Context())

	childID, err := strconv.Atoi(r.PathValue("child_id"))
	if err != nil || childID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	// Establish visibility first, so a child that is not the caller's answers
	// 404 rather than the 403 the database function would produce - a 403
	// would confirm the child exists.
	if _, err := s.db.Child(r.Context(), ident.Username, childID); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail:   "CHILD_NOT_VISIBLE child_id=" + strconv.Itoa(childID) + " on=" + what,
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	body, status, err := fn(r.Context(), ident.Username, childID)
	if err != nil {
		switch store.Code(err) {
		case store.ErrAlreadyLogged:
			writeError(w, r, http.StatusConflict, CodeAlreadyLogged)
		case store.ErrNoSuchActivity:
			// The activity is unknown, or belongs to another child. Same
			// answer for both, for the same reason as everywhere else.
			writeError(w, r, http.StatusNotFound, CodeNotFound)
		case store.ErrNotGuardian:
			// The child IS visible - we just checked - so this is the honest
			// case for 403: a staff account may read this child but may not
			// act for the family. It confirms nothing new.
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail:   "NOT_A_GUARDIAN child_id=" + strconv.Itoa(childID) + " on=" + what,
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusForbidden, CodeForbidden)
		case store.ErrCheckViolation, store.ErrForeignKeyViolation:
			// A well-formed body the schema will not accept - a RESCHEDULE
			// that names no appointment, an appointment identifier that does
			// not exist. The constraint name is logged for the operator and
			// not returned: it is a schema detail.
			s.log.WarnContext(r.Context(), "a write was refused by a constraint",
				"on", what, "child_id", childID, "err", err)
			writeError(w, r, http.StatusBadRequest, CodeValidation)
		default:
			writeInternal(w, r, s.log, err)
		}
		return
	}

	// No audit call on success, deliberately. This is a CHANGE, and D-1 puts
	// change records on hbh.trg_audit inside the transaction that made them -
	// so a write that is rolled back takes its own record with it, which is
	// correct. hbh.audit_attempt is for attempts, and it accepts only LOGIN,
	// DENY and READ; filing a successful insert under one of those to get a
	// line in the log would put a lie in the audit trail.
	writeJSON(w, status, body)
}
