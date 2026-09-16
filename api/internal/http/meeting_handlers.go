package http

import (
	"net/http"
	"strconv"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/handbyhand/hbh/api/internal/meeting"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The door into an online consultation.
//
// THERE IS NO AUTHORIZATION CODE IN THIS FILE, and that is the design.
// hbh.authorize_meeting_entry asks every question - is this appointment yours,
// is it a consultation, has the invoice been paid, has the hour come, is the
// room still open - and answers with a named code. A second check here would be
// a second copy of the rule, and the day the copies disagreed the weaker one
// would decide. Rule 4.
//
// What this file owns is the ORDER, and the order is the whole of it:
//
//	  ask the database        -> a decision, and nothing written
//	  sign the pass           -> in this process, where the provider key lives
//	  RECORD that it exists   -> before anybody is told
//	  answer
//
// THE RECORD COMES BEFORE THE ANSWER because a Jitsi pass cannot be called
// back. Once it reaches a browser it works until it expires, so the only moment
// at which this service can still guarantee that an issued pass has an owner
// written down is BEFORE it hands it over. If the recording fails, nobody
// enters - which is the right trade for a consultation about a child.

// handleEnterConsultation issues one pass into one consultation.
func (s *Server) handleEnterConsultation(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	appointmentID, err := strconv.Atoi(r.PathValue("appointment_id"))
	if err != nil || appointmentID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	// A deployment with no working provider must say so here rather than
	// producing a pass nothing can open. Asked per request and not only at
	// startup, because a provider can be reconfigured under a running
	// process - and because the development one refuses in production,
	// which is a guarantee worth re-asserting at the moment it matters.
	if err := s.meetings.Usable(); err != nil {
		s.log.ErrorContext(r.Context(), "a consultation was asked for and no provider can carry it",
			"provider", s.meetings.Code(), "err", err)
		writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		return
	}

	grant, err := s.db.AuthorizeMeetingEntry(r.Context(), ident.Username, appointmentID)
	if err != nil {
		code := store.Code(err)
		if status, clientCode, ok := businessRefusal(code); ok {
			// EVERY REFUSAL IS RECORDED AS A DENY, including the ordinary
			// ones. "The hour has not come" and "somebody else's family
			// asked" are the same shape from here - a pass not issued - and
			// the difference between them is exactly what an audit trail is
			// for.
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail:   "CONSULT_ENTRY " + code + " appointment_id=" + strconv.Itoa(appointmentID),
				ClientIP: s.clientIP(r),
			})
			s.log.WarnContext(r.Context(), "consultation entry refused",
				"appointment_id", appointmentID, "code", code)
			writeError(w, r, status, clientCode)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	// The provider the ROOM was opened with, not the one configured today.
	// A centre that changes provider must not strand a consultation booked
	// last week - and if it has, this says so instead of minting a pass for
	// a room that is somewhere else.
	if grant.Provider != s.meetings.Code() {
		s.log.ErrorContext(r.Context(), "the room was opened with a provider this service is not configured for",
			"appointment_id", appointmentID, "room_provider", grant.Provider,
			"service_provider", s.meetings.Code())
		writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		return
	}

	pass, err := s.meetings.Mint(meeting.Grant{
		MeetingID:   grant.MeetingID,
		RoomRef:     grant.RoomRef,
		Provider:    grant.Provider,
		Moderator:   grant.Moderator,
		ExpiresAt:   grant.ExpiresAt,
		UserRef:     grant.UserRef,
		DisplayName: grant.DisplayName,
	})
	if err != nil {
		// The error may name the key or the account, so it goes to the log
		// and not to the family.
		s.log.ErrorContext(r.Context(), "the consultation pass could not be signed",
			"appointment_id", appointmentID, "provider", s.meetings.Code(), "err", err)
		writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		return
	}

	issuedAt := time.Now()
	if err := s.db.RecordMeetingToken(r.Context(), ident.Username, grant.MeetingID,
		meeting.Fingerprint(pass, meeting.Grant{RoomRef: grant.RoomRef, UserRef: grant.UserRef}, issuedAt),
		grant.Moderator, grant.ExpiresAt, s.clientIP(r)); err != nil {

		// SIGNED AND NOT RECORDED. The pass exists in this function's memory
		// and nowhere else, and it dies here - which is why this is the
		// order. Answering anyway would put a working credential into a
		// browser with nothing anywhere saying who holds it.
		s.log.ErrorContext(r.Context(), "a consultation pass was signed and could not be recorded - it is being discarded",
			"appointment_id", appointmentID, "meeting_id", grant.MeetingID, "err", err)
		writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		return
	}

	// THE FIELDS HERE ARE SAFE TO WRITE DOWN. The appointment, the room's
	// own identifier, the window and whether this pass runs the room - no
	// token, no room name, no display name. The first is a credential and
	// the last two are a person and a place.
	s.audit.Record(r.Context(), audit.Event{
		Action: audit.ActionLogin, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail: "CONSULT_ENTRY meeting_id=" + strconv.FormatInt(grant.MeetingID, 10) +
			" appointment_id=" + strconv.Itoa(appointmentID),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusCreated, domain.MeetingPass{
		Provider:    grant.Provider,
		Domain:      pass.Domain,
		Room:        pass.Room,
		Token:       pass.Token,
		DisplayName: grant.DisplayName,
		Moderator:   grant.Moderator,
		ExpiresAt:   grant.ExpiresAt,
	})
}
