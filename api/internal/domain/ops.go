package domain

import "time"

// The operations app reads the same data as the portal, indexed by the CENTRE
// and the DAY rather than by a child.
//
// That difference is not cosmetic. A guardian enters through their child; a
// receptionist opens a day. Serving the second from the first means one request
// per child and a merge in the browser - dozens of calls to draw one page,
// ordering and paging broken, and no knowledge of a child nobody asked about.
//
// EVERY ROW CARRIES NAMES, NOT ONLY IDENTIFIERS. A day view that returned
// therapist_id alone would need a lookup per row, which is the same defect in
// a smaller box. The identifier is there too, because the screen needs it to
// navigate.

// ChildRef names a child on a row that is not about the child.
type ChildRef struct {
	ChildID    int    `json:"child_id"`
	ChildNo    string `json:"child_no"`
	FullNameAr string `json:"full_name_ar"`
}

// PersonRef names a user - the author of a report, the guardian who asked.
type PersonRef struct {
	UserID     int    `json:"user_id"`
	FullNameAr string `json:"full_name_ar"`
}

// GuardianRef names the family member behind a request.
//
// IT HANGS OFF guardian_id, NOT user_id, and that distinction is the
// whole reason it is not a PersonRef. A guardian in this schema is a
// person the centre knows; an account is optional. A family that filled
// in a paper form, or one converted from an enrolment application, has a
// guardians row and no user - hbh.convert_enrolment creates exactly that.
//
// Keying the name to the account made every such request arrive with no
// guardian at all, so reception saw a request and could not see WHO asked,
// which is the one thing that screen exists to answer.
//
// UserID stays, as a pointer, because a screen that wants to open the
// person's account needs to know whether there is one.
type GuardianRef struct {
	GuardianID int    `json:"guardian_id"`
	FullNameAr string `json:"full_name_ar"`
	Mobile     string `json:"mobile,omitempty"`
	UserID     *int   `json:"user_id,omitempty"`
}

// OpsReport is a progress report as the centre sees it: every report,
// including the drafts a family may not see.
//
// The visibility ladder is unchanged - it is the POLICY that admits a draft to
// staff and withholds it from a guardian, and this struct is simply what comes
// back when staff ask. Status is exposed so a screen can show which are still
// drafts, which is the entire point of the list.
type OpsReport struct {
	ReportID    int        `json:"report_id"`
	ReportNo    string     `json:"report_no"`
	TitleAr     string     `json:"title_ar"`
	PeriodStart Date       `json:"period_start"`
	PeriodEnd   Date       `json:"period_end"`
	Status      string     `json:"status"`
	PublishedAt *time.Time `json:"published_at,omitempty"`
	Child       *ChildRef  `json:"child,omitempty"`
	PublishedBy *PersonRef `json:"published_by,omitempty"`
}

// OpsInvoice is an invoice as the centre sees it.
//
// Amounts are exact decimal strings, as everywhere else money appears (D-25).
// The currency travels with the amount and is never assumed.
type OpsInvoice struct {
	InvoiceID    int       `json:"invoice_id"`
	InvoiceNo    string    `json:"invoice_no"`
	IssueDate    Date      `json:"issue_date"`
	DueDate      Date      `json:"due_date"`
	CurrencyCode string    `json:"currency_code"`
	TotalAmt     Money     `json:"total_amt"`
	PaidAmt      Money     `json:"paid_amt"`
	Status       string    `json:"status"`
	Child        *ChildRef `json:"child,omitempty"`
}

// OpsRequest is a family's request as reception sees it.
//
// This is the other side of a door the portal already writes through: a
// guardian opens a request, and this is where it is read and decided.
type OpsRequest struct {
	RequestID      int          `json:"request_id"`
	RequestNo      string       `json:"request_no"`
	KindCode       string       `json:"kind_code"`
	Status         string       `json:"status"`
	BodyAr         string       `json:"body_ar,omitempty"`
	PreferredAt    *time.Time   `json:"preferred_at,omitempty"`
	AppointmentID  *int         `json:"appointment_id,omitempty"`
	CreatedAt      time.Time    `json:"created_at"`
	DecidedAt      *time.Time   `json:"decided_at,omitempty"`
	DecisionNoteAr string       `json:"decision_note_ar,omitempty"`
	Child          *ChildRef    `json:"child,omitempty"`
	Guardian       *GuardianRef `json:"guardian,omitempty"`
}

// SlotCheck is what validate_slot answers.
//
// It exists so a screen can tell somebody the therapist is busy WHILE they are
// choosing, instead of after they have filled in the whole form. Reason is a
// code, never a sentence: the Arabic lives in the translation files.
type SlotCheck struct {
	OK     bool   `json:"ok"`
	Reason string `json:"reason"`
}

// Slot is one bookable window: when, and in which free room.
//
// It comes from hbh.available_slots, which passes every candidate through
// hbh.validate_slot - the same function the booking itself goes through. So a
// slot in this list is one the service has already said yes to, on the
// therapist, the room, the working hours, the closures and the existing
// diary.
//
// WHAT IT HAS NOT BEEN ASKED ABOUT IS THE CHILD. The child is chosen after
// the slot, so a family already booked elsewhere at that hour is refused at
// confirm with CHILD_BUSY. "Free" here means free for the therapist and the
// room, which is what the receptionist is choosing between.
type Slot struct {
	StartsAt   time.Time `json:"starts_at"`
	EndsAt     time.Time `json:"ends_at"`
	RoomID     int       `json:"room_id"`
	RoomNameAr string    `json:"room_name_ar"`
}
