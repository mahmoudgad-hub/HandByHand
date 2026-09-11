// Package store is the only place in this service that talks to PostgreSQL.
//
// One rule governs the whole package: every transaction sets the request
// identity before it does anything else, and no query runs outside a
// transaction. Both halves matter.
//
//   - Setting the identity is what makes the policies apply. Forgetting it
//     does not open the door, it closes it: hbh.current_portal_user() returns
//     NULL and every policy yields zero rows. The failure is safe, but it
//     looks like a bug in the query, so it is worth recognising on sight.
//
//   - Using SET LOCAL - here, set_config(..., true) - rather than SET is what
//     keeps one request's identity out of the next request's. A pgx pool
//     reuses connections, so a session-level setting leaks across callers.
//     That is not a hypothetical: it is the HBH_PKG_UI defect from the Oracle
//     system, which held a package-global BOOLEAN as if it were per-page
//     state. See docs/01-stack-decisions.md, D-3.
package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DB is a pool of connections made as the hbh_app role.
type DB struct {
	pool *pgxpool.Pool
}

// Open connects and verifies the connection is usable.
func Open(ctx context.Context, url string, maxConns int32) (*DB, error) {
	cfg, err := pgxpool.ParseConfig(url)
	if err != nil {
		return nil, fmt.Errorf("parse DATABASE_URL: %w", err)
	}
	cfg.MaxConns = maxConns
	cfg.MaxConnLifetime = 30 * time.Minute
	cfg.MaxConnIdleTime = 5 * time.Minute
	cfg.HealthCheckPeriod = 30 * time.Second

	// UTC on every connection. D-5 makes every column timestamptz so the
	// stored instant is unambiguous; pinning the session removes the last
	// place a local time zone could enter a comparison.
	cfg.ConnConfig.RuntimeParams["timezone"] = "UTC"
	cfg.ConnConfig.RuntimeParams["application_name"] = "hbhd"

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("connect: %w", err)
	}
	if err := pool.Ping(ctx); err != nil {
		pool.Close()
		return nil, fmt.Errorf("ping: %w", err)
	}
	return &DB{pool: pool}, nil
}

// Close releases every connection.
func (d *DB) Close() { d.pool.Close() }

// Pool exposes the pool for the audit writer, which deliberately writes
// outside the caller's transaction. Nothing else should reach for it.
func (d *DB) Pool() *pgxpool.Pool { return d.pool }

// Ping is the readiness probe.
func (d *DB) Ping(ctx context.Context) error { return d.pool.Ping(ctx) }

// AssertSafeRole refuses to start against a connection that can step around
// row level security.
//
// This is the single most valuable check in the service. Postgres bypasses RLS
// for a superuser and for the owner of the table, so an API that connected as
// hbh_owner would make every policy in the schema decorative - with no error,
// no denied row, and no trace in any log. A silent failure of the entire
// access control model is not something to discover from a support ticket, so
// the process refuses to run at all. See D-2.
func (d *DB) AssertSafeRole(ctx context.Context) error {
	var (
		role     string
		super    bool
		bypass   bool
		owned    int
		identity *string
	)

	err := d.pool.QueryRow(ctx, `
		SELECT current_user,
		       r.rolsuper,
		       r.rolbypassrls,
		       (SELECT count(*) FROM pg_tables t
		         WHERE t.schemaname = 'hbh' AND t.tableowner = current_user),
		       hbh.current_portal_user()
		FROM   pg_roles r
		WHERE  r.rolname = current_user`).Scan(&role, &super, &bypass, &owned, &identity)
	if err != nil {
		return fmt.Errorf("inspect connection role: %w", err)
	}

	var problems []error
	if super {
		problems = append(problems, fmt.Errorf("role %q is a superuser and bypasses every policy", role))
	}
	if bypass {
		problems = append(problems, fmt.Errorf("role %q has BYPASSRLS and bypasses every policy", role))
	}
	if owned > 0 {
		problems = append(problems, fmt.Errorf("role %q owns %d table(s) in schema hbh and bypasses their policies", role, owned))
	}
	// A fresh connection must carry no identity. If it does, something is
	// setting it at session level, which is the leak SET LOCAL exists to
	// prevent - and it would hand one user's identity to the next request.
	if identity != nil {
		problems = append(problems, fmt.Errorf("a fresh connection already carries identity %q; hbh.user_id must only ever be set with SET LOCAL", *identity))
	}
	return errors.Join(problems...)
}

// AssertMigrated refuses to start against a database that is reachable but
// older than the code. A missing function surfaces otherwise as a confusing
// runtime error on the first login rather than at boot.
//
// It asks hbh.migration_applied() rather than reading hbh.schema_migrations,
// because hbh_app has no read on that table and should not be given one: it
// carries no row level security, so a grant there would be the one unfiltered
// table read in the service. The function answers a boolean and nothing else.
func (d *DB) AssertMigrated(ctx context.Context, versions ...string) error {
	for _, v := range versions {
		var present bool
		err := d.pool.QueryRow(ctx, `SELECT hbh.migration_applied($1)`, v).Scan(&present)
		if err != nil {
			return fmt.Errorf("probe migration %s (is hbh.migration_applied present? run scripts/db.sh migrate): %w", v, err)
		}
		if !present {
			return fmt.Errorf("migration %s is not applied - run scripts/db.sh migrate", v)
		}
	}
	return nil
}

// InTx runs fn in a read-write transaction with ident established as the
// request identity.
//
// Pass an empty ident for an unauthenticated request. That is not a loophole:
// hbh.current_portal_user() maps the empty string to NULL, so the transaction
// sees nothing. The authentication functions are reachable anyway because they
// are SECURITY DEFINER and granted explicitly.
func (d *DB) InTx(ctx context.Context, ident string, fn func(context.Context, pgx.Tx) error) error {
	return d.inTx(ctx, ident, pgx.ReadWrite, fn)
}

// InReadTx is InTx with the transaction marked read-only.
//
// Every portal endpoint is a read today, and saying so lets the server refuse
// a write that no reader should have been making. It is a cheap second lock on
// a door the grants already close.
func (d *DB) InReadTx(ctx context.Context, ident string, fn func(context.Context, pgx.Tx) error) error {
	return d.inTx(ctx, ident, pgx.ReadOnly, fn)
}

func (d *DB) inTx(ctx context.Context, ident string, mode pgx.TxAccessMode, fn func(context.Context, pgx.Tx) error) error {
	tx, err := d.pool.BeginTx(ctx, pgx.TxOptions{AccessMode: mode})
	if err != nil {
		return fmt.Errorf("begin: %w", err)
	}
	// Rollback after a successful Commit is a no-op, so this is safe as the
	// single unconditional cleanup path.
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()

	// set_config rather than SET because SET takes no parameters, and the
	// third argument - is_local - is the whole point: this binding dies with
	// the transaction and cannot reach the next borrower of the connection.
	if _, err := tx.Exec(ctx, `SELECT set_config('hbh.user_id', $1, true)`, ident); err != nil {
		return fmt.Errorf("set request identity: %w", err)
	}

	if err := fn(ctx, tx); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// ErrNotFound is returned when a row does not exist or the caller is not
// allowed to see it.
//
// The two are deliberately the same error, and that is a security property
// rather than laziness: a handler that answered 403 for "exists but not yours"
// and 404 for "does not exist" would confirm the existence of another family's
// child to anyone willing to walk the identifiers.
var ErrNotFound = errors.New("not found")

// ErrForbidden is returned when the caller may see that a thing exists and
// may not read it.
//
// It is the DELIBERATE opposite of ErrNotFound, and the two are not
// interchangeable. ErrNotFound hides existence, which is right when the
// alternative would confirm another family's child. This is for the case
// where existence is not a secret and silence would MISLEAD: a billing
// screen that answers an empty list to somebody without BILLING.VIEW
// reads as "the centre is owed nothing", and there is nothing to
// disclose by refusing, because every centre has billing.
var ErrForbidden = errors.New("forbidden")

func noRows(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}
