package http

import (
	"testing"
	"time"

	"github.com/handbyhand/hbh/api/internal/store"
)

// THE CONDITION THAT MADE A WHOLE FEATURE UNREACHABLE.
//
// validAppointment demanded `RoomID > 0` on every booking. Migration 0117 had
// made an appointment able to be ONLINE, 0120-0124 built its room, its door
// and its pass, the portal drew the screen, and 1150 acceptance checks passed
// - and nobody could book one, because this function answered 400 before the
// schema was ever asked. Nothing was broken. One line was simply older than
// the feature, and no test in the tree could see it.
//
// So these tests assert the SHAPE rule and, more importantly, the boundary:
// this function decides what a booking looks like, and hbh.validate_slot
// decides whether it is allowed. Anything here that starts having an opinion
// about rooms and modes is a second copy of a rule that already exists.

func aBooking() store.NewAppointment {
	start := time.Now().Add(24 * time.Hour)
	return store.NewAppointment{
		ChildID:     1,
		TherapistID: 2,
		ServiceID:   3,
		StartsAt:    start,
		EndsAt:      start.Add(45 * time.Minute),
	}
}

func intp(n int) *int { return &n }

func TestABookingWithNoRoomIsAcceptedForShape(t *testing.T) {
	// The regression itself. An online consultation names no room, and this
	// function must not be the thing that refuses it.
	in := aBooking()
	in.DeliveryMode = "ONLINE"
	in.RoomID = nil

	if !validAppointment(in) {
		t.Fatal("a roomless online booking was refused on shape; " +
			"whether it may be roomless is hbh.validate_slot's answer, not this one")
	}
}

func TestAnInPersonBookingWithNoRoomIsAlsoAcceptedForShape(t *testing.T) {
	// Deliberate, and worth stating: IN_PERSON with no room IS refused - by
	// validate_slot, with ROOM_REQUIRED, which is a sentence the screen can
	// show. Refusing it here would produce a bare 400 instead, and the
	// receptionist would be told the request was malformed rather than that
	// she had not picked a room.
	in := aBooking()
	in.DeliveryMode = "IN_PERSON"
	in.RoomID = nil

	if !validAppointment(in) {
		t.Fatal("refused on shape; ROOM_REQUIRED from validate_slot is the answer " +
			"that names the missing field")
	}
}

func TestARoomThatIsNotAnIdentifierIsRefused(t *testing.T) {
	in := aBooking()
	in.RoomID = intp(0)

	if validAppointment(in) {
		t.Fatal("room 0 was accepted; it is not a room, and sending it to the " +
			"schema asks about a row that cannot exist")
	}
}

func TestTheOrdinaryBookingStillWorks(t *testing.T) {
	// The acceptance half. A test file that only proves refusals stays green
	// on a function that refuses everything.
	in := aBooking()
	in.RoomID = intp(7)

	if !validAppointment(in) {
		t.Fatal("an ordinary in-person booking with a room was refused")
	}
}

func TestDeliveryModeIsAllowedByName(t *testing.T) {
	for _, mode := range []string{"", "IN_PERSON", "ONLINE", "EXTERNAL"} {
		if !validDeliveryMode(mode) {
			t.Errorf("%q is a mode the schema admits and this refused it", mode)
		}
	}
}

func TestAnUnknownDeliveryModeIsRefusedHere(t *testing.T) {
	// Not passed through. An unknown string reaches validate_slot and comes
	// back as 200 ok:false BAD_DELIVERY_MODE, which a screen renders as "that
	// hour is not available" - a sentence about the diary for what is
	// actually a typo in a request.
	for _, mode := range []string{"online", "IN PERSON", "VIDEO", "TELEPATHY"} {
		if validDeliveryMode(mode) {
			t.Errorf("%q was accepted; the schema does not know it", mode)
		}
	}
}

func TestEmptyModeMeansInPerson(t *testing.T) {
	// The default is applied in the struct rather than by leaving the
	// argument off, so what the schema receives is what this type says.
	if got := (store.NewAppointment{}).Mode(); got != "IN_PERSON" {
		t.Fatalf("an unset delivery mode became %q, not IN_PERSON", got)
	}
	if got := (store.NewAppointment{DeliveryMode: "ONLINE"}).Mode(); got != "ONLINE" {
		t.Fatalf("a set delivery mode was overwritten with %q", got)
	}
}
