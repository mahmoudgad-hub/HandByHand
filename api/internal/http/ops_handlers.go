package http

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The centre-indexed endpoints: five reads a day is opened from, and the
// writes that make those screens do something.
//
// No permission check lives in this file. Every call runs as hbh_app under the
// policies, and the PL/pgSQL functions check the narrower rules from inside -
// who may close a session, whether a slot is free, whether an invoice may take
// a payment. This layer maps a database answer to a status code and records
// what happened.

// opsQuery reads the filters the five lists share.
//
// The day window is resolved in the CENTRE's time zone, taken from the centre
// row. "Today" for a screen in Cairo is not "today" in UTC, and which one is
// meant is a property of the centre rather than of this code - so a second
// centre in another country changes a row, not a release.
func (s *Server) opsQuery(r *http.Request, ident string, wantWindow bool) (store.OpsQuery, error) {
	q := r.URL.Query()
	out := store.OpsQuery{
		Status: strings.TrimSpace(q.Get("status")),
		Kind:   strings.TrimSpace(q.Get("kind")),
		Limit:  defaultLimit,
	}

	if raw := q.Get("limit"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 || n > maxLimit {
			return out, errBadLimit
		}
		out.Limit = n
	}
	if raw := q.Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 {
			return out, errBadPage
		}
		out.Offset = (n - 1) * out.Limit
	}
	for _, p := range []struct {
		name string
		dst  **int
	}{{"therapist_id", &out.TherapistID}, {"room_id", &out.RoomID}, {"service_id", &out.ServiceID}, {"child_id", &out.ChildID}} {
		raw := q.Get(p.name)
		if raw == "" {
			continue
		}
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			return out, errBadFilter
		}
		v := n
		*p.dst = &v
	}

	// mine=1 - "this is MY day", answered from the session.
	//
	// It OVERRIDES therapist_id rather than combining with it. Two filters
	// naming different therapists have no sensible intersection, and the
	// weaker of two answers to the same question is the one that would
	// eventually decide - the shape rule 4 of this project exists to
	// refuse. The store resolves the therapist itself; nothing the caller
	// sends can name somebody else.
	if raw := strings.TrimSpace(q.Get("mine")); raw != "" {
		if raw != "1" && raw != "true" {
			return out, errBadFilter
		}
		out.MineOnly = true
		out.TherapistID = nil
	}

	if !wantWindow {
		// Reports and invoices filter by DAY, not by instant, so an empty
		// bound means "no bound" rather than "today". A screen listing
		// invoices does not open on one day the way a diary does.
		if raw := q.Get("from"); raw != "" {
			t, err := time.Parse("2006-01-02", raw)
			if err != nil {
				return out, errBadDate
			}
			out.Window.From = t
		}
		if raw := q.Get("to"); raw != "" {
			t, err := time.Parse("2006-01-02", raw)
			if err != nil {
				return out, errBadDate
			}
			out.Window.To = t
		}
		return out, nil
	}

	tzName, err := s.db.CenterTimeZone(r.Context(), ident)
	if err != nil {
		return out, err
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		return out, err
	}

	// An explicit instant pair wins. It is the precise form, and a client that
	// knows its own zone can always express exactly what it wants.
	from, hasFrom := q.Get("from"), q.Get("from") != ""
	to, hasTo := q.Get("to"), q.Get("to") != ""
	if hasFrom || hasTo {
		if hasFrom {
			t, err := time.Parse(time.RFC3339, from)
			if err != nil {
				return out, errBadInstant
			}
			out.Window.From = t
		}
		if hasTo {
			t, err := time.Parse(time.RFC3339, to)
			if err != nil {
				return out, errBadInstant
			}
			out.Window.To = t
		}
		if out.Window.From.IsZero() {
			out.Window.From = time.Unix(0, 0)
		}
		if out.Window.To.IsZero() {
			out.Window.To = time.Now().AddDate(100, 0, 0)
		}
		return out, nil
	}

	// Otherwise one calendar day in the centre's zone: the given date, or
	// today. The window is half-open so an appointment starting exactly at
	// midnight belongs to one day and not to two.
	day := time.Now().In(loc)
	if raw := q.Get("date"); raw != "" {
		t, err := time.ParseInLocation("2006-01-02", raw, loc)
		if err != nil {
			return out, errBadDate
		}
		day = t
	}
	start := time.Date(day.Year(), day.Month(), day.Day(), 0, 0, 0, 0, loc)
	out.Window.From = start
	out.Window.To = start.AddDate(0, 0, 1)
	return out, nil
}

var (
	errBadLimit   = errors.New("limit")
	errBadPage    = errors.New("page")
	errBadFilter  = errors.New("filter")
	errBadDate    = errors.New("date")
	errBadInstant = errors.New("instant")
	// A term was sent to a resource with no searchable columns. Named
	// rather than ignored: silently dropping `q` is the defect this
	// batch exists to remove, and dropping it on SOME resources would
	// leave a caller unable to tell a filter that matched nothing from
	// one that was never applied.
	errNoSearch = errors.New("q")
	// The query string itself would not parse - a raw ";" is the usual
	// cause. Named so the reply says which half of the request was wrong.
	errBadQueryString = errors.New("query")
)

// badQuery turns a filter complaint into a 400 that names the field.
func badQuery(w http.ResponseWriter, r *http.Request, err error) {
	field := map[error]string{
		errBadLimit:       "limit",
		errBadPage:        "page",
		errBadFilter:      "therapist_id|room_id|child_id",
		errBadDate:        "date (YYYY-MM-DD)",
		errBadInstant:     "from|to (RFC3339)",
		errNoSearch:       "q (this resource has no searchable fields)",
		errBadQueryString: "query string (a raw ';' must be percent-encoded)",
	}[err]
	if field == "" {
		field = "query"
	}
	writeErrorFields(w, r, http.StatusBadRequest, CodeValidation, map[string]any{"field": field})
}

func (s *Server) handleOpsAppointments(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q, err := s.opsQuery(r, ident.Username, true)
	if err != nil {
		if isQueryErr(err) {
			badQuery(w, r, err)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}
	rows, total, err := s.db.CentreAppointments(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, "APPOINTMENTS")
	writeJSON(w, http.StatusOK, page("appointments", rows, total, q.Limit, q.Offset))
}

func (s *Server) handleOpsSessions(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q, err := s.opsQuery(r, ident.Username, true)
	if err != nil {
		if isQueryErr(err) {
			badQuery(w, r, err)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}
	rows, total, err := s.db.OpsSessions(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, "SESSIONS")
	writeJSON(w, http.StatusOK, page("sessions", rows, total, q.Limit, q.Offset))
}

func (s *Server) handleOpsReports(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q, err := s.opsQuery(r, ident.Username, false)
	if err != nil {
		badQuery(w, r, err)
		return
	}
	rows, total, err := s.db.OpsReports(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, "REPORTS")
	writeJSON(w, http.StatusOK, page("reports", rows, total, q.Limit, q.Offset))
}

func (s *Server) handleOpsInvoices(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q, err := s.opsQuery(r, ident.Username, false)
	if err != nil {
		badQuery(w, r, err)
		return
	}
	rows, total, err := s.db.OpsInvoices(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, "INVOICES")
	writeJSON(w, http.StatusOK, page("invoices", rows, total, q.Limit, q.Offset))
}

func (s *Server) handleOpsRequests(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q, err := s.opsQuery(r, ident.Username, false)
	if err != nil {
		badQuery(w, r, err)
		return
	}
	rows, total, err := s.db.OpsRequests(r.Context(), ident.Username, q)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	s.recordOpsRead(r, "REQUESTS")
	writeJSON(w, http.StatusOK, page("requests", rows, total, q.Limit, q.Offset))
}

// =====================================================================
// WRITES
// =====================================================================

func (s *Server) handleValidateSlot(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in store.NewAppointment
	if err := decodeJSON(w, r, &in); err != nil || !validAppointment(in) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	// A refusal here is a 200 with ok:false, not an error status. The caller
	// asked a QUESTION and got an answer; nothing failed.
	check, err := s.db.ValidateSlot(r.Context(), ident.Username, in, nil)
	if err != nil {
		s.opsError(w, r, "VALIDATE_SLOT", err)
		return
	}
	writeJSON(w, http.StatusOK, check)
}

// handleAvailableSlots answers "which windows would be accepted", which is
// the question the booking screen actually has.
//
// The old screen could only ask the opposite one - propose an instant, get a
// refusal - so finding a gap in a busy therapist's day meant guessing at it
// eight times. Same rulebook either way: hbh.available_slots runs every
// candidate through hbh.validate_slot.
//
// The date is a DAY in the centre's zone, parsed the way every other diary
// read parses it. Sending an instant here is a 400 naming the field rather
// than a silent reinterpretation of somebody's midnight.
func (s *Server) handleAvailableSlots(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	q := r.URL.Query()

	therapistID, err1 := strconv.Atoi(q.Get("therapist_id"))
	serviceID, err2 := strconv.Atoi(q.Get("service_id"))
	if err1 != nil || err2 != nil || therapistID <= 0 || serviceID <= 0 {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	tzName, err := s.db.CenterTimeZone(r.Context(), ident.Username)
	if err != nil {
		s.opsError(w, r, "AVAILABLE_SLOTS", err)
		return
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		s.opsError(w, r, "AVAILABLE_SLOTS", err)
		return
	}
	day := time.Now().In(loc)
	if raw := q.Get("date"); raw != "" {
		t, err := time.ParseInLocation("2006-01-02", raw, loc)
		if err != nil {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
		day = t
	}

	// Optional: pin the search to one room. Absent, the function offers the
	// first free room per slot rather than the same hour once per room.
	var roomID *int
	if raw := q.Get("room_id"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
		roomID = &n
	}

	// Which kind of hour is being looked for. Absent means IN_PERSON, so
	// every caller written before consultations existed asks the question it
	// always asked and gets the answer it always got.
	mode := q.Get("delivery_mode")
	if !validDeliveryMode(mode) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	slots, err := s.db.AvailableSlots(
		r.Context(), ident.Username, therapistID, serviceID, day, roomID, mode)
	if err != nil {
		s.opsError(w, r, "AVAILABLE_SLOTS", err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"slots": slots,
		"date":  day.Format("2006-01-02"),
		"total": len(slots),
	})
}

func (s *Server) handleBookAppointment(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in store.NewAppointment
	if err := decodeJSON(w, r, &in); err != nil || !validAppointment(in) {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	id, err := s.db.BookAppointment(r.Context(), ident.Username, in)
	if err != nil {
		s.opsError(w, r, "BOOK_APPOINTMENT", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"appointment_id": id})
}

type statusIn struct {
	Status string `json:"status"`
	Reason string `json:"reason"`
}

func (s *Server) handleAppointmentStatus(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "appointment_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in statusIn
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.Status) == "" {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := s.db.SetAppointmentStatus(r.Context(), ident.Username, id, in.Status, in.Reason); err != nil {
		s.opsError(w, r, "APPOINTMENT_STATUS", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleStartSession(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "appointment_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	sessionID, err := s.db.StartSession(r.Context(), ident.Username, id)
	if err != nil {
		s.opsError(w, r, "START_SESSION", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"session_id": sessionID})
}

func (s *Server) handleCloseSession(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "session_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in statusIn
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.Status) == "" {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := s.db.CloseSession(r.Context(), ident.Username, id, in.Status, in.Reason); err != nil {
		s.opsError(w, r, "CLOSE_SESSION", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type noteIn struct {
	BodyAr string `json:"body_ar"`
}

func (s *Server) handleWriteNote(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "session_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in noteIn
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.BodyAr) == "" {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	noteID, err := s.db.WriteSessionNote(r.Context(), ident.Username, id, in.BodyAr)
	if err != nil {
		s.opsError(w, r, "WRITE_NOTE", err)
		return
	}
	// 201 and INTERNAL. The note exists; it has not reached the family, and
	// will not until somebody publishes it.
	writeJSON(w, http.StatusCreated, map[string]any{"note_id": noteID, "visibility": "INTERNAL"})
}

// handleCreateReport opens a DRAFT progress report for a child.
//
// The body names the child, the period and the title. It does NOT name the
// centre, the author, the report number or the status: the function derives
// all four, so a client that sent them would be ignored rather than obeyed.
// There is no therapist_id on this table - authorship is created_by, taken
// from the session - so there is nothing here to impersonate.
func (s *Server) handleCreateReport(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	var in store.NewReport
	if err := decodeJSON(w, r, &in); err != nil {
		return
	}
	if in.ChildID <= 0 || strings.TrimSpace(in.TitleAr) == "" ||
		in.PeriodStart == "" || in.PeriodEnd == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"required": "child_id, title_ar, period_start, period_end"})
		return
	}

	id, version, err := s.db.CreateReport(r.Context(), ident.Username, in)
	if err != nil {
		s.opsError(w, r, "CREATE_REPORT", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"report_id": id, "version": version})
}

// handleUpdateReport edits a draft. Every rule about who and when is in
// hbh.update_report; this reads a body and reports what the schema said.
func (s *Server) handleUpdateReport(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "report_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.ReportEdit
	if err := decodeJSON(w, r, &in); err != nil {
		return
	}
	version, err := s.db.UpdateReport(r.Context(), ident.Username, id, in)
	if err != nil {
		s.opsError(w, r, "UPDATE_REPORT", err)
		return
	}
	// 200 with the new version, not 204: the editor's next save names it.
	writeJSON(w, http.StatusOK, map[string]any{"version": version})
}

func (s *Server) handlePublishReport(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "report_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.PublishReport(r.Context(), ident.Username, id); err != nil {
		s.opsError(w, r, "PUBLISH_REPORT", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// consentBody is what both guardian-consent handlers accept. child_id is a
// pointer because the two consent shapes are different rows: one about the
// guardian, one about a named child, and hbh.grant_consent refuses the wrong
// shape for the type rather than guessing.
type consentBody struct {
	ConsentType string `json:"consent_type"`
	ChildID     *int   `json:"child_id"`
	TextVersion string `json:"text_version"`
	NoteAr      string `json:"note_ar"`
}

func (s *Server) handleGrantGuardianConsent(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "guardian_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in consentBody
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	in.ConsentType = strings.TrimSpace(in.ConsentType)
	if in.ConsentType == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"consent_type": "REQUIRED"})
		return
	}
	consentID, err := s.db.GrantGuardianConsent(r.Context(), ident.Username, id,
		in.ConsentType, in.ChildID, in.TextVersion, in.NoteAr)
	if err != nil {
		s.opsError(w, r, "GRANT_CONSENT", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"consent_id": consentID})
}

func (s *Server) handleWithdrawGuardianConsent(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "guardian_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in consentBody
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	in.ConsentType = strings.TrimSpace(in.ConsentType)
	if in.ConsentType == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"consent_type": "REQUIRED"})
		return
	}
	if err := s.db.WithdrawGuardianConsent(r.Context(), ident.Username, id,
		in.ConsentType, in.ChildID, in.NoteAr); err != nil {
		s.opsError(w, r, "WITHDRAW_CONSENT", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handlePublishSessionNote sends one clinical note to the family.
//
// It carries no rule of its own: hbh.publish_session_note checks NOTE.PUBLISH
// and refuses anyone else, so a condition here would be a second copy of that
// rule and the weaker of the two would decide (rule 4).
func (s *Server) handlePublishSessionNote(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "note_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.PublishSessionNote(r.Context(), ident.Username, id); err != nil {
		s.opsError(w, r, "PUBLISH_NOTE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleIssueInvoice(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "invoice_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.IssueInvoice(r.Context(), ident.Username, id); err != nil {
		s.opsError(w, r, "ISSUE_INVOICE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type paymentIn struct {
	// A decimal STRING, not a number. JSON has one number type and it is a
	// float; money is the one figure in this system that gets added up and
	// compared against a total (D-25).
	Amount     string `json:"amount"`
	MethodCode string `json:"method_code"`
	NoteAr     string `json:"note_ar"`
}

func (s *Server) handleAddPayment(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "invoice_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in paymentIn
	if err := decodeJSON(w, r, &in); err != nil ||
		strings.TrimSpace(in.Amount) == "" || strings.TrimSpace(in.MethodCode) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"amount": "DECIMAL_STRING", "method_code": "REQUIRED"})
		return
	}
	paymentID, err := s.db.AddPayment(r.Context(), ident.Username, id, in.Amount, in.MethodCode, in.NoteAr)
	if err != nil {
		s.opsError(w, r, "ADD_PAYMENT", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"payment_id": paymentID})
}

type sellPackageIn struct {
	PackageID int `json:"package_id"`
}

func (s *Server) handleSellPackage(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	childID, ok := pathID(r, "child_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in sellPackageIn
	if err := decodeJSON(w, r, &in); err != nil || in.PackageID <= 0 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"package_id": "REQUIRED"})
		return
	}
	id, err := s.db.SellPackage(r.Context(), ident.Username, childID, in.PackageID)
	if err != nil {
		s.opsError(w, r, "SELL_PACKAGE", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"child_package_id": id})
}

type decideIn struct {
	Status string `json:"status"`
	NoteAr string `json:"note_ar"`
}

func (s *Server) handleDecideRequest(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "request_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in decideIn
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.Status) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"status": "ACCEPTED|REJECTED"})
		return
	}
	if err := s.db.DecideRequest(r.Context(), ident.Username, id, in.Status, in.NoteAr); err != nil {
		s.opsError(w, r, "DECIDE_REQUEST", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// =====================================================================
// SHARED
// =====================================================================

// page builds the list envelope every centre-indexed read returns.
func page(name string, rows any, total, limit, offset int) map[string]any {
	return map[string]any{name: rows, "total": total, "limit": limit, "offset": offset}
}

// opsError maps one database refusal to one status code.
//
// The HB0xx classes are business rules, and each has a distinct meaning worth
// a distinct status. Anything unrecognised becomes a 500 with the cause in the
// log - never a polite 400 - because dressing up a rule this layer does not
// understand is how a real defect gets served as a shrug.
func (s *Server) opsError(w http.ResponseWriter, r *http.Request, what string, err error) {
	ident, _ := auth.FromContext(r.Context())

	if errors.Is(err, store.ErrNotFound) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	code := store.Code(err)
	switch code {
	case pgWriteRefused:
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
			Detail: "WRITE_REFUSED " + what, ClientIP: s.clientIP(r),
		})
		s.log.WarnContext(r.Context(), "the engine refused an operations write",
			"on", what, "actor", ident.Username, "err", err)
		writeError(w, r, http.StatusForbidden, CodeForbidden)

	case store.ErrCheckViolation, store.ErrForeignKeyViolation, pgUniqueViolation,
		pgNotNullViolation, pgInvalidText, pgInvalidDatetime, pgNumericValue,
		pgStringTooLong:
		s.log.WarnContext(r.Context(), "an operations write was refused by the schema",
			"on", what, "err", err)
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"constraint": constraintCode(code)})

	case pgExclusionViolation:
		// The slot is taken. Two receptionists raced and the exclusion
		// constraint decided - which is the whole point of D-13.
		writeError(w, r, http.StatusConflict, CodeSlotTaken)

	default:
		if status, clientCode, ok := businessRefusal(code); ok {
			// A refusal the map answers with 5xx is not a refusal at all -
			// it is this installation being misconfigured, HB170-HB172.
			// The client gets nothing but the request id; the cause goes
			// to the log, because an operator is the only person who can
			// act on it and the caller cannot.
			//
			// Without this the code would travel the quiet path: a 500
			// answered politely, with nothing written down anywhere.
			if status >= http.StatusInternalServerError {
				writeInternal(w, r, s.log, err)
				return
			}
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail: what + " " + code, ClientIP: s.clientIP(r),
			})
			writeError(w, r, status, clientCode)
			return
		}
		writeInternal(w, r, s.log, err)
	}
}

func (s *Server) recordOpsRead(r *http.Request, what string) {
	ident, _ := auth.FromContext(r.Context())
	s.audit.Record(r.Context(), audit.Event{
		Action: audit.ActionRead, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail: "CENTRE_" + what, ClientIP: s.clientIP(r),
	})
}

func isQueryErr(err error) bool {
	return errors.Is(err, errBadLimit) || errors.Is(err, errBadPage) ||
		errors.Is(err, errBadFilter) || errors.Is(err, errBadDate) ||
		errors.Is(err, errBadInstant) || errors.Is(err, errNoSearch) ||
		errors.Is(err, errBadQueryString)
}

// validAppointment checks only that the required identifiers and instants are
// present and coherent. Whether the SLOT is free is not asked here - that is
// hbh.validate_slot's question, and asking it twice would be two answers.
// validAppointment rejects a request that is not even shaped like a booking.
//
// IT DOES NOT DECIDE WHETHER THE ROOM IS RIGHT, and the line matters. Whether
// this mode may have a room, whether this service may be held without one,
// whether that room is free - all three are hbh.validate_slot's, and it
// answers them by name (ROOM_REQUIRED, ROOM_NOT_ALLOWED, SERVICE_NEEDS_ROOM)
// so the screen can say which. A copy of any of them here would be a second
// rule, and the day the two disagreed the weaker one would decide - rule 4.
//
// What is left here is the shape: identifiers that are identifiers, and an
// end after a start. It used to demand `RoomID > 0` unconditionally, and that
// one condition is what made an online consultation impossible to book
// through this service at all - a 400 before the schema was ever asked.
func validAppointment(in store.NewAppointment) bool {
	if in.ChildID <= 0 || in.TherapistID <= 0 || in.ServiceID <= 0 {
		return false
	}
	if in.StartsAt.IsZero() || in.EndsAt.IsZero() || !in.EndsAt.After(in.StartsAt) {
		return false
	}
	// A room that is named must be a real identifier. A room that is absent
	// is a question for validate_slot, not an answer here.
	if in.RoomID != nil && *in.RoomID <= 0 {
		return false
	}
	return validDeliveryMode(in.DeliveryMode)
}

// validDeliveryMode admits the three the schema admits, and empty for the
// callers written before the field existed.
//
// Listed rather than passed through: an unknown string would reach
// validate_slot and come back BAD_DELIVERY_MODE as a 200 with ok:false, which
// reads to a screen as "that hour is taken" rather than "this build sent
// nonsense". A 400 naming validation is the truthful answer to a typo.
func validDeliveryMode(mode string) bool {
	switch mode {
	case "", "IN_PERSON", "ONLINE", "EXTERNAL":
		return true
	default:
		return false
	}
}

// The exclusion-constraint violation. Two callers raced for one slot and the
// engine picked a winner - which is exactly what D-13 built it to do.
const pgExclusionViolation = "23P01"

// businessRefusal maps the schema's own HB0xx classes to a status and a client
// code.
//
// Each is a rule written in PL/pgSQL, and the mapping is the only place this
// layer is allowed to have an opinion about them - it decides how to SAY the
// refusal, never whether to make it.
//
// A code this table does not know is reported as a 409 with REFUSED rather
// than a 500: it is still a rule the database enforced deliberately, so
// calling it a server fault would be wrong. It is logged either way.
func businessRefusal(code string) (int, string, bool) {
	switch code {
	// State machines. 409, because repeating the request cannot help and the
	// caller's view of the current state is simply out of date.
	case "HB020", "HB025", "HB030", "HB034", "HB040", "HB050":
		return http.StatusConflict, "ILLEGAL_TRANSITION", true

	case "HB021":
		// The slot was refused - a weekend, a holiday, outside working hours,
		// a service this therapist does not offer. validate_slot names which.
		return http.StatusConflict, "SLOT_UNAVAILABLE", true
	case "HB022":
		return http.StatusConflict, "SESSION_EXISTS", true
	case "HB023":
		return http.StatusConflict, "NO_CASELOAD", true
	case "HB024":
		return http.StatusConflict, "NOT_CHECKED_IN", true

	// FROM 0117. The appointment is not delivered in person - an online
	// consultation, or one held somewhere else - and only an in-person
	// appointment opens a therapy session.
	//
	// Its own code rather than the generic REFUSED, because the two
	// sentences a therapist needs are different: "check the child in
	// first" is something to go and do, and "this is a consultation,
	// write it up as a note" is a different thing entirely. Telling
	// somebody the request was refused and leaving them to guess which
	// is how a working button gets reported as broken.
	case "HB250":
		return http.StatusConflict, "NOT_IN_PERSON", true

	// FROM 0118, and it is refused at BOOKING rather than at start: a
	// service that opens a therapy session was given no room, and
	// hbh.therapy_sessions.room_id is NOT NULL.
	//
	// 400 rather than 409. A state-machine refusal means the caller's
	// view is out of date and repeating cannot help; this one is a form
	// with a field missing, and the caller fixes it and sends it again.
	case "HB251":
		return http.StatusBadRequest, "SERVICE_NEEDS_ROOM", true

	// FROM 0121, and the two are kept apart because the family does
	// different things about them.
	//
	// HB252 is the hour: too early, too late, or a room that was closed
	// when the consultation was cancelled. Nothing to fix - come back at
	// the time, or speak to the centre.
	//
	// HB253 is the money: the consultation is booked and its invoice is
	// not paid, so the appointment is still BOOKED rather than CONFIRMED.
	// There IS something to do about that, and "the door is not open"
	// would have hidden it behind a sentence about time.
	case "HB252":
		return http.StatusConflict, "DOOR_CLOSED", true
	case "HB253":
		return http.StatusConflict, "NOT_CONFIRMED", true
	case "HB033":
		return http.StatusConflict, "ALREADY_PUBLISHED", true
	// FROM 0141 (#14, numbered 0150 until 2026-09-13). A colleague saved this draft after the caller opened
	// it. 409 and its own name, not ALREADY_PUBLISHED: the draft is still
	// editable, and the screen's job is to keep what was typed and offer
	// the newer text - which it cannot do if it is told the report is closed.
	case "HB290":
		return http.StatusConflict, "REPORT_CHANGED", true

	// A report's own content is not fit for what was asked: no title, a
	// period that runs backwards, a plan belonging to another child, or -
	// at publish only - no summary for the family to read. 400 rather
	// than 409: the caller can fix this and send it again, which is not
	// true of a state-machine refusal.
	case "HB029":
		return http.StatusBadRequest, CodeValidation, true
	case "HB053":
		return http.StatusConflict, "OVERPAYMENT", true
	case "HB051":
		return http.StatusNotFound, CodeNotFound, true

	// Permission refusals from inside a function. 403 rather than 404: the
	// caller can already see the row - they listed it - so this confirms
	// nothing new.
	case "HB026", "HB027", "HB028", "HB031", "HB032", "HB043":
		return http.StatusForbidden, CodeForbidden, true

	// The caller HOLDS SESSION.NOTES.EDIT and this session belongs to a
	// colleague. Its own code, because the screen would otherwise have to
	// tell somebody who does have the right that their permissions do not
	// allow it - which is both wrong and unactionable.
	//
	// It is safe to be specific here only because hbh.check_session_edit
	// asks for the permission FIRST: a stranger gets NOT_PERMITTED and
	// never learns whether the session exists or whose it is. Reverse that
	// order and this message becomes a way to probe the diary.
	case "HB035":
		return http.StatusForbidden, "NOT_YOUR_SESSION", true

	// HB052 is used for BOTH "needs BILLING.MANAGE" and "this invoice's
	// amounts can no longer change", and the two cannot be told apart from
	// the code alone. 409 is the safer of the two: it does not assert a
	// permission problem that may not exist.
	case "HB052":
		return http.StatusConflict, "REFUSED", true

	// The child is not one this caller may act for. It is a separate code
	// from HB052 precisely BECAUSE HB052 is already overloaded - folding a
	// third meaning into it would cost the interface the one thing it can
	// still say precisely here.
	case "HB054":
		return http.StatusForbidden, CodeForbidden, true

	// Asked the booking diary without APPOINTMENT.BOOK. hbh.available_slots
	// is SECURITY DEFINER, so it checks the permission itself and RAISES
	// rather than returning nothing: "you may not ask" and "there is nothing
	// free" are different answers, and a screen that prints the second for
	// the first sends a receptionist to ring a family about a day that was
	// never full.
	case "HB240":
		return http.StatusForbidden, CodeForbidden, true

	// THE ROW BELONGS TO ANOTHER CENTRE.
	//
	// Its own SQLSTATE, and the reason is not the client - it is the audit
	// log. A cross-tenant attempt and an ordinary permission refusal are
	// the same sentence to the person who made it and completely different
	// sentences to whoever reads the log afterwards. Folding this into
	// HB052 or HB101 would have cost exactly the distinction that matters
	// when somebody asks "has anyone tried this?".
	//
	// The CLIENT, though, is told nothing new: FORBIDDEN, the same body as
	// every other 403. A caller who supplied an identifier they could not
	// have listed learns only that they may not have it - not that it
	// exists, and not that it belongs to somebody else.
	//
	// 403 rather than 404 is a deliberate choice and a close one. db.go
	// argues for 404 on "exists but not yours", because distinguishing the
	// two confirms existence to anybody walking identifiers. It is 403
	// here because every caller that can reach these functions is STAFF
	// holding a real permission - not an anonymous prober - and because a
	// receptionist who has genuinely mistyped an id deserves a refusal
	// that says "not allowed" rather than one that says "no such thing"
	// and sends them looking for a row that is right there.
	case "HB232":
		return http.StatusForbidden, CodeForbidden, true

	case "HB060":
		return http.StatusForbidden, CodeForbidden, true

	// Intake. HB090 is the queue's state machine and HB091 is convert being
	// asked from a state it does not accept - both 409, both "your view of
	// this application is out of date". HB092 is the missing permission.
	case "HB090", "HB091":
		return http.StatusConflict, "ILLEGAL_TRANSITION", true
	case "HB092":
		return http.StatusForbidden, CodeForbidden, true

	// A score outside 0..10. The caller's mistake and nothing else's, so 400
	// rather than the 409 the rest of this table hands out.
	case "HB093":
		return http.StatusBadRequest, CodeValidation, true

	// The therapist's profile.
	case "HB140":
		return http.StatusNotFound, CodeNotFound, true
	case "HB141":
		return http.StatusForbidden, CodeForbidden, true

	// Publication was refused because nobody consented. Its OWN code, not
	// FORBIDDEN: the caller may well be permitted, and what is missing is
	// the therapist's agreement - which is a thing to go and obtain, not
	// a permission to request. A screen told FORBIDDEN would send an
	// administrator to the wrong person.
	case "HB142":
		return http.StatusConflict, "CONSENT_REQUIRED", true
	case "HB143":
		return http.StatusConflict, "ALREADY_PUBLISHED", true

	// Only the person themselves may consent on their own behalf.
	case "HB144":
		return http.StatusForbidden, "NOT_YOUR_CONSENT", true
	case "HB145":
		return http.StatusConflict, "ILLEGAL_TRANSITION", true

	// Administering users. HB150 is the missing permission; the rest name
	// what the caller got wrong, because a screen that can only say
	// "refused" makes somebody try the same thing again.
	case "HB150":
		return http.StatusForbidden, CodeForbidden, true
	case "HB151":
		return http.StatusBadRequest, CodeValidation, true
	case "HB152":
		return http.StatusConflict, "USERNAME_TAKEN", true
	case "HB153":
		return http.StatusNotFound, CodeNotFound, true

	// An account acting on itself. Two separate codes because the screen
	// says two different things: you cannot remove yourself, and you
	// cannot write yourself a promotion.
	case "HB154":
		return http.StatusConflict, "NOT_YOURSELF", true
	case "HB155":
		return http.StatusConflict, "NOT_YOUR_OWN_ROLES", true
	case "HB156":
		return http.StatusBadRequest, "NO_SUCH_ROLE", true

	// Editing a role's permissions.
	//
	// HB190 is the only refusal in this service that protects the PRODUCT
	// rather than a rule: the change would leave nobody holding
	// USER.MANAGE, and USER.MANAGE is what grants permissions - so no
	// screen could ever put it back. Its own code, and not FORBIDDEN,
	// because the caller is permitted; what they asked for is a door that
	// locks from the outside with the key inside.
	case "HB190":
		return http.StatusConflict, "LAST_ADMIN", true
	case "HB191":
		return http.StatusBadRequest, CodeValidation, true
	case "HB192":
		return http.StatusBadRequest, "NO_SUCH_PERMISSION", true

	// Attachments, including a child's photograph. Five codes and five
	// answers, because each one sends a person somewhere different: ask for
	// the permission, choose a smaller file, choose a different KIND of
	// file, or go and get the family's agreement.
	//
	// HB120 WAS MISSING AND CAME BACK AS 500. hbh.attach_file raises it for
	// an identity it does not recognise and for a caller without
	// ATTACHMENT.UPLOAD - so a guardian who tried to upload got "internal
	// server error" for a refusal the database had made correctly and on
	// purpose. Nobody looks for a permission problem behind a 500; they
	// look for an outage. Found by the acceptance session against the new
	// photograph route, and it was reachable from the attachment routes
	// before that too.
	//
	// HB121 WAS A LIVE 500 TOO, on the shipped values, with no parameter
	// edited by anybody:
	//
	//	config.MaxImageUpload  = 6 MB
	//	MAX_ATTACHMENT_MB      = 5 MB
	//
	// The Go ceiling is the LONGER of the two, so everything between them
	// passes this layer and is refused by hbh.attach_file. A 5.5 MB image
	// returned "internal server error" for a limit the centre had set on
	// purpose. It now answers 413, verified on that exact window.
	//
	// THE TWO CEILINGS ARE NOT THE SAME NUMBER AND SHOULD NOT BE MADE ONE
	// HERE. The database's is a centre parameter and may be changed by the
	// people who run the centre; this one is a memory bound on a request
	// this process has to hold. Whichever is shorter has to be the one that
	// answers, and it can be either - so both need a real reply. Copying
	// the parameter into Go would make the shorter one drift silently the
	// first time somebody changes it.
	case "HB120":
		return http.StatusForbidden, CodeForbidden, true
	case "HB121":
		return http.StatusRequestEntityTooLarge, CodeTooLarge, true
	case "HB122":
		return http.StatusUnsupportedMediaType, CodeValidation, true

	// HB123 is not FORBIDDEN. The caller is permitted to upload; what is
	// missing is the family's agreement, and calling that a permission
	// problem sends a receptionist to an administrator instead of to the
	// parent.
	case "HB123":
		return http.StatusConflict, "PHOTO_CONSENT_MISSING", true
	case "HB124":
		return http.StatusUnsupportedMediaType, CodeValidation, true

	// The centre's own parameters. Four codes and not one, because the four
	// send a person to four different places: ask for the permission, check
	// the name, accept that this value is not yours to move, or correct what
	// you typed.
	case "HB180":
		return http.StatusForbidden, CodeForbidden, true
	case "HB181":
		return http.StatusNotFound, CodeNotFound, true
	// Not FORBIDDEN. The caller may hold SETTINGS.MANAGE and still be
	// refused: RECORDING_ENABLED is a product decision and
	// STREAM_TOKEN_TTL_MIN a security ceiling, and neither becomes editable
	// by granting anybody anything. Telling an administrator they lack a
	// permission would send them to ask for one that would not help.
	case "HB182":
		return http.StatusConflict, "NOT_EDITABLE", true
	case "HB183":
		return http.StatusBadRequest, CodeValidation, true

	// The centre's own row. `code` never reaches here - it carries no
	// grant - but the rule is in the trigger too, so the code exists.
	case "HB160":
		return http.StatusConflict, "IMMUTABLE", true
	// Not FORBIDDEN and not VALIDATION: the value is well formed and the
	// caller is permitted. What refuses it is that money already exists
	// in the old currency, and nothing converts stored amounts.
	case "HB161":
		return http.StatusConflict, "CURRENCY_LOCKED", true
	case "HB162":
		return http.StatusBadRequest, CodeValidation, true
	case "HB061":
		return http.StatusConflict, CodeNotLive, true
	case "HB063":
		return http.StatusServiceUnavailable, CodeStreamUnavailable, true

	// =================================================================
	// THE WAITING LIST AND THE RECURRING COURSE
	// =================================================================
	case "HB100":
		// A waiting entry cannot go from this state to that one.
		return http.StatusConflict, "ILLEGAL_TRANSITION", true
	// HB101 IS OVERLOADED, like HB052 before it: the schema raises it for
	// "needs APPOINTMENT.BOOK", for "needs APPOINTMENT.CANCEL", for "no
	// such child" AND for "a cancellation needs a stated reason". Four
	// meanings, one code, and nothing in the code tells them apart.
	//
	// 403 is the least wrong of the four. Three of the meanings are a
	// refusal the caller cannot retry away, and answering 400 would tell
	// somebody to fix a body that is already correct. D-35: a code
	// carrying two meanings has already cost the interface the thing it
	// could otherwise say precisely - this one carries four.
	case "HB101":
		return http.StatusForbidden, CodeForbidden, true
	case "HB102":
		// The entry is not waiting, or its offer has lapsed. Repeating the
		// request cannot help; the caller's view is out of date.
		return http.StatusConflict, "ILLEGAL_TRANSITION", true

	// =================================================================
	// ASSESSMENTS
	// =================================================================
	case "HB110":
		// The state machine: only a COMPLETED assessment may be published.
		return http.StatusConflict, "ILLEGAL_TRANSITION", true
	// Overloaded the same way: ASSESSMENT.RECORD, ASSESSMENT.PUBLISH, "no
	// such assessment", "no such child" and "not permitted to assess this
	// child" all arrive as HB111. Three of the five are permission, so
	// 403 - and a screen should say "you may not do this to this child"
	// rather than naming a permission the caller may already hold.
	case "HB111":
		return http.StatusForbidden, CodeForbidden, true
	case "HB112":
		// A published assessment is frozen - scores included. Its own code
		// because the screen says something specific and actionable: this
		// is final, and a correction is a new assessment.
		return http.StatusConflict, "ALREADY_PUBLISHED", true

	case "HB130":
		// Backup health needs OPS.VIEW, and an identity at all. Answering
		// anything softer would tell an unauthenticated caller how long
		// this installation has gone without a verified backup.
		return http.StatusForbidden, CodeForbidden, true

	// =================================================================
	// THE CENTRE'S OWN CONFIGURATION IS BROKEN - NOT THE REQUEST
	// =================================================================
	//
	// ONLY HB172, and getting this wrong was nearly a regression.
	//
	// The first draft read `case "HB170", "HB171", "HB172"` - three codes,
	// one answer - which is the overloading this file complains about in
	// four other places. They are not one thing:
	//
	//   HB170  the mobile does not match MOBILE_PATTERN      the caller's
	//   HB171  the national id is not NATIONAL_ID_LENGTH     the caller's
	//   HB172  the PARAMETER ITSELF is unset or not a number  ours
	//
	// The first two are a person mistyping a number, answered 400 with the
	// field named - crud_handlers.go does that already, and the contract
	// documents it. Mapping them to 500 here would have turned a typo into
	// a server fault on every path that does not go through the CRUD
	// handler, and the screen would tell somebody to report a bug about
	// their own telephone number.
	//
	// HB172 is the one the caller can do nothing about: this centre's
	// sys_params row is missing or malformed, so nobody can be registered
	// at all. That is a 500 with the cause in the log, where the only
	// person who can fix it will see it.
	case "HB170":
		return http.StatusBadRequest, CodeValidation, true
	case "HB171":
		return http.StatusBadRequest, CodeValidation, true
	case "HB172":
		return http.StatusInternalServerError, CodeInternal, true

	// THE STRAGGLERS. Fifteen codes live in PL/pgSQL that this table never
	// named, found by asking the database rather than by reading this file.
	//
	// They are not a new family. They are HB0xx and HB1xx - the ranges this
	// table thought it covered - with holes in the middle, which is why
	// nobody spotted them: HB040 and HB043 are here, so HB041 and HB042
	// look covered until you go and count.

	// Our own faults, not the caller's. An append-only table mutated, a
	// number series never seeded, audit_attempt handed a non-attempt. No
	// request body reaches any of them; each means this service called a
	// function wrongly or the centre was deployed half-configured. 500 so
	// opsError logs the cause - the same call HB172 makes.
	case "HB001", "HB010", "HB012":
		return http.StatusInternalServerError, CodeInternal, true

	// The OTP matched and the account is still not allowed to open a
	// session - dismissed staff, a disabled family. 403 and not 401: the
	// caller proved who they are, and 401 would invite the client to try
	// authenticating again at a door that will never open. It tells a
	// holder of a valid code that the account is disabled, which is not a
	// leak - they are holding the code sent to that mobile.
	case "HB011":
		return http.StatusForbidden, CodeForbidden, true

	// Activity logging. HB041 conflates "no such activity" with "not
	// yours" on purpose and 404 keeps them conflated; HB042 is the second
	// click on a button whose first click landed.
	case "HB041":
		return http.StatusNotFound, CodeNotFound, true
	case "HB042":
		return http.StatusConflict, CodeAlreadyLogged, true

	// Passwords. HB071 is an account that signs in by one-time code, so
	// there is no password to set - 409, because nothing about the request
	// is malformed and a different body would not help. HB072 is the
	// length rule and names the field. HB073 conflates absent with
	// not-permitted, and 404 keeps it conflated.
	case "HB071":
		return http.StatusConflict, "NOT_A_PASSWORD_USER", true
	case "HB072":
		return http.StatusBadRequest, CodeValidation, true
	case "HB073":
		return http.StatusNotFound, CodeNotFound, true

	// Consent. HB080 is the caller sending a child with a guardian-only
	// consent or omitting one from a child consent - a malformed request,
	// 400. HB082 conflates no such guardian, not linked to this child, and
	// not permitted; 404 keeps all three indistinguishable, which is the
	// point.
	case "HB080":
		return http.StatusBadRequest, CodeValidation, true
	case "HB082":
		return http.StatusNotFound, CodeNotFound, true

	// HB081 IS THE LIVE-VIEWING CONSENT GATE and the only one of these
	// that a family will ever see.
	//
	// can_view_live_flg cannot be set for a guardian and child with no
	// recorded LIVE_VIEW consent. 409 with a code of its own rather than
	// the catch-all's "REFUSED", because the screen has something useful
	// to say - record the consent - and a generic refusal sends reception
	// to an administrator instead. This is the rule that keeps a camera
	// from being opened to somebody who never agreed to it, so it answers
	// in its own name.
	case "HB081":
		return http.StatusConflict, "CONSENT_REQUIRED", true

	// HB094: the survey is closed, archived, or belongs to another centre -
	// one message for all three, so one status for all three. 404 puts it
	// with HB041, HB073 and HB082, every other place in this table where
	// the schema refuses to say which of "gone" and "not yours" it means.
	case "HB094":
		return http.StatusNotFound, CodeNotFound, true

	// HB113 is a score above the item's maximum: the caller's number, and
	// the field is named. It sits beside HB093, which is the 0-10 bound on
	// an NPS score and is already a 400 here.
	case "HB113":
		return http.StatusBadRequest, CodeValidation, true

	// HB173 is canonical_mobile refusing a number, and it belongs with
	// HB170 - the caller's mobile - and not with HB172, which is our
	// unseeded parameter. Three of its four messages are about the number
	// that arrived; the fourth, "no country to read a national mobile
	// number against", is a missing default dial code and is ours. They
	// share a code, so they share an answer, and 400 is the one that is
	// wrong in the direction that does not hide a caller's typo behind a
	// server fault.
	case "HB173":
		return http.StatusBadRequest, CodeValidation, true

	// HB2xx - AND THE SAME LESSON AGAIN, ONE FAMILY LATER.
	//
	// The HB1xx fix below replaced a fallback the schema had outgrown. It
	// did not stop the schema growing. Six HB2xx codes are live in
	// PL/pgSQL right now and none of them was named here, so every one
	// answered 409 REFUSED through the catch-all - which is the safe
	// direction to be wrong in, and still wrong in three different ways
	// at once. That is the whole complaint I made about HB101.
	//
	// The catch-all cannot be the plan for a family. It is the plan for a
	// code invented after this build shipped.

	// Portal access for a guardian. HB200 is the missing permission and
	// belongs with every other missing permission: a caller without
	// GUARDIAN.MANAGE must be told they are not allowed, not that the
	// request conflicts with something.
	case "HB200":
		return http.StatusForbidden, CodeForbidden, true

	// HB201 is "no such guardian in this centre" - which conflates absent,
	// archived and belonging to another centre, deliberately, because the
	// answer must not distinguish them.
	//
	// 404 here where HB232 above chose 403, and the difference is real:
	// HB200 has already established that this caller holds GUARDIAN.MANAGE
	// in this centre. What is left is a staff member who mistyped an id,
	// and telling them "not allowed" sends them to an administrator over a
	// row that does not exist. HB232 refuses a reach ACROSS centres, where
	// 404 would confirm nothing and 403 names the actual rule.
	case "HB201":
		return http.StatusNotFound, CodeNotFound, true

	// HB204: the family's mobile already belongs to an account that is
	// not a guardian - a member of staff enrolling her own child is the
	// ordinary way this happens in a small centre.
	//
	// 409 and not 400: nothing the caller typed is malformed. The values
	// are right and the world conflicts with them, which is what 409 is
	// for. Before 0126 this arrived as a bare 23505 and became
	// "VALIDATION / DUPLICATE" - a sentence with no field and no reason,
	// on a screen holding a dozen values.
	//
	// Its own code rather than the catch-all, because the answer is
	// actionable and specific: the number needs to differ from the staff
	// one, and that is a decision for the centre to make, not a retry.
	case "HB204":
		return http.StatusConflict, "MOBILE_NOT_A_GUARDIAN", true

	// HB203: the text states a permanent rule - "no recording, ever" is
	// the one that exists - and the row is locked against rewording. 409
	// because the row is real, the caller may edit site text in general,
	// and this particular text refuses. Named rather than left to the
	// catch-all so the screen can say why instead of saying "refused".
	case "HB203":
		return http.StatusConflict, "TEXT_LOCKED", true

	// HB220, HB230 and HB231 are not refusals of anything a client asked
	// for. They are assertions inside the notification and delivery
	// machinery - a staff notification handed a kind that is not a staff
	// kind, the outbox reached from a user session, a delivery record
	// without a centre. No request body can produce them and no client can
	// act on them; if one ever surfaces, this service called a function
	// wrongly. 500 so that opsError logs the cause rather than filing our
	// own bug as the caller's conflict.
	//
	// HB254 joins them: record_verification_delivery handed no centre or no
	// destination. Nothing in api/ calls it yet, and when something does,
	// both values come from this service, not from a request body.
	case "HB220", "HB230", "HB231", "HB254":
		return http.StatusInternalServerError, CodeInternal, true

	// FROM 0129/0130. A record's origin is written once. HB241 is the
	// second write - 409, because the row is real, the caller may edit the
	// guardian, and this one column refuses. It was briefly HB240, which
	// already meant "may not read the booking diary"; a receptionist would
	// have been told she lacked a permission she holds.
	case "HB241":
		return http.StatusConflict, "ORIGIN_LOCKED", true

	// FROM 0132. Matching needs GUARDIAN.MANAGE - and the same code is also
	// raised for "this guardian is not this centre's", AFTER the permission
	// has been established. 403 fits the first branch and is the HB232
	// answer to the second; HB201's reasoning (a caller who holds the
	// permission and mistyped an id deserves 404) argues the other way. It
	// is recorded as a split still owed, not settled here.
	case "HB255":
		return http.StatusForbidden, CodeForbidden, true

	// FROM 0133. A profile-completeness rule naming a field the table does
	// not have. The caller wrote the rule, so the caller fixes it: 400.
	case "HB256":
		return http.StatusBadRequest, CodeValidation, true

	// FROM 0135/0136 - catalogue prices, named to the owner's pricing
	// contract of 2026-09-12. HB258 and HB260 were each raised for more
	// than one reason; each now means exactly one thing, and the reasons
	// split away from them have their own codes.
	//
	// HB257: strict pricing is on and the service has no effective price.
	// Nothing the caller typed is wrong; the catalogue is incomplete.
	case "HB257":
		return http.StatusConflict, "NO_EFFECTIVE_CATALOGUE_PRICE", true

	// HB258: overriding a price without BILLING.PRICE_OVERRIDE - and only
	// that. Its own client code rather than FORBIDDEN, because the person
	// refused may bill the line at the catalogue price and the screen can
	// say so.
	case "HB258":
		return http.StatusForbidden, "PRICE_OVERRIDE_FORBIDDEN", true

	// HB260: editing a price without BILLING.PRICE_EDIT - and only that.
	// A service of another centre is NOT this code: set_service_price
	// answers it with HB051 and the text of a service that does not exist,
	// so a foreign id and a ghost id are indistinguishable.
	case "HB260":
		return http.StatusForbidden, "PRICE_MANAGEMENT_FORBIDDEN", true

	// HB259: the service's billing model refuses this charge - a
	// package-only service booked with no package, or a package sold for a
	// service that has none. A rule about the service, not the request.
	case "HB259":
		return http.StatusConflict, "BILLING_MODEL_DISALLOWS_CHARGE", true

	// HB262: an override reason on a line with no service_id - there is no
	// catalogue price to override. 422, by the owner's contract: the body
	// is well-formed and each field valid on its own, and it is the
	// combination the rule refuses.
	case "HB262":
		return http.StatusUnprocessableEntity, CodeValidation, true

	// HB264: a price kind that is neither PACKAGE nor SINGLE. The contract
	// did not name it; 400, a malformed field the caller corrects.
	case "HB264":
		return http.StatusBadRequest, CodeValidation, true

	// FROM 0138 (OD-26: two guardians may share one phone). HB261: the
	// number's portal account already belongs to another guardian. Before
	// it, grant_portal_access linked the second guardian to the first
	// one's account and died on uix_guardians_user as a bare 23505 -
	// "VALIDATION / DUPLICATE", the defect 0126 fixed for staff numbers.
	// 409 for HB204's reason: the values are right and the world
	// conflicts with them. The API names it before the migration ships,
	// because an unknown code answers 500 - worse than today's 400.
	case "HB261":
		return http.StatusConflict, "MOBILE_HELD_BY_GUARDIAN", true

	// FROM 0142 - payment plans, layer A. Named before the migration ships,
	// one meaning per code.
	//
	// 409: the plan or the invoice is in a state that forbids the action.
	// HB265 is a plan transition off the DRAFT -> ACTIVE -> RETIRED path;
	// HB266 is everything a plan's CURRENT status forbids - editing a
	// template that is no longer DRAFT, issuing on a plan that is not
	// ACTIVE, making one default, retiring the default.
	case "HB265":
		return http.StatusConflict, "PAYMENT_PLAN_TRANSITION", true
	case "HB266":
		return http.StatusConflict, "PAYMENT_PLAN_STATE", true

	// 422: every field is well-formed and the combination is refused.
	// HB267 a plan that cannot be activated as written; HB268 fixed amounts
	// larger than the invoice; HB271 an override with a blank reason; HB272
	// new rows that do not add up to the total less what is already PAID.
	case "HB267":
		return http.StatusUnprocessableEntity, "PAYMENT_PLAN_INCOMPLETE", true
	case "HB268":
		return http.StatusUnprocessableEntity, "SCHEDULE_EXCEEDS_TOTAL", true
	case "HB271":
		return http.StatusUnprocessableEntity, "OVERRIDE_REASON_REQUIRED", true
	case "HB272":
		return http.StatusUnprocessableEntity, "SCHEDULE_TOTAL_MISMATCH", true

	// HB270: overriding a schedule without BILLING.SCHEDULE_OVERRIDE.
	case "HB270":
		return http.StatusForbidden, "SCHEDULE_OVERRIDE_FORBIDDEN", true

	// HB273: a schedule entry that is not the shape the function reads -
	// not an array, an amount that is not a positive number, not exactly
	// one of due_date / due_after_sessions, a date that is not a date.
	case "HB273":
		return http.StatusBadRequest, CodeValidation, true

	// HB269: an instalment moved off its state machine, or its amount
	// rewritten. Only schema code writes instalments - no request body
	// reaches that UPDATE - so if this ever surfaces, a function we wrote
	// is wrong. 500, with HB220/HB230/HB231/HB254, so the cause is logged
	// rather than handed to the caller as a conflict they could resolve.
	case "HB269":
		return http.StatusInternalServerError, CodeInternal, true
	}

	// THE FALLBACK USED TO READ "HB0", AND THE SCHEMA GREW PAST IT.
	//
	// Every code was HB0xx when this line was written. The schema now
	// raises HB100 through HB190, so eight live codes - the waiting list,
	// the assessments, backup health - fell through to a 500 and reached
	// the screen as "an unexpected error occurred", each one a business
	// rule refusing on purpose.
	//
	// Nobody had noticed because the API answers what it answers and
	// nothing compares it to the schema. It is the lesson in CLAUDE.md
	// exactly: the schema and the code do not move in the same step, and
	// whichever waits is the one that breaks when the other moves first.
	//
	// "HB" rather than "HB0" means the next family the schema invents is
	// a deliberate refusal rather than a server fault - which is the safe
	// direction to be wrong in. A code this table does not know is still
	// logged by the caller.
	// A SQLSTATE is five characters, always. Checking the prefix alone
	// would accept the bare string "HB" - which the unit test caught on
	// the first run, and which is not a code the engine can ever raise.
	// A guard that accepts things that cannot happen is a guard whose
	// meaning nobody can state.
	if len(code) == 5 && strings.HasPrefix(code, "HB") {
		return http.StatusConflict, "REFUSED", true
	}
	return 0, "", false
}

// =====================================================================
// AUTHORING AN INVOICE, AND WHAT A THERAPIST OFFERS
//
// Two gaps the console session found by trying to run a centre through
// this API: it could create everything a booking needs and never book,
// because nothing wrote hbh.therapist_services; and its billing screen
// had issue and payment and no way to reach either, because nothing
// created an invoice.
// =====================================================================

func (s *Server) handleCreateInvoice(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	var in store.NewInvoice
	if err := decodeJSON(w, r, &in); err != nil || in.ChildID <= 0 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "child_id"})
		return
	}
	id, err := s.db.CreateInvoice(r.Context(), ident.Username, in)
	if err != nil {
		s.opsError(w, r, "CREATE_INVOICE", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"invoice_id": id})
}

func (s *Server) handleAddInvoiceLine(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "invoice_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.NewInvoiceLine
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.DescriptionAr) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "description_ar"})
		return
	}
	lineID, err := s.db.AddInvoiceLine(r.Context(), ident.Username, id, in)
	if err != nil {
		s.opsError(w, r, "ADD_INVOICE_LINE", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"line_id": lineID})
}

func (s *Server) handleRemoveInvoiceLine(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	lineID, ok := pathID(r, "line_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.RemoveInvoiceLine(r.Context(), ident.Username, lineID); err != nil {
		s.opsError(w, r, "REMOVE_INVOICE_LINE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleTherapistServices(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	rows, err := s.db.TherapistServices(r.Context(), ident.Username, id)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"services": rows, "total": len(rows)})
}

// handleServiceTherapists lists who offers one service.
//
// The mirror of handleTherapistServices, and the direction the booking
// screen reads: a dropdown of every therapist lets somebody pick one who
// does not do speech therapy and learn it from a refusal afterwards.
func (s *Server) handleServiceTherapists(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "service_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	rows, err := s.db.ServiceTherapists(r.Context(), ident.Username, id)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"therapists": rows, "total": len(rows)})
}

func (s *Server) handleAddTherapistService(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		ServiceID int `json:"service_id"`
	}
	if err := decodeJSON(w, r, &in); err != nil || in.ServiceID <= 0 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "service_id"})
		return
	}
	if err := s.db.AddTherapistService(r.Context(), ident.Username, id, in.ServiceID); err != nil {
		s.opsError(w, r, "ADD_THERAPIST_SERVICE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleRemoveTherapistService(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	serviceID, ok := pathID(r, "service_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.RemoveTherapistService(r.Context(), ident.Username, id, serviceID); err != nil {
		s.opsError(w, r, "REMOVE_THERAPIST_SERVICE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// =====================================================================
// THE THERAPIST'S PROFILE
//
// Two of these endpoints exist as endpoints of their own because the
// act they perform is its own decision: consenting to publication, and
// releasing a certificate's scan. Folded into a general edit, each
// would ride along with a typo correction.
// =====================================================================

func (s *Server) handleTherapistLanguages(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	rows, err := s.db.TherapistLanguages(r.Context(), ident.Username, id)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"languages": rows, "total": len(rows)})
}

func (s *Server) handleSetTherapistLanguage(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.TherapistLanguage
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.LangCode) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "lang_code"})
		return
	}
	if err := s.db.SetTherapistLanguage(r.Context(), ident.Username, id, in); err != nil {
		s.opsError(w, r, "SET_THERAPIST_LANGUAGE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleRemoveTherapistLanguage(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	lang := r.PathValue("lang_code")
	if strings.TrimSpace(lang) == "" {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.RemoveTherapistLanguage(r.Context(), ident.Username, id, lang); err != nil {
		s.opsError(w, r, "REMOVE_THERAPIST_LANGUAGE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleTherapistCertificates(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	rows, err := s.db.TherapistCertificates(r.Context(), ident.Username, id)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"certificates": rows, "total": len(rows)})
}

func (s *Server) handleAddTherapistCertificate(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.NewCertificate
	if err := decodeJSON(w, r, &in); err != nil || strings.TrimSpace(in.TitleAr) == "" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "title_ar"})
		return
	}
	certID, err := s.db.AddTherapistCertificate(r.Context(), ident.Username, id, in)
	if err != nil {
		s.opsError(w, r, "ADD_THERAPIST_CERTIFICATE", err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"certificate_id": certID})
}

// handleCertificateImage releases or withdraws one certificate's scan.
//
// A body of {"is_image_public": true} publishes a document that usually
// carries a national ID number, a date of birth and a signature. It is
// its own endpoint so that the request says so.
func (s *Server) handleCertificateImage(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	certID, ok := pathID(r, "certificate_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		IsImagePublic *bool `json:"is_image_public"`
	}
	if err := decodeJSON(w, r, &in); err != nil || in.IsImagePublic == nil {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "is_image_public"})
		return
	}
	if err := s.db.SetCertificateImagePublic(r.Context(), ident.Username, certID, *in.IsImagePublic); err != nil {
		s.opsError(w, r, "CERTIFICATE_IMAGE", err)
		return
	}
	// The change is recorded by trg_thc_audit, inside the transaction,
	// where a change record belongs (D-1) - old value and new, so
	// releasing an identity document and withdrawing one are both
	// answerable later. No attempt record: hbh.audit_attempt takes LOGIN,
	// DENY or READ, and this is none of the three.
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleTherapistConsent(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in struct {
		TextVersion string `json:"text_version"`
	}
	if r.ContentLength > 0 {
		if err := decodeJSON(w, r, &in); err != nil {
			writeError(w, r, http.StatusBadRequest, CodeValidation)
			return
		}
	}
	if err := s.db.RecordTherapistConsent(r.Context(), ident.Username, id, in.TextVersion); err != nil {
		s.opsError(w, r, "THERAPIST_CONSENT", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleWithdrawTherapistConsent(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.WithdrawTherapistConsent(r.Context(), ident.Username, id); err != nil {
		s.opsError(w, r, "WITHDRAW_THERAPIST_CONSENT", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handlePublishTherapistProfile(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	if err := s.db.PublishTherapistProfile(r.Context(), ident.Username, id); err != nil {
		s.opsError(w, r, "PUBLISH_THERAPIST_PROFILE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleUpdateTherapistProfile(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	id, ok := pathID(r, "therapist_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	var in store.ProfileEdit
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}
	if err := s.db.UpdateTherapistProfile(r.Context(), ident.Username, id, in); err != nil {
		var unknown store.ErrUnknownClear
		if errors.As(err, &unknown) {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"field": "clear"})
			return
		}
		s.opsError(w, r, "UPDATE_THERAPIST_PROFILE", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// =====================================================================
// THE CENTRE'S PARAMETERS
//
// Everything the centre runs on is a row in hbh.sys_params, and until
// these two handlers nothing read or wrote one over HTTP. The settings
// screen said so, in a banner, and meant it.
//
// The read is open to any signed-in caller and returns what RLS lets
// them see - a screen listing its own centre's values confirms nothing
// they could not already infer from the application working. The WRITE
// is where SETTINGS.MANAGE is asked for, and it is asked for inside
// hbh.set_center_param, not here.
// =====================================================================

func (s *Server) handleCenterParams(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.CenterParams(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"params": rows, "total": len(rows)})
}

type paramBody struct {
	Value string `json:"value"`
}

// PATCH /api/v1/settings/params/{code}
//
// The code travels in the path and the value in the body. It is a PATCH and
// not a PUT because the row it lands on may not exist yet: the first write
// creates the centre's override beside the global default, and the caller
// neither knows nor needs to know which of the two happened.
func (s *Server) handleSetCenterParam(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	// A code is matched against the table, never used to build SQL - but it
	// is still bounded here so a caller cannot make the database compare a
	// megabyte, and so the audit line stays a line.
	code := strings.TrimSpace(r.PathValue("code"))
	if code == "" || len(code) > 64 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	var in paramBody
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	stored, err := s.db.SetCenterParam(r.Context(), ident.Username, code, in.Value)
	if err != nil {
		s.opsError(w, r, "SET_PARAM "+code, err)
		return
	}

	// Nothing is recorded here on purpose. The row-level audit trigger on
	// hbh.sys_params already wrote the change with its old and new value and
	// the username, inside the same transaction - and hbh.audit_attempt
	// accepts LOGIN, DENY and READ only, so a second line would have to
	// borrow one of those headings and file a write under the wrong one.
	writeJSON(w, http.StatusOK, map[string]any{"code": code, "value": stored})
}

// PATCH /api/v1/settings/center
//
// The centre's own row - its name, country, currency, time zone and weekend.
// Migration 0051 opened it and put all three gates in the database; this
// handler carries the answer and never asks a question of its own.
//
// A caller without SETTINGS.MANAGE is refused by the POLICY, which means the
// UPDATE matches no row rather than raising - so it arrives here as
// ErrNotFound and leaves as 404. That is deliberate and it is the same answer
// the rest of this service gives for "not yours or not there": a settings
// screen is drawn from /me, so somebody who can see the values already knows
// the centre exists, and the 404 confirms nothing new.
func (s *Server) handleUpdateCenter(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	var in store.CenterEdit
	if err := decodeJSON(w, r, &in); err != nil {
		writeError(w, r, http.StatusBadRequest, CodeValidation)
		return
	}

	if _, err := s.db.UpdateCenter(r.Context(), ident.Username, in); err != nil {
		if errors.Is(err, store.ErrNothingToDo) {
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"field": "body"})
			return
		}
		// The three CHECK constraints on this table each belong to one named
		// field, and the database says which one it was. Translating that to
		// the field's name is not disclosing the constraint - `currency_code`
		// is the word printed above the box, `ck_centers_currency` is not.
		// Which field, from the database when it says so and from the
		// request when it does not. country_code is character(2), so "EGY"
		// is refused by the TYPE with 22001 and no constraint attached -
		// and a screen that edits one row at a time still knows exactly
		// which box the person was in. Only when ONE field was sent: with
		// two, naming either would be a guess.
		field := centerField(store.ConstraintName(err))
		if field == "" && store.Code(err) == "HB162" {
			// 0059 refuses a zone the engine cannot resolve. It is a rule about
			// one named field, so it is answered like one - the generic
			// mapping below would only say "check your input" about a form
			// with five boxes.
			field = "time_zone"
		}
		if field == "" && store.Code(err) == pgStringTooLong {
			field = soleField(in)
		}
		if field != "" {
			s.log.WarnContext(r.Context(), "a centre settings write was refused by the schema",
				"field", field)
			writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
				map[string]any{"field": field, "constraint": "FORMAT"})
			return
		}
		s.opsError(w, r, "UPDATE_CENTER", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// centerField names the field behind one of hbh.centers' check constraints.
//
// Three constraints, three fields, and the mapping is written out rather than
// derived from the name: a constraint renamed in a migration would otherwise
// silently stop naming its field, and the screen would go back to saying
// "check your input" about a form with five boxes in it.
func centerField(constraint string) string {
	switch constraint {
	case "ck_centers_country":
		return "country_code"
	case "ck_centers_currency":
		return "currency_code"
	case "ck_centers_weekend":
		return "weekend_days"
	default:
		return ""
	}
}

// soleField names the one field a CenterEdit sets, or "" when it sets none or
// several. It exists to attach a name to a refusal the database raised
// without one - never to decide anything.
func soleField(in store.CenterEdit) string {
	named := ""
	count := 0
	set := func(name string, present bool) {
		if present {
			named, count = name, count+1
		}
	}
	set("name_ar", in.NameAr != nil)
	set("country_code", in.CountryCode != nil)
	set("currency_code", in.CurrencyCode != nil)
	set("time_zone", in.TimeZone != nil)
	set("weekend_days", in.WeekendDays != nil)
	if count == 1 {
		return named
	}
	return ""
}

// DELETE /api/v1/settings/params/{code}
//
// "Return this to the default." The route says DELETE because that is what the
// person means; the database deactivates the centre's override and keeps it,
// the same way every other archive in this schema works.
//
// It answers 200 with the value now in force rather than 204, and that is the
// point of the endpoint: the screen has just told somebody a number is going
// to change, and the reply is the number.
func (s *Server) handleClearCenterParam(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	code := strings.TrimSpace(r.PathValue("code"))
	if code == "" || len(code) > 64 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	restored, err := s.db.ClearCenterParam(r.Context(), ident.Username, code)
	if err != nil {
		s.opsError(w, r, "CLEAR_PARAM "+code, err)
		return
	}
	// As in the PATCH: the row-level audit trigger already recorded the
	// change, with both values and the username, inside the transaction.
	writeJSON(w, http.StatusOK, map[string]any{"code": code, "value": restored})
}

// GET /api/v1/settings/time-zones
//
// The picker's list. Any signed-in caller may read it: it is the engine's own
// tzdata and says nothing about this centre.
func (s *Server) handleTimeZones(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	zones, err := s.db.TimeZones(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"zones": zones, "total": len(zones)})
}

// handleServicePairs lists every deliverable (service, therapist) pair.
//
// It exists so the booking screen can ask ONE question instead of two. The
// old form asked for a service and then a therapist, and the second answer
// could contradict the first - which is why /services/{id}/therapists was
// added to narrow it. A single list of valid pairs goes one step further:
// an incompatible combination is not merely discouraged, it cannot be
// expressed.
//
// Not a substitute for the rule. hbh.validate_slot still answers
// THERAPIST_SERVICE_MISMATCH for a request that names one anyway.
func (s *Server) handleServicePairs(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.ServicePairs(r.Context(), ident.Username)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pairs": rows, "total": len(rows)})
}
