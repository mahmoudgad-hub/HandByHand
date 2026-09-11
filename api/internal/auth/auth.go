// Package auth carries the authenticated identity through a request and mints
// the opaque session token.
//
// There is no JWT here, and that is a decision rather than an omission. The
// database already implements revocable server-side sessions, and
// hbh.resolve_auth_session refuses a suspended account on the next request
// rather than at the next login. A stateless token cannot honour that: it
// stays valid until it expires, which is exactly the guarantee we would be
// giving up. See docs/01-stack-decisions.md, D-10.
package auth

import (
	"context"
	"crypto/rand"
	"encoding/base64"
)

// Identity is the authenticated caller. It is set by the authentication
// middleware and by nothing else.
//
// CenterID is present because the audit writer needs it. It is NOT sent to the
// database as a filter: every policy derives the centre from the user row via
// hbh.current_center_id(), so a caller cannot claim another centre even if
// this value were wrong. See D-3.
type Identity struct {
	Username string
	UserID   int
	CenterID int
}

type contextKey struct{}

// WithIdentity returns a context carrying ident.
func WithIdentity(ctx context.Context, ident Identity) context.Context {
	return context.WithValue(ctx, contextKey{}, ident)
}

// FromContext returns the authenticated identity, if any.
//
// The zero Identity has an empty Username, which the store passes to
// set_config as an empty string, which hbh.current_portal_user() turns into
// NULL. An unauthenticated request therefore sees zero rows rather than every
// row - the fail-closed property, preserved by construction rather than by the
// caller remembering to check.
func FromContext(ctx context.Context) (Identity, bool) {
	ident, ok := ctx.Value(contextKey{}).(Identity)
	return ident, ok
}

// tokenBytes is the entropy of a session token. 32 bytes is why the database
// stores a SHA-256 of it rather than a bcrypt hash: bcrypt exists to slow down
// guessing of a low-entropy secret, and this is not one.
const tokenBytes = 32

// NewToken mints a session token. The plaintext is returned to the caller
// once, sent to the client, and never written anywhere: the database keeps
// only its digest.
func NewToken() (string, error) {
	b := make([]byte, tokenBytes)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}
