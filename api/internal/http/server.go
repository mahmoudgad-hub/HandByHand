// Package http is the transport layer: routing, middleware, and the mapping
// from a database outcome to a status code.
//
// It contains no access control of its own. Every decision about who may see
// what is made by a row level security policy or by a PL/pgSQL function, and
// this layer only reports what came back. A check written here as well would
// be a second copy of a rule, and the two copies would eventually disagree -
// with the weaker one deciding.
package http

import (
	"log/slog"
	"net/http"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/config"
	"github.com/handbyhand/hbh/api/internal/sms"
	"github.com/handbyhand/hbh/api/internal/store"
)

// Server holds the dependencies every handler shares.
type Server struct {
	cfg     config.Config
	db      *store.DB
	params  *store.Params
	audit   *audit.Recorder
	log     *slog.Logger
	authLim *limiter

	// sender delivers one-time codes. It is the SAME implementation the
	// outbox worker uses, so a deployment cannot end up texting appointment
	// reminders through a real provider and login codes through something
	// else.
	//
	// A login code is sent INSIDE the request that asked for it rather than
	// queued: its whole life is fifteen minutes, a parent is watching the
	// screen, and queueing it would mean writing a live credential into a
	// table to wait there. See store.EnqueueOTPDelivery.
	sender sms.Sender
}

// NewServer wires the routes.
func NewServer(cfg config.Config, db *store.DB, params *store.Params, rec *audit.Recorder, log *slog.Logger, sender sms.Sender) *Server {
	return &Server{
		cfg:     cfg,
		db:      db,
		params:  params,
		audit:   rec,
		log:     log,
		authLim: newLimiter(cfg.AuthRatePerMinute),
		sender:  sender,
	}
}

// Handler returns the fully wrapped root handler.
func (s *Server) Handler() http.Handler {
	rt := newRouter()

	// Liveness and readiness are separate on purpose. Liveness says the
	// process is running; readiness says it can serve. An orchestrator that
	// conflates them restarts a healthy process because the database blinked.
	rt.route(http.MethodGet, "/healthz", http.HandlerFunc(s.handleHealth))
	rt.route(http.MethodGet, "/readyz", http.HandlerFunc(s.handleReady))

	// The login endpoints are rate limited by caller address. See the note in
	// ratelimit.go for what the database throttles and what it cannot.
	rt.route(http.MethodPost, "/api/v1/auth/otp/request", s.rateLimited(http.HandlerFunc(s.handleRequestOTP)))
	rt.route(http.MethodPost, "/api/v1/auth/otp/verify", s.rateLimited(http.HandlerFunc(s.handleVerifyOTP)))
	rt.route(http.MethodPost, "/api/v1/auth/staff/login", s.rateLimited(http.HandlerFunc(s.handleStaffLogin)))
	// Setting a first password from a code. Unauthenticated by necessity -
	// the person has no way in yet - so it is rate limited exactly like the
	// login endpoints beside it.
	rt.route(http.MethodPost, "/api/v1/auth/password-setup", s.rateLimited(http.HandlerFunc(s.handleRedeemPasswordSetup)))
	rt.route(http.MethodPost, "/api/v1/auth/logout", s.requireAuth(http.HandlerFunc(s.handleLogout)))
	rt.route(http.MethodPost, "/api/v1/auth/password", s.requireAuth(http.HandlerFunc(s.handleChangeOwnPassword)))

	rt.route(http.MethodGet, "/api/v1/me", s.requireAuth(http.HandlerFunc(s.handleMe)))

	// THE TWO FIELDS A PARENT OWNS. Their own pair rather than fields on
	// /me: that endpoint answers "who am I and what may I do" for every
	// audience, and a guardian's postal city has no business in a
	// therapist's session bootstrap. See migration 0107 for why the list
	// is email and city and not the mobile or the name.
	rt.route(http.MethodGet, "/api/v1/me/contact", s.requireAuth(http.HandlerFunc(s.handleGuardianContact)))
	rt.route(http.MethodPatch, "/api/v1/me/contact", s.requireAuth(http.HandlerFunc(s.handleSetGuardianContact)))
	rt.route(http.MethodGet, "/api/v1/children", s.requireAuth(http.HandlerFunc(s.handleChildren)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}", s.requireAuth(http.HandlerFunc(s.handleChild)))
	// The same screen as the six below it, in one request and one snapshot.
	// It replaces nothing: a caller that wants one part still asks for one part.
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/profile", s.requireAuth(http.HandlerFunc(s.handleChildProfile)))

	// The clinical history. Every one of these hangs off a child and inherits
	// the same gate: the store proves the child is visible inside the same
	// transaction as the read.
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/guardians", s.requireAuth(http.HandlerFunc(s.handleChildGuardians)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/appointments", s.requireAuth(http.HandlerFunc(s.handleAppointments)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/sessions", s.requireAuth(http.HandlerFunc(s.handleSessions)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/plans", s.requireAuth(http.HandlerFunc(s.handlePlans)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/reports", s.requireAuth(http.HandlerFunc(s.handleReports)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/notes", s.requireAuth(http.HandlerFunc(s.handleNotes)))

	// Addressed by its own identifier, with no child in the path: the policy
	// on progress_reports already requires can_access_child, and for a
	// guardian that the report is published.
	rt.route(http.MethodGet, "/api/v1/reports/{report_id}", s.requireAuth(http.HandlerFunc(s.handleReport)))

	// The home programme, and the only two endpoints that write.
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/activities", s.requireAuth(http.HandlerFunc(s.handleActivities)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/activity-log", s.requireAuth(http.HandlerFunc(s.handleActivityLog)))
	rt.route(http.MethodPost, "/api/v1/children/{child_id}/activities/{child_activity_id}/log", s.requireAuth(http.HandlerFunc(s.handleLogActivity)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/requests", s.requireAuth(http.HandlerFunc(s.handleRequests)))
	rt.route(http.MethodPost, "/api/v1/children/{child_id}/requests", s.requireAuth(http.HandlerFunc(s.handleSubmitRequest)))

	// Billing, read only. The portal never takes money.
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/invoices", s.requireAuth(http.HandlerFunc(s.handleInvoices)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/packages", s.requireAuth(http.HandlerFunc(s.handlePackages)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/balance", s.requireAuth(http.HandlerFunc(s.handleBalance)))
	rt.route(http.MethodGet, "/api/v1/invoices/{invoice_id}", s.requireAuth(http.HandlerFunc(s.handleInvoice)))

	// The live stream. See live_handlers.go before changing any of these.
	rt.route(http.MethodPost, "/api/v1/sessions/{session_id}/stream", s.requireAuth(http.HandlerFunc(s.handleOpenStream)))
	rt.route(http.MethodPost, "/api/v1/stream/close", s.requireAuth(http.HandlerFunc(s.handleCloseStream)))

	// The one endpoint not behind requireAuth, and the only one. A <video>
	// element cannot set an Authorization header, so this is authenticated by
	// the stream cookie - a strictly narrower credential than the session
	// token: one session, one camera, one user, fifteen minutes, revocable.
	rt.route(http.MethodGet, playbackPath, http.HandlerFunc(s.handleStreamMedia))

	// The centre-indexed reads. Same rows and same policies as the portal,
	// indexed by day and centre rather than by child - because a receptionist
	// opens a day, not a file.
	rt.route(http.MethodGet, "/api/v1/appointments", s.requireAuth(http.HandlerFunc(s.handleOpsAppointments)))
	rt.route(http.MethodGet, "/api/v1/sessions", s.requireAuth(http.HandlerFunc(s.handleOpsSessions)))
	rt.route(http.MethodGet, "/api/v1/reports", s.requireAuth(http.HandlerFunc(s.handleOpsReports)))
	rt.route(http.MethodGet, "/api/v1/invoices", s.requireAuth(http.HandlerFunc(s.handleOpsInvoices)))
	rt.route(http.MethodGet, "/api/v1/requests", s.requireAuth(http.HandlerFunc(s.handleOpsRequests)))

	// Booking. validate before book is the difference between a screen people
	// use and one they work around: it tells the receptionist the therapist is
	// busy WHILE she is choosing, not after the form is full.
	rt.route(http.MethodPost, "/api/v1/appointments/validate", s.requireAuth(http.HandlerFunc(s.handleValidateSlot)))

	// WHICH WINDOWS ARE FREE, rather than "is this one". The screen used to
	// have only the second question, so finding a gap in a busy day meant
	// proposing times until one stuck. Same rulebook: hbh.available_slots
	// runs every candidate through hbh.validate_slot.
	rt.route(http.MethodGet, "/api/v1/appointments/slots", s.requireAuth(http.HandlerFunc(s.handleAvailableSlots)))
	rt.route(http.MethodPost, "/api/v1/appointments", s.requireAuth(http.HandlerFunc(s.handleBookAppointment)))
	rt.route(http.MethodPatch, "/api/v1/appointments/{appointment_id}/status", s.requireAuth(http.HandlerFunc(s.handleAppointmentStatus)))

	// The session, from the appointment it belongs to.
	rt.route(http.MethodPost, "/api/v1/appointments/{appointment_id}/session", s.requireAuth(http.HandlerFunc(s.handleStartSession)))
	rt.route(http.MethodPatch, "/api/v1/sessions/{session_id}/close", s.requireAuth(http.HandlerFunc(s.handleCloseSession)))
	rt.route(http.MethodPut, "/api/v1/sessions/{session_id}/note", s.requireAuth(http.HandlerFunc(s.handleWriteNote)))

	// Publishing and billing. Each one is a rung on a ladder the database
	// owns, not a field this layer sets.
	// AUTHORING A REPORT. The write half of a domain that shipped with a
	// read half only: hbh_app has SELECT on progress_reports and nothing
	// more, so both of these go through SECURITY DEFINER functions that
	// ask for REPORT.WRITE and for access to the child (migration 0088).
	rt.route(http.MethodPost, "/api/v1/reports", s.requireAuth(http.HandlerFunc(s.handleCreateReport)))
	rt.route(http.MethodPatch, "/api/v1/reports/{report_id}", s.requireAuth(http.HandlerFunc(s.handleUpdateReport)))
	rt.route(http.MethodPost, "/api/v1/reports/{report_id}/publish", s.requireAuth(http.HandlerFunc(s.handlePublishReport)))
	// The top of the note ladder. PUT .../note writes one and it is born
	// INTERNAL; this is the only thing that puts it in front of a family.
	rt.route(http.MethodPost, "/api/v1/notes/{note_id}/publish", s.requireAuth(http.HandlerFunc(s.handlePublishSessionNote)))
	// Recorded consent. The schema will not let live viewing be switched on
	// without one, so without these two the rule could only be satisfied by
	// writing to the database by hand.
	rt.route(http.MethodPost, "/api/v1/guardians/{guardian_id}/consent", s.requireAuth(http.HandlerFunc(s.handleGrantGuardianConsent)))
	rt.route(http.MethodDelete, "/api/v1/guardians/{guardian_id}/consent", s.requireAuth(http.HandlerFunc(s.handleWithdrawGuardianConsent)))
	// A child's photograph, which is an attachment and not a link. Both are
	// authenticated, so no <img src> can reach one: the console fetches the
	// blob through the HTTP client. The upload is refused by the schema
	// unless a PHOTO_USE consent is on record, and the read is written to
	// the audit trail before the bytes go out.
	rt.route(http.MethodPost, "/api/v1/children/{child_id}/photo", s.requireAuth(http.HandlerFunc(s.handleUploadChildPhoto)))
	rt.route(http.MethodGet, "/api/v1/children/{child_id}/photo", s.requireAuth(http.HandlerFunc(s.handleChildPhoto)))
	rt.route(http.MethodPost, "/api/v1/invoices", s.requireAuth(http.HandlerFunc(s.handleCreateInvoice)))
	rt.route(http.MethodPost, "/api/v1/invoices/{invoice_id}/lines", s.requireAuth(http.HandlerFunc(s.handleAddInvoiceLine)))
	rt.route(http.MethodDelete, "/api/v1/invoices/{invoice_id}/lines/{line_id}", s.requireAuth(http.HandlerFunc(s.handleRemoveInvoiceLine)))
	rt.route(http.MethodPost, "/api/v1/invoices/{invoice_id}/issue", s.requireAuth(http.HandlerFunc(s.handleIssueInvoice)))
	rt.route(http.MethodPost, "/api/v1/invoices/{invoice_id}/payments", s.requireAuth(http.HandlerFunc(s.handleAddPayment)))
	rt.route(http.MethodPost, "/api/v1/children/{child_id}/packages", s.requireAuth(http.HandlerFunc(s.handleSellPackage)))

	// The other side of a door the portal already writes through.
	rt.route(http.MethodPatch, "/api/v1/requests/{request_id}", s.requireAuth(http.HandlerFunc(s.handleDecideRequest)))

	// INTAKE. The first line is the only write in this service that answers a
	// caller with no token: a family that is not a client yet, filling in a
	// form on the login screen. It is rate limited by address like the login
	// endpoints, and the database applies its own two limits on top - see
	// intake_handlers.go for why the refusal it gives back is not forwarded.
	rt.route(http.MethodPost, "/api/v1/enrolments", s.rateLimited(http.HandlerFunc(s.handleSubmitEnrolment)))
	rt.route(http.MethodGet, "/api/v1/enrolments", s.requireAuth(http.HandlerFunc(s.handleEnrolments)))
	rt.route(http.MethodGet, "/api/v1/enrolments/{application_id}", s.requireAuth(http.HandlerFunc(s.handleEnrolment)))
	rt.route(http.MethodPatch, "/api/v1/enrolments/{application_id}", s.requireAuth(http.HandlerFunc(s.handleEnrolmentStatus)))
	rt.route(http.MethodPost, "/api/v1/enrolments/{application_id}/convert", s.requireAuth(http.HandlerFunc(s.handleConvertEnrolment)))

	// The notification feed. One pair of routes for every audience, because
	// the policy on hbh.notifications is `user_id = current_user_id()` and a
	// second endpoint would be a second copy of it. There is deliberately no
	// route that CREATES a notification - see notification_handlers.go.
	rt.route(http.MethodGet, "/api/v1/notifications", s.requireAuth(http.HandlerFunc(s.handleNotifications)))
	rt.route(http.MethodPost, "/api/v1/notifications/{notification_id}/read", s.requireAuth(http.HandlerFunc(s.handleMarkNotificationRead)))

	// The satisfaction survey. skip is not an afterthought: without it the
	// cooldown never starts and the same question returns on every page load.
	rt.route(http.MethodGet, "/api/v1/nps/due", s.requireAuth(http.HandlerFunc(s.handleNPSDue)))
	rt.route(http.MethodPost, "/api/v1/nps/{survey_id}/response", s.requireAuth(http.HandlerFunc(s.handleSubmitNPS)))
	rt.route(http.MethodPost, "/api/v1/nps/{survey_id}/skip", s.requireAuth(http.HandlerFunc(s.handleSkipNPS)))
	rt.route(http.MethodGet, "/api/v1/nps/summary", s.requireAuth(http.HandlerFunc(s.handleNPSSummary)))

	// The service watching itself. Reads of hbh.api_request_log, which this
	// process writes one row of per request.
	rt.route(http.MethodPost, "/api/v1/family-messages/{guardian_id}/read", s.requireAuth(http.HandlerFunc(s.handleReadFamilyMessages)))
	rt.route(http.MethodGet, "/api/v1/family-contacts", s.requireAuth(http.HandlerFunc(s.handleFamilyContacts)))
	rt.route(http.MethodGet, "/api/v1/family-messages/{guardian_id}", s.requireAuth(http.HandlerFunc(s.handleFamilyMessages)))
	rt.route(http.MethodPost, "/api/v1/family-messages/{guardian_id}", s.requireAuth(http.HandlerFunc(s.handleSendFamilyMessage)))
	rt.route(http.MethodGet, "/api/v1/billing/ledger", s.requireAuth(http.HandlerFunc(s.handleBillingLedger)))
	rt.route(http.MethodGet, "/api/v1/billing/summary", s.requireAuth(http.HandlerFunc(s.handleBillingSummary)))
	rt.route(http.MethodGet, "/api/v1/dashboard/metrics", s.requireAuth(http.HandlerFunc(s.handleDashboardMetrics)))
	rt.route(http.MethodGet, "/api/v1/ops/health", s.requireAuth(http.HandlerFunc(s.handleOpsHealth)))
	rt.route(http.MethodGet, "/api/v1/ops/errors", s.requireAuth(http.HandlerFunc(s.handleOpsErrors)))

	// The centre's operating parameters. Read by anyone signed in - RLS
	// decides what that is - and written only through hbh.set_center_param,
	// which asks for SETTINGS.MANAGE and refuses the values that are not
	// settings at all.
	rt.route(http.MethodGet, "/api/v1/settings/params", s.requireAuth(http.HandlerFunc(s.handleCenterParams)))
	rt.route(http.MethodPatch, "/api/v1/settings/params/{code}", s.requireAuth(http.HandlerFunc(s.handleSetCenterParam)))
	rt.route(http.MethodDelete, "/api/v1/settings/params/{code}", s.requireAuth(http.HandlerFunc(s.handleClearCenterParam)))
	rt.route(http.MethodPatch, "/api/v1/settings/center", s.requireAuth(http.HandlerFunc(s.handleUpdateCenter)))
	rt.route(http.MethodGet, "/api/v1/settings/time-zones", s.requireAuth(http.HandlerFunc(s.handleTimeZones)))
	rt.route(http.MethodGet, "/api/v1/ops/activity", s.requireAuth(http.HandlerFunc(s.handleOpsActivity)))

	// WHICH SERVICES A THERAPIST OFFERS. Not part of registerCRUD: the
	// table is keyed on the pair and has no surrogate id, so it cannot be
	// addressed by the /{id} shape the others share. Without a row here
	// validate_slot answers THERAPIST_SERVICE_MISMATCH and a centre that
	// has everything else still cannot book.
	rt.route(http.MethodGet, "/api/v1/therapists/{therapist_id}/services", s.requireAuth(http.HandlerFunc(s.handleTherapistServices)))

	// AND THE SAME PAIR READ THE OTHER WAY. The booking screen asks "who
	// does this service", because a dropdown of every therapist lets
	// somebody choose one who does not - and validate_slot then answers
	// THERAPIST_SERVICE_MISMATCH about a fact it knew beforehand.
	rt.route(http.MethodGet, "/api/v1/services/{service_id}/therapists", s.requireAuth(http.HandlerFunc(s.handleServiceTherapists)))

	// EVERY deliverable pair, in one read. The booking screen offers the
	// two as a single choice, so an incompatible combination cannot be
	// expressed at all - and asking per service would be one request per
	// row of a dropdown, arriving in whatever order the network chose.
	rt.route(http.MethodGet, "/api/v1/service-therapists", s.requireAuth(http.HandlerFunc(s.handleServicePairs)))
	rt.route(http.MethodPost, "/api/v1/therapists/{therapist_id}/services", s.requireAuth(http.HandlerFunc(s.handleAddTherapistService)))
	rt.route(http.MethodDelete, "/api/v1/therapists/{therapist_id}/services/{service_id}", s.requireAuth(http.HandlerFunc(s.handleRemoveTherapistService)))

	// THE THERAPIST'S PROFILE. A family reads it while signed in - the
	// owner decided that, so no unauthenticated read enters this schema
	// and enrolment stays the only anonymous path.
	//
	// Consent and certificate-image release are endpoints of their own,
	// not fields on an edit: each is its own decision, and folded into a
	// general update either would ride along with a typo correction.
	rt.route(http.MethodPatch, "/api/v1/therapists/{therapist_id}/profile", s.requireAuth(http.HandlerFunc(s.handleUpdateTherapistProfile)))
	rt.route(http.MethodGet, "/api/v1/therapists/{therapist_id}/languages", s.requireAuth(http.HandlerFunc(s.handleTherapistLanguages)))
	rt.route(http.MethodPut, "/api/v1/therapists/{therapist_id}/languages", s.requireAuth(http.HandlerFunc(s.handleSetTherapistLanguage)))
	rt.route(http.MethodDelete, "/api/v1/therapists/{therapist_id}/languages/{lang_code}", s.requireAuth(http.HandlerFunc(s.handleRemoveTherapistLanguage)))

	rt.route(http.MethodGet, "/api/v1/therapists/{therapist_id}/certificates", s.requireAuth(http.HandlerFunc(s.handleTherapistCertificates)))
	rt.route(http.MethodPost, "/api/v1/therapists/{therapist_id}/certificates", s.requireAuth(http.HandlerFunc(s.handleAddTherapistCertificate)))
	rt.route(http.MethodPatch, "/api/v1/certificates/{certificate_id}/image", s.requireAuth(http.HandlerFunc(s.handleCertificateImage)))

	rt.route(http.MethodPost, "/api/v1/therapists/{therapist_id}/consent", s.requireAuth(http.HandlerFunc(s.handleTherapistConsent)))
	rt.route(http.MethodDelete, "/api/v1/therapists/{therapist_id}/consent", s.requireAuth(http.HandlerFunc(s.handleWithdrawTherapistConsent)))
	rt.route(http.MethodPost, "/api/v1/therapists/{therapist_id}/publish", s.requireAuth(http.HandlerFunc(s.handlePublishTherapistProfile)))

	// USERS, ROLES AND PERMISSIONS - the mechanism by which every other
	// permission in this system is handed out. Not one rule is checked in
	// the handlers: migration 0036 holds all of them.
	rt.route(http.MethodGet, "/api/v1/users", s.requireAuth(http.HandlerFunc(s.handleUsers)))
	rt.route(http.MethodPost, "/api/v1/users", s.requireAuth(http.HandlerFunc(s.handleCreateUser)))
	rt.route(http.MethodPatch, "/api/v1/users/{user_id}", s.requireAuth(http.HandlerFunc(s.handleUpdateUser)))
	rt.route(http.MethodDelete, "/api/v1/users/{user_id}", s.requireAuth(http.HandlerFunc(s.handleArchiveUser)))
	rt.route(http.MethodPut, "/api/v1/users/{user_id}/roles", s.requireAuth(http.HandlerFunc(s.handleSetUserRoles)))
	rt.route(http.MethodPost, "/api/v1/users/{user_id}/password-setup", s.requireAuth(http.HandlerFunc(s.handleIssuePasswordSetup)))
	rt.route(http.MethodGet, "/api/v1/roles", s.requireAuth(http.HandlerFunc(s.handleRoles)))
	rt.route(http.MethodPut, "/api/v1/roles/{code}/permissions", s.requireAuth(http.HandlerFunc(s.handleSetRolePermissions)))

	// A member of staff's scanned documents. The upload writes the file
	// and the row together - see staff_doc_handlers.go for why - and the
	// download is addressed by ROW, never by filename, so row level
	// security decides and there is no path a client can construct.
	//
	// Both are behind requireAuth. Unlike /api/v1/site-media, which is
	// open because it serves a public page, nothing here is ever public.
	rt.route(http.MethodPost, "/api/v1/users/{user_id}/documents", s.requireAuth(http.HandlerFunc(s.handleUploadStaffDoc)))
	rt.route(http.MethodGet, "/api/v1/staff-documents/{document_id}/file", s.requireAuth(http.HandlerFunc(s.handleStaffDocFile)))
	rt.route(http.MethodPost, "/api/v1/users/{user_id}/photo", s.requireAuth(http.HandlerFunc(s.handleUploadStaffPhoto)))
	rt.route(http.MethodGet, "/api/v1/users/{user_id}/photo", s.requireAuth(http.HandlerFunc(s.handleStaffPhoto)))
	rt.route(http.MethodGet, "/api/v1/permissions", s.requireAuth(http.HandlerFunc(s.handlePermissions)))

	// A photograph or an introduction film for the public site. The only
	// route in this service that writes a file rather than a row, and the
	// only one that checks a permission itself - see site_media_handlers.go
	// for why, and for what it refuses to let the client decide.
	rt.route(http.MethodPost, "/api/v1/site-media", s.requireAuth(http.HandlerFunc(s.handleSiteUpload)))
	// Reading one back, so the console can show what was just uploaded.
	//
	// NOT behind requireAuth, and that is a decision rather than an
	// oversight. This service authenticates with a bearer token in a header,
	// and an <img src> or a <video src> sends no headers - so an
	// authenticated route here would render a broken image to the person who
	// had just uploaded the file, with no way to tell whether it worked. The
	// alternative, fetching through the interceptor and rendering a blob,
	// means pulling a hundred-megabyte film into browser memory to show a
	// preview.
	//
	// What makes it acceptable: these are marketing assets for a page with
	// no login on it. Every one of them is bound for the open internet, and
	// the older ones - team-nermin.jpeg and its siblings - have been served
	// publicly by the site all along. An uploaded file is named by the
	// SHA-256 of its own contents, so the name cannot be guessed or
	// enumerated and knowing it means already having the file.
	//
	// STATED PLAINLY: a photograph uploaded but not yet published is
	// reachable by anyone holding its hash. That is the cost, it is small
	// for this content, and it would NOT be acceptable for anything
	// clinical - which is why nothing clinical is served from here.
	rt.route(http.MethodGet, "/api/v1/site-media/{name}", http.HandlerFunc(s.handleSiteMediaGet))

	s.registerCRUD(rt)

	rt.mux.Handle("/", http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
	}))

	// Outermost first. Recovery is outside logging so a panic still produces
	// a request line, and logging is outside everything else so a refusal by
	// CORS or by the rate limiter is still recorded.
	// The database request log sits INSIDE withRequestID and outside
	// everything else: it needs the id in order to record it, and it must see
	// the status of a request that CORS or the rate limiter refused - those
	// are exactly the ones an operator is looking for.
	return chain(rt.finish(),
		withRecover(s.log),
		withRequestID,
		withLogging(s.log),
		s.withRequestLog,
		withSecurityHeaders,
		withCORS(s.cfg.CORSOrigins),
	)
}

// router collects the routes so the method-not-allowed fallback can be
// registered once per PATH rather than once per route.
//
// The distinction is not cosmetic, and it cost a boot: the standard mux panics
// on a duplicate pattern, so the first path to gain a second method - GET and
// POST on .../requests - took the whole process down at startup. Registering
// the fallback per path also lets Allow name every method the path really
// accepts, instead of whichever one happened to be registered last.
type router struct {
	mux     *http.ServeMux
	methods map[string][]string
	order   []string
}

func newRouter() *router {
	return &router{mux: http.NewServeMux(), methods: map[string][]string{}}
}

// route registers a handler for one method on one path.
//
// Every handler is wrapped so the request log knows which TEMPLATE was
// matched. Taking it from the router's own constant rather than from the
// request means the recorded route is the one this service registered - and
// that a 404 records a sentinel instead of a path a stranger chose.
func (rt *router) route(method, pattern string, h http.Handler) {
	rt.mux.Handle(method+" "+pattern, noteRoute(pattern, h))
	if _, seen := rt.methods[pattern]; !seen {
		rt.order = append(rt.order, pattern)
	}
	rt.methods[pattern] = append(rt.methods[pattern], method)
}

// finish adds the fallback for every registered path.
//
// Without it the standard mux answers a method mismatch with a plain-text
// body, and a client that parses every response as JSON gets a parse error
// instead of the reason it was refused.
func (rt *router) finish() *http.ServeMux {
	for _, pattern := range rt.order {
		allow := strings.Join(rt.methods[pattern], ", ")
		rt.mux.Handle(pattern, noteRoute(pattern, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Allow", allow)
			writeError(w, r, http.StatusMethodNotAllowed, CodeMethodNotAllowed)
		})))
	}
	return rt.mux
}

func (s *Server) rateLimited(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		key := "unknown"
		if ip := s.clientIP(r); ip != nil {
			key = *ip
		}
		if !s.authLim.allow(key) {
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Detail: "RATE_LIMITED " + r.URL.Path, ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusTooManyRequests, CodeRateLimited)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleReady(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(r.Context()); err != nil {
		s.log.WarnContext(r.Context(), "not ready", "err", err)
		writeError(w, r, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}
