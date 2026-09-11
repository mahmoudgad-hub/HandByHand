package domain

import "time"

// StreamGrant is the entire answer a client gets when it is allowed to watch.
//
// Read the fields that are NOT here, because they are the design:
//
//   - no token. The stream token is a live credential and it never touches
//     JavaScript. It is set as an HttpOnly cookie scoped to the playback path,
//     so the browser sends it and no script can read it, and it never appears
//     in a URL where a proxy log or a browser history would keep it.
//   - no gateway path, no camera id, no address, no credential. The API talks
//     to the media gateway; the client talks to the API. CLAUDE.md: "لا رابط
//     كاميرا ولا عنوان IP ولا بيانات اعتماد في أي مكان يبلغه عميل".
//
// PlaybackPath is a fixed path on this API. It is the same string for every
// viewer and every session, so it identifies nothing.
type StreamGrant struct {
	PlaybackPath string    `json:"playback_path"`
	ExpiresAt    time.Time `json:"expires_at"`

	// The window in seconds, so a player can schedule its own renewal
	// without doing clock arithmetic against a server it does not trust.
	// Capped at fifteen minutes by the database - in the function that
	// issues the token AND by a CHECK constraint on the row, so no caller
	// can widen it.
	ExpiresInSeconds int `json:"expires_in_seconds"`
}
