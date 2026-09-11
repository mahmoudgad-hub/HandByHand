package http

import (
	"sync"
	"time"
)

// A token bucket over the login endpoints.
//
// The database already throttles a single account: hbh.request_otp refuses a
// second code inside OTP_RESEND_SECONDS, and hbh.verify_otp locks the account
// after OTP_MAX_ATTEMPTS. Neither of those constrains a caller who walks a
// list of numbers, one attempt each - every request is the first for its
// account and every one is allowed. That is the gap this closes, and it is why
// the key is the caller's address rather than the mobile number.
//
// It is deliberately in memory. A shared store would be the right answer for
// several instances behind a balancer; there is one instance, and a limiter
// that needs its own infrastructure to start is a limiter that gets turned off.
type limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket

	ratePerSecond float64
	burst         float64
	lastSweep     time.Time

	// now is injectable so the tests can move time without sleeping.
	now func() time.Time
}

type bucket struct {
	tokens float64
	seen   time.Time
}

// idleTTL is how long an untouched bucket is kept. Long enough that a caller
// cannot reset their own limit by pausing, short enough that the map does not
// grow with every address that ever knocked.
const idleTTL = 10 * time.Minute

func newLimiter(perMinute int) *limiter {
	return &limiter{
		buckets:       make(map[string]*bucket),
		ratePerSecond: float64(perMinute) / 60,
		burst:         float64(perMinute),
		now:           time.Now,
	}
}

// allow takes one token for key, reporting whether there was one to take.
func (l *limiter) allow(key string) bool {
	now := l.now()

	l.mu.Lock()
	defer l.mu.Unlock()

	l.sweepLocked(now)

	b, ok := l.buckets[key]
	if !ok {
		b = &bucket{tokens: l.burst}
		l.buckets[key] = b
	} else {
		b.tokens += now.Sub(b.seen).Seconds() * l.ratePerSecond
		if b.tokens > l.burst {
			b.tokens = l.burst
		}
	}
	b.seen = now

	if b.tokens < 1 {
		return false
	}
	b.tokens--
	return true
}

// sweepLocked drops idle buckets, at most once a minute. The caller holds the
// lock.
func (l *limiter) sweepLocked(now time.Time) {
	if now.Sub(l.lastSweep) < time.Minute {
		return
	}
	l.lastSweep = now
	for k, b := range l.buckets {
		if now.Sub(b.seen) > idleTTL {
			delete(l.buckets, k)
		}
	}
}
