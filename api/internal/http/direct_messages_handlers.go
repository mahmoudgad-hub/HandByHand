package http

import (
	"github.com/handbyhand/hbh/api/internal/auth"
	"net/http"
	"strconv"
	"strings"
	"unicode/utf8"
)

func (s *Server) handleChatContacts(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if utf8.RuneCountInString(q) > 100 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	rows, err := s.db.ChatContacts(r.Context(), ident.Username, q)
	if err != nil {
		s.opsError(w, r, "FAMILY_CONTACTS", err)
		return
	}
	more := false
	writeJSON(w, http.StatusOK, map[string]any{"rows": rows, "more": more})
}
func (s *Server) handleDirectMessages(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, err := strconv.Atoi(r.PathValue("user_id"))
	if err != nil || id <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	before := int64(0)
	if value := r.URL.Query().Get("before"); value != "" {
		before, err = strconv.ParseInt(value, 10, 64)
		if err != nil || before < 0 {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
	}
	rows, err := s.db.DirectMessages(r.Context(), ident.Username, id, before)
	if err != nil {
		s.opsError(w, r, "FAMILY_MESSAGES", err)
		return
	}
	more := len(rows) > 50
	if more {
		rows = rows[:50]
	}
	writeJSON(w, http.StatusOK, map[string]any{"rows": rows, "more": more})
}
func (s *Server) handleSendDirectMessage(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, err := strconv.Atoi(r.PathValue("user_id"))
	if err != nil || id <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	var in struct {
		Body      string `json:"body"`
		RequestID string `json:"request_id"`
	}
	if decodeJSON(w, r, &in) != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	in.Body = strings.TrimSpace(in.Body)
	if utf8.RuneCountInString(in.Body) < 1 || utf8.RuneCountInString(in.Body) > 4000 || !messageRequestID.MatchString(in.RequestID) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	mid, err := s.db.SendDirectMessage(r.Context(), ident.Username, id, in.Body, in.RequestID)
	if err != nil {
		s.opsError(w, r, "SEND_FAMILY_MESSAGE", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"message_id": mid})
}

func (s *Server) handleReadDirectMessages(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, err := strconv.Atoi(r.PathValue("user_id"))
	var in struct {
		MessageID int64 `json:"message_id"`
	}
	if err != nil || id <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := decodeJSON(w, r, &in); err != nil || in.MessageID <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := s.db.ReadDirectMessages(r.Context(), ident.Username, id, in.MessageID); err != nil {
		s.opsError(w, r, "FAMILY_READ", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}
func (s *Server) handleBroadcastStaff(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in struct {
		Body      string `json:"body"`
		RequestID string `json:"request_id"`
	}
	if decodeJSON(w, r, &in) != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	in.Body = strings.TrimSpace(in.Body)
	if utf8.RuneCountInString(in.Body) < 1 || utf8.RuneCountInString(in.Body) > 4000 || !messageRequestID.MatchString(in.RequestID) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	count, err := s.db.BroadcastStaff(r.Context(), ident.Username, in.Body, in.RequestID)
	if err != nil {
		s.opsError(w, r, "CHAT_BROADCAST", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"count": count})
}
