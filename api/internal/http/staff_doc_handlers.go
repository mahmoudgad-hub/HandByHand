package http

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/config"
)

// A member of staff's scanned documents.
//
// NOT the site media route, and the difference is the whole design.
// /api/v1/site-media is unauthenticated on purpose: it serves a public
// page's photographs, named by a content hash. A scan of somebody's
// identity card must never touch that route, that directory, or that
// naming scheme - so it has its own of each.
//
//	NAMED FROM RANDOM BYTES, not from the contents. A content hash is a
//	stable identifier for a file, which is a useful property for a public
//	photograph and a liability here: two people who submit copies of the
//	same document would get the same name, and anybody holding the file
//	could confirm it is stored by asking for its hash.
//
//	SERVED ONLY THROUGH THE DATABASE. The download route does not take a
//	filename - it takes a document id, reads the row AS THE CALLER, and
//	only then opens what the row names. Row level security decides, so a
//	caller who may not see the row gets the same "not found" as one
//	asking about a document that does not exist. There is no path a
//	client can construct.
//
// The permission is not checked here either. The INSERT is subject to
// p_sd_insert, which admits STAFF.PII or the person's own record; a
// check in Go would be a second answer to the same question.

const maxStaffDoc = 20 * 1024 * 1024

var staffDocTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"image/webp":      ".webp",
	"application/pdf": ".pdf",
}

// POST /api/v1/users/{user_id}/documents
//
// The file and the row are written together. Splitting them would leave
// the upload endpoint answering to anybody authenticated - it cannot know
// whose document it is until the row names one - and a directory of
// unreferenced scans is exactly the thing not to have.
func (s *Server) handleUploadStaffDoc(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	if s.cfg.StaffDocsDir == "" {
		writeError(w, r, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}
	userID, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, maxStaffDoc)
	file, _, err := r.FormFile("file")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, r, http.StatusRequestEntityTooLarge, CodeTooLarge)
			return
		}
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	defer file.Close()

	kind := strings.ToUpper(strings.TrimSpace(r.FormValue("kind")))
	switch kind {
	case "ID", "QUALIFICATION", "CONTRACT", "OTHER":
	default:
		kind = "OTHER"
	}

	// Sniffed, never trusted from the header. A document store that will
	// accept anything labelled image/jpeg is a way to put a file of the
	// attacker's choosing on the centre's disk.
	head := make([]byte, 512)
	n, err := io.ReadFull(file, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		writeInternal(w, r, s.log, err)
		return
	}
	mime := stripParams(http.DetectContentType(head[:n]))
	ext, allowed := staffDocTypes[mime]
	if !allowed {
		writeErrorFields(w, r, http.StatusUnsupportedMediaType, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	// Random, not derived from the bytes. See the note at the top.
	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	name := hex.EncodeToString(raw) + ext

	tmp, err := os.CreateTemp(s.cfg.StaffDocsDir, ".upload-*")
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	written, err := io.Copy(tmp, io.LimitReader(file, maxStaffDoc+1))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if written > maxStaffDoc {
		writeError(w, r, http.StatusRequestEntityTooLarge, CodeTooLarge)
		return
	}

	// THE ROW FIRST, then the rename. If the policy refuses - not this
	// caller's record and no STAFF.PII - the file is still a temporary
	// name that the deferred Remove deletes. A scan of somebody's
	// identity card must not survive a refused write.
	id, err := s.db.AddStaffDocument(r.Context(), ident.Username,
		userID, kind, name, r.FormValue("title_ar"), mime, written)
	if err != nil {
		s.opsError(w, r, "ADD_STAFF_DOCUMENT", err)
		return
	}

	if err := os.Rename(tmpName, filepath.Join(s.cfg.StaffDocsDir, name)); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	s.log.Info("staff document stored", "actor", ident.Username, "document", id)
	writeJSON(w, http.StatusCreated, map[string]any{
		"document_id": id, "mime_type": mime, "size_bytes": written,
	})
}

// GET /api/v1/staff-documents/{document_id}/file
//
// Addressed by ROW, never by filename. The row is read as the caller, so
// row level security answers "may you"; a caller who may not see it gets
// the same not-found as one asking about a document that is not there.
//
// The read is recorded. Triggers do not see SELECTs, and "who looked at
// this person's identity card, and when" is a question this table has to
// be able to answer.
func (s *Server) handleStaffDocFile(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	if s.cfg.StaffDocsDir == "" {
		writeError(w, r, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}
	id, ok := pathID(r, "document_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	doc, err := s.db.StaffDocument(r.Context(), ident.Username, id)
	if err != nil {
		s.opsError(w, r, "READ_STAFF_DOCUMENT", err)
		return
	}

	// The stored name is written by this service and never by a client,
	// but it is checked anyway: the value travels through a database a
	// future migration could let something else write to.
	if !safeAssetName(doc.Path) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	dir, err := filepath.Abs(s.cfg.StaffDocsDir)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	full := filepath.Join(dir, doc.Path)
	if !strings.HasPrefix(full, dir+string(filepath.Separator)) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	f, err := os.Open(full)
	if err != nil {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action: audit.ActionRead, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail: "STAFF_DOCUMENT " + doc.Path, ClientIP: s.clientIP(r),
	})

	w.Header().Set("X-Content-Type-Options", "nosniff")
	// Never cached by a shared cache, and revalidated every time: this is
	// personal data, and a proxy holding a copy is a copy nobody granted.
	w.Header().Set("Cache-Control", "private, no-store")
	if doc.MimeType != "" {
		w.Header().Set("Content-Type", doc.MimeType)
	}
	http.ServeContent(w, r, doc.Path, info.ModTime(), f)
}

// A member of staff's photograph.
//
// It lives with the documents and NOT with the site's media, and the
// reason is worth stating because it is not obvious: a photograph of an
// employee is not marketing. The people whose pictures belong on the
// public page are in hbh.site_team, where a row cannot be published
// without a recorded consent to be shown. This one is a personnel record
// - it is here because the centre keeps staff files, and nobody agreed to
// have it on the internet.
//
// So it is served by the same authenticated, row-resolved route as the
// rest of the personnel file, and it is stored in the same directory,
// which no open route can reach.

// POST /api/v1/users/{user_id}/photo
func (s *Server) handleUploadStaffPhoto(w http.ResponseWriter, r *http.Request) {
	s.uploadAccountImage(w, r, false)
}

func (s *Server) handleUploadUserAvatar(w http.ResponseWriter, r *http.Request) {
	s.uploadAccountImage(w, r, true)
}

func (s *Server) uploadAccountImage(w http.ResponseWriter, r *http.Request, avatar bool) {
	ident, _ := auth.FromContext(r.Context())

	if s.cfg.StaffDocsDir == "" {
		writeError(w, r, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}
	userID, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, config.MaxImageUpload)
	file, _, err := r.FormFile("file")
	if err != nil {
		var tooBig *http.MaxBytesError
		if errors.As(err, &tooBig) {
			writeError(w, r, http.StatusRequestEntityTooLarge, CodeTooLarge)
			return
		}
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	defer file.Close()

	head := make([]byte, 512)
	n, err := io.ReadFull(file, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) && !errors.Is(err, io.EOF) {
		writeInternal(w, r, s.log, err)
		return
	}
	mime := stripParams(http.DetectContentType(head[:n]))
	// Images only. A PDF is a document and belongs on the documents route,
	// where it gets a kind and a title; letting one in here would put a
	// file nothing can render behind an <img>.
	ext, allowed := map[string]string{
		"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
	}[mime]
	if !allowed {
		writeErrorFields(w, r, http.StatusUnsupportedMediaType, CodeValidation,
			map[string]any{"field": "file"})
		return
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	raw := make([]byte, 16)
	if _, err := rand.Read(raw); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	name := hex.EncodeToString(raw) + ext

	tmp, err := os.CreateTemp(s.cfg.StaffDocsDir, ".upload-*")
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)

	written, err := io.Copy(tmp, io.LimitReader(file, config.MaxImageUpload+1))
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if written > config.MaxImageUpload {
		writeError(w, r, http.StatusRequestEntityTooLarge, CodeTooLarge)
		return
	}

	// The row before the rename, as on the documents route: a refused
	// write must not leave the file behind.
	save := s.db.SetStaffPhoto
	if avatar {
		save = s.db.SetUserAvatar
	}
	if err := save(r.Context(), ident.Username, userID, name); err != nil {
		s.opsError(w, r, "SET_STAFF_PHOTO", err)
		return
	}
	if err := os.Rename(tmpName, filepath.Join(s.cfg.StaffDocsDir, name)); err != nil {
		writeInternal(w, r, s.log, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{"size_bytes": written})
}

// GET /api/v1/users/{user_id}/photo
//
// Behind requireAuth, so a browser cannot fetch it from an <img src>. The
// console reads it through the HTTP client, which carries the session
// token, and renders the blob - which is the only correct way to show an
// authenticated image and is why this route does not try to be clever
// with a guessable name.
func (s *Server) handleStaffPhoto(w http.ResponseWriter, r *http.Request) {
	s.serveAccountImage(w, r, false)
}

func (s *Server) handleUserAvatar(w http.ResponseWriter, r *http.Request) {
	s.serveAccountImage(w, r, true)
}

func (s *Server) serveAccountImage(w http.ResponseWriter, r *http.Request, avatar bool) {
	ident, _ := auth.FromContext(r.Context())

	if s.cfg.StaffDocsDir == "" {
		writeError(w, r, http.StatusServiceUnavailable, CodeUnavailable)
		return
	}
	userID, ok := pathID(r, "user_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	read := s.db.StaffPhoto
	if avatar {
		read = s.db.UserAvatar
	}
	name, err := read(r.Context(), ident.Username, userID)
	if err != nil {
		s.opsError(w, r, "READ_STAFF_PHOTO", err)
		return
	}
	if !safeAssetName(name) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	dir, err := filepath.Abs(s.cfg.StaffDocsDir)
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	full := filepath.Join(dir, name)
	if !strings.HasPrefix(full, dir+string(filepath.Separator)) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	f, err := os.Open(full)
	if err != nil {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "private, no-store")
	http.ServeContent(w, r, name, info.ModTime(), f)
}
