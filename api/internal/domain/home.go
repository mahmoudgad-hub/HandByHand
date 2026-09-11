package domain

import "time"

// The home programme: what the therapist asked the family to practise at
// home, and what the family reported back.

// Activity is one assigned exercise, with the family's recent adherence.
//
// The adherence figures come from hbh.v_activity_adherence, a
// security_invoker view, so the policies apply to the caller exactly as they
// would on a direct read.
type Activity struct {
	ChildActivityID int    `json:"child_activity_id"`
	ActivityID      int    `json:"activity_id"`
	TitleAr         string `json:"title_ar"`
	HowToAr         string `json:"how_to_ar,omitempty"`
	InstructionsAr  string `json:"instructions_ar,omitempty"`
	TimesPerWeek    int    `json:"times_per_week"`
	MinutesEach     int    `json:"minutes_each"`
	StartDate       Date   `json:"start_date"`
	EndDate         Date   `json:"end_date"`

	// The last seven days, as the view computes them. DoneLast7 is a count,
	// not a percentage, so a family that was asked for three sessions and did
	// three reads as complete rather than as 43% of a week.
	DoneLast7    int64    `json:"done_last_7"`
	AdherencePct *float64 `json:"adherence_pct,omitempty"`
	LastDoneOn   Date     `json:"last_done_on"`
}

// ActivityLogEntry is one day the family reported on.
type ActivityLogEntry struct {
	LogID           int64  `json:"log_id"`
	ChildActivityID int    `json:"child_activity_id"`
	LogDate         Date   `json:"log_date"`
	Done            bool   `json:"done"`
	ParentNoteAr    string `json:"parent_note_ar,omitempty"`
}

// Request is something the family asked the centre for.
//
// DecisionNoteAr is included because it is written FOR the family - it is the
// answer to their own question - unlike a session note, which is written about
// the child and has a publication step before it reaches anybody.
type Request struct {
	RequestID      int        `json:"request_id"`
	RequestNo      string     `json:"request_no"`
	KindCode       string     `json:"kind_code"`
	Status         string     `json:"status"`
	BodyAr         string     `json:"body_ar,omitempty"`
	PreferredAt    *time.Time `json:"preferred_at,omitempty"`
	AppointmentID  *int       `json:"appointment_id,omitempty"`
	CreatedAt      time.Time  `json:"created_at"`
	DecidedAt      *time.Time `json:"decided_at,omitempty"`
	DecisionNoteAr string     `json:"decision_note_ar,omitempty"`
}

// NewRequest is what a family sends to open one.
type NewRequest struct {
	KindCode      string     `json:"kind_code"`
	BodyAr        string     `json:"body_ar"`
	AppointmentID *int       `json:"appointment_id"`
	PreferredAt   *time.Time `json:"preferred_at"`
}
