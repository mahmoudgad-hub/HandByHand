package http

import (
	"testing"
	"time"
)

// clock is a hand-cranked time source. Tests that sleep are tests that are
// slow when they pass and flaky when they fail.
type clock struct{ t time.Time }

func (c *clock) now() time.Time      { return c.t }
func (c *clock) add(d time.Duration) { c.t = c.t.Add(d) }

func fixedLimiter(perMinute int) (*limiter, *clock) {
	c := &clock{t: time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)}
	l := newLimiter(perMinute)
	l.now = c.now
	return l, c
}

func TestLimiterAllowsTheBurstThenRefuses(t *testing.T) {
	l, _ := fixedLimiter(6)
	for i := 0; i < 6; i++ {
		if !l.allow("ip") {
			t.Fatalf("request %d was refused inside the burst", i+1)
		}
	}
	if l.allow("ip") {
		t.Fatal("the seventh request was allowed")
	}
}

func TestLimiterRefillsOverTime(t *testing.T) {
	l, c := fixedLimiter(6)
	for i := 0; i < 6; i++ {
		l.allow("ip")
	}
	// Six per minute is one every ten seconds.
	c.add(10 * time.Second)
	if !l.allow("ip") {
		t.Fatal("no token had been refilled after ten seconds")
	}
	if l.allow("ip") {
		t.Fatal("two tokens were refilled where one was earned")
	}
}

// The point of the whole thing: one exhausted caller must not lock out
// everybody else.
func TestLimiterKeysAreIndependent(t *testing.T) {
	l, _ := fixedLimiter(2)
	l.allow("a")
	l.allow("a")
	if l.allow("a") {
		t.Fatal("caller a was not limited")
	}
	if !l.allow("b") {
		t.Fatal("caller b was limited by caller a")
	}
}

func TestLimiterForgetsIdleCallers(t *testing.T) {
	l, c := fixedLimiter(2)
	l.allow("a")
	c.add(idleTTL + time.Minute)
	l.allow("b")
	if _, present := l.buckets["a"]; present {
		t.Fatal("an idle bucket was kept")
	}
}
