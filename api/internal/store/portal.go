package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// Not one query in this file carries a centre filter or an ownership check,
// and that is the point. hbh.current_center_id() and hbh.can_access_child()
// are applied by the row level security policies, underneath the query, where
// a forgotten WHERE clause cannot reach. A guardian who edits an identifier in
// a URL gets no rows - not because this code checked, but because the engine
// never handed the row over. See CLAUDE.md, security rule 2.

// Profile returns the caller's own account, their centre and their
// permissions.
func (d *DB) Profile(ctx context.Context, ident string) (domain.Profile, error) {
	var p domain.Profile
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			SELECT u.user_id, u.center_id, u.username, u.full_name_ar, u.user_type, u.status, u.mobile,
			       -- LEFT JOIN: most accounts are not therapists, and a
			       -- plain join would have made the whole profile - and
			       -- therefore every screen - unreachable for reception.
			       t.therapist_id,
			       c.center_id, c.code, c.name_ar, c.country_code, c.currency_code, c.time_zone, c.weekend_days
			FROM   hbh.users u
			JOIN   hbh.centers c ON c.center_id = u.center_id
			LEFT   JOIN hbh.therapists t
			       ON t.user_id = u.user_id AND t.active_flg
			WHERE  u.user_id = hbh.current_user_id()`).
			Scan(&p.User.UserID, &p.User.CenterID, &p.User.Username, &p.User.FullNameAr,
				&p.User.UserType, &p.User.Status, &p.User.Mobile, &p.User.TherapistID,
				&p.Center.CenterID, &p.Center.Code, &p.Center.NameAr, &p.Center.CountryCode,
				&p.Center.CurrencyCode, &p.Center.TimeZone, &p.Center.WeekendDays)
		if err != nil {
			return noRows(err)
		}

		rows, err := tx.Query(ctx, `
			SELECT p.code
			FROM   hbh.user_roles ur
			JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
			JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
			WHERE  ur.user_id = hbh.current_user_id()
			ORDER  BY p.code`)
		if err != nil {
			return err
		}
		defer rows.Close()

		// An empty slice, never nil: the JSON must read [] and not null, so
		// that a client testing "has no permissions" and a client testing
		// "the field is missing" cannot disagree.
		p.Permissions = []string{}
		for rows.Next() {
			var code string
			if err := rows.Scan(&code); err != nil {
				return err
			}
			p.Permissions = append(p.Permissions, code)
		}
		return rows.Err()
	})
	if err != nil {
		return domain.Profile{}, fmt.Errorf("profile: %w", err)
	}
	return p, nil
}

// childColumns is shared by the list and the single read so the two can never
// drift into showing different fields for the same child.
const childColumns = `
	c.child_id, c.child_no, c.full_name_ar, c.birth_date, c.gender, c.status, c.active_flg,
	gc.relationship_code, gc.is_primary_flg, gc.can_view_live_flg, gc.can_view_reports_flg`

// childFrom joins the caller's own link row, when they have one.
//
// The guardian subquery is itself policy-filtered: hbh.guardians only yields
// the caller's own record unless they hold CHILD.VIEW_ALL. For a staff member
// it yields nothing, the join finds nothing, and Link comes back null - which
// is correct, because staff reach a child through a permission and not through
// a family relationship.
const childFrom = `
	FROM hbh.children c
	LEFT JOIN hbh.guardian_children gc
	       ON gc.child_id = c.child_id
	      AND gc.guardian_id = (SELECT g.guardian_id FROM hbh.guardians g
	                             WHERE g.user_id = hbh.current_user_id())`

// ChildQuery narrows a list of children.
//
// The same endpoint serves both audiences, and the POLICY is what decides
// which rows exist for the caller: a guardian sees their own children, a staff
// member holding CHILD.VIEW_ALL sees the centre's. That is why there is no
// second path for the operations console - a second path would be a second
// place for the rule to live.
type ChildQuery struct {
	GuardianID int
	// Search over the folded Arabic name, the child number, or the PARENT's
	// name or mobile. Folding is hbh.normalize_arabic, the same function the
	// index uses, so a search for "احمد" finds "أحمد".
	//
	// The parent half is there because it is how reception actually finds a
	// family: the phone rings, and the number on the screen is the mother's,
	// not the child's. Searching only the child's name means asking a
	// caller to spell a name you are about to type wrong.
	//
	// AND IT LEAKS NOTHING, because the policy decides. The guardian row is
	// read as hbh_app under the caller's own identity, so a caller who may
	// not see that guardian matches nothing and learns nothing - no handler
	// condition, no permission check up here, and no yes/no oracle over a
	// number somebody is not allowed to read.
	//
	// EVERY CHARACTER OF IT IS LITERAL. Children escapes the term with
	// likeEscape before binding it, so '%' and '_' are searched for rather
	// than obeyed.
	Q string
	// Status filters standing at the centre (ACTIVE, GRADUATED, WITHDRAWN).
	Status string
	// Archived includes archived records. Default false: archiving a child
	// must actually remove them from the list, or it has done nothing
	// visible and the screen cannot tell it worked.
	Archived bool

	Limit  int
	Offset int
}

// Children lists the children the caller may see, and how many there are in
// total before paging.
//
// The count is returned because a screen showing page 1 of an unknown number
// cannot say so. It is computed in the SAME transaction as the page, or the
// two could disagree and the last page would be empty for no visible reason.
func (d *DB) Children(ctx context.Context, ident string, q ChildQuery) ([]domain.Child, int, error) {
	out := []domain.Child{}
	total := 0

	// hbh.normalize_arabic is STRICT, so it returns NULL for a NULL argument
	// rather than matching everything - hence the explicit IS NULL guard
	// rather than relying on the comparison.
	//
	// EVERY PATTERN CARRIES ESCAPE '\', and the term arrives already escaped
	// by likeEscape. Without it the wildcards in a typed term are wildcards:
	// a receptionist typing a single '%' gets every child in the centre, and
	// a name holding '_' matches the wrong family. Like the same treatment in
	// crud.go this is a correctness fix and not a security one - the term is
	// bound as $3 either way and never reaches the parser as SQL.
	//
	// THE ESCAPING HAPPENS BEFORE THE FOLDING, which is the only order
	// available: likeEscape runs here in Go, hbh.normalize_arabic runs over
	// its result inside the statement. It is also the correct one, because
	// normalize_arabic leaves the backslash alone - it lowercases, deletes
	// the diacritics and tatweel, folds the alef/ya/ta-marbuta variants,
	// collapses runs of whitespace and trims the ends. A backslash is in none
	// of those translate sets and is not whitespace, so '\%' survives folding
	// as the two characters the ESCAPE clause expects.
	const where = `
		WHERE ($1::boolean OR c.active_flg)
		AND   ($2::text IS NULL OR c.status = $2::text)
		AND   ($3::text IS NULL
		       OR hbh.normalize_arabic(c.full_name_ar)
		          LIKE '%' || hbh.normalize_arabic($3::text) || '%' ESCAPE '\'
		       OR c.child_no ILIKE '%' || $3::text || '%' ESCAPE '\'
		       -- The parent's name or number. Reception finds a family from
		       -- the phone that is ringing, and that number is the mother's.
		       --
		       -- Plain SQL, not SECURITY DEFINER: the guardian row is read
		       -- under the caller's own identity, so whoever may not see a
		       -- guardian matches nothing through this branch. The policy
		       -- decides, which is the only place it may be decided.
		       OR EXISTS (SELECT 1
		                    FROM hbh.guardian_children gl
		                    JOIN hbh.guardians g ON g.guardian_id = gl.guardian_id
		                   WHERE gl.child_id = c.child_id
		                     AND gl.active_flg AND g.active_flg
		                     AND (g.mobile ILIKE '%' || $3::text || '%' ESCAPE '\'
		                          OR hbh.normalize_arabic(g.full_name_ar)
		                             LIKE '%' || hbh.normalize_arabic($3::text) || '%' ESCAPE '\')))
		AND ($4::integer = 0 OR EXISTS (SELECT 1 FROM hbh.guardian_children link WHERE link.child_id = c.child_id AND link.guardian_id = $4 AND link.active_flg))`

	// Escaped ONCE, and both statements bind this same value. The count and
	// the page have to agree about what was searched, or the screen reports a
	// total it did not produce.
	term := nullif(likeEscape(q.Q))

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx,
			`SELECT count(*) FROM hbh.children c`+where,
			q.Archived, nullif(q.Status), term, q.GuardianID).Scan(&total); err != nil {
			return err
		}

		rows, err := tx.Query(ctx,
			`SELECT`+childColumns+childFrom+where+`
			 ORDER BY c.full_name_ar, c.child_id
			 LIMIT $5 OFFSET $6`,
			q.Archived, nullif(q.Status), term, q.GuardianID, q.Limit, q.Offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			child, err := scanChild(rows)
			if err != nil {
				return err
			}
			out = append(out, child)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, 0, fmt.Errorf("children: %w", err)
	}
	return out, total, nil
}

// nullif turns an empty filter into SQL NULL, which every clause above reads
// as "no filter".
func nullif(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// Child returns one child, or ErrNotFound.
//
// ErrNotFound covers both "no such child" and "not yours", deliberately. See
// the note on ErrNotFound: distinguishing them would confirm another family's
// child to anyone walking the identifiers.
func (d *DB) Child(ctx context.Context, ident string, childID int) (domain.Child, error) {
	var child domain.Child
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		child, err = childTx(ctx, tx, childID)
		return err
	})
	if err != nil {
		return domain.Child{}, err
	}
	return child, nil
}

// childTx returns ErrNotFound for a child the caller cannot see, which is
// the same answer as one that does not exist. RLS decides which of the two
// it is and this layer is not told - deliberately, because telling the
// difference is what turns an identifier into a question about a family.
func childTx(ctx context.Context, tx pgx.Tx, childID int) (domain.Child, error) {
	rows, err := tx.Query(ctx, `SELECT`+childColumns+childFrom+` WHERE c.child_id = $1`, childID)
	if err != nil {
		return domain.Child{}, err
	}
	defer rows.Close()
	if !rows.Next() {
		if err := rows.Err(); err != nil {
			return domain.Child{}, err
		}
		return domain.Child{}, ErrNotFound
	}
	return scanChild(rows)
}

func scanChild(rows pgx.Rows) (domain.Child, error) {
	var (
		c              domain.Child
		relationship   *string
		isPrimary      *bool
		canViewLive    *bool
		canViewReports *bool
	)
	if err := rows.Scan(&c.ChildID, &c.ChildNo, &c.FullNameAr, &c.BirthDate, &c.Gender, &c.Status,
		&c.ActiveFlg, &relationship, &isPrimary, &canViewLive, &canViewReports); err != nil {
		return domain.Child{}, err
	}
	if relationship != nil {
		c.Link = &domain.GuardianLink{
			RelationshipCode: *relationship,
			IsPrimary:        derefBool(isPrimary),
			CanViewLive:      derefBool(canViewLive),
			CanViewReports:   derefBool(canViewReports),
		}
	}
	return c, nil
}

// derefBool reads a nullable flag as false. Every flag it is used on is a
// permission, and an unknown permission is a withheld one.
func derefBool(b *bool) bool { return b != nil && *b }

// ChildGuardians lists the people responsible for one child.
//
// THE ORDER IS TOTAL, and that is the whole point of the endpoint.
// is_primary_flg first, then the oldest link, then the identifier as a
// final tiebreak - so two callers asking the same question get the same
// answer, always. A printed emergency card whose number came from an
// unordered read is a card carrying somebody else's family, and the
// person holding it has no way to know.
//
// Migration 0032 made the first term decisive on its own: one primary
// guardian per child, among live links. The other two terms cover what
// that index does not - several NON-primary guardians.
//
// The mobile number is here because that is what the endpoint is for. It
// is not a leak: hbh.guardians already refuses a caller who is neither
// the guardian themselves nor holds CHILD.VIEW_ALL, so a family reading
// this sees their own row and the centre sees the household. What the
// policy admits, this returns; it adds nothing.
func (d *DB) ChildGuardians(ctx context.Context, ident string, childID int) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'guardian_id',       g.guardian_id,
			         'full_name_ar',      g.full_name_ar,
			         'mobile',            g.mobile,
			         'relationship_code', gc.relationship_code,
			         'is_primary',        gc.is_primary_flg,
			         'can_view_live',     gc.can_view_live_flg,
			         'can_view_reports',  gc.can_view_reports_flg,
			         'has_account',       (g.user_id IS NOT NULL))
			FROM   hbh.guardian_children gc
			JOIN   hbh.guardians g ON g.guardian_id = gc.guardian_id
			WHERE  gc.child_id = $1 AND gc.active_flg AND g.active_flg
			ORDER  BY gc.is_primary_flg DESC, gc.created_at, g.guardian_id`, childID)
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
		return nil, fmt.Errorf("child guardians: %w", err)
	}
	return out, nil
}

// GuardianContact is the part of a guardian's record that is theirs to change.
//
// Two fields, and the list of what is NOT here is the interesting half: the
// mobile is the login (the one-time code goes to it), and the name and the
// national id are checked against a document at reception. See migration
// 0107 for the reasoning on each.
type GuardianContact struct {
	Email string `json:"email"`
	City  string `json:"city"`
}

// GuardianContactOf reads the caller's own contact fields.
//
// No identifier argument and no centre filter: the policy on hbh.guardians
// yields the caller's own row and nothing else. A guardian who edits a URL
// finds nothing to edit.
func (d *DB) GuardianContactOf(ctx context.Context, ident string) (GuardianContact, error) {
	var out GuardianContact
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `
			SELECT coalesce(g.email, ''), coalesce(g.city, '')
			FROM   hbh.guardians g
			WHERE  g.user_id = hbh.current_user_id()
			AND    g.active_flg`).Scan(&out.Email, &out.City)
	})
	if err != nil {
		return GuardianContact{}, noRows(err)
	}
	return out, nil
}

// SetGuardianContact changes those two fields and can change nothing else.
//
// The function takes two arguments, so there is no third to send. That is the
// whole guarantee: an UPDATE policy can say which ROWS a caller may write and
// never which COLUMNS, so opening the row would have opened the mobile with
// it - the one field that would let a signed-in phone move the account to a
// new number.
func (d *DB) SetGuardianContact(
	ctx context.Context, ident, email, city string,
) (GuardianContact, error) {
	var out GuardianContact
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// coalesce, because the function returns the COLUMNS and an empty
		// field is stored as NULL - which is right in the table and is not a
		// Go string. Clearing both fields answered 500 until this was here,
		// and only because the clear path was actually exercised: the happy
		// path returns two non-null values and looks perfect.
		return tx.QueryRow(ctx,
			`SELECT coalesce(email, ''), coalesce(city, '')
			   FROM hbh.update_own_guardian_contact($1, $2)`,
			email, city).Scan(&out.Email, &out.City)
	})
	if err != nil {
		return GuardianContact{}, fmt.Errorf("guardian contact: %w", err)
	}
	return out, nil
}
