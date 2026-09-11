// Package domain holds the entities this service reads.
//
// It holds no business rules. Every rule about who may see what lives in
// PL/pgSQL and in the row level security policies, because Oracle remains
// production and a rule written twice is a rule that will disagree with
// itself. See CLAUDE.md, rules 2 and 3.
package domain

// User is the authenticated account.
type User struct {
	UserID     int     `json:"user_id"`
	CenterID   int     `json:"center_id"`
	Username   string  `json:"username"`
	FullNameAr string  `json:"full_name_ar"`
	UserType   string  `json:"user_type"`
	Status     string  `json:"status"`
	Mobile     *string `json:"mobile,omitempty"`

	// TherapistID is this account's row in hbh.therapists, when it has one.
	//
	// Nil for reception, for an administrator, for anybody who does not see
	// children - which is why it is a pointer and omitted rather than zero:
	// "not a therapist" and "therapist number 0" must not read alike.
	//
	// IT IS NOT A PERMISSION. Every rule about what a therapist may see is
	// already in a policy; this only answers "which of these rows are MINE",
	// which is a question about a screen's default filter. /my-day asked it
	// and had no way to find out, so it showed the whole centre's day to a
	// clinician who wanted their own six appointments.
	TherapistID *int `json:"therapist_id,omitempty"`
}

// Center is the tenant. Currency, time zone and weekend are data, not code:
// a second centre in another country needs a row, not a release.
type Center struct {
	CenterID     int     `json:"center_id"`
	Code         string  `json:"code"`
	NameAr       string  `json:"name_ar"`
	CountryCode  string  `json:"country_code"`
	CurrencyCode string  `json:"currency_code"`
	TimeZone     string  `json:"time_zone"`
	WeekendDays  []int16 `json:"weekend_days"`
}

// Profile is what GET /api/v1/me answers with.
type Profile struct {
	User        User     `json:"user"`
	Center      Center   `json:"center"`
	Permissions []string `json:"permissions"`
}

// Child is a child as the caller is allowed to see them. Reaching this struct
// at all means hbh.can_access_child() said yes; there is no field on it that
// the caller was not entitled to.
type Child struct {
	ChildID    int    `json:"child_id"`
	ChildNo    string `json:"child_no"`
	FullNameAr string `json:"full_name_ar"`
	BirthDate  Date   `json:"birth_date"`
	Gender     string `json:"gender"`

	// Status is the child's standing at the centre - ACTIVE, GRADUATED,
	// WITHDRAWN. ActiveFlg is whether the RECORD is archived. They answer
	// different questions and a screen needs both: a graduated child is
	// still a live record, and an archived record is not a graduated child.
	//
	// ActiveFlg was missing here while every other resource carried it, so
	// the operations console could not tell an archived child from a live
	// one - and archiving appeared to do nothing at all.
	Status    string `json:"status"`
	ActiveFlg bool   `json:"active_flg"`

	// The guardian's own view of this child. Nil for staff, who reach the
	// child through a permission rather than through a link.
	Link *GuardianLink `json:"link,omitempty"`
}

// GuardianLink is the guardian-to-child relationship and the two switches
// hanging off it. CanViewLive defaults to false in the schema: watching a
// child in a therapy session is the most sensitive thing this system does, and
// it is granted deliberately or not at all.
type GuardianLink struct {
	RelationshipCode string `json:"relationship_code"`
	IsPrimary        bool   `json:"is_primary"`
	CanViewLive      bool   `json:"can_view_live"`
	CanViewReports   bool   `json:"can_view_reports"`
}
