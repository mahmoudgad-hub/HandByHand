package http

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/auth"
)

// The notification feed.
//
// hbh.notifications has existed since migration 0015 and seven triggers have
// been filling it ever since. Until now NO ROUTE READ IT - the table was
// write-only at the transport layer, and the portal's shell carries a comment
// saying the bell was removed because "there is no notifications feature to
// open". This is that feature.
//
// ONE ENDPOINT FOR BOTH AUDIENCES, and deliberately so. 0089 added kinds
// addressed to staff, and a therapist's feed and a parent's feed are the same
// query against the same policy: `user_id = hbh.current_user_id()`. A second
// endpoint for the operations console would be a second place for that rule to
// live, and handleChildren's header already gives the argument.
//
// THERE IS NO ENDPOINT THAT CREATES ONE. Notifications are written by triggers
// on the events that matter, which is 0015's whole design - a family is told
// because something HAPPENED, not because a handler remembered. A POST here
// would also be the "send anything to anyone" capability the brief refuses.

const (
	notificationsDefaultLimit = 30
	notificationsMaxLimit     = 100
)

func (s *Server) handleNotifications(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := r.URL.Query()

	limit := notificationsDefaultLimit
	if raw := strings.TrimSpace(q.Get("limit")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > notificationsMaxLimit {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"limit": "RANGE"})
			return
		}
		limit = n
	}
	offset := 0
	if raw := strings.TrimSpace(q.Get("offset")); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 0 {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"offset": "RANGE"})
			return
		}
		offset = n
	}

	page, err := s.db.Notifications(r.Context(), ident.Username, limit, offset)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, page)
}

// handleMarkNotificationRead marks one item read.
//
// READ STATE IS UI STATE AND NOTHING ELSE. Nothing in this schema branches on
// it: a report is published whether or not its notification was opened, an
// appointment is confirmed either way. That is worth saying because the moment
// a business rule reads read_at, a parent who never opens the portal changes
// what the centre may do.
//
// A row that is not the caller's answers 404, the same as one that does not
// exist. Distinguishing them would confirm the existence of another family's
// notification to anybody willing to walk the identifiers - db.go's ErrNotFound
// comment, applied to a different table.
func (s *Server) handleMarkNotificationRead(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	id, err := strconv.ParseInt(r.PathValue("notification_id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	ok, err := s.db.MarkNotificationRead(r.Context(), ident.Username, id)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if !ok {
		// Also the answer for an item that was ALREADY read, which is not an
		// error: a client that taps twice has done nothing wrong. 204 would
		// be wrong the other way - it would tell a prober that the id exists.
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
