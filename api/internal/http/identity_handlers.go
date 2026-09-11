package http

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

// Users, roles and permissions.
//
// This is the surface through which every other permission in the system
// is handed out, so it is worth saying what this file does NOT do: it
// checks nothing. USER.MANAGE, the centre pin, the refusal to let an
// account change its own roles, the stamp on a grant - all of it is in
// migration 0036, in PL/pgSQL, in one place. A check written here as
// well would be a second answer to "may you", and the weaker one would
// decide.

func (s *Server) handleUsers(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := r.URL.Query()
	uq := store.UserQuery{
		Q:        strings.TrimSpace(q.Get("q")),
		Status:   strings.TrimSpace(q.Get("status")),
		Role:     strings.TrimSpace(q.Get("role")),
		Archived: q.Get("archived") == "true",
		Limit:    defaultLimit,
	}
	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > maxLimit {
			badQuery(w, r, errBadLimit)
			return
		}
		uq.Limit = n
	}
	if raw := q.Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			badQuery(w, r, errBadPage)
			return
		}
		uq.Offset = (n - 1) * uq.Limit
	}

	rows, total, err := s.db.Users(r.Context(), ident.Username, uq)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	// Who works here and what each of them may do. Sensitive enough to
	// record the read: triggers do not catch reads.
	s.recordOpsRead(r, "USERS")
	writeJSON(w, http.StatusOK, page("users", rows, total, uq.Limit, uq.Offset))
}

func (s *Server) handleRoles(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.Roles(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"roles": rows, "total": len(rows)})
}

func (s *Server) handlePermissions(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.Permissions(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"permissions": rows, "total": len(rows)})
}

func (s *Server) handleCreateUser(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in store.NewUser
	if err := decodeJSON(w, r, &in); err != nil ||
		strings.TrimSpace(in.Username) == "" || strings.TrimSpace(in.FullNameAr) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "username|full_name_ar"})
		return
	}
	if in.UserType != "STAFF" && in.UserType != "THERAPIST" && in.UserType != "GUARDIAN" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"user_type": "STAFF|THERAPIST|GUARDIAN"})
		return
	}
	id, err := s.db.CreateUser(r.Context(), ident.Username, in)
	if err != nil {
		s.opsError(w, r, "CREATE_USER", err)
		return
	}
	// The account exists and cannot yet be signed into. Saying so is not
	// decoration: a screen that showed nothing here would leave somebody
	// waiting for a password that was never going to arrive.
	writeJSON(w, http.StatusCreated, map[string]any{
		"user_id": id, "has_password": false,
	})
}

func (s *Server) handleUpdateUser(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.UserEdit
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := s.db.UpdateUser(r.Context(), ident.Username, id, in); err != nil {
		s.opsError(w, r, "UPDATE_USER", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleArchiveUser(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	restore := r.URL.Query().Get("restore") == "true"
	if err := s.db.ArchiveUser(r.Context(), ident.Username, id, restore); err != nil {
		s.opsError(w, r, "ARCHIVE_USER", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleSetUserRoles replaces somebody's whole set of roles.
//
// PUT and not POST, and a complete list and not a delta. The screen
// shows a final state; a half-applied change leaves an account holding a
// combination nobody chose, and on this table that combination is
// somebody's access to a centre's clinical records.
func (s *Server) handleSetUserRoles(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		RoleCodes []string `json:"role_codes"`
	}
	if err := decodeJSON(w, r, &in); err != nil || in.RoleCodes == nil {
		// An empty ARRAY means "no roles" and is accepted; a MISSING
		// field means the screen forgot to send them, and stripping
		// somebody's access because a key was absent is the one mistake
		// this endpoint must not make quietly.
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "role_codes"})
		return
	}
	if err := s.db.SetUserRoles(r.Context(), ident.Username, id, in.RoleCodes); err != nil {
		s.opsError(w, r, "SET_USER_ROLES", err)
		return
	}
	// NO ATTEMPT RECORD HERE, and that is deliberate rather than an
	// omission. hbh.audit_attempt takes LOGIN, DENY or READ, and a
	// successful grant is none of the three - filing it under one of
	// them would put a wrong word on the row somebody reads when they
	// are trying to find out what happened.
	//
	// The grant is recorded where a CHANGE belongs (D-1): inside the
	// transaction, by hbh.user_roles.granted_by and granted_at, which
	// roll back with it if it fails. That is the record that answers
	// "who gave this person billing access, and when".
	w.WriteHeader(http.StatusNoContent)
}

// PUT /api/v1/roles/{code}/permissions - what a role may do.
//
// The most consequential write this service exposes, and not because of
// what it touches: editing a role changes it for EVERY person holding it,
// at once. Moving one person between roles affects one person; this
// affects a group whose size the caller may not have in mind.
//
// The screen is expected to say who is affected before it calls this. It
// is not this handler's job to refuse a change on that basis - a manager
// widening reception's access deliberately is doing something ordinary -
// but it IS the database's job to refuse the one change that cannot be
// undone from inside the product, and a deferred constraint trigger does
// exactly that. See migration 0064.
func (s *Server) handleSetRolePermissions(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	code := r.PathValue("code")
	if code == "" {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		PermissionCodes []string `json:"permission_codes"`
	}
	// A MISSING field is refused, an empty ARRAY is accepted. "This role
	// grants nothing" is a real instruction; "the screen forgot to send
	// them" must never be executed as one.
	if err := decodeJSON(w, r, &in); err != nil || in.PermissionCodes == nil {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "permission_codes"})
		return
	}
	if err := s.db.SetRolePermissions(r.Context(), ident.Username, code, in.PermissionCodes); err != nil {
		s.opsError(w, r, "SET_ROLE_PERMISSIONS", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// POST /api/v1/users/{user_id}/password-setup
//
// Mints a single-use code for somebody to set their OWN password with.
//
// THE CODE COMES BACK ONCE. There is no endpoint that reads it again and
// no column that holds it in the clear; an administrator who loses it
// issues another, which cancels the first. That is deliberate: a code
// that can be looked up later is a standing credential, and a table of
// them is a table of temporary passwords.
//
// It is NOT a password. The administrator hands the code over, the
// person chooses their own password with it, and the code stops working.
// Nobody but that person ever knows what they chose - which is the whole
// reason this exists rather than a "set password" field.
func (s *Server) handleIssuePasswordSetup(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	token, err := s.db.IssuePasswordSetup(r.Context(), ident.Username, id)
	if err != nil {
		s.opsError(w, r, "ISSUE_PASSWORD_SETUP", err)
		return
	}
	// Recorded as a change of standing, because it is one: from this
	// moment somebody can take over that account with the code.
	s.log.Info("password setup issued", "actor", ident.Username, "for", id)
	writeJSON(w, http.StatusCreated, map[string]any{"setup_code": token})
}

// POST /api/v1/auth/password-setup
//
// UNAUTHENTICATED, and it has to be: the person has no way in yet. The
// code is the authorisation, which is why it is single use, expiring and
// counted - and why this route is rate limited like the login endpoints.
func (s *Server) handleRedeemPasswordSetup(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Username string `json:"username"`
		Code     string `json:"setup_code"`
		Password string `json:"password"`
	}
	if err := decodeJSON(w, r, &in); err != nil ||
		strings.TrimSpace(in.Username) == "" || in.Code == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "username|setup_code"})
		return
	}

	outcome, err := s.db.RedeemPasswordSetup(r.Context(),
		strings.TrimSpace(in.Username), in.Code, in.Password)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	switch outcome {
	case "OK":
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionLogin, Actor: strings.TrimSpace(in.Username),
			Detail: "PASSWORD_SET", ClientIP: s.clientIP(r),
		})
		w.WriteHeader(http.StatusNoContent)
	case "TOO_SHORT":
		// Its own answer. The code was right; saying it was invalid would
		// send somebody back for a new code when the one they have works.
		writeError(w, r, http.StatusBadRequest, "PASSWORD_TOO_SHORT")
	default:
		// One answer for no such account, no live code, an expired one and
		// a wrong one. Telling them apart would make this a way to find
		// out which accounts are waiting to be set up.
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Actor: strings.TrimSpace(in.Username),
			Detail: "PASSWORD_SETUP_REFUSED", ClientIP: s.clientIP(r),
		})
		writeError(w, r, http.StatusUnauthorized, "SETUP_CODE_INVALID")
	}
}

// POST /api/v1/auth/password
//
// Changing your own password. Authenticated, and it still asks for the
// current one: a session is not proof of identity here, because an
// unlocked terminal is somebody else's session and a password change with
// no confirmation is how a borrowed screen becomes a taken account.
//
// No user id anywhere in it. The database resolves the caller itself, so
// there is no shape of this request that reaches another account.
func (s *Server) handleChangeOwnPassword(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in struct {
		Current string `json:"current_password"`
		Next    string `json:"new_password"`
	}
	if err := decodeJSON(w, r, &in); err != nil || in.Current == "" || in.Next == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "current_password|new_password"})
		return
	}

	outcome, err := s.db.ChangeOwnPassword(r.Context(), ident.Username, in.Current, in.Next)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	// Each outcome sends a person somewhere different, so each keeps its
	// own code. Flattening them into "refused" would leave somebody who
	// mistyped their NEW password looking for a mistake in their old one.
	switch outcome {
	case "OK":
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionLogin, Actor: ident.Username, CenterID: &ident.CenterID,
			Detail: "PASSWORD_CHANGED", ClientIP: s.clientIP(r),
		})
		w.WriteHeader(http.StatusNoContent)
	case "TOO_SHORT":
		writeError(w, r, http.StatusBadRequest, "PASSWORD_TOO_SHORT")
	case "UNCHANGED":
		writeError(w, r, http.StatusBadRequest, "PASSWORD_UNCHANGED")
	case "TEMPORARILY_LOCKED", "USER_LOCKED":
		writeError(w, r, http.StatusForbidden, "ACCOUNT_LOCKED")
	case "NOT_PASSWORD_USER":
		writeError(w, r, http.StatusForbidden, CodeForbidden)
	default:
		// The current password was wrong. Recorded, because a run of these
		// on a signed-in session is worth being able to see afterwards.
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
			Detail: "PASSWORD_CHANGE_REFUSED", ClientIP: s.clientIP(r),
		})
		writeError(w, r, http.StatusUnauthorized, "BAD_CURRENT_PASSWORD")
	}
}
