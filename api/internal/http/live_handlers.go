package http

import (
	"errors"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/handbyhand/hbh/api/internal/store"
)

// Watching a child in a therapy session is the most sensitive thing this
// system does. Three rules from CLAUDE.md shape every line in this file:
//
//   * live only, never recorded. Nothing here writes a byte of media
//     anywhere; the proxy streams and forgets.
//   * the token is opaque, at most fifteen minutes, hashed at rest, and bound
//     to one session, one camera and one user. All four are the database's
//     doing - the cap is in the issuing function AND in a CHECK on the row.
//   * no camera link, no address and no credential in any place a client can
//     reach. That is why the browser never receives the gateway path, and why
//     it never receives the token either.
//
// The shape that follows from those rules: the API holds the credential, the
// browser holds a cookie it cannot read, and the media travels through here.

const (
	// streamCookie holds the stream token. HttpOnly, so no script can read
	// it; scoped to the playback path, so it is not sent anywhere else;
	// SameSite=Strict, so another site cannot embed the stream and have the
	// browser attach it.
	streamCookie = "hbh_stream"
	streamPath   = "/api/v1/stream"
	playbackPath = "/api/v1/stream/media"
)

// handleOpenStream issues a viewing window on a running session.
//
// The response body carries no token, no gateway path, no camera. See
// domain.StreamGrant for why each is absent.
func (s *Server) handleOpenStream(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	sessionID, err := strconv.Atoi(r.PathValue("session_id"))
	if err != nil || sessionID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	// Is the session even visible to this caller? Answering that first lets a
	// refusal to WATCH be distinguished from a session that is not theirs,
	// without the second case ever confirming that the session exists.
	visible, err := s.db.SessionVisible(r.Context(), ident.Username, sessionID)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if !visible {
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
			Detail:   "SESSION_NOT_VISIBLE session_id=" + strconv.Itoa(sessionID),
			ClientIP: s.clientIP(r),
		})
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	token, err := s.db.IssueStreamToken(r.Context(), ident.Username, sessionID, s.clientIP(r))
	if err != nil {
		switch store.Code(err) {
		case store.ErrLiveRefused:
			// The session IS visible, so 403 confirms nothing new: this
			// guardian may see their child's session and has not been granted
			// can_view_live_flg on the link. The database has already written
			// its own DENY record from inside issue_stream_token.
			writeError(w, r, http.StatusForbidden, CodeForbidden)
		case store.ErrLiveNotRunning:
			writeError(w, r, http.StatusConflict, CodeNotLive)
		case store.ErrGatewayUnusable:
			// The default state of a fresh install, and it must stay an
			// obvious refusal rather than a puzzling blank player.
			s.log.WarnContext(r.Context(), "live stream refused: the media gateway is not usable",
				"session_id", sessionID)
			writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		default:
			writeInternal(w, r, s.log, err)
		}
		return
	}

	ttl := time.Until(token.ExpiresAt)
	if ttl < 0 {
		ttl = 0
	}

	http.SetCookie(w, &http.Cookie{
		Name:     streamCookie,
		Value:    token.Token,
		Path:     streamPath,
		HttpOnly: true,
		Secure:   s.isTLS(r),
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(ttl.Seconds()),
	})

	writeJSON(w, http.StatusCreated, domain.StreamGrant{
		PlaybackPath:     playbackPath,
		ExpiresAt:        token.ExpiresAt,
		ExpiresInSeconds: int(ttl.Seconds()),
	})
}

// handleCloseStream ends a viewing window early.
func (s *Server) handleCloseStream(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie(streamCookie); err == nil && c.Value != "" {
		if _, err := s.db.RevokeStreamToken(r.Context(), c.Value); err != nil {
			writeInternal(w, r, s.log, err)
			return
		}
	}
	s.clearStreamCookie(w, r)
	w.WriteHeader(http.StatusNoContent)
}

// handleStreamMedia proxies the live stream.
//
// This is the only endpoint in the service that is NOT authenticated by the
// bearer token, and the reason is concrete: a <video> element cannot set an
// Authorization header. It is authenticated by the stream cookie instead,
// which is a strictly narrower credential - one session, one camera, one user,
// at most fifteen minutes, revocable, and unreadable by script.
func (s *Server) handleStreamMedia(w http.ResponseWriter, r *http.Request) {
	cookie, err := r.Cookie(streamCookie)
	if err != nil || cookie.Value == "" {
		writeError(w, r, http.StatusUnauthorized, CodeUnauthenticated)
		return
	}

	target, err := s.db.ResolveStreamToken(r.Context(), cookie.Value)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if !target.OK {
		// Every reason here means "stop watching now", including
		// SESSION_ENDED - a token outliving its session would otherwise be a
		// window into an empty room, or into the next child's session in the
		// same room. The cookie goes with the refusal so the player does not
		// keep retrying with a credential that is already dead.
		s.clearStreamCookie(w, r)
		s.audit.Record(r.Context(), audit.Event{
			Action: audit.ActionDeny, Detail: "STREAM_" + target.Reason, ClientIP: s.clientIP(r),
		})
		writeError(w, r, http.StatusUnauthorized, CodeUnauthenticated)
		return
	}

	// The base URL is read from sys_params through the database, not from this
	// service's environment. issue_stream_token consulted the same parameter
	// before minting the token; a second copy in an environment variable could
	// disagree with the value the safety check actually looked at.
	base, err := s.db.GatewayBase(r.Context(), "")
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	upstream, err := gatewayURL(base, target.GatewayPath)
	if err != nil {
		s.log.ErrorContext(r.Context(), "the media gateway address is unusable", "err", err)
		writeError(w, r, http.StatusServiceUnavailable, CodeStreamUnavailable)
		return
	}

	s.proxy(upstream).ServeHTTP(w, r)
}

// gatewayURL joins the configured base with the camera's path.
//
// The path itself is constrained by the database to ^[A-Za-z0-9_/-]{1,120}$,
// so it cannot contain a scheme, a host, a query or a traversal - but this
// function refuses anything odd anyway rather than trusting that constraint to
// be the only writer the table ever has.
func gatewayURL(base, path string) (*url.URL, error) {
	base = strings.TrimSpace(base)
	if base == "" {
		return nil, errors.New("MEDIA_GATEWAY_BASE_URL is empty")
	}
	u, err := url.Parse(base)
	if err != nil {
		return nil, err
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return nil, errors.New("the media gateway base must be an http or https URL")
	}
	if u.Host == "" {
		return nil, errors.New("the media gateway base has no host")
	}
	if path == "" || strings.ContainsAny(path, "?#\\") || strings.Contains(path, "..") {
		return nil, errors.New("the camera path is not a plain path")
	}
	return u.JoinPath(path), nil
}

// proxy streams the upstream response through, and is written to leak nothing
// about where it came from.
func (s *Server) proxy(upstream *url.URL) *httputil.ReverseProxy {
	return &httputil.ReverseProxy{
		// -1 flushes as soon as bytes arrive. Anything else buffers a live
		// stream into a delayed one.
		FlushInterval: -1,

		Rewrite: func(pr *httputil.ProxyRequest) {
			pr.Out.URL = upstream
			pr.Out.Host = upstream.Host

			// A fresh header set, built from an allow list. The inbound
			// request carries the viewer's session cookie and possibly their
			// bearer token, and neither has any business reaching a media
			// gateway.
			out := make(http.Header, 4)
			for _, h := range []string{"Range", "Accept", "Accept-Encoding", "If-Range"} {
				if v := pr.In.Header.Get(h); v != "" {
					out.Set(h, v)
				}
			}
			pr.Out.Header = out
			// Deliberately no SetXForwarded: the gateway does not need to
			// know the family's address, and this is a chance to send it.
		},

		ModifyResponse: func(resp *http.Response) error {
			// A redirect would hand the browser the gateway's own address in
			// a Location header - exactly the disclosure this whole design
			// exists to prevent. Refuse rather than forward it.
			if resp.StatusCode >= 300 && resp.StatusCode < 400 {
				return errors.New("the media gateway answered with a redirect, which would disclose its address")
			}
			for _, h := range []string{"Server", "X-Powered-By", "Via", "Location", "Content-Location"} {
				resp.Header.Del(h)
			}
			return nil
		},

		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			// The cause goes to the log; the client gets a code. The error
			// text from a failed dial contains the gateway's host and port.
			s.log.ErrorContext(r.Context(), "the media gateway could not be reached",
				"request_id", RequestIDFrom(r.Context()), "err", err)
			writeError(w, r, http.StatusBadGateway, CodeStreamUnavailable)
		},
	}
}

func (s *Server) clearStreamCookie(w http.ResponseWriter, r *http.Request) {
	http.SetCookie(w, &http.Cookie{
		Name:     streamCookie,
		Value:    "",
		Path:     streamPath,
		HttpOnly: true,
		Secure:   s.isTLS(r),
		SameSite: http.SameSiteStrictMode,
		MaxAge:   -1,
	})
}

// isTLS reports whether the request reached us over TLS, and therefore
// whether the stream cookie may be marked Secure.
//
// X-Forwarded-Proto is believed only when TRUST_PROXY declares a proxy we
// control, for the same reason X-Forwarded-For is: otherwise it is a header
// the client writes, and here it decides whether a live credential is allowed
// to travel in clear text.
func (s *Server) isTLS(r *http.Request) bool {
	if r.TLS != nil {
		return true
	}
	if s.cfg.TrustProxy {
		return strings.EqualFold(r.Header.Get("X-Forwarded-Proto"), "https")
	}
	return false
}
