package store

import (
	"context"
	"fmt"
	"regexp"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
)

// Params reads hbh.sys_params.
//
// Nothing in this service hardcodes a business value. The accepted mobile
// pattern is Egyptian today because a row says so, not because a regular
// expression in Go says so, and a second centre in another country changes a
// row rather than a release. See CLAUDE.md: "ولا شيء منها مكتوب في الكود".
//
// hbh.param() is SECURITY DEFINER, so this works before a caller is
// authenticated - which it must, since the mobile pattern is needed to
// validate the very request that starts a login.
type Params struct {
	db  *DB
	ttl time.Duration

	mu     sync.RWMutex
	values map[string]cached

	reMu       sync.Mutex
	reSource   string
	reCompiled *regexp.Regexp
}

type cached struct {
	value   string
	fetched time.Time
}

// NewParams returns a reader that re-reads a parameter at most once per ttl.
// A parameter change reaches a running process within that window; nothing
// needs a restart.
func NewParams(db *DB, ttl time.Duration) *Params {
	return &Params{db: db, ttl: ttl, values: make(map[string]cached)}
}

// Get returns the global value of code, or def when no row defines it.
//
// The centre argument to hbh.param is NULL on purpose. A login request has no
// identity yet, so there is no centre to scope by; per-centre overrides apply
// once a caller is known and an endpoint asks for them.
func (p *Params) Get(ctx context.Context, code, def string) (string, error) {
	p.mu.RLock()
	c, ok := p.values[code]
	p.mu.RUnlock()
	if ok && time.Since(c.fetched) < p.ttl {
		return c.value, nil
	}

	var value string
	err := p.db.InReadTx(ctx, "", func(ctx context.Context, tx pgx.Tx) error {
		return tx.QueryRow(ctx, `SELECT hbh.param(NULL, $1, $2)`, code, def).Scan(&value)
	})
	if err != nil {
		// A cached value that is merely stale beats failing a login because
		// the parameter table was briefly unreachable.
		if ok {
			return c.value, nil
		}
		return "", fmt.Errorf("read parameter %s: %w", code, err)
	}

	p.mu.Lock()
	p.values[code] = cached{value: value, fetched: time.Now()}
	p.mu.Unlock()
	return value, nil
}

// MobilePattern compiles the centre's accepted mobile format.
//
// There is no fallback pattern. A default here would be a business value in
// code wearing a disguise, and the disguise is the dangerous part: it would
// silently accept the wrong shape of number on a database whose seed had not
// run. Missing parameter, refused request.
func (p *Params) MobilePattern(ctx context.Context) (*regexp.Regexp, error) {
	raw, err := p.Get(ctx, "MOBILE_PATTERN", "")
	if err != nil {
		return nil, err
	}
	if raw == "" {
		return nil, fmt.Errorf("sys_params.MOBILE_PATTERN is not set - run scripts/db.sh migrate to load the reference seed")
	}

	p.reMu.Lock()
	defer p.reMu.Unlock()
	if p.reCompiled != nil && p.reSource == raw {
		return p.reCompiled, nil
	}
	re, err := regexp.Compile(raw)
	if err != nil {
		return nil, fmt.Errorf("sys_params.MOBILE_PATTERN %q is not a valid expression: %w", raw, err)
	}
	p.reSource, p.reCompiled = raw, re
	return re, nil
}
