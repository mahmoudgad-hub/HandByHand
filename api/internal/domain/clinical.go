package domain

import (
	"encoding/json"
	"fmt"
	"time"
)

// Date is a calendar day with no time and no zone.
//
// It exists because a birth date and a report period are days, not instants,
// and rendering them as "2020-03-15T00:00:00Z" invites exactly the bug D-5
// exists to prevent: a client in Cairo reading that back as a local instant
// and landing on the 14th. An instant is timestamptz and stays UTC; a day is
// this.
type Date struct {
	time.Time
	Valid bool
}

// Scan reads a Postgres date. NULL is a valid answer, not an error.
func (d *Date) Scan(v any) error {
	switch t := v.(type) {
	case nil:
		d.Time, d.Valid = time.Time{}, false
		return nil
	case time.Time:
		d.Time, d.Valid = t, true
		return nil
	default:
		return fmt.Errorf("cannot scan %T into a Date", v)
	}
}

func (d Date) MarshalJSON() ([]byte, error) {
	if !d.Valid {
		return []byte("null"), nil
	}
	return []byte(`"` + d.Format("2006-01-02") + `"`), nil
}

// The three references below are flattened deliberately. A parent looking at
// an appointment wants the service, the therapist and the room named on the
// row; making the client fetch three lookup endpoints to render one line is
// how a screen ends up with a loading spinner per row.
type ServiceRef struct {
	ServiceID int    `json:"service_id"`
	NameAr    string `json:"name_ar"`
	KindCode  string `json:"kind_code"`
	ColorHex  string `json:"color_hex,omitempty"`
}

type TherapistRef struct {
	TherapistID int    `json:"therapist_id"`
	FullNameAr  string `json:"full_name_ar"`
	TitleAr     string `json:"title_ar,omitempty"`
}

// RoomRef carries the room's name and nothing else. rooms.notes_ar is
// internal, and a room is the one object in this domain that will eventually
// have a camera attached to it - so the habit of exposing only what the screen
// needs starts here, before there is anything dangerous to expose.
type RoomRef struct {
	RoomID int    `json:"room_id"`
	NameAr string `json:"name_ar"`
}

// Appointment is a booked slot.
//
// note_ar is not exposed. It is a free-text field written by whoever booked,
// and this service has no way to know whether a given row is a message to the
// family or a remark about them. The visibility ladder on session_notes says
// how this centre answers that question - a clinical text reaches a parent
// only when it is marked PARENT, is not a draft, and has been approved - and
// an appointment note has no such ladder. Withheld until it gets one.
type Appointment struct {
	AppointmentID int           `json:"appointment_id"`
	AppointmentNo string        `json:"appointment_no"`
	StartsAt      time.Time     `json:"starts_at"`
	EndsAt        time.Time     `json:"ends_at"`
	Status        string        `json:"status"`
	CancelReason  *string       `json:"cancel_reason,omitempty"`
	Service       *ServiceRef   `json:"service,omitempty"`
	Therapist     *TherapistRef `json:"therapist,omitempty"`
	Room          *RoomRef      `json:"room,omitempty"`

	// Child is present on the centre-indexed reads and absent on the
	// child-scoped ones, where it would repeat the path.
	Child *ChildRef `json:"child,omitempty"`

	// The session opened against this appointment, if one has been.
	//
	// Populated by the centre-indexed read only, so it stays absent from
	// the family's own appointment list. It exists so the console can stop
	// offering "start" on an appointment that already has a session:
	// hbh.start_session refuses that with HB022, and a button whose only
	// possible outcome is a refusal is a dead end, not a control.
	//
	// A pointer with omitempty, because "no session yet" and "a session
	// whose id is zero" are different facts and the client branches on it.
	SessionID     *int    `json:"session_id,omitempty"`
	SessionStatus *string `json:"session_status,omitempty"`
}

// Session is a therapy session that actually happened.
//
// abort_reason is withheld for the same reason as note_ar: it is staff prose
// about a session that went wrong, and it has no approval step.
type Session struct {
	SessionID     int           `json:"session_id"`
	AppointmentID *int          `json:"appointment_id,omitempty"`
	StartedAt     time.Time     `json:"started_at"`
	EndedAt       *time.Time    `json:"ended_at,omitempty"`
	Status        string        `json:"status"`
	Service       *ServiceRef   `json:"service,omitempty"`
	Therapist     *TherapistRef `json:"therapist,omitempty"`
	Room          *RoomRef      `json:"room,omitempty"`

	// Child is present on the centre-indexed reads and absent on the
	// child-scoped ones, where it would repeat the path.
	Child *ChildRef `json:"child,omitempty"`
}

// Goal is one target in a plan, with its most recent measurement.
//
// The percentages come from hbh.v_goal_progress, a security_invoker view - so
// the policies on plan_goals and goal_measurements apply to the caller exactly
// as they would to a direct read. A view that was not security_invoker would
// run as its owner and hand every centre's goals to anybody.
type Goal struct {
	GoalID           int      `json:"goal_id"`
	TitleAr          string   `json:"title_ar"`
	BaselinePct      *float64 `json:"baseline_pct,omitempty"`
	TargetPct        *float64 `json:"target_pct,omitempty"`
	Status           string   `json:"status"`
	SortOrder        int      `json:"sort_order"`
	LatestPct        *float64 `json:"latest_pct,omitempty"`
	LatestMeasuredOn Date     `json:"latest_measured_on"`
	MeasurementCount int64    `json:"measurement_count"`
}

type Plan struct {
	PlanID    int           `json:"plan_id"`
	TitleAr   string        `json:"title_ar"`
	StartDate Date          `json:"start_date"`
	EndDate   Date          `json:"end_date"`
	Status    string        `json:"status"`
	Service   *ServiceRef   `json:"service,omitempty"`
	Therapist *TherapistRef `json:"therapist,omitempty"`

	// Always an array, never null - see the note on Profile.Permissions.
	Goals []Goal `json:"goals"`
}

// ReportSummary is a progress report as it appears in a list.
//
// A guardian reaching one of these at all means the policy said PUBLISHED. A
// draft report is not hidden by this struct; it never arrives.
type ReportSummary struct {
	ReportID    int        `json:"report_id"`
	ReportNo    string     `json:"report_no"`
	TitleAr     string     `json:"title_ar"`
	PeriodStart Date       `json:"period_start"`
	PeriodEnd   Date       `json:"period_end"`
	Status      string     `json:"status"`
	PublishedAt *time.Time `json:"published_at,omitempty"`
	PlanID      *int       `json:"plan_id,omitempty"`
}

// Report adds the body and the frozen goal snapshot.
//
// GoalsSnapshot is passed through as stored. hbh.publish_report takes it once,
// at publication, and never reads the goals live again - so a report shows
// what was true when it was signed, and a later measurement cannot silently
// rewrite a document a parent has already read.
type Report struct {
	ReportSummary
	SummaryAr     *string         `json:"summary_ar,omitempty"`
	GoalsSnapshot json.RawMessage `json:"goals_snapshot,omitempty"`
}

// Note is a session note that has been published to the family.
//
// visibility and is_draft_flg are not fields here. For a guardian they are
// constants - PARENT and false - because the policy admits nothing else, and a
// field that can only hold one value teaches a client to check something the
// server already guaranteed.
type Note struct {
	NoteID    int    `json:"note_id"`
	SessionID int    `json:"session_id"`
	BodyAr    string `json:"body_ar"`
	// Visibility is INTERNAL or PARENT. It is returned because a screen that
	// cannot see it cannot tell a clinician which of these notes the family
	// is already reading - the internal one and the published one arrived
	// looking identical, and neither the reader nor the client could
	// distinguish them. A guardian only ever receives PARENT rows, so this
	// discloses nothing to them that the row itself does not.
	Visibility string     `json:"visibility"`
	CreatedAt  time.Time  `json:"created_at"`
	ApprovedAt *time.Time `json:"approved_at,omitempty"`
	AuthorAr   *string    `json:"author_ar,omitempty"`
}
