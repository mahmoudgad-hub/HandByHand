package http

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/config"
)

// Uploading a photograph or an introduction film for the public site.
//
// This is the one write in the service that is NOT authorised by a row level
// security policy, because it does not write a row. It writes a file, and RLS
// does not reach a disk. The check is therefore here - but it asks
// hbh.has_permission, the same function every policy calls, rather than
// deciding in Go what SITE.EDIT means.
//
// WHAT THE CLIENT DOES NOT GET TO DECIDE.
//
//	The name. The stored file is named from the SHA-256 of its own contents,
//	so a caller cannot choose a path, cannot traverse out of the directory,
//	cannot overwrite somebody else's file, and cannot collide with one. The
//	same file uploaded twice is the same file once.
//
//	The type. The Content-Type header is ignored and the bytes are sniffed.
//	A header saying "image/jpeg" over an HTML document is how a file store
//	becomes a way to serve script from the centre's own origin - the one
//	origin the site's pages trust.
//
// The extension comes from the sniffed type, never from the submitted name.
var allowedUploads = map[string]struct {
	ext   string
	limit int64
}{
	"image/jpeg": {".jpg", config.MaxImageUpload},
	"image/png":  {".png", config.MaxImageUpload},
	"image/webp": {".webp", config.MaxImageUpload},
	"image/gif":  {".gif", config.MaxImageUpload},
	"video/mp4":  {".mp4", config.MaxVideoUpload},
	"video/webm": {".webm", config.MaxVideoUpload},
}

type uploadOut struct {
	// Relative to the site root, which is what site_team.photo_path and
	// intro_video_path hold and what the page puts in a src attribute.
	Path      string `json:"path"`
	MimeType  string `json:"mime_type"`
	SizeBytes int64  `json:"size_bytes"`
}

func (s *Server) handleSiteUpload(w http.ResponseWriter, req *http.Request) {
	ident, _ := auth.FromContext(req.Context())

	if s.cfg.SiteAssetsDir == "" {
		// No directory configured is not a client error. Saying "forbidden"
		// would send whoever debugs it to the permission map, which is fine.
		writeError(w, req, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}

	allowed, err := s.db.HasPermission(req.Context(), ident.Username, "SITE.EDIT")
	if err != nil {
		writeInternal(w, req, s.log, err)
		return
	}
	if !allowed {
		writeError(w, req, http.StatusForbidden, CodeForbidden)
		return
	}

	// The ceiling before anything is read. MaxVideoUpload is the larger of
	// the two; the per-type limit is applied again once the type is known,
	// so an oversized image is refused as an image and not as a video.
	req.Body = http.MaxBytesReader(w, req.Body, config.MaxVideoUpload)
	file, _, err := req.FormFile("file")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, req, http.StatusRequestEntityTooLarge, CodeTooLarge)
			return
		}
		writeErrorFields(w, req, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	defer file.Close()

	// Sniff from the first 512 bytes, which is what DetectContentType reads,
	// then rewind so the whole file is still written.
	head := make([]byte, 512)
	n, err := io.ReadFull(file, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		writeInternal(w, req, s.log, err)
		return
	}
	kind, ok := allowedUploads[stripParams(http.DetectContentType(head[:n]))]
	if !ok {
		writeErrorFields(w, req, http.StatusUnsupportedMediaType, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeInternal(w, req, s.log, err)
		return
	}

	// Written to a temporary name first and renamed once it is whole. A
	// crash halfway through otherwise leaves a truncated film under a name
	// the database already points at, and a half file is worse than none:
	// the page shows a broken player rather than no player.
	tmp, err := os.CreateTemp(s.cfg.SiteAssetsDir, ".upload-*")
	if err != nil {
		writeInternal(w, req, s.log, err)
		return
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName) // no-op once the rename has happened

	sum := sha256.New()
	written, err := io.Copy(io.MultiWriter(tmp, sum), io.LimitReader(file, kind.limit+1))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		writeInternal(w, req, s.log, err)
		return
	}
	if written > kind.limit {
		writeError(w, req, http.StatusRequestEntityTooLarge, CodeTooLarge)
		return
	}

	name := hex.EncodeToString(sum.Sum(nil))[:32] + kind.ext
	if err := os.Rename(tmpName, filepath.Join(s.cfg.SiteAssetsDir, name)); err != nil {
		writeInternal(w, req, s.log, err)
		return
	}

	s.log.Info("site upload", "user", ident.Username, "file", name, "bytes", written)
	writeJSON(w, http.StatusCreated, uploadOut{
		Path:      s.mediaPrefix(req) + name,
		MimeType:  stripParams(http.DetectContentType(head[:n])),
		SizeBytes: written,
	})
}

// The prefix the site reads media under, from hbh.sys_params.
//
// It is a row because it is a path the SITE uses, and nothing in this project
// hardcodes a value the centre might reasonably change - the same reason the
// currency and the weekend are rows.
//
// It is NOT the directory this service writes to. That stays SITE_ASSETS_DIR,
// an environment value fixed by the deployment, because a filesystem
// destination read from a table is a way for anyone who can edit that table
// to aim this service's writes somewhere else on the disk. The row decides
// what the PAGE looks under; the mount decides what the SERVICE can touch,
// and only the second one is a security boundary.
//
// A missing or malformed value falls back to "assets/" rather than failing:
// the upload has already succeeded by the time this is read, and losing the
// file over a bad parameter would be the worse outcome.
func (s *Server) mediaPrefix(r *http.Request) string {
	raw, err := s.params.Get(r.Context(), "SITE_MEDIA_PREFIX", "assets")
	if err != nil {
		return "assets/"
	}
	prefix := strings.Trim(strings.TrimSpace(raw), "/")
	// The database refuses a path with ".." in it on site_team, so a prefix
	// carrying one would produce rows that cannot be saved. Refuse it here
	// too, where the reason is legible.
	if prefix == "" || strings.Contains(prefix, "..") || strings.Contains(prefix, ":") {
		return "assets/"
	}
	return prefix + "/"
}

// DetectContentType appends "; charset=utf-8" to text types. The map is keyed
// on the bare type.
func stripParams(mime string) string {
	for i := 0; i < len(mime); i++ {
		if mime[i] == ';' {
			return mime[:i]
		}
	}
	return mime
}

// Serving an uploaded file back.
//
// The console is a different origin from the public site, so it cannot
// resolve "assets/x.jpg" the way the site does. Without this the person who
// just uploaded a photograph would be shown a broken image and have no way to
// tell whether it worked.
//
// THE NAME IS THE WHOLE ATTACK SURFACE, so it is checked twice: once as a
// pattern with no separator in it at all, and again after joining, by
// confirming the result is still inside the directory. Either check alone
// would probably do; the pair costs nothing and neither has to be perfect.
//
// Content-Disposition: attachment and a nosniff header, so a file that
// somehow got past the upload sniffing still cannot execute as script on this
// origin - the origin holding the console's session.
func (s *Server) handleSiteMediaGet(w http.ResponseWriter, req *http.Request) {
	if s.cfg.SiteAssetsDir == "" {
		writeError(w, req, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}

	name := req.PathValue("name")
	if name == "" || !safeAssetName(name) {
		writeError(w, req, http.StatusNotFound, CodeNotFound)
		return
	}

	dir, err := filepath.Abs(s.cfg.SiteAssetsDir)
	if err != nil {
		writeInternal(w, req, s.log, err)
		return
	}
	full := filepath.Join(dir, name)
	if !strings.HasPrefix(full, dir+string(filepath.Separator)) {
		writeError(w, req, http.StatusNotFound, CodeNotFound)
		return
	}

	f, err := os.Open(full)
	if err != nil {
		writeError(w, req, http.StatusNotFound, CodeNotFound)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		writeError(w, req, http.StatusNotFound, CodeNotFound)
		return
	}

	w.Header().Set("X-Content-Type-Options", "nosniff")
	// A hash name never names a different file, so it can be cached hard.
	// The legacy hand-placed names can change, so they are not.
	if len(name) > 32 && isHex(name[:32]) {
		w.Header().Set("Cache-Control", "public, max-age=31536000, immutable")
	} else {
		w.Header().Set("Cache-Control", "no-cache")
	}
	http.ServeContent(w, req, name, info.ModTime(), f)
}

// No separator, no dot-dot, no leading dot. Letters, digits, dot, dash and
// underscore is everything an asset name here has ever needed.
func safeAssetName(name string) bool {
	if len(name) > 128 || strings.Contains(name, "..") || strings.HasPrefix(name, ".") {
		return false
	}
	for _, c := range name {
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9':
		case c == '.', c == '-', c == '_':
		default:
			return false
		}
	}
	return true
}

func isHex(s string) bool {
	for _, c := range s {
		if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
			return false
		}
	}
	return true
}
