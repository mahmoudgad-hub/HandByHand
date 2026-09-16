package domain

import "time"

// The three things a family or an operator meets outside the clinical record:
// an application from someone who is not a client yet, a satisfaction survey,
// and the service's own request log.
//
// They share nothing but their newness, so they share a file rather than a
// pretence of a common shape.

// Enrolment is an application from a family with no account.
//
// It is the first row in this schema written by somebody the system has never
// authenticated, which is why every field here is UNTRUSTED TEXT: a name, a
// mobile, a paragraph about a child, typed by whoever found the login page. It
// is quarantined in its own table until a person at the centre reads it and
// converts it - hbh.convert_enrolment - and only then does a guardian and a
// child exist.
//
// WHAT IS NOT ON THIS STRUCT, and why:
//
//   - client_ip. It is kept on the row for the per-address rate limit and for
//     the log, and it is a household's approximate location. The queue screen
//     needs a name and a number to call back; it does not need where the
//     family was sitting.
//   - center_id, assigned_to, decided_by, created_by. Internal bookkeeping.
//     The caller is already inside exactly one centre, because the policy saw
//     to that, so echoing the identifier back tells a screen nothing.
type Enrolment struct {
	ApplicationID int    `json:"application_id"`
	ApplicationNo string `json:"application_no"`
	Status        string `json:"status"`

	ParentNameAr         string `json:"parent_name_ar"`
	ParentMobile         string `json:"parent_mobile"`
	ParentEmail          string `json:"parent_email,omitempty"`
	RelationshipCode     string `json:"relationship_code"`
	AddressAr            string `json:"address_ar,omitempty"`
	PreferredContactTime string `json:"preferred_contact_time,omitempty"`

	ChildNameAr       string `json:"child_name_ar"`
	ChildBirthDate    Date   `json:"child_birth_date"`
	ChildGender       string `json:"child_gender"`
	MainConcernAr     string `json:"main_concern_ar,omitempty"`
	PreviousTherapyAr string `json:"previous_therapy_ar,omitempty"`

	PreferredService *ServiceRef `json:"preferred_service,omitempty"`
	SourceCode       string      `json:"source_code"`
	SubmittedAt      time.Time   `json:"submitted_at"`

	ContactedAt    *time.Time `json:"contacted_at,omitempty"`
	AssessmentAt   *time.Time `json:"assessment_at,omitempty"`
	ContactNoteAr  string     `json:"contact_note_ar,omitempty"`
	DecidedAt      *time.Time `json:"decided_at,omitempty"`
	DecisionNoteAr string     `json:"decision_note_ar,omitempty"`

	// Set once the application became a family. Both are present or neither
	// is: hbh.convert_enrolment writes them in one statement.
	ConvertedGuardianID *int `json:"converted_guardian_id,omitempty"`
	ConvertedChildID    *int `json:"converted_child_id,omitempty"`

	ActiveFlg bool `json:"active_flg"`

	// ONE APPLICATION IS ONE CHILD, so a family with two children sends two.
	// That is right - each child needs their own birth date, their own main
	// concern, and eventually their own file - and hbh.convert_enrolment
	// attaches the second child to the parent already on record rather than
	// duplicating them.
	//
	// The hazard is on the SCREEN, not in the data: reception sees two rows
	// with one mobile number, and the queue has a DUPLICATE status sitting
	// right there. Marking the second one duplicate is the obvious mistake,
	// and it would quietly leave a real child unenrolled with no error
	// anywhere. These two fields exist so the screen can say "siblings"
	// where it would otherwise say nothing.
	//
	// Both are counted over enrolment_applications alone, deliberately: the
	// same table means the same policy, so a caller never sees a count that
	// includes rows they may not read.
	SiblingApplications int  `json:"sibling_applications"`
	FamilyAlreadyHere   bool `json:"family_already_here"`
}

// Converted is what hbh.convert_enrolment answers: the family that now exists.
type Converted struct {
	GuardianID int    `json:"guardian_id"`
	ChildID    int    `json:"child_id"`
	ChildNo    string `json:"child_no"`
}

// NPSPrompt is the question to put on the screen right now, if there is one.
//
// The TEXT comes from the database and is not a code, unlike every error this
// service returns. That is deliberate and it is not an exception to D-11: an
// error code is a fixed vocabulary the interface translates, while a survey
// question is content the centre writes, edits, and replaces without a
// release. A question hardcoded in Angular could not be changed by the person
// who owns the question.
//
// ContextKind and ContextID say what the question is ABOUT - the session that
// just ended, the report that was published - and must be returned unchanged
// with the answer or the cooldown records the wrong thing.
type NPSPrompt struct {
	SurveyID           int    `json:"survey_id"`
	Code               string `json:"code"`
	QuestionAr         string `json:"question_ar"`
	FollowupQuestionAr string `json:"followup_question_ar"`
	ContextKind        string `json:"context_kind,omitempty"`
	ContextID          *int   `json:"context_id,omitempty"`
}
