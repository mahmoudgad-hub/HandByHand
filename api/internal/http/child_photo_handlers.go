package http

import (
	"bytes"
	"errors"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/config"
)

// A child's photograph.
//
// This replaces hbh.children.photo_url, which held an address and nothing
// else. Three things were wrong with a column:
//
//   - A URL is a capability. Row level security protects the ROW; once the
//     address inside it has been read it works for whoever holds it, from
//     anywhere, with no identity and no expiry. This project's rules say no
//     personal data in a link, and a photograph of a child is the most
//     personal datum in the schema.
//   - Nothing recorded that a family had agreed to the centre holding it.
//   - And nobody could answer who had looked.
//
// All three are answered by moving the picture onto the rail that already
// existed. The bytes live in hbh.attachments, the consent is enforced by a
// trigger in the schema, and the read below is recorded explicitly - triggers
// do not fire on reads, so a read that is not written down did not happen as
// far as the trail is concerned.
//
// BOTH ROUTES ARE BEHIND requireAuth, which means a browser cannot fetch one
// from an <img src>: a plain navigation carries no bearer token and would get
// 401. The console reads it through the HTTP client and renders the blob.
// That is not a workaround - it is the only correct way to show an
// authenticated image, and it is why neither route tries to be clever with a
// guessable name.

// POST /api/v1/children/{child_id}/photo
//
// Refused unless a guardian linked to this child has a recorded PHOTO_USE
// consent. That refusal comes from the database (HB123) and not from a check
// here, so it holds for every caller on every path - including a console
// somebody writes next year.
func (s *Server) handleUploadChildPhoto(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	childID, ok := pathID(r, "child_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	r.Body = http.MaxBytesReader(w, r.Body, config.MaxImageUpload)
	file, header, err := r.FormFile("file")
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

	// Read it once, into memory, because hbh.attachments stores the bytes
	// and computes the digest over them. The size ceiling is what makes
	// that safe, and it is checked twice: MaxBytesReader on the request and
	// the length below, because a multipart part can lie about its length.
	content, err := io.ReadAll(io.LimitReader(file, config.MaxImageUpload+1))
	if err != nil {
		writeInternal(w, r, s.log, err)
		return
	}
	if int64(len(content)) > config.MaxImageUpload {
		writeError(w, r, http.StatusRequestEntityTooLarge, CodeTooLarge)
		return
	}
	if len(content) == 0 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "file"})
		return
	}

	// SNIFFED, never taken from the client. A caller that says image/jpeg
	// decides nothing here; the first bytes do. The schema refuses a
	// non-image portrait as well (HB124 and ck_att_photo_shape), so this is
	// the outer of two gates rather than the only one.
	mime := stripParams(http.DetectContentType(content))
	ext, allowed := map[string]string{
		"image/jpeg": ".jpg", "image/png": ".png", "image/webp": ".webp",
	}[mime]
	if !allowed {
		writeErrorFields(w, r, http.StatusUnsupportedMediaType, CodeValidation,
			map[string]any{"field": "file"})
		return
	}

	// A name for the record, not for addressing. Nothing resolves a
	// portrait by its file name - the row is the address - so this is
	// only what somebody reads in an audit line. The uploaded name is
	// discarded rather than stored: it routinely carries a child's name,
	// and a filename is not a field anybody agreed to fill in.
	_ = header
	name := "child-" + strconv.Itoa(childID) + "-" +
		strconv.FormatInt(time.Now().UTC().Unix(), 10) + ext

	id, err := s.db.SetChildPhoto(r.Context(), ident.Username, childID, name, mime, content)
	if err != nil {
		s.opsError(w, r, "SET_CHILD_PHOTO", err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"attachment_id": id, "size_bytes": len(content),
	})
}

// GET /api/v1/children/{child_id}/photo
func (s *Server) handleChildPhoto(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	childID, ok := pathID(r, "child_id")
	if !ok {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	photo, err := s.db.ChildPhoto(r.Context(), ident.Username, childID)
	if err != nil {
		s.opsError(w, r, "READ_CHILD_PHOTO", err)
		return
	}

	// Recorded before it is served, and by attachment id rather than by
	// child: the id says exactly which picture was handed over, which is
	// the question somebody asks after a consent is withdrawn.
	s.audit.Record(r.Context(), audit.Event{
		Action: audit.ActionRead, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail: "CHILD_PHOTO " + strconv.Itoa(photo.AttachmentID), ClientIP: s.clientIP(r),
	})

	w.Header().Set("X-Content-Type-Options", "nosniff")
	// Never cached by a shared cache, and revalidated every time: this is
	// personal data, and a proxy holding a copy is a copy nobody granted.
	w.Header().Set("Cache-Control", "private, no-store")
	if photo.MimeType != "" {
		w.Header().Set("Content-Type", photo.MimeType)
	}
	// A zero time, so no Last-Modified is emitted. The stored row has no
	// modification instant a client should be caching against, and a header
	// that invites revalidation of a no-store response is noise.
	http.ServeContent(w, r, "photo", time.Time{}, bytes.NewReader(photo.Content))
}
