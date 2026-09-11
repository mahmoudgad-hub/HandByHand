package http

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/handbyhand/hbh/api/internal/store"
)

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	profile, err := s.db.Profile(r.Context(), ident.Username)
	if err != nil {
		// A resolved session whose user row is invisible means the account
		// was deactivated between the two statements. Unauthenticated is the
		// honest answer, not 500.
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, r, http.StatusUnauthorized, CodeUnauthenticated)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, profile)
}

type childrenOut struct {
	Children []domain.Child `json:"children"`

	// Paging, so a screen can say "page 1 of 4" instead of guessing. Total
	// is the count BEFORE the page is cut.
	Total  int `json:"total"`
	Limit  int `json:"limit"`
	Offset int `json:"offset"`
}

// handleChildren serves one list to two audiences.
//
// A guardian gets their own children; a staff member holding CHILD.VIEW_ALL
// gets the centre's. Nothing here branches on which - the policy on
// hbh.children decides, and a second endpoint for the operations console
// would be a second place for that rule to live.
//
// Archived records are excluded unless asked for. That is not cosmetic: while
// this list ignored active_flg, archiving a child changed nothing a screen
// could see, and the console reasonably concluded the archive had failed.
func (s *Server) handleChildren(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := r.URL.Query()

	query := store.ChildQuery{
		Q:        strings.TrimSpace(q.Get("q")),
		Status:   strings.TrimSpace(q.Get("status")),
		Archived: q.Get("archived") == "true",
		Limit:    defaultLimit,
	}

	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > maxLimit {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"limit": "1.." + strconv.Itoa(maxLimit)})
			return
		}
		query.Limit = n
	}
	// page is 1-based because that is what a screen shows. Offset is derived
	// so the client never has to do the arithmetic and get it off by one.
	if raw := q.Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"page": "1.."})
			return
		}
		query.Offset = (n - 1) * query.Limit
	}

	if raw := q.Get("guardian_id"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation, map[string]any{"guardian_id": "positive integer required"})
			return
		}
		query.GuardianID = n
	}
	children, total, err := s.db.Children(r.Context(), ident.Username, query)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, childrenOut{
		Children: children, Total: total, Limit: query.Limit, Offset: query.Offset,
	})
}

// handleChild is the endpoint the security gate exists for.
//
// A guardian who edits the identifier in the URL reaches this handler exactly
// as they would for their own child. Nothing here compares anything: the
// policy on hbh.children calls hbh.can_access_child(), the row is not returned,
// and the handler sees the same "no rows" it would see for a child that never
// existed. That sameness is the point - a 403 here would confirm that some
// other family's child exists, and identifiers are easy to walk.
func (s *Server) handleChild(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	childID, err := strconv.Atoi(r.PathValue("child_id"))
	if err != nil || childID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	child, err := s.db.Child(r.Context(), ident.Username, childID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			// A refusal is an event. This is the record that shows one
			// account reaching for a child that is not theirs - the only
			// place that attempt is visible at all, since the query itself
			// looked entirely ordinary.
			s.audit.Record(r.Context(), audit.Event{
				Action:   audit.ActionDeny,
				Actor:    ident.Username,
				CenterID: &ident.CenterID,
				Detail:   "CHILD_NOT_VISIBLE child_id=" + strconv.Itoa(childID),
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	// A child's profile is a sensitive read, and a trigger cannot see a
	// SELECT. It is recorded here or it is not recorded at all.
	s.audit.Record(r.Context(), audit.Event{
		Action:   audit.ActionRead,
		Actor:    ident.Username,
		CenterID: &ident.CenterID,
		Detail:   "CHILD_PROFILE child_id=" + strconv.Itoa(childID),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, child)
}

// handleChildGuardians answers with the people responsible for a child.
//
// It closes two screens at once: the child's file, which showed the field
// as unavailable, and the printed identity card, whose back carries two
// emergency numbers. The card is the reason the ORDER matters - a number
// taken from an unordered read is a number that may belong to another
// family, on a card nobody can check.
func (s *Server) handleChildGuardians(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "child_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	rows, err := s.db.ChildGuardians(r.Context(), ident.Username, id)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}
	// A household's names and telephone numbers. Read-sensitive, so the
	// read is recorded - triggers do not catch reads.
	s.recordOpsRead(r, "CHILD_GUARDIANS")
	writeJSON(w, http.StatusOK, map[string]any{"guardians": rows, "total": len(rows)})
}

// handleChildProfile answers the whole child screen in one request.
//
// The six single-purpose endpoints it replaces are still there and still
// work; this one exists because the screen wanted all of them at once, and
// six requests over a phone connection cost six round trips - which on the
// measured tunnel is most of a second before the database has done anything.
//
// The audit line says CHILD_PROFILE_FULL rather than reusing CHILD_PROFILE,
// so the record still distinguishes "opened the screen" from "read the child
// record alone". A sensitive read that cannot be told apart from another one
// is a weaker record than it looks.
func (s *Server) handleChildProfile(w http.ResponseWriter, r *http.Request) {
	win, ok := window(r)
	if !ok {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"from": "RFC3339", "to": "RFC3339", "limit": "1.." + strconv.Itoa(maxLimit)})
		return
	}
	s.childRead(w, r, "CHILD_PROFILE_FULL", func(ctx context.Context, ident string, childID int) (any, error) {
		return s.db.ChildProfile(ctx, ident, childID, win)
	})
}

// handleGuardianContact reads the two fields a parent owns.
//
// A 404 when the signed-in account has no guardian record - a staff member
// asking this question has no answer, and inventing an empty one would read
// as "you have no email on file".
func (s *Server) handleGuardianContact(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	out, err := s.db.GuardianContactOf(r.Context(), ident.Username)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

// handleSetGuardianContact changes them.
//
// BOTH FIELDS ARE ALWAYS SENT, and an empty one clears the column. The
// alternative - "absent means leave it" - gives a parent a way to add an
// address and no way to remove one, which is the wrong default for a field
// somebody may want gone.
//
// The email SHAPE is checked here because that is where every other format
// check in this service lives; whether a parent may write the field at all
// is decided in hbh.update_own_guardian_contact, which is the only path to
// the column.
func (s *Server) handleSetGuardianContact(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in struct {
		Email string `json:"email"`
		City  string `json:"city"`
	}
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	in.Email = strings.TrimSpace(in.Email)
	in.City = strings.TrimSpace(in.City)

	// Deliberately loose: one @, something either side, no spaces, and a
	// length ceiling. A stricter pattern rejects addresses that work - the
	// cost of a wrong refusal here is a parent who cannot save their own
	// email, and the cost of a wrong acceptance is mail that bounces.
	if in.Email != "" && !plausibleEmail(in.Email) {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "email"})
		return
	}
	if len(in.City) > 120 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "city"})
		return
	}

	out, err := s.db.SetGuardianContact(r.Context(), ident.Username, in.Email, in.City)
	if err != nil {
		s.opsError(w, r, "GUARDIAN_CONTACT", err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func plausibleEmail(s string) bool {
	if len(s) > 254 || strings.ContainsAny(s, " \t\r\n") {
		return false
	}
	at := strings.IndexByte(s, '@')
	return at > 0 && at == strings.LastIndexByte(s, '@') &&
		at < len(s)-1 && strings.Contains(s[at+1:], ".")
}
