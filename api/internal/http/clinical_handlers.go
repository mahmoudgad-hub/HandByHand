package http

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

// Every endpoint below hangs off a child, and every one of them inherits the
// gate the same way: the store checks that the child is visible inside the
// same transaction as the read, and answers ErrNotFound when it is not. This
// file turns that into 404 plus a recorded refusal, once, for all five.
//
// Doing it in one helper is not only about repetition. Five copies of "if not
// found, audit and 404" is five chances for one of them to answer 403 by
// accident, or to skip the audit line - and the one that skipped it would be
// the one nobody noticed.

// listLimit bounds a page. These are transport limits, not business values: a
// centre never wants to configure them, and an unbounded list is a way to turn
// one request into a very long one.
const (
	defaultLimit = 200
	maxLimit     = 500
)

// childRead runs one child-scoped read and handles the three outcomes.
//
// `what` names the read in the audit trail. It is a constant per endpoint and
// never carries anything the caller supplied.
func (s *Server) childRead(w http.ResponseWriter, r *http.Request, what string,
	fn func(ctx context.Context, ident string, childID int) (any, error)) {

	ident, _ := auth.FromContext(r.Context())

	childID, err := strconv.Atoi(r.PathValue("child_id"))
	if err != nil || childID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	body, err := fn(r.Context(), ident.Username, childID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			s.audit.Record(r.Context(), audit.Event{
				Action:   audit.ActionDeny,
				Actor:    ident.Username,
				CenterID: &ident.CenterID,
				Detail:   "CHILD_NOT_VISIBLE child_id=" + strconv.Itoa(childID) + " on=" + what,
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	// A trigger cannot see a SELECT. Clinical history read by anybody is
	// recorded here or it is recorded nowhere.
	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionRead,
		Actor:    ident.Username,
		CenterID: &ident.CenterID,
		Detail:   what + " child_id=" + strconv.Itoa(childID),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, body)
}

// window reads the optional from/to/limit query parameters.
//
// from and to must be RFC 3339 instants, not bare dates. A bare date would
// force this layer to decide which midnight it meant - Cairo's or UTC's - and
// that decision is a business rule, which does not belong in code (D-5, and
// the rule about parameters). The client knows its own zone and sends an
// instant.
func window(r *http.Request) (store.Window, bool) {
	w := store.Window{Limit: defaultLimit}
	q := r.URL.Query()

	for _, p := range []struct {
		name string
		dst  **string
	}{{"from", &w.From}, {"to", &w.To}} {
		raw := q.Get(p.name)
		if raw == "" {
			continue
		}
		if _, err := time.Parse(time.RFC3339, raw); err != nil {
			return store.Window{}, false
		}
		v := raw
		*p.dst = &v
	}

	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > maxLimit {
			return store.Window{}, false
		}
		w.Limit = n
	}
	return w, true
}

func (s *Server) handleAppointments(w http.ResponseWriter, r *http.Request) {
	win, ok := window(r)
	if !ok {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"from": "RFC3339", "to": "RFC3339", "limit": "1.." + strconv.Itoa(maxLimit)})
		return
	}
	s.childRead(w, r, "CHILD_APPOINTMENTS", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Appointments(ctx, ident, childID, win)
		if err != nil {
			return nil, err
		}
		return map[string]any{"appointments": rows}, nil
	})
}

func (s *Server) handleSessions(w http.ResponseWriter, r *http.Request) {
	win, ok := window(r)
	if !ok {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"from": "RFC3339", "to": "RFC3339", "limit": "1.." + strconv.Itoa(maxLimit)})
		return
	}
	s.childRead(w, r, "CHILD_SESSIONS", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Sessions(ctx, ident, childID, win)
		if err != nil {
			return nil, err
		}
		return map[string]any{"sessions": rows}, nil
	})
}

func (s *Server) handlePlans(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_PLANS", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Plans(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"plans": rows}, nil
	})
}

func (s *Server) handleReports(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_REPORTS", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Reports(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"reports": rows}, nil
	})
}

func (s *Server) handleNotes(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_NOTES", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Notes(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"notes": rows}, nil
	})
}

// handleReport reads one progress report by its own identifier.
//
// There is no child in the path and no ownership check here. The policy on
// progress_reports requires can_access_child AND, for a guardian, that the
// report is PUBLISHED - so a draft about the caller's own child answers
// exactly like a report that was never written. That sameness is the point: a
// parent must not be able to learn that a report about their child exists
// before the clinician has decided to publish it.
func (s *Server) handleReport(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	reportID, err := strconv.Atoi(r.PathValue("report_id"))
	if err != nil || reportID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	report, childID, err := s.db.Report(r.Context(), ident.Username, reportID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			s.audit.Record(r.Context(), audit.Event{
				Action:   audit.ActionDeny,
				Actor:    ident.Username,
				CenterID: &ident.CenterID,
				Detail:   "REPORT_NOT_VISIBLE report_id=" + strconv.Itoa(reportID),
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionRead,
		Actor:    ident.Username,
		CenterID: &ident.CenterID,
		Detail:   "REPORT report_id=" + strconv.Itoa(reportID) + " child_id=" + strconv.Itoa(childID),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, report)
}
