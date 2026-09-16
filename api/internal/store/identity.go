package store

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/jackc/pgx/v5"
)

// Users, roles and permissions - the mechanism by which every other
// permission in this system is handed out.
//
// NOT ONE RULE IS DECIDED HERE. Every function below calls a PL/pgSQL
// function that checks USER.MANAGE, pins the centre, refuses a caller
// changing their own roles, and stamps who granted what. This file
// carries values across the wire and nothing else - which matters more
// on this surface than anywhere else in the service, because a second
// copy of an authorisation rule is a second answer to "may you", and
// the weaker one decides.
//
// WHAT IS ABSENT: a password, on every path. Creating a user does not
// set one, and there is no endpoint that accepts one for somebody else.
// A password field on a creation screen is a password read aloud and
// written on paper. hbh.set_password remains the only way an account
// gets one.

// UserQuery filters the user list.
type UserQuery struct {
	// Q searches the name, the username and the mobile. EVERY CHARACTER OF
	// IT IS LITERAL - Users escapes the term with likeEscape before binding
	// it, so '%' and '_' are searched for rather than obeyed.
	Q        string
	Status   string
	Role     string
	Archived bool
	Limit    int
	Offset   int
}

// Users lists the centre's accounts with the roles each one holds.
//
// The roles come back as a nested array rather than one row per pair,
// because the screen shows a person and their roles - and flattening
// would make the caller regroup, which is the same defect the
// centre-indexed reads exist to remove.
//
// It could not be written at all before migration 0036: the policy on
// hbh.user_roles admitted only the caller's OWN roles, so an
// administrator listing users saw every role column empty.
func (d *DB) Users(ctx context.Context, ident string, q UserQuery) ([]json.RawMessage, int, error) {
	out := []json.RawMessage{}
	total := 0

	// THE PERMISSION IS IN THE QUERY, and it has to be.
	//
	// p_users_select admits ANY authenticated user of the centre - it
	// predates this endpoint and other reads lean on it, a therapist's
	// name on a session row among them. So without this line the user
	// list handed a guardian every colleague's username, telephone number
	// and standing. The acceptance suite caught it on the first run: a
	// therapist and a guardian each saw nine people.
	//
	// The DATABASE answers it, with the same hbh.has_permission the
	// policies use. That is the difference between asking the schema a
	// question and inventing a second rule here.
	//
	// A caller without USER.MANAGE gets an empty list rather than a
	// refusal - the same fail-closed shape as every other policy in this
	// schema, and it keeps the endpoint from confirming that a centre has
	// users at all.
	const where = `
		WHERE hbh.has_permission('USER.MANAGE')
		AND   ($1::boolean OR u.active_flg)
		AND   ($2::text IS NULL OR u.status = $2::text)
		AND   ($3::text IS NULL OR u.full_name_ar ILIKE '%' || $3 || '%' ESCAPE '\'
		                        OR u.username     ILIKE '%' || $3 || '%' ESCAPE '\'
		                        OR u.mobile       LIKE  '%' || $3 || '%' ESCAPE '\')
		AND   ($4::text IS NULL OR EXISTS (
		        SELECT 1 FROM hbh.user_roles ur
		        JOIN hbh.roles r ON r.role_id = ur.role_id
		        WHERE ur.user_id = u.user_id AND ur.active_flg AND r.code = $4::text))`

	// EVERY PATTERN CARRIES ESCAPE '\', and the term is escaped once here.
	// Without it the wildcards in a typed term are wildcards: an
	// administrator typing a single '%' is handed every account in the
	// centre, and a username holding '_' - which usernames here routinely do
	// - matches the wrong colleague. Like the same treatment in crud.go and
	// portal.go this is a correctness fix and not a security one: the term
	// is bound as $3 either way and never reaches the parser as SQL.
	//
	// One value for both statements, because the count and the page have to
	// agree about what was searched.
	term := nullif(likeEscape(q.Q))

	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM hbh.users u`+where,
			q.Archived, nullif(q.Status), term, nullif(q.Role)).Scan(&total); err != nil {
			return err
		}

		// password_hash is not in the projection and never will be. Nor
		// is failed_login_cnt or locked_until: a screen showing how many
		// times somebody mistyped their password is a screen for
		// gossiping about colleagues, and the lock has its own path.
		rows, err := tx.Query(ctx, `
			SELECT jsonb_build_object(
			         'user_id',      u.user_id,
			         'username',     u.username,
			         'full_name_ar', u.full_name_ar,
			         'user_type',    u.user_type,
			         'mobile',       u.mobile,
                         'center_name', (SELECT c.name_ar FROM hbh.centers c WHERE c.center_id=u.center_id),
                         'time_zone', (SELECT c.time_zone FROM hbh.centers c WHERE c.center_id=u.center_id),
			         'status',       u.status,
			         'active_flg',   u.active_flg,
			         'has_password', (u.password_hash IS NOT NULL),
			         'roles', coalesce((
			           SELECT jsonb_agg(jsonb_build_object(
			                    'code', r.code, 'name_ar', r.name_ar,
			                    'granted_at', ur.granted_at)
			                  ORDER BY r.code)
			           FROM   hbh.user_roles ur
			           JOIN   hbh.roles r ON r.role_id = ur.role_id
			           WHERE  ur.user_id = u.user_id AND ur.active_flg), '[]'::jsonb))
			FROM   hbh.users u`+where+`
			ORDER  BY u.full_name_ar, u.user_id
			LIMIT  $5 OFFSET $6`,
			q.Archived, nullif(q.Status), term, nullif(q.Role), q.Limit, q.Offset)
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
		return nil, 0, fmt.Errorf("users: %w", err)
	}
	return out, total, nil
}

// Roles lists the centre's roles and what each one may do.
//
// The permissions are nested here rather than left to a second call
// because this is the answer to "what does RECEPTION actually get", and
// a screen that had to ask twice would end up caching the first answer.
//
// It is also why the console must NOT hold its own copy of this map: a
// second copy goes silently wrong the first time a grant changes, on the
// one screen where people go to ask this exact question.
func (d *DB) Roles(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.jsonRows(ctx, ident, `
		SELECT jsonb_build_object(
		         'code',      r.code,
		         'name_ar',   r.name_ar,
		         'is_system', r.is_system_flg,
		         'permissions', coalesce((
		           SELECT jsonb_agg(p.code ORDER BY p.code)
		           FROM   hbh.role_permissions rp
		           JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
		           WHERE  rp.role_id = r.role_id AND rp.active_flg AND p.active_flg), '[]'::jsonb))
		FROM   hbh.roles r
		WHERE  r.active_flg
		ORDER  BY r.code`)
}

// Permissions lists every permission the schema defines, with its name.
func (d *DB) Permissions(ctx context.Context, ident string) ([]json.RawMessage, error) {
	return d.jsonRows(ctx, ident, `
		SELECT jsonb_build_object('code', p.code, 'name_ar', p.name_ar, 'name_en', p.name_en)
		FROM   hbh.permissions p WHERE p.active_flg ORDER BY p.code`)
}

// jsonRows runs a read whose single column is jsonb.
//
// The SQL comes from this file. Nothing from a request reaches it -
// requests supply values, which travel as bound parameters.
func (d *DB) jsonRows(ctx context.Context, ident, sql string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, sql)
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
		return nil, fmt.Errorf("read: %w", err)
	}
	return out, nil
}

// NewUser is an account being created. No password: see the file header.
type NewUser struct {
	Username   string `json:"username"`
	FullNameAr string `json:"full_name_ar"`
	UserType   string `json:"user_type"`
	Mobile     string `json:"mobile"`
	BranchID   *int   `json:"branch_id"`
}

// CreateUser opens an account with no way to sign in yet.
func (d *DB) CreateUser(ctx context.Context, ident string, in NewUser) (int, error) {
	var id int
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.create_user($1, $2, $3, nullif($4, ''), $5)`,
			in.Username, in.FullNameAr, in.UserType, in.Mobile, in.BranchID).Scan(&id)
	})
	if err != nil {
		return 0, fmt.Errorf("create user: %w", err)
	}
	return id, nil
}

// UserEdit is the part of an account the centre may change.
//
// Not the username, not the user type. Changing a username orphans every
// audit row that names it; changing the type turns a family into staff.
type UserEdit struct {
	FullNameAr  *string `json:"full_name_ar"`
	Mobile      *string `json:"mobile"`
	Status      *string `json:"status"`
	ClearMobile bool    `json:"clear_mobile"`
}

// UpdateUser edits a name, a number and a standing.
func (d *DB) UpdateUser(ctx context.Context, ident string, userID int, in UserEdit) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.update_user($1, $2, $3, $4, $5)`,
			userID, in.FullNameAr, in.Mobile, in.Status, in.ClearMobile)
		return err
	})
}

// ArchiveUser removes an account from the list, or puts it back.
func (d *DB) ArchiveUser(ctx context.Context, ident string, userID int, restore bool) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.archive_user($1, $2)`, userID, restore)
		return err
	})
}

// SetUserRoles replaces somebody's whole set of roles.
//
// The WHOLE set, because the screen shows a final state. Sending
// additions and removals separately means a request that fails halfway
// leaves an account holding a combination nobody chose - and on this
// table that combination is somebody's access to a centre's clinical
// records.
func (d *DB) SetUserRoles(ctx context.Context, ident string, userID int, codes []string) error {
	if codes == nil {
		codes = []string{}
	}
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx, `SELECT hbh.set_user_roles($1, $2::text[])`, userID, codes)
		return err
	})
}

// SetRolePermissions replaces what a role may do.
//
// The complete list, not a delta - see hbh.set_role_permissions for why,
// and for every rule this does not restate. A nil slice is passed through
// as NULL rather than turned into an empty array: the function refuses
// NULL on purpose, because "the screen forgot to send the field" and "this
// role grants nothing" must not arrive as the same request.
func (d *DB) SetRolePermissions(ctx context.Context, ident, roleCode string, codes []string) error {
	return d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`SELECT hbh.set_role_permissions($1, $2::text[])`, roleCode, codes)
		return err
	})
}

// IssuePasswordSetup mints a single-use code a member of staff redeems to
// choose their own password.
//
// The token is returned ONCE, to the caller who asked for it, and is stored
// only as a bcrypt hash. There is no way to read it back - not from here,
// not from the database, not from a backup.
//
// This is the whole of the answer to "how does a new member of staff get a
// password". The alternative an administrator usually asks for - typing one
// in for them - is refused everywhere in this service on purpose: it is a
// password said out loud, it gets written down, and whoever chose it can
// sign in as that person until it changes.
func (d *DB) IssuePasswordSetup(ctx context.Context, ident string, userID int) (string, error) {
	var token string
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.issue_password_setup($1)`, userID).Scan(&token)
	})
	if err != nil {
		return "", fmt.Errorf("issue password setup: %w", err)
	}
	return token, nil
}

// RedeemPasswordSetup exchanges a code and a chosen password for a working
// account, and returns the outcome as a word.
//
// A STATUS AND NOT AN ERROR, because the function counts failed attempts and
// an exception would roll the counter back with it - which is unlimited
// guesses. See D-1, and the comment on hbh.redeem_password_setup.
func (d *DB) RedeemPasswordSetup(ctx context.Context, username, token, password string) (string, error) {
	var outcome string
	// No identity: the caller has no way in yet, which is the point of the
	// token. InTx takes the empty string and sets no hbh.user_id.
	err := d.InTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.redeem_password_setup($1, $2, $3)`,
			username, token, password).Scan(&outcome)
	})
	if err != nil {
		return "", fmt.Errorf("redeem password setup: %w", err)
	}
	return outcome, nil
}

// ChangeOwnPassword changes the caller's own password and nobody else's.
//
// There is no user id in the signature, and that is the design: the
// function resolves hbh.current_user_id() itself, so no version of this
// call reaches another account. An administrator resetting somebody else
// issues a setup code instead.
//
// It RETURNS AN OUTCOME rather than an error. hbh.verify_password counts a
// wrong attempt toward the lock, and an exception would roll that increment
// back - the same trap D-1 was written about.
func (d *DB) ChangeOwnPassword(ctx context.Context, ident, current, next string) (string, error) {
	var outcome string
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.change_own_password($1, $2)`, current, next).Scan(&outcome)
	})
	if err != nil {
		return "", fmt.Errorf("change own password: %w", err)
	}
	return outcome, nil
}
