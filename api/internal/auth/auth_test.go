package auth

import (
	"context"
	"testing"
)

func TestNewTokenIsUnpredictable(t *testing.T) {
	seen := make(map[string]struct{}, 512)
	for i := 0; i < 512; i++ {
		tok, err := NewToken()
		if err != nil {
			t.Fatalf("NewToken: %v", err)
		}
		if len(tok) < 40 {
			t.Fatalf("token is too short to be a credential: %q", tok)
		}
		if _, dup := seen[tok]; dup {
			t.Fatalf("token repeated after %d draws", i)
		}
		seen[tok] = struct{}{}
	}
}

// An identity that was never set must not read as an authenticated one. The
// zero value carries an empty username, which the database turns into NULL,
// which every policy treats as "no rows".
func TestFromContextFailsClosed(t *testing.T) {
	ident, ok := FromContext(context.Background())
	if ok {
		t.Fatal("a bare context reported an identity")
	}
	if ident.Username != "" || ident.UserID != 0 {
		t.Fatalf("zero identity is not zero: %+v", ident)
	}
}

func TestWithIdentityRoundTrips(t *testing.T) {
	want := Identity{Username: "guardian1", UserID: 7, CenterID: 1}
	got, ok := FromContext(WithIdentity(context.Background(), want))
	if !ok || got != want {
		t.Fatalf("got %+v (%v), want %+v", got, ok, want)
	}
}
