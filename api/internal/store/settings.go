package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// The centre's operating parameters.
//
// Every value here is a ROW, not a constant - that is rule 1 of this project
// and the reason hbh.sys_params exists at all. Until this file there was no
// endpoint that read or wrote one, so the settings screen said so in a banner
// and the values could only be changed at a psql prompt.
//
// WHAT THIS READS. The parameter list resolves centre-before-global the same
// way hbh.param() does, and says WHICH of the two answered. That distinction
// is the whole model: the global row is the shipped default and never moves,
// a centre's change is an override beside it, and "return this to the
// default" is a matter of removing one row rather than remembering a number.
//
// RLS decides what comes back. A caller with no identity sees nothing - the
// policy on sys_params refuses global rows to an unauthenticated connection,
// which is the specific trap CLAUDE.md records - and a caller from another
// centre never sees this centre's overrides.

// CenterParams reads the centre's effective parameters, one JSON row each.
//
// The SQL is here and takes nothing from the request. `editable_flg` travels
// with each row so the screen knows which boxes to draw, but it is NOT what
// enforces anything: hbh.set_center_param checks it again, in the database,
// where a caller cannot skip it. A hidden field is not a control.
func (d *DB) CenterParams(ctx context.Context, ident string) ([]json.RawMessage, error) {
	const q = `
		SELECT to_jsonb(x) FROM (
		  SELECT DISTINCT ON (p.param_code)
		         p.param_code            AS code,
		         p.param_value           AS value,
		         p.data_type             AS "dataType",
		         p.description_ar        AS "descriptionAr",
		         p.editable_flg          AS editable,
		         (p.center_id IS NOT NULL) AS overridden,
		         g.param_value           AS "defaultValue"
		    FROM hbh.sys_params p
		    LEFT JOIN hbh.sys_params g
		           ON g.param_code = p.param_code
		          AND g.center_id IS NULL
		          AND g.active_flg
		   WHERE p.active_flg
		   -- A centre row wins over the global one of the same code. NULLS
		   -- LAST on center_id is what puts it first: DISTINCT ON keeps the
		   -- first row per code, so the override has to sort ahead.
		   ORDER BY p.param_code, p.center_id NULLS LAST
		) x
		ORDER BY x.code`

	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, q)
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
		return nil, fmt.Errorf("read centre parameters: %w", err)
	}
	return out, nil
}

// SetCenterParam writes a centre-scoped override and returns what was stored.
//
// Every rule is in hbh.set_center_param: the permission, whether the
// parameter may be edited at all, the declared type, and the refusal to touch
// the global default. This function decides nothing - it carries the answer.
// A check repeated here would be a second copy, and the weaker copy is the
// one that ends up deciding.
func (d *DB) SetCenterParam(ctx context.Context, ident, code, value string) (string, error) {
	var stored string
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.set_center_param($1, $2)`, code, value).Scan(&stored)
	})
	if err != nil {
		return "", err
	}
	return stored, nil
}

// ErrNothingToDo is a PATCH that named no field. Nothing was refused, so
// it is not a database error - but it is not a success either: a caller who
// meant to change something and changed nothing should be told that,
// rather than answered 204 for a write that never happened.
var ErrNothingToDo = errors.New("no fields to update")

// CenterEdit is a partial write of the centre row.
//
// Pointers and not values: a PATCH says what it wants changed, and nothing
// about the fields it leaves out. With plain strings an omitted name arrives
// as "" and there is no way left to tell "do not touch this" from "make this
// empty" - which is how a settings screen blanks a centre's name because
// somebody edited its weekend.
//
// `code` is absent, and so is every audit column. 0051 grants neither, and
// the trigger refuses the first even to the owner: the code is the centre's
// identity outside this database and the seeds and the site exporter match on
// it. `name_en` IS granted but is not here either - GET /me does not return
// it, so a screen could write it and never read it back, and a field you
// cannot see the result of is not an editable field.
type CenterEdit struct {
	NameAr       *string `json:"name_ar"`
	CountryCode  *string `json:"country_code"`
	CurrencyCode *string `json:"currency_code"`
	TimeZone     *string `json:"time_zone"`
	WeekendDays  *[]int  `json:"weekend_days"`
}

// UpdateCenter writes the centre's own row.
//
// EVERY RULE IS ALREADY IN THE DATABASE and none of them is repeated here.
// Migration 0051 put the three gates in three different places because they
// answer three different questions, and this function passes through all of
// them without knowing what they are:
//
//	which columns may move at all   a column-level GRANT - `code` has none
//	who may write                   the RLS policy, which asks for
//	                                SETTINGS.MANAGE inside itself
//	whether a change is sound       a BEFORE trigger comparing OLD to NEW:
//	                                the currency freezes once money exists,
//	                                and 0059 added the time zone
//
// So a caller without the permission does not get a refusal from this code -
// the policy matches no row and the UPDATE reports zero rows, which is why
// the zero-row case below is ErrNotFound and not a silent success. That is
// the shape a refusal takes once a write grant exists, and asserting on an
// exception here instead would pass on the day somebody widened the policy.
func (d *DB) UpdateCenter(ctx context.Context, ident string, in CenterEdit) (int64, error) {
	sets := make([]string, 0, 5)
	args := make([]any, 0, 5)
	add := func(col string, value any) {
		args = append(args, value)
		sets = append(sets, fmt.Sprintf("%s = $%d", col, len(args)))
	}

	// The column names come from THIS FILE. Nothing from the request reaches
	// the statement except as a parameter.
	if in.NameAr != nil {
		add("name_ar", *in.NameAr)
	}
	if in.CountryCode != nil {
		add("country_code", *in.CountryCode)
	}
	if in.CurrencyCode != nil {
		add("currency_code", *in.CurrencyCode)
	}
	if in.TimeZone != nil {
		add("time_zone", *in.TimeZone)
	}
	if in.WeekendDays != nil {
		add("weekend_days", *in.WeekendDays)
	}
	if len(sets) == 0 {
		return 0, ErrNothingToDo
	}

	var affected int64
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		// No WHERE on center_id. The policy pins the row to the caller's own
		// centre, in both its USING and its WITH CHECK clauses - adding the
		// condition here would be a second copy of it, and the copy that
		// drifts is the one nobody tests.
		tag, err := tx.Exec(ctx,
			`UPDATE hbh.centers SET `+strings.Join(sets, ", "), args...)
		if err != nil {
			return err
		}
		affected = tag.RowsAffected()
		return nil
	})
	if err != nil {
		return 0, err
	}
	if affected == 0 {
		return 0, ErrNotFound
	}
	return affected, nil
}

// ClearCenterParam returns a parameter to the value it shipped with, and
// answers with that value.
//
// The verb on the screen is "delete" and nothing is deleted: rule 3, and
// hbh_app holds no DELETE grant on any table in this schema. The override row
// is deactivated inside hbh.clear_center_param, hbh.param() steps over it, and
// the audit trail keeps both the setting and the clearing on one attributed
// row. Overriding the same parameter later revives it.
//
// Clearing what is already clear is not an error and does not raise. The
// answer is the value now in force, which is what the caller asked for.
func (d *DB) ClearCenterParam(ctx context.Context, ident, code string) (string, error) {
	var restored string
	err := d.InTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx,
			`SELECT hbh.clear_center_param($1)`, code).Scan(&restored)
	})
	if err != nil {
		return "", err
	}
	return restored, nil
}

// TimeZone is one entry in the picker.
type TimeZone struct {
	Name string `json:"name"`
	// Minutes east of UTC, RIGHT NOW. A zone that observes summer time
	// answers differently in January and in July, and that is honest: the
	// number is a hint to help somebody recognise their own zone in a list of
	// five hundred, not a property of the zone.
	OffsetMinutes int `json:"offsetMinutes"`
}

// TimeZones lists the zones a centre may be set to.
//
// FROM pg_timezone_names, because that is what hbh.guard_center_settings
// checks against (migration 0059). A list written in the client would drift
// from the server's tzdata and start offering names the database refuses.
//
// FILTERED THROUGH time.LoadLocation, because Postgres is not the only reader.
// The value is loaded by name in Go to resolve "today" for the diary, and a
// zone the engine knows but this binary cannot load would pass the trigger and
// then break the appointments screen. Offering only what BOTH can resolve is
// not a second copy of the rule - the trigger still decides what may be
// stored - it is the narrower question "what is safe to offer".
//
// A zone Postgres accepts and Go cannot is still storable by a caller who
// types it into the endpoint directly. That seam is real and small: both run
// on the same image with the same tzdata. It is written here so the next
// person meets it as a note rather than as a 500.
//
// The `posix/`, `right/` and `Etc/` trees are left out - they are duplicates
// and fixed-offset synthetics, and offering four names for one zone makes the
// list harder to use rather than more complete. UTC is kept: it is a real
// answer for a centre that wants no local time at all.
func (d *DB) TimeZones(ctx context.Context, ident string) ([]TimeZone, error) {
	const q = `
		SELECT name, (extract(epoch FROM utc_offset) / 60)::int
		  FROM pg_timezone_names
		 WHERE (name LIKE '%/%' OR name = 'UTC')
		   AND name NOT LIKE 'posix/%'
		   AND name NOT LIKE 'right/%'
		   AND name NOT LIKE 'Etc/%'
		 ORDER BY name`

	out := []TimeZone{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, q)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var z TimeZone
			if err := rows.Scan(&z.Name, &z.OffsetMinutes); err != nil {
				return err
			}
			if _, err := time.LoadLocation(z.Name); err != nil {
				continue
			}
			out = append(out, z)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, fmt.Errorf("read time zones: %w", err)
	}
	return out, nil
}
