package http

import (
	"errors"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/jackc/pgx/v5/pgconn"
	"net/http"
	"regexp"
	"strconv"
	"time"
)

var usageFeature = regexp.MustCompile(`^[a-zA-Z0-9_.:-]{1,100}$`)

func validAnalyticsRange(from, to string) bool {
	a, e1 := time.Parse("2006-01-02", from)
	b, e2 := time.Parse("2006-01-02", to)
	return e1 == nil && e2 == nil && !b.Before(a) && b.Sub(a) <= 365*24*time.Hour
}

func (s *Server) handleOpsAnalytics(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	offset := 0
	var err error
	if q.Get("offset") != "" {
		offset, err = strconv.Atoi(q.Get("offset"))
	}
	if err != nil || offset < 0 || offset > 1000000 || !validAnalyticsRange(q.Get("from"), q.Get("to")) || len(q.Get("feature")) > 250 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	ident, _ := auth.FromContext(r.Context())
	result, err := s.db.OpsAnalytics(r.Context(), ident.Username, q.Get("from"), q.Get("to"), q.Get("kind"), q.Get("feature"), offset)
	if err != nil {
		s.analyticsError(w, r, err)
		return
	}
	s.recordOpsRead(r, "OPS_ANALYTICS")
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleUsageEvent(w http.ResponseWriter, r *http.Request) {
	var in struct {
		App     string `json:"app"`
		Feature string `json:"feature"`
		Kind    string `json:"kind"`
		Action  string `json:"action"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 2048)
	if decodeJSON(w, r, &in) != nil || !usageFeature.MatchString(in.Feature) || (in.App != "ops" && in.App != "portal") ||
		(in.Kind != "page" && in.Kind != "action") || (in.Kind == "page" && in.Action != "view") ||
		(in.Kind == "action" && in.Action != "POST" && in.Action != "PATCH" && in.Action != "PUT" && in.Action != "DELETE") {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	ident, _ := auth.FromContext(r.Context())
	if err := s.db.RecordUsage(r.Context(), ident.Username, in.App, in.Feature, in.Kind, in.Action); err != nil {
		s.analyticsError(w, r, err)
		return
	}
	writeJSON(w, http.StatusNoContent, nil)
}

func (s *Server) analyticsError(w http.ResponseWriter, r *http.Request, err error) {
	var pg *pgconn.PgError
	if errors.As(err, &pg) {
		if pg.Code == "42501" {
			writeError(w, r, http.StatusForbidden, CodeForbidden)
			return
		}
		if pg.Code == "22023" {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
	}
	writeInternal(w, r, s.log, err)
}
