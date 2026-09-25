package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

// Generic CRUD over a declared set of resources.
//
// WHY A TABLE AND NOT SIXTY HANDLERS. Sixteen resources times five
// operations is eighty places to forget the same four things: pin the centre
// on insert, refuse a column the client should not set, never hard-delete, and
// write the audit line. One code path cannot forget them unevenly. What varies
// between resources is data - the table, the key, the columns - so it is
// written as data.
//
// WHY THIS IS NOT AN INJECTION SURFACE. Every identifier that reaches SQL -
// table, primary key, column name - comes from the constants in this file.
// Nothing from a request is ever interpolated: request values travel as bound
// parameters, and a request KEY that is not in the resource's allow list is a
// 400 rather than a column name. Grep for fmt.Sprintf below and check each
// one: the arguments are all resource fields.
//
// WHAT THE DATABASE STILL DECIDES. All of it. Every statement here runs as
// hbh_app under the policies from migration 0012, so an INSERT without
// CATALOG.MANAGE is refused by the engine, not by this file. There is no
// permission check in this package and there must not be one.

// Resource is one thing the operations app can manage.
type Resource struct {
	// Name is the URL segment: /api/v1/<Name>.
	Name string
	// Param is the path parameter for a single row, e.g. "child_id". It
	// matters because the portal already routes /children/{child_id}.
	Param string

	table string
	pk    string

	// insertCols and updateCols are allow lists. A key outside them is a
	// refusal, never a column name.
	//
	// center_id is in NEITHER, deliberately: the server derives it from the
	// caller (D-3). A client that could name the centre could write a child
	// into another tenant.
	//
	// active_flg and deleted_at are in neither either: they are the soft
	// delete, and it has its own path.
	insertCols []string
	updateCols []string

	// hide names columns that must never leave the server.
	hide []string

	// mask names columns that come back null unless a condition holds.
	//
	// IT EXISTS BECAUSE RLS FILTERS ROWS AND NOT COLUMNS.
	// p_therapists_select admits any authenticated user of the centre -
	// rightly, a parent choosing an appointment must see who the
	// therapists are - and this code then returned the whole row,
	// personal mobile number included. Verified against a running build,
	// not deduced.
	//
	// THE CONDITION IS A ROW EXPRESSION, not just a fact about the
	// caller, and that second dimension was missing at first. The three
	// profile tables gate on profile_status = 'PUBLISHED'; the columns on
	// the therapist row itself did not, so a DRAFT biography - the most
	// personal field on the profile, a paragraph somebody wrote about
	// themselves - reached every family at the centre before its author
	// had consented to publishing it. The console session found it by
	// reading a draft profile as a guardian.
	//
	// IS THIS A RULE IN THE WRONG PLACE? No, and the distinction matters.
	// This file names columns and a predicate; the DATABASE evaluates the
	// predicate, with the same functions the policies use. What would
	// break rule 4 is deciding in Go - reading the caller's type and
	// choosing a query - and that is exactly what this avoids.
	//
	// Not the same as hide: hide is for things no client ever receives,
	// like a camera's path. These are things some callers read on some
	// rows.
	mask []maskRule

	// money names numeric columns to render as exact decimal strings (D-25).
	money []string

	// search is the allow list of columns a free-text term may match.
	//
	// EMPTY MEANS THE RESOURCE TAKES NO TERM, and the handler answers 400
	// rather than ignoring one - which is exactly what this code used to
	// do to every search box in the console.
	//
	// Two rules decide what goes in it, and neither is "every text column":
	//
	//   A masked column NEVER goes here. therapists.mobile is nulled for
	//   anyone but staff or its owner, and a term that filters on it would
	//   hand a guardian a yes/no oracle over the number the mask exists to
	//   withhold - the search would leak precisely what the projection
	//   does not. Search only what the caller may already read.
	//
	//   national_id NEVER goes here either, on children or on guardians.
	//   It is an identity document, not a workflow lookup; reception finds
	//   a family by name or by the number they are calling from. A search
	//   box over it is a confirmation service for a number somebody
	//   already has.
	//
	// Long prose columns are left out for a duller reason: how_to_ar and
	// the survey question text are paragraphs, and matching a substring
	// inside them returns rows nobody was looking for.
	search []string

	order string
}

// maskRule is one group of columns and the condition under which they may
// be read.
//
// when is a SQL boolean expression written IN THIS FILE and nowhere else.
// It may refer to the row as t, and to the schema's own predicates -
// hbh.current_user_is_staff(), hbh.current_user_id(). Nothing from a
// request reaches it: a request supplies values, which travel as bound
// parameters, and never fragments of SQL.
type maskRule struct {
	cols []string
	when string
}

// resources is the whole allow list. A table that is not here cannot be
// reached by this code at all, whatever a URL says.
//
// Note the columns that are absent from updateCols on purpose:
//
//   - treatment_plans.status. It is a state machine with a transition
//     trigger, and rule 5 says no free update of a status column. Goals,
//     children and therapists carry a plain CHECK rather than a machine, so
//     their status is an ordinary field.
//   - cameras.gateway_path is writable but never readable - see hide.
var resources = []Resource{
	{
		Name: "services", Param: "service_id", table: "hbh.services", pk: "service_id",
		// creates_session_flg and needs_caseload_flg, from 0118, are the two
		// that decide whether an appointment for this service opens a therapy
		// session and whether it wants a caseload row first. A consultation
		// sets both false.
		//
		// SAFE TO ADD WITHOUT TOUCHING THE CONSOLE. A key absent from the body
		// is skipped rather than nulled - see bind() - so a form that has
		// never heard of them leaves them at their database default of true,
		// which is what every service in the table already means.
		insertCols: []string{"branch_id", "code", "name_ar", "name_en", "kind_code", "default_duration_min", "color_hex", "sort_order", "creates_session_flg", "needs_caseload_flg"},
		updateCols: []string{"branch_id", "code", "name_ar", "name_en", "kind_code", "default_duration_min", "color_hex", "sort_order", "creates_session_flg", "needs_caseload_flg"},
		search:     []string{"code", "name_ar", "name_en"},
		order:      "sort_order, service_id",
	},
	{
		// notes_ar is the centre's own note about a room, and the room list
		// is readable by every user of the centre. domain.RoomRef has said
		// since batch 2 that this column is internal; this is the same
		// statement made where it is actually enforced.
		Name: "rooms", Param: "room_id", table: "hbh.rooms", pk: "room_id",
		insertCols: []string{"branch_id", "code", "name_ar", "name_en", "notes_ar"},
		updateCols: []string{"branch_id", "code", "name_ar", "name_en", "notes_ar"},
		mask:       []maskRule{{cols: []string{"notes_ar"}, when: "hbh.current_user_is_staff()"}},
		search:     []string{"code", "name_ar", "name_en"},
		order:      "code, room_id",
	},
	{
		// The camera path and the credential name are writable by an
		// administrator and readable by nobody through this API. CLAUDE.md:
		// no camera link, address or credential anywhere a client reaches.
		Name: "cameras", Param: "camera_id", table: "hbh.cameras", pk: "camera_id",
		insertCols: []string{"branch_id", "room_id", "code", "name_ar", "gateway_path", "credential_ref", "status"},
		updateCols: []string{"branch_id", "room_id", "code", "name_ar", "gateway_path", "credential_ref", "status"},
		hide:       []string{"gateway_path", "credential_ref"},
		order:      "code, camera_id",
	},
	{
		Name: "activity-library", Param: "activity_id", table: "hbh.activity_library", pk: "activity_id",
		insertCols: []string{"code", "title_ar", "how_to_ar", "service_id", "age_from_mon", "age_to_mon"},
		updateCols: []string{"code", "title_ar", "how_to_ar", "service_id", "age_from_mon", "age_to_mon"},
		search:     []string{"code", "title_ar"},
		order:      "title_ar, activity_id",
	},
	{
		Name: "service-packages", Param: "package_id", table: "hbh.service_packages", pk: "package_id",
		insertCols: []string{"service_id", "code", "name_ar", "sessions_cnt", "price_amt", "validity_days"},
		updateCols: []string{"service_id", "code", "name_ar", "sessions_cnt", "price_amt", "validity_days"},
		money:      []string{"price_amt"},
		order:      "name_ar, package_id",
	},
	{
		// A guardian may READ this table - the policy admits any
		// authenticated user of the centre, because a parent choosing an
		// appointment has to see who the therapists are. What they may not
		// read is the therapist's personal mobile number, or the account
		// identifier that links this person to a login.
		Name: "therapists", Param: "therapist_id", table: "hbh.therapists", pk: "therapist_id",
		insertCols: []string{"branch_id", "user_id", "full_name_ar", "mobile", "title_ar", "status"},
		// ONLY THE COLUMNS THE CENTRE OWNS. The profile columns are not
		// here and were briefly: adding them meant a therapist could only
		// edit their own biography through a route whose policy demands
		// STAFF.MANAGE, and widening that policy would have handed them
		// status, user_id and branch_id as well - RLS grants rows, not
		// columns. They move through hbh.update_therapist_profile, which
		// names them.
		//
		// profile_status and the consent columns are absent for a
		// stronger reason: a status is a state machine (rule 5), and a
		// consent a caller can write for themselves is not a consent.
		updateCols: []string{"branch_id", "user_id", "full_name_ar", "mobile", "title_ar", "status"},
		mask: []maskRule{
			// The centre's own fields. A personal mobile number, and the
			// account identifiers behind the bookkeeping.
			{
				cols: []string{"mobile", "user_id", "consent_by", "published_by"},
				when: "hbh.current_user_is_staff() OR t.user_id = hbh.current_user_id()",
			},
			// THE PROFILE, WHICH IS NOT PUBLIC UNTIL IT IS PUBLISHED.
			//
			// The three profile tables carried this condition from the
			// start and these columns did not, so a DRAFT biography - a
			// paragraph somebody wrote about themselves, in their own
			// voice - reached every family at the centre before its
			// author had agreed to publish it. profile_status and the
			// recorded consent exist to prevent exactly that, and they
			// were guarding the side rooms while the front door stood
			// open.
			//
			// The condition is the same one the policies use, written
			// once more because a projection cannot borrow a policy.
			{
				cols: []string{"bio_ar", "practice_since_year", "age_from_mon", "age_to_mon"},
				when: "t.profile_status = 'PUBLISHED'" +
					" OR hbh.current_user_is_staff()" +
					" OR t.user_id = hbh.current_user_id()",
			},
		},
		// NOT mobile: it is masked above. See the note on Resource.search.
		search: []string{"full_name_ar", "title_ar"},
		order:  "full_name_ar, therapist_id",
	},
	{
		Name: "working-hours", Param: "working_hour_id", table: "hbh.therapist_working_hours", pk: "working_hour_id",
		insertCols: []string{"therapist_id", "weekday", "start_time", "end_time"},
		updateCols: []string{"therapist_id", "weekday", "start_time", "end_time"},
		order:      "therapist_id, weekday, working_hour_id",
	},
	// WHICH SERVICES A THERAPIST OFFERS is NOT in this table, and the
	// reason is mechanical rather than a judgement: hbh.therapist_services
	// has a composite primary key (therapist_id, service_id) and no
	// surrogate id, so every route here - which addresses a row by one
	// integer - cannot name a row of it. It has its own endpoints in
	// store/therapist_services.go.
	{
		Name: "caseload", Param: "caseload_id", table: "hbh.caseload", pk: "caseload_id",
		insertCols: []string{"therapist_id", "child_id", "service_id", "is_primary_flg"},
		updateCols: []string{"therapist_id", "child_id", "service_id", "is_primary_flg"},
		order:      "child_id, caseload_id",
	},
	{
		Name: "children", Param: "child_id", table: "hbh.children", pk: "child_id",
		insertCols: []string{"branch_id", "child_no", "full_name_ar", "birth_date", "gender", "national_id", "status"},
		updateCols: []string{"branch_id", "child_no", "full_name_ar", "birth_date", "gender", "national_id", "status"},
		// DECLARED BUT NOT REACHED, and deliberately left here.
		//
		// registerCRUD skips GET on /children: the portal's handleChildren
		// answers it, and that one already filtered and paged properly -
		// which is why the children box was the one search in the console
		// that worked. These are the same two columns it matches, written
		// where every other resource's are, so the day the route is
		// unified the answer does not quietly change.
		search: []string{"full_name_ar", "child_no"},
		order:  "full_name_ar, child_id",
	},
	{
		Name: "guardians", Param: "guardian_id", table: "hbh.guardians", pk: "guardian_id",
		insertCols: []string{"branch_id", "user_id", "full_name_ar", "mobile", "national_id", "email", "city", "relationship"},
		updateCols: []string{"branch_id", "user_id", "full_name_ar", "mobile", "national_id", "email", "city", "relationship"},
		search:     []string{"full_name_ar", "mobile", "email"},
		order:      "full_name_ar, guardian_id",
	},
	{
		Name: "plans", Param: "plan_id", table: "hbh.treatment_plans", pk: "plan_id",
		insertCols: []string{"branch_id", "child_id", "service_id", "therapist_id", "title_ar", "start_date", "end_date"},
		updateCols: []string{"branch_id", "service_id", "therapist_id", "title_ar", "start_date", "end_date"},
		order:      "start_date DESC, plan_id DESC",
	},
	{
		Name: "goals", Param: "goal_id", table: "hbh.plan_goals", pk: "goal_id",
		insertCols: []string{"plan_id", "title_ar", "description_ar", "baseline_pct", "target_pct", "sort_order", "status"},
		updateCols: []string{"title_ar", "description_ar", "baseline_pct", "target_pct", "sort_order", "status"},
		order:      "plan_id, sort_order, goal_id",
	},
	{
		Name: "child-activities", Param: "child_activity_id", table: "hbh.child_activities", pk: "child_activity_id",
		insertCols: []string{"child_id", "activity_id", "plan_id", "goal_id", "assigned_by", "times_per_week", "minutes_each", "instructions_ar", "start_date", "end_date"},
		updateCols: []string{"activity_id", "plan_id", "goal_id", "times_per_week", "minutes_each", "instructions_ar", "start_date", "end_date"},
		order:      "child_id, child_activity_id DESC",
	},
	{
		Name: "measurements", Param: "measurement_id", table: "hbh.goal_measurements", pk: "measurement_id",
		insertCols: []string{"goal_id", "session_id", "measured_on", "value_pct", "trials_cnt", "note_ar"},
		updateCols: []string{"measured_on", "value_pct", "trials_cnt", "note_ar"},
		order:      "goal_id, measured_on DESC, measurement_id DESC",
	},
	{
		// A therapist's qualifications: text, always, with no attachment.
		// Ordinary enough for this table - there is no column here a
		// family may not read, which is exactly what makes the
		// certificates below a different case.
		Name: "therapist-qualifications", Param: "qualification_id",
		table: "hbh.therapist_qualifications", pk: "qualification_id",
		insertCols: []string{"therapist_id", "title_ar", "issuer_ar", "year_awarded", "sort_order"},
		updateCols: []string{"title_ar", "issuer_ar", "year_awarded", "sort_order"},
		order:      "therapist_id, sort_order, qualification_id",
	},
	// CERTIFICATES ARE NOT HERE, deliberately. Their attachment_id must
	// disappear for a family unless THAT certificate says its image is
	// public. The mask above could express that now, and the read still
	// lives in its own file: the row also carries has_image and a
	// registration number with their own conditions, and three rules in
	// one declarative slot is harder to read than one query that says them.
	{
		// The satisfaction survey's configuration - the question itself, who
		// is asked, what triggers it, how long before it may be asked again.
		//
		// It is here rather than in a handler of its own because it is
		// exactly what this table is for: a row an administrator edits. The
		// question TEXT is data for the same reason the trigger is - a
		// question hardcoded in Angular cannot be changed by the person who
		// owns the question.
		//
		// The schema refuses a survey that could never fire: PERIOD needs
		// period_days and no action_code, ACTION needs the reverse, and
		// anything else is a check violation rather than a survey that sits
		// there silently never appearing.
		Name: "nps-surveys", Param: "survey_id", table: "hbh.nps_surveys", pk: "survey_id",
		insertCols: []string{"code", "name_ar", "question_ar", "followup_question_ar", "audience",
			"trigger_kind", "period_days", "action_code", "cooldown_days", "starts_on", "ends_on"},
		updateCols: []string{"code", "name_ar", "question_ar", "followup_question_ar", "audience",
			"trigger_kind", "period_days", "action_code", "cooldown_days", "starts_on", "ends_on"},
		search: []string{"code", "name_ar"},
		order:  "code, survey_id",
	},

	// -----------------------------------------------------------------
	// The public site's content (migrations 0040 and 0041).
	//
	// These four go through the same path as everything above and get the
	// same four guarantees for free: the centre pinned on insert, an
	// allow list per column, no hard delete, one audit line. What is
	// different about them is where the words end up - on the open
	// internet - and none of that difference is enforced here. It is in
	// the database: the policies decide who may write, a trigger decides
	// who may publish, and a CHECK makes a published testimonial without
	// a recorded consent impossible to write at all.
	//
	// NOTE the columns that are NOT in these lists. `status`,
	// `published_at` and `published_by` are absent from every one of
	// them: publishing is not an edit and must not be reachable by
	// putting a field in a PATCH body. It gets its own endpoint, gated on
	// SITE.PUBLISH, and the trigger refuses it whatever the route.
	// `consent_given_at` IS writable on the two tables that need it, and
	// its value is thrown away. Sending anything non-null means "I have
	// taken this consent"; migration 0043's trigger stamps the real time
	// and the real person from the session, and null withdraws it.
	// `consent_obtained_by` is never writable at all - a request that
	// could name who took a consent is a request that could name somebody
	// who was not in the room.
	//
	// It had to become writable: 0040 made a published testimonial
	// without a consent impossible and left no way to record one, so
	// nothing could ever be published. A gate with no key is a wall.
	{
		Name: "site-contact", Param: "contact_id", table: "hbh.site_contact", pk: "contact_id",
		insertCols: []string{"phone", "landline", "whatsapp", "email", "address_ar", "address_en",
			"map_url", "hours_ar", "hours_en", "weekend_ar", "weekend_en",
			"arrival_ar", "arrival_en"},
		updateCols: []string{"phone", "landline", "whatsapp", "email", "address_ar", "address_en",
			"map_url", "hours_ar", "hours_en", "weekend_ar", "weekend_en",
			"arrival_ar", "arrival_en", "status"},
		order: "contact_id",
	},
	{
		// The page's own words, keyed by the data-i18n attribute already on
		// each element.
		//
		// text_key IS NOT UPDATABLE. A key is a position in the page, not a
		// value: renaming one does not move the sentence, it orphans it -
		// the old key goes unanswered and falls back to what is written in
		// index.html, and the new key matches no element at all. Nothing on
		// screen would say so. Creating a row names its key once; after
		// that only the words move.
		//
		// is_locked is absent from both lists deliberately. The six
		// live-streaming statements carry it, and hbh.guard_site_text_locked
		// refuses any edit to them - but a flag this layer could clear would
		// make that guard a formality.
		Name: "site-texts", Param: "text_id", table: "hbh.site_texts", pk: "text_id",
		insertCols: []string{"text_key", "text_ar", "text_en"},
		updateCols: []string{"text_ar", "text_en", "status"},
		// THE ONE RESOURCE THAT MOST NEEDS A SEARCH SHIPPED WITHOUT ONE.
		//
		// This table is a hundred-odd short strings keyed by dotted path,
		// and the screen was built around a search box. With no searchable
		// column the service refused `?q=` with 400 - correctly, because a
		// term that filters nothing is worse than a refusal - and the screen
		// showed its generic "could not load" line, so the fault read as a
		// broken LIST rather than a rejected search. Found by the session
		// that uses the screen, not by the one that wrote it.
		//
		// Both columns, because people arrive from both directions: from the
		// page ("مواعيد العمل", the words they can see) and from the markup
		// ("contact.hours", the key they found in a data-i18n attribute).
		search: []string{"text_key", "text_ar"},
		order:  "text_key",
	},
	{
		Name: "site-faq", Param: "faq_id", table: "hbh.site_faq", pk: "faq_id",
		insertCols: []string{"question_ar", "question_en", "answer_ar", "answer_en", "sort_order"},
		updateCols: []string{"question_ar", "question_en", "answer_ar", "answer_en", "sort_order", "status"},
		order:      "sort_order, faq_id",
	},
	{
		Name: "site-team", Param: "member_id", table: "hbh.site_team", pk: "member_id",
		insertCols: []string{"name_ar", "name_en", "role_ar", "role_en", "sort_order",
			"photo_path", "profile_href", "consent_given_at",
			"org_ar", "org_en", "bio_ar", "bio_en"},
		updateCols: []string{"name_ar", "name_en", "role_ar", "role_en", "sort_order",
			"photo_path", "profile_href", "status", "consent_given_at",
			"org_ar", "org_en", "bio_ar", "bio_en",
			"intro_video_path", "intro_video_poster_path",
			"intro_video_caption_ar", "intro_video_caption_en",
			"video_consent_given_at"},
		order: "sort_order, member_id",
	},
	{
		// A member of staff's personal record.
		//
		// center_id and user_id are absent from updateCols: a profile
		// belongs to the account it was opened for, and moving one would
		// carry somebody's identity number onto another person's row.
		//
		// The policy - not this table - decides who may read it: STAFF.PII,
		// or it is your own record.
		Name: "staff-profiles", Param: "profile_id",
		table: "hbh.staff_profiles", pk: "profile_id",
		insertCols: []string{"user_id", "national_id", "birth_date", "address_ar", "photo_path"},
		updateCols: []string{"national_id", "birth_date", "address_ar", "photo_path"},
		order:      "profile_id",
	},
	{
		// The metadata of a scanned document. The FILE is uploaded through
		// POST /users/{id}/documents, which writes the row and the file
		// together; this exists so a title can be corrected and a document
		// archived without touching the file at all.
		//
		// path is absent from both: it is written once, by the upload, and
		// a client that could set it could point a row at another person's
		// file.
		Name: "staff-documents", Param: "document_id",
		table: "hbh.staff_documents", pk: "document_id",
		insertCols: []string{},
		updateCols: []string{"kind", "title_ar", "note_ar"},
		order:      "user_id, document_id",
	},
	{
		// A member's films and photographs, one row per file.
		//
		// member_id is settable on INSERT and not on UPDATE: a file
		// belongs to the person who agreed to it, and moving one to
		// another member would carry their consent with it.
		//
		// published_at and published_by are absent from both. The
		// database stamps them - see trg_site_publish_stamp - so a
		// client cannot claim somebody else published a film.
		Name: "site-team-media", Param: "media_id", table: "hbh.site_team_media", pk: "media_id",
		insertCols: []string{"member_id", "kind", "path", "poster_path",
			"caption_ar", "caption_en", "duration_s", "sort_order", "consent_given_at"},
		updateCols: []string{"path", "poster_path", "caption_ar", "caption_en",
			"duration_s", "sort_order", "status", "consent_given_at"},
		order: "member_id, kind, sort_order, media_id",
	},
	{
		// The specialities shown as chips on a member's profile.
		Name: "site-team-specialties", Param: "specialty_id",
		table: "hbh.site_team_specialties", pk: "specialty_id",
		insertCols: []string{"member_id", "name_ar", "name_en", "sort_order"},
		updateCols: []string{"name_ar", "name_en", "sort_order"},
		order:      "member_id, sort_order, specialty_id",
	},
	{
		Name: "site-reviews", Param: "review_id", table: "hbh.site_reviews", pk: "review_id",
		// guardian_id is settable: it is how the consent stays attributable
		// and how a withdrawal later finds the row. It never leaves the
		// database - the exporter writes display_name and the text.
		insertCols: []string{"guardian_id", "display_name", "body_ar", "body_en", "sort_order", "rating", "consent_given_at", "text_reviewed_at"},
		updateCols: []string{"guardian_id", "display_name", "body_ar", "body_en", "sort_order", "rating", "status", "consent_given_at", "text_reviewed_at"},
		order:      "sort_order, review_id",
	},
	{
		// Scanned certificates belonging to named members of staff.
		//
		// TWO ATTESTATIONS, and both are write-once-by-the-database:
		// `consent_given_at` says the person agreed to have this DOCUMENT
		// published - which is not what agreeing to a photograph means -
		// and `redaction_checked_at` says somebody looked at the scan and
		// states it carries no national identity number, address or
		// telephone. The value sent for either is discarded; the triggers
		// stamp who and when from the session.
		//
		// `consent_obtained_by` and `redaction_checked_by` are absent from
		// both lists on purpose. A request that could name the person who
		// checked could name somebody who never opened the file.
		Name: "site-team-certificates", Param: "certificate_id",
		table: "hbh.site_team_certificates", pk: "certificate_id",
		insertCols: []string{"member_id", "path", "caption_ar", "caption_en", "sort_order",
			"consent_given_at", "redaction_checked_at"},
		updateCols: []string{"path", "caption_ar", "caption_en", "sort_order", "status",
			"consent_given_at", "redaction_checked_at"},
		order: "member_id, sort_order, certificate_id",
	},
	{
		// One qualification per row, because each is a claim about a named
		// person's credentials published under the centre's name -
		// "certified by the Air Force Hospital's psychiatry unit" and the
		// like. Rows mean one can be corrected or withdrawn on its own, and
		// the audit trail records which claim changed.
		Name: "site-team-facts", Param: "fact_id", table: "hbh.site_team_facts", pk: "fact_id",
		insertCols: []string{"member_id", "text_ar", "text_en", "sort_order"},
		updateCols: []string{"text_ar", "text_en", "sort_order"},
		order:      "member_id, sort_order, fact_id",
	},
	{
		// Marketing text FOR a catalogue row. There is no title here: the
		// name comes from hbh.services, so the page and the booking screen
		// cannot disagree about what a service is called - and a service
		// cannot be advertised into existence, which is what a second
		// independent list would allow.
		Name: "site-services", Param: "site_service_id", table: "hbh.site_services", pk: "site_service_id",
		insertCols: []string{"service_id", "blurb_ar", "blurb_en", "icon_key", "sort_order"},
		updateCols: []string{"blurb_ar", "blurb_en", "icon_key", "sort_order", "status"},
		order:      "sort_order, site_service_id",
	},
	{
		// Marketing copy only - no price, no duration, no link to a
		// bookable service. "Music therapy" now appears here AND in
		// hbh.services, and until the owner says which is the source of
		// truth this table must not be able to promise anything the
		// booking system cannot keep.
		Name: "site-programs", Param: "program_id", table: "hbh.site_programs", pk: "program_id",
		insertCols: []string{"title_ar", "title_en", "desc_ar", "desc_en",
			"detail_ar", "detail_en", "icon_key", "sort_order"},
		updateCols: []string{"title_ar", "title_en", "desc_ar", "desc_en",
			"detail_ar", "detail_en", "icon_key", "sort_order", "status"},
		order: "sort_order, program_id",
	},
	{
		// Whether a block of the public page is drawn at all. Twelve rows,
		// one per <section> the page has, and that is the whole table.
		//
		// insertCols IS NIL, AND NOT AN OVERSIGHT. A section is a position
		// in site/index.html, not a record: a thirteenth row names an
		// element that does not exist and changes nothing on the page,
		// while a second 'team' row is a unique violation. ck_ss_code and
		// uq_site_sections say the same thing in the schema, and 0041
		// granted hbh_app UPDATE and no INSERT - so a POST here is refused
		// by the engine whatever this file says. The nil keeps this layer
		// from being the one place that disagrees.
		//
		// code IS NOT UPDATABLE, for the reason written above site-texts
		// about text_key: a code is a position, not a value. Renaming one
		// does not move a section, it points the row at a different
		// element - or at none, silently.
		//
		// visible_flg is the only writable column, and the trigger from
		// 0041 gates it on SITE.PUBLISH rather than SITE.EDIT. Taking a
		// section off the public internet is a publishing act. This layer
		// does not check that and must not: the trigger raises HB100 and
		// the refusal is the database's.
		Name: "site-sections", Param: "section_id", table: "hbh.site_sections", pk: "section_id",
		updateCols: []string{"visible_flg"},
		// By code and not by section_id: the identifiers were handed out in
		// whatever order the seed ran, so ordering by them would shuffle
		// the list every time the table is rebuilt.
		order: "code",
	},
}

// Resources returns the allow list.
func Resources() []Resource { return resources }

// ErrUnknownColumn is returned when a request body names something that is not
// on the resource's allow list.
type ErrUnknownColumn struct{ Key string }

func (e ErrUnknownColumn) Error() string { return "unknown field " + e.Key }

// projection builds the SELECT expression.
//
// to_jsonb lets Postgres render every type correctly on its own: a date comes
// out as "2020-03-15" and not as a midnight instant, which is the defect D-5
// exists to remove. Hidden columns are subtracted, and money columns are
// re-added as exact decimal strings (D-25) because to_jsonb would render
// numeric as a JSON number and the nearest float is not the amount.
func (r Resource) projection() string {
	expr := "to_jsonb(t)"
	for _, h := range r.hide {
		expr += " - " + quoteLiteral(h)
	}
	// The masked columns are OVERWRITTEN with null rather than removed, so
	// the shape of the object is the same for everybody. A field that
	// disappears for one caller and appears for another makes a client
	// guess which case it is in; a null says "there is such a field, and
	// it is not for you".
	for _, m := range r.mask {
		var pairs []string
		for _, c := range m.cols {
			pairs = append(pairs, quoteLiteral(c)+
				", CASE WHEN "+m.when+" THEN to_jsonb(t."+c+") END")
		}
		expr += " || jsonb_build_object(" + strings.Join(pairs, ", ") + ")"
	}
	if len(r.money) > 0 {
		var pairs []string
		for _, m := range r.money {
			pairs = append(pairs, quoteLiteral(m)+", t."+m+"::text")
		}
		expr += " || jsonb_build_object(" + strings.Join(pairs, ", ") + ")"
	}
	return expr
}

// quoteLiteral wraps an identifier from THIS FILE as a SQL string literal.
// It is never called with anything from a request.
func quoteLiteral(s string) string { return "'" + strings.ReplaceAll(s, "'", "''") + "'" }

// ListOptions is what a caller may vary about a listing. Every field is a
// VALUE - none of them ever becomes SQL. The only thing that shapes the
// statement is Resource.search, which is written in this file.
type ListOptions struct {
	// Archived includes rows whose active_flg is false.
	Archived bool
	// Q is a free-text term, already trimmed. Empty means "no filter".
	Q string
	// Limit and Offset are set by the handler, which owns the defaults and
	// the ceiling. A zero Limit here would mean "no rows", so the handler
	// is not allowed to pass one.
	Limit  int
	Offset int
}

// likeEscape makes a user's term literal inside a LIKE pattern.
//
// Without it '%' matches everything and '_' matches any character, so a
// receptionist searching for a name containing an underscore gets the wrong
// rows and somebody typing a single '%' pages through the entire table. It is
// a correctness fix, not a security one - the term is a bound parameter
// either way and never reaches the parser as SQL.
//
// The backslash is doubled FIRST, or escaping the wildcards would then have
// their new backslashes escaped again.
func likeEscape(s string) string {
	s = strings.ReplaceAll(s, `\`, `\\`)
	s = strings.ReplaceAll(s, "%", `\%`)
	s = strings.ReplaceAll(s, "_", `\_`)
	return s
}

// searchWhere builds the OR-chain for a term, or "" when this resource has
// no searchable columns.
//
// The column names come from r.search - a literal in this file - and the
// TERM travels as $2. That split is the whole security story: a name here
// can only ever be a column this file already named, and nothing a client
// sends is ever concatenated into the statement.
func (r Resource) searchWhere() string {
	if len(r.search) == 0 {
		// $2 is still NAMED, even though nothing is matched against it.
		// Every listing binds the same four parameters, and Postgres
		// rejects a bind carrying a parameter the statement never
		// mentions - so dropping the clause here would turn every
		// unsearchable resource into a 500. The handler refuses `q` on
		// these resources, so the term is always NULL and this is TRUE.
		return "AND ($2::text IS NULL)"
	}
	parts := make([]string, 0, len(r.search))
	for _, c := range r.search {
		// ILIKE, not LOWER(col) LIKE LOWER(...): it folds case for English
		// without wrapping the column in a function, and Arabic has no case
		// for either of them to fold. ESCAPE names the character likeEscape
		// used above.
		parts = append(parts, fmt.Sprintf(`t.%s ILIKE '%%' || $2::text || '%%' ESCAPE '\'`, c))
	}
	return "AND ($2::text IS NULL OR (" + strings.Join(parts, " OR ") + "))"
}

// Searchable reports whether this resource accepts a free-text term. The
// handler asks before it accepts one, so that `?q=` on a resource with no
// searchable columns is a refusal rather than a filter that silently does
// nothing - which is the defect this whole change exists to remove.
func (r Resource) Searchable() bool { return len(r.search) > 0 }

// List returns one page of the resource's rows, and how many the filter
// matches in total.
//
// The order of the clauses is the order the requirements are in: the policy
// decides which rows exist for this caller, then the archived flag, then the
// search term, then the sort, and only then the page. Filtering after paging
// would search one page instead of the table.
//
// TOTAL IS A SECOND COUNT over the same predicate, the way Users and
// CentreAppointments already do it. It costs a second scan and it is what
// the console draws "صفحة ١ من ٤" from; on tables of this size - hundreds of
// rows, not millions - that is the cheaper mistake than a screen that cannot
// say how much it is not showing. If a table here ever grows past that, the
// count is the thing to make approximate, not the page.
func (d *DB) List(ctx context.Context, ident string, r Resource, opts ListOptions) ([]json.RawMessage, int, error) {
	out := []json.RawMessage{}
	total := 0

	// $1 archived, $2 term. Both bound; neither is ever formatted in.
	//
	// "Not archived only - everything": a screen that offers "show archived"
	// means "show me all of it", and the row carries active_flg so the
	// client can tell them apart.
	where := `WHERE ($1::boolean OR t.active_flg) ` + r.searchWhere()

	var term any
	if opts.Q != "" && r.Searchable() {
		term = likeEscape(opts.Q)
	}

	countSQL := fmt.Sprintf(`SELECT count(*) FROM %s t %s`, r.table, where)
	pageSQL := fmt.Sprintf(`SELECT %s FROM %s t %s ORDER BY %s LIMIT $3 OFFSET $4`,
		r.projection(), r.table, where, r.order)

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, countSQL, opts.Archived, term).Scan(&total); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, pageSQL, opts.Archived, term, opts.Limit, opts.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, json.RawMessage(raw))
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("list %s: %w", r.Name, err)
	}
	return out, total, nil
}

// Get returns one row, or ErrNotFound.
//
// ErrNotFound covers "no such row" and "not yours" together, as everywhere
// else in this service: distinguishing them confirms existence to anybody
// willing to walk the identifiers.
func (d *DB) Get(ctx context.Context, ident string, r Resource, id int) (json.RawMessage, error) {
	var raw []byte
	q := fmt.Sprintf(`SELECT %s FROM %s t WHERE t.%s = $1`, r.projection(), r.table, r.pk)
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, q, id).Scan(&raw)
	})
	if err != nil {
		return nil, noRows(err)
	}
	return json.RawMessage(raw), nil
}

// Create inserts one row and returns it.
//
// center_id is set from hbh.current_center_id() inside the statement and is
// not accepted from the caller - the same rule that keeps a reader inside
// their own tenant, applied to writing.
func (d *DB) Create(ctx context.Context, ident string, r Resource, body map[string]any) (json.RawMessage, error) {
	cols, args, err := bind(r.insertCols, body)
	if err != nil {
		return nil, err
	}

	names := []string{"center_id"}
	values := []string{"hbh.current_center_id()"}
	for i, c := range cols {
		names = append(names, c)
		values = append(values, "$"+strconv.Itoa(i+1))
	}

	// THREE statements, and NOT one INSERT ... RETURNING. This looks like
	// clumsiness and is not; the reason cost a debugging session.
	//
	// RETURNING applies the table's SELECT policy to the new row. The policy
	// on hbh.children is "center_id = mine AND can_access_child(child_id)",
	// and can_access_child is STABLE - so inside the very statement that
	// creates the row it evaluates against the snapshot taken when that
	// statement began, where the row does not exist yet. It returns false,
	// the RETURNING row fails the check, and Postgres reports "new row
	// violates row-level security policy" for an INSERT the policy actually
	// allowed. Reception could create a child directly in psql and not
	// through this code, which is what identified it.
	//
	// It is the same family as the CTE trap already recorded in CLAUDE.md: a
	// statement cannot see what it is itself writing. So the insert commits
	// its own statement, the key comes from the sequence, and the read-back
	// is a THIRD statement with a fresh snapshot in which the row exists.
	var raw []byte
	q := fmt.Sprintf(`INSERT INTO %s (%s) VALUES (%s)`,
		r.table, strings.Join(names, ", "), strings.Join(values, ", "))

	err = d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if _, err := tx.Exec(ctx, q, args...); err != nil {
			return err
		}
		// currval is per-session and per-sequence, so it names the row this
		// transaction just inserted even under concurrency.
		var id int64
		if err := tx.QueryRow(ctx,
			`SELECT currval(pg_get_serial_sequence($1, $2))`, r.table, r.pk).Scan(&id); err != nil {
			return err
		}
		sel := fmt.Sprintf(`SELECT %s FROM %s t WHERE t.%s = $1`, r.projection(), r.table, r.pk)
		return tx.QueryRow(ctx, sel, id).Scan(&raw)
	})
	if err != nil {
		return nil, err
	}
	return json.RawMessage(raw), nil
}

// Update changes the named columns of one row and returns it.
func (d *DB) Update(ctx context.Context, ident string, r Resource, id int, body map[string]any) (json.RawMessage, error) {
	cols, args, err := bind(r.updateCols, body)
	if err != nil {
		return nil, err
	}
	if len(cols) == 0 {
		return nil, ErrUnknownColumn{Key: "(empty body)"}
	}

	sets := make([]string, 0, len(cols))
	for i, c := range cols {
		sets = append(sets, c+" = $"+strconv.Itoa(i+1))
	}
	args = append(args, id)

	q := fmt.Sprintf(`UPDATE %s SET %s WHERE %s = $%d`,
		r.table, strings.Join(sets, ", "), r.pk, len(args))

	var raw []byte
	err = d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, q, args...)
		if err != nil {
			return err
		}
		// Zero rows means the policy did not admit this row. That is the
		// fail-closed answer, and it is reported as "not found" rather than
		// as a refusal, for the usual reason.
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		sel := fmt.Sprintf(`SELECT %s FROM %s t WHERE t.%s = $1`, r.projection(), r.table, r.pk)
		return tx.QueryRow(ctx, sel, id).Scan(&raw)
	})
	if err != nil {
		return nil, noRows(err)
	}
	return json.RawMessage(raw), nil
}

// SoftDelete archives one row. It is the only "delete" this service performs.
//
// There is no DELETE grant on any table in this schema, so a hard delete is
// not merely discouraged here - it is impossible from this connection. What
// this does is set active_flg = false and stamp the time, which keeps the row
// restorable and keeps the fact that it once existed visible to an auditor.
// A child's clinical record may not be destroyed without a documented
// compliance action, and that rule survives the move away from Oracle.
func (d *DB) SoftDelete(ctx context.Context, ident string, r Resource, id int) error {
	q := fmt.Sprintf(
		`UPDATE %s SET active_flg = false, deleted_at = now() WHERE %s = $1 AND active_flg`,
		r.table, r.pk)

	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, q, id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// Restore brings an archived row back.
//
// The counterpart of SoftDelete, and the reason migration 0013 exists: a
// manager can see what they archived, so they can undo it. Without this,
// "delete" would be irreversible from the screen and the soft delete would
// have bought nothing.
func (d *DB) Restore(ctx context.Context, ident string, r Resource, id int) error {
	q := fmt.Sprintf(
		`UPDATE %s SET active_flg = true, deleted_at = NULL WHERE %s = $1 AND NOT active_flg`,
		r.table, r.pk)

	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		tag, err := tx.Exec(ctx, q, id)
		if err != nil {
			return err
		}
		if tag.RowsAffected() == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// bind matches the request body against an allow list.
//
// Every value is handed to Postgres as text or as a boolean, and Postgres
// coerces it to the column's own type. That is deliberate: JSON has one number
// type and it is a float, so decoding 14 into a float64 and sending it to an
// integer column is a conversion this code would have to guess at. Sending the
// digits and letting the column decide removes the guess - and an unparseable
// value becomes a database refusal, which the handler already maps to 400.
func bind(allowed []string, body map[string]any) ([]string, []any, error) {
	index := make(map[string]struct{}, len(allowed))
	for _, c := range allowed {
		index[c] = struct{}{}
	}

	// Ordered by the allow list, not by map iteration, so the same body always
	// produces the same statement and the query plan cache is not defeated.
	var (
		cols []string
		args []any
	)
	for key := range body {
		if _, ok := index[key]; !ok {
			return nil, nil, ErrUnknownColumn{Key: key}
		}
	}
	for _, c := range allowed {
		v, present := body[c]
		if !present {
			continue
		}
		arg, err := scalar(v)
		if err != nil {
			return nil, nil, ErrUnknownColumn{Key: c}
		}
		cols = append(cols, c)
		args = append(args, arg)
	}
	return cols, args, nil
}

func scalar(v any) (any, error) {
	switch t := v.(type) {
	case nil:
		return nil, nil
	case bool:
		return t, nil
	case string:
		return t, nil
	case json.Number:
		return t.String(), nil
	default:
		return nil, fmt.Errorf("unsupported value %T", v)
	}
}
