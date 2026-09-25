package domain

import "time"

// MeetingPass is the entire answer a client gets when it may enter a
// consultation.
//
// Read the fields that are NOT here, because they are the design:
//
//   - no appointment, no child, no therapist, no service. The caller asked
//     about an appointment it already named; repeating any of it back would
//     put a child's affairs into a response that is about opening a video
//     window.
//   - no room_ref. Room is the name AT THE PROVIDER, which for JaaS is
//     namespaced under the tenant. The secret in hbh.meetings.room_ref is
//     never sent as itself, so a copied response is a pass that expires
//     rather than a door that stays open.
//   - no expiry seconds for a renewal. There is no renewal. When this pass
//     dies the page asks the door again, and the door asks all of its
//     questions again - which is the point of it being short.
//
// AND ONE FIELD THAT IS HERE AND WOULD RATHER NOT BE. Token is a live
// credential in JavaScript, which the live-stream path deliberately avoids by
// keeping its token in an HttpOnly cookie and proxying the video. Real-time
// media cannot be proxied: the browser negotiates with the provider directly,
// so it must authenticate directly. Migration 0120 records the decision and
// what narrows it.
type MeetingPass struct {
	// Provider is which company is carrying this call, so the page loads the
	// right client rather than holding a constant that a change of provider
	// would strand.
	Provider string `json:"provider"`

	// Domain is the host the embedded client loads from. It is also what the
	// deployment's Content-Security-Policy has to allow, and the two must
	// agree or the video is a blank box with nothing in the console.
	Domain string `json:"domain"`

	Room string `json:"room"`

	// Token is empty for a provider that has none - the development one.
	// A client must not read "" as "refused": a refusal is a status code.
	Token string `json:"token,omitempty"`

	// DisplayName is what the provider will show in the waiting room. It is
	// returned so the page can show the family the same name the therapist
	// is about to see, rather than leaving them to wonder who "guest-481"
	// is on the other side.
	DisplayName string `json:"display_name"`

	// Moderator says whether this pass runs the room. The page uses it to
	// decide what to show, never to decide what is allowed - the claim
	// inside the signed token is what the provider enforces.
	Moderator bool `json:"moderator"`

	ExpiresAt time.Time `json:"expires_at"`
}
