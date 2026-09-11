package http

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

type requestIDKey struct{}

// RequestIDFrom returns the id assigned to this request, or "".
func RequestIDFrom(ctx context.Context) string {
	id, _ := ctx.Value(requestIDKey{}).(string)
	return id
}

func newRequestID() string {
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		return ""
	}
	return hex.EncodeToString(b[:])
}

// withRequestID stamps every request and echoes the id back.
//
// The header the client sent is never reused as the id: it would let a caller
// choose how their own actions appear in the log, and collide two requests on
// purpose.
func withRequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := newRequestID()
		w.Header().Set("X-Request-Id", id)
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), requestIDKey{}, id)))
	})
}

// trace is the one mutable thing a request carries.
//
// It exists because the request log is written by the OUTERMOST middleware and
// the three facts it needs are learned deeper in: the route template by the
// router, the identity by requireAuth, the error code by whoever refused. Each
// of those layers hands the next a NEW request value - r.WithContext returns a
// copy - so a value written into a context inside cannot be read outside. A
// pointer placed on the way in can.
//
// It is per-request and never shared: one allocation in withRequestLog, read
// once after the handler has returned. Nothing here is written concurrently,
// because a handler has exactly one goroutine that owns its response.
type trace struct {
	route     string
	ident     string
	errCode   string
	errFields map[string]any
}

type traceKey struct{}

func traceFrom(ctx context.Context) *trace {
	t, _ := ctx.Value(traceKey{}).(*trace)
	return t
}

// noteRoute records the pattern this request matched.
//
// The template, not the path: /api/v1/children/{child_id} rather than
// /api/v1/children/42. Grouping the log by path would give one row per child
// and say nothing about which endpoint is slow - and it would put a stream of
// identifiers in a table an operator reads.
//
// It comes from the router's own constant rather than from r.Pattern so that
// the value is the one this service registered, whatever the standard library
// decides to expose.
func noteRoute(pattern string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if t := traceFrom(r.Context()); t != nil {
			t.route = pattern
		}
		next.ServeHTTP(w, r)
	})
}

// statusWriter remembers what was written so the log can report it.
type statusWriter struct {
	http.ResponseWriter
	status int
	bytes  int
}

func (w *statusWriter) WriteHeader(status int) {
	if w.status == 0 {
		w.status = status
	}
	w.ResponseWriter.WriteHeader(status)
}

func (w *statusWriter) Write(b []byte) (int, error) {
	if w.status == 0 {
		w.status = http.StatusOK
	}
	n, err := w.ResponseWriter.Write(b)
	w.bytes += n
	return n, err
}

// withLogging records one line per request.
//
// It logs the path as routed, never the query string: no personal data goes in
// a URL in this system, and logging the query would quietly reward the first
// endpoint that broke that rule.
func withLogging(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			start := time.Now()
			sw := &statusWriter{ResponseWriter: w}
			next.ServeHTTP(sw, r)
			if sw.status == 0 {
				sw.status = http.StatusOK
			}
			level := slog.LevelInfo
			if sw.status >= 500 {
				level = slog.LevelError
			} else if sw.status >= 400 {
				level = slog.LevelWarn
			}
			log.Log(r.Context(), level, "request",
				"request_id", RequestIDFrom(r.Context()),
				"method", r.Method,
				"path", r.URL.Path,
				"status", sw.status,
				"bytes", sw.bytes,
				"ms", time.Since(start).Milliseconds())
		})
	}
}

// unrouted is the route recorded for a request that matched no pattern.
//
// A constant rather than the path, because the path of a 404 is chosen by
// whoever sent it: logging it verbatim would let a stranger write a thousand
// distinct rows into an operator's screen, and would file a scan of the
// identifier space as a thousand endpoints.
const unrouted = "(unrouted)"

// withRequestLog writes one row per finished request to the database.
//
// Three things about it are deliberate:
//
//   - The health probes are skipped. An orchestrator calls them every few
//     seconds forever, and burying the real traffic under them would make the
//     screen useless while making the table large.
//   - It NEVER fails a request. store.LogRequest swallows its own errors, and
//     a request that worked must not be reported as one that did not.
//   - The identity comes from the trace, so an unauthenticated request is
//     filed against nobody rather than against whoever it claimed to be.
func (s *Server) withRequestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		t := &trace{}
		r = r.WithContext(context.WithValue(r.Context(), traceKey{}, t))

		start := time.Now()
		sw := &statusWriter{ResponseWriter: w}
		next.ServeHTTP(sw, r)
		if sw.status == 0 {
			sw.status = http.StatusOK
		}

		if !s.cfg.RequestLog || r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			return
		}

		route := t.route
		if route == "" {
			route = unrouted
		}
		code := t.errCode
		if sw.status >= 400 && code == "" {
			// The schema refuses a failed row with no code, and rightly: an
			// error nobody named is an error nobody can count. This is the
			// backstop for a path that answered a failure without going
			// through writeError - a hijacked connection, a proxy that ended
			// mid-stream.
			code = CodeInternal
		}

		var detail []byte
		if len(t.errFields) > 0 {
			// The fields map names WHICH field was refused - "limit",
			// "score" - and never the value that was sent. See writeErrorFields.
			detail, _ = json.Marshal(t.errFields)
		}

		s.db.LogRequest(r.Context(), t.ident, store.RequestRecord{
			Method:     r.Method,
			Route:      route,
			Path:       r.URL.Path,
			StatusCode: sw.status,
			DurationMS: int(time.Since(start).Milliseconds()),
			RequestID:  RequestIDFrom(r.Context()),
			ClientIP:   s.clientIP(r),
			UserAgent:  r.UserAgent(),
			// ErrorMessage stays empty, always. This service answers in codes
			// and never in sentences, so there is no message to carry - and
			// the only text available to put there would be a database error,
			// which can quote a row value. A child's name in an error string
			// would put clinical data on an operations screen.
			ErrorCode: code,
			Detail:    detail,
		})
	})
}

// withRecover turns a panic into a 500 rather than a dead connection and a
// silent process.
func withRecover(log *slog.Logger) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			defer func() {
				if v := recover(); v != nil {
					log.ErrorContext(r.Context(), "panic recovered",
						"request_id", RequestIDFrom(r.Context()),
						"method", r.Method, "path", r.URL.Path, "panic", v)
					writeError(w, r, http.StatusInternalServerError, CodeInternal)
				}
			}()
			next.ServeHTTP(w, r)
		})
	}
}

// withSecurityHeaders sets the headers that matter for a JSON API.
//
// This service returns no HTML, so the policy is simply "nothing": a response
// that a browser were ever tricked into rendering has nothing it may load.
func withSecurityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Referrer-Policy", "no-referrer")
		h.Set("Content-Security-Policy", "default-src 'none'; frame-ancestors 'none'")
		next.ServeHTTP(w, r)
	})
}

// withCORS answers cross-origin requests from an exact allow list.
//
// There is no wildcard and no "reflect whatever origin asked", because this
// API carries credentials. An empty list means no cross-origin request is
// answered at all, which is what a production deployment serving the Angular
// bundle from the same origin should run with.
func withCORS(origins []string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			origin := r.Header.Get("Origin")
			if origin != "" && slices.Contains(origins, origin) {
				h := w.Header()
				h.Set("Access-Control-Allow-Origin", origin)
				h.Set("Access-Control-Allow-Credentials", "true")
				h.Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				h.Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
				h.Set("Access-Control-Max-Age", "600")
				h.Add("Vary", "Origin")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// clientIP returns the caller's address for the audit log.
//
// X-Forwarded-For is believed only when TRUST_PROXY says a proxy we control
// sets it. Without that switch the header is client-controlled, and a
// client-controlled audit trail records whatever the client preferred.
func (s *Server) clientIP(r *http.Request) *string {
	if s.cfg.TrustProxy {
		if fwd := r.Header.Get("X-Forwarded-For"); fwd != "" {
			first := strings.TrimSpace(strings.Split(fwd, ",")[0])
			if net.ParseIP(first) != nil {
				return &first
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		host = r.RemoteAddr
	}
	if net.ParseIP(host) == nil {
		return nil
	}
	return &host
}

// bearerToken extracts the session token from the Authorization header.
//
// Header only. A token in a query string ends up in every proxy log and every
// browser history, and this one is a live credential.
func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if len(h) <= len(prefix) || !strings.EqualFold(h[:len(prefix)], prefix) {
		return ""
	}
	return strings.TrimSpace(h[len(prefix):])
}

// requireAuth resolves the bearer token and puts the identity in the context.
//
// The refusal is recorded, not just returned. A denied request is an event
// worth keeping - it is the trail that shows a token being tried after it was
// revoked - and hbh.audit_attempt writes it outside this request's
// transaction so it survives however the request ends.
func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Detail: "NO_BEARER_TOKEN", ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusUnauthorized, CodeUnauthenticated)
			return
		}

		res, err := s.db.ResolveSession(r.Context(), token)
		if err != nil {
			writeInternal(w, r, s.log, err)
			return
		}
		if !res.OK {
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Detail: "SESSION_" + res.Reason, ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusUnauthorized, CodeUnauthenticated)
			return
		}

		ident := auth.Identity{Username: res.Username, UserID: res.UserID, CenterID: res.CenterID}
		// The request log is written outside this layer, by a middleware that
		// will never see the context created below. The trace is how the
		// identity reaches it - so a logged row says who made the request
		// rather than filing an authenticated call against nobody.
		if t := traceFrom(r.Context()); t != nil {
			t.ident = ident.Username
		}
		next.ServeHTTP(w, r.WithContext(auth.WithIdentity(r.Context(), ident)))
	})
}

// chain applies middleware so the first argument is the outermost layer.
func chain(h http.Handler, mw ...func(http.Handler) http.Handler) http.Handler {
	for i := len(mw) - 1; i >= 0; i-- {
		h = mw[i](h)
	}
	return h
}
