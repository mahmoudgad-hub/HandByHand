package http

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/config"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The operations app: create, read, update and archive, over the resources
// declared in store/crud.go.
//
// There is no permission check anywhere in this file, and that is the design.
// Every statement runs as hbh_app under the policies from migration 0012, so
// a create without CATALOG.MANAGE is refused by the engine. A second check
// here would be a second copy of the rule, and the day the copies disagreed
// the weaker one would decide.
//
// What this file does own is the MAPPING: which database refusal becomes which
// status code, and what gets written to the audit trail.

// registerCRUD wires five routes per resource.
//
// DELETE is an archive, not a delete. See store.SoftDelete: there is no DELETE
// grant on any table in this schema, so the verb describes what the screen
// means rather than what the database does.
func (s *Server) registerCRUD(rt *router) {
	for _, res := range store.Resources() {
		r := res // captured by the closures below
		base := "/api/v1/" + r.Name
		one := base + "/{" + r.Param + "}"

		// children already has GET on both paths from the portal, and the
		// portal's answer is the right one for a guardian. Only the write
		// verbs are added here.
		if r.Name != "children" {
			rt.route(http.MethodGet, base, s.requireAuth(s.crudList(r)))
			rt.route(http.MethodGet, one, s.requireAuth(s.crudGet(r)))
		}
		rt.route(http.MethodPost, base, s.requireAuth(s.crudCreate(r)))
		rt.route(http.MethodPatch, one, s.requireAuth(s.crudUpdate(r)))
		rt.route(http.MethodDelete, one, s.requireAuth(s.crudArchive(r)))
		rt.route(http.MethodPost, one+"/restore", s.requireAuth(s.crudRestore(r)))
	}
}

func (s *Server) crudList(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())

		// PARSED WITH THE ERROR READ, because req.URL.Query() throws it away.
		//
		// Since Go 1.17 a ';' in a query string is a parse error, and Query()
		// answers with the parameters it managed to read and no sign that it
		// dropped the rest. A term containing a semicolon therefore arrived
		// as NO TERM AT ALL - and the reply was the entire table, which is
		// the exact failure this batch exists to remove, wearing a 200.
		// `archived` disappeared with it, so a malformed query could also
		// silently widen what was asked for.
		//
		// Found by searching for "'); DROP TABLE hbh.guardians; --": nothing
		// was injected - the term is a bound parameter and never reaches the
		// parser - but all six guardians came back, and a search that answers
		// "everything" to a hostile string is a bug whatever the cause.
		query, err := url.ParseQuery(req.URL.RawQuery)
		if err != nil {
			badQuery(w, req, errBadQueryString)
			return
		}

		// Active or everything. This is a DISPLAY choice, not an access rule:
		// the policy decides whether the caller may see an archived row at
		// all, and this only decides whether to ask for them.
		opts := store.ListOptions{
			Archived: query.Get("archived") == "true",
			Q:        strings.TrimSpace(query.Get("q")),
			Limit:    defaultLimit,
		}

		// A TERM ON A RESOURCE THAT CANNOT MATCH IT IS A REFUSAL.
		//
		// It used to be silently dropped - along with every other term,
		// on every resource - so a receptionist typing a name got the
		// whole table back and no sign that the box did nothing. Ignoring
		// a parameter you do not implement is how that survived.
		if opts.Q != "" && !r.Searchable() {
			badQuery(w, req, errNoSearch)
			return
		}

		// Same convention as the centre-indexed reads: `limit` bounded by
		// maxLimit, `page` 1-based. Written once there and read once here
		// rather than invented again - a console that pages one screen with
		// `page` and another with `offset` is a console nobody can script.
		if raw := query.Get("limit"); raw != "" {
			n, err := strconv.Atoi(raw)
			if err != nil || n <= 0 || n > maxLimit {
				badQuery(w, req, errBadLimit)
				return
			}
			opts.Limit = n
		}
		if raw := query.Get("page"); raw != "" {
			n, err := strconv.Atoi(raw)
			if err != nil || n < 1 {
				badQuery(w, req, errBadPage)
				return
			}
			opts.Offset = (n - 1) * opts.Limit
		}

		rows, total, err := s.db.List(req.Context(), ident.Username, r, opts)
		if err != nil {
			writeInternal(w, req, s.log, err)
			return
		}
		s.recordRead(req, r, "LIST")
		// The named array keeps its key, so every existing consumer reads
		// the same field it always did; total, limit and offset are added
		// beside it. The console's OpsApi.list already looked for all three
		// and fell back to the row count when they were missing.
		writeJSON(w, http.StatusOK, page(r.Name, rows, total, opts.Limit, opts.Offset))
	})
}

func (s *Server) crudGet(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())
		id, ok := pathID(req, r.Param)
		if !ok {
			writeError(w, req, http.StatusNotFound, CodeNotFound)
			return
		}
		row, err := s.db.Get(req.Context(), ident.Username, r, id)
		if err != nil {
			s.crudError(w, req, r, id, err)
			return
		}
		s.recordRead(req, r, "GET "+strconv.Itoa(id))
		writeJSON(w, http.StatusOK, row)
	})
}

func (s *Server) crudCreate(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())
		body, ok := decodeBody(w, req)
		if !ok {
			writeError(w, req, http.StatusBadRequest, CodeValidation)
			return
		}
		row, err := s.db.Create(req.Context(), ident.Username, r, body)
		if err != nil {
			s.crudError(w, req, r, 0, err)
			return
		}
		// No audit call on success: the change is recorded by hbh.trg_audit
		// inside the transaction that made it, which is where a change record
		// belongs (D-1).
		writeJSON(w, http.StatusCreated, row)
	})
}

func (s *Server) crudUpdate(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())
		id, ok := pathID(req, r.Param)
		if !ok {
			writeError(w, req, http.StatusNotFound, CodeNotFound)
			return
		}
		body, ok := decodeBody(w, req)
		if !ok {
			writeError(w, req, http.StatusBadRequest, CodeValidation)
			return
		}
		row, err := s.db.Update(req.Context(), ident.Username, r, id, body)
		if err != nil {
			s.crudError(w, req, r, id, err)
			return
		}
		writeJSON(w, http.StatusOK, row)
	})
}

func (s *Server) crudArchive(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())
		id, ok := pathID(req, r.Param)
		if !ok {
			writeError(w, req, http.StatusNotFound, CodeNotFound)
			return
		}
		if err := s.db.SoftDelete(req.Context(), ident.Username, r, id); err != nil {
			s.crudError(w, req, r, id, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
}

func (s *Server) crudRestore(r store.Resource) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		ident, _ := auth.FromContext(req.Context())
		id, ok := pathID(req, r.Param)
		if !ok {
			writeError(w, req, http.StatusNotFound, CodeNotFound)
			return
		}
		if err := s.db.Restore(req.Context(), ident.Username, r, id); err != nil {
			s.crudError(w, req, r, id, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
}

// crudError maps one database outcome to one status code.
//
// The important line is the last one. A refusal this layer does not recognise
// becomes a 500 with the cause in the log - never a polite 400 - because
// inventing a friendly answer for a rule the code does not understand is how a
// real defect gets served as a shrug.
func (s *Server) crudError(w http.ResponseWriter, req *http.Request, r store.Resource, id int, err error) {
	ident, _ := auth.FromContext(req.Context())

	var unknown store.ErrUnknownColumn
	switch {
	case errors.As(err, &unknown):
		writeErrorFields(w, req, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": unknown.Key})

	case errors.Is(err, store.ErrNotFound):
		// Also the answer when the policy refused the write: the UPDATE
		// matched zero rows. "Not found" and "not permitted" are one answer
		// here as everywhere, so identifiers cannot be walked.
		s.audit.Record(req.Context(), audit.Event{
			Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
			Detail:   "NOT_VISIBLE " + r.Name + "=" + strconv.Itoa(id),
			ClientIP: s.clientIP(req),
		})
		writeError(w, req, http.StatusNotFound, CodeNotFound)

	default:
		switch store.Code(err) {
		case pgWriteRefused:
			// The engine refused the write. The caller may be able to READ
			// this resource and not to change it, so this is an honest 403 -
			// it confirms nothing that a list did not already show.
			// Logged as well as recorded: a refusal by the engine is the
			// answer to "which policy said no", and without the cause in
			// the log that question can only be answered by guessing.
			s.log.WarnContext(req.Context(), "the engine refused a write",
				"resource", r.Name, "actor", ident.Username, "err", err)
			s.audit.Record(req.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail:   "WRITE_REFUSED " + r.Name,
				ClientIP: s.clientIP(req),
			})
			writeError(w, req, http.StatusForbidden, CodeForbidden)

		case store.ErrMobileFormat, store.ErrNationalIDFormat, store.ErrMobileCountry:
			// A rule about a named field, so the answer names the field.
			//
			// docs/02-api-contract.md has always allowed `fields.field`
			// beside `fields.constraint`, and the console has always read
			// both - `readRefusal` lifts `field` and `refusal-screen` lights
			// that box. Nothing on this path ever SET it, so every refusal
			// arrived as a bare constraint and the form had no box to point
			// at. These two rules know which value they mean, so they say so.
			//
			// Naming a field is not naming a constraint: `mobile` is the
			// word already printed above the input, where `ck_guardians_
			// mobile` would be a schema disclosure. The value itself never
			// appears - it is a mobile number, and this line reaches a log.
			field := "mobile"
			if store.Code(err) == store.ErrNationalIDFormat {
				field = "national_id"
			}

			// AND THE RULE ITSELF, when the rule is a number.
			//
			// "The value is not in the accepted format" names the field and
			// stops there, which leaves the reader to guess what the format
			// IS. The centre owner met this on the staff card with a national
			// id one digit short: correct refusal, and nothing on the screen
			// said fourteen. So the length travels with the refusal - it is
			// the rule, not the value, and it is the only place that knows
			// it, since sys_params may override it per centre and no screen
			// may read that table.
			//
			// Mobile gets no equivalent: MOBILE_PATTERN is a regular
			// expression, and printing one at somebody filling in a form
			// explains nothing and discloses the shape of the check.
			//
			// Unreadable parameter, absent key. A guessed 14 here would be
			// the business value in code that this whole rule exists to keep
			// out - and it would read as authoritative.
			fields := map[string]any{"field": field, "constraint": "FORMAT"}
			if field == "national_id" {
				if want, perr := s.params.GetForCenter(
					req.Context(), ident.CenterID, "NATIONAL_ID_LENGTH", "",
				); perr == nil && want != "" {
					if n, cerr := strconv.Atoi(want); cerr == nil {
						fields["expected_length"] = n
					}
				}
			}

			s.log.WarnContext(req.Context(), "a write was refused by an identity format rule",
				"resource", r.Name, "field", field)
			writeErrorFields(w, req, http.StatusBadRequest, CodeValidation, fields)

		case store.ErrCheckViolation, store.ErrForeignKeyViolation, pgUniqueViolation,
			pgNotNullViolation, pgInvalidText, pgInvalidDatetime, pgNumericValue,
			pgStringTooLong:
			// A well-formed body the schema will not take: a duplicate code, a
			// missing required column, a date that is not a date. The caller's
			// mistake, so 400 - and the constraint name goes to the log only,
			// because it is a schema detail.
			s.log.WarnContext(req.Context(), "a write was refused by the schema",
				"resource", r.Name, "err", err)
			writeErrorFields(w, req, http.StatusBadRequest, CodeValidation,
				map[string]any{"constraint": constraintCode(store.Code(err))})

		default:
			writeInternal(w, req, s.log, err)
		}
	}
}

// SQLSTATEs that mean "the caller sent something the schema will not take", or
// "the engine refused this write". None of them is a fault in this service.
const (
	// One code covers both "permission denied for table" and "new row
	// violates row-level security policy". They are the same answer here:
	// the engine refused the write.
	pgWriteRefused     = "42501"
	pgUniqueViolation  = "23505"
	pgNotNullViolation = "23502"
	pgInvalidText      = "22P02"
	pgInvalidDatetime  = "22007"
	pgNumericValue     = "22003"
	// A value longer than its column. Seen on hbh.centers.country_code,
	// which is character(2): "EGY" is refused by the TYPE before the CHECK
	// constraint is ever reached, so it arrives with no constraint name and
	// used to fall through to a 500. It is the caller's mistake like the
	// rest of this list - and it can happen on any text column in the
	// schema, not only that one.
	pgStringTooLong = "22001"
)

// constraintCode names the KIND of refusal for the client, without naming the
// constraint. "there is already one of those" is actionable; "uq_services_code"
// is a schema disclosure.
func constraintCode(sqlstate string) string {
	switch sqlstate {
	case pgUniqueViolation:
		return "DUPLICATE"
	case pgNotNullViolation:
		return "REQUIRED"
	case store.ErrForeignKeyViolation:
		return "NO_SUCH_REFERENCE"
	case pgInvalidText, pgInvalidDatetime, pgNumericValue, pgStringTooLong:
		return "FORMAT"
	default:
		return "REFUSED"
	}
}

// recordRead writes the READ line. A trigger cannot see a SELECT, so an
// operations screen listing a centre's children is recorded here or nowhere.
func (s *Server) recordRead(req *http.Request, r store.Resource, what string) {
	ident, _ := auth.FromContext(req.Context())
	s.audit.Record(req.Context(), audit.Event{
		Action: audit.ActionRead, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail:   r.Name + " " + what,
		ClientIP: s.clientIP(req),
	})
}

func pathID(req *http.Request, param string) (int, bool) {
	id, err := strconv.Atoi(req.PathValue(param))
	return id, err == nil && id > 0
}

// decodeBody reads a bounded JSON object with numbers kept as text.
//
// UseNumber matters: JSON has one number type and it is a float. Decoding 14
// into a float64 and handing it to an integer column is a conversion this code
// would have to guess at, so the digits travel as text and the column decides.
func decodeBody(w http.ResponseWriter, req *http.Request) (map[string]any, bool) {
	if ct := req.Header.Get("Content-Type"); ct != "" {
		if mt := strings.TrimSpace(strings.Split(ct, ";")[0]); mt != "application/json" {
			return nil, false
		}
	}
	raw, err := io.ReadAll(http.MaxBytesReader(w, req.Body, config.MaxRequestBody))
	if err != nil {
		return nil, false
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()

	var body map[string]any
	if err := dec.Decode(&body); err != nil || body == nil {
		return nil, false
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return nil, false
	}
	return body, true
}
