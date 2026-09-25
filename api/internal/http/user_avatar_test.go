package http

import (
	"bytes"
	"context"
	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/config"
	"github.com/jackc/pgx/v5/pgxpool"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestUserAvatarRequiresAuthentication(t *testing.T) {
	pool, err := pgxpool.New(context.Background(), "postgres://unused:unused@127.0.0.1:1/unused")
	if err != nil {
		t.Fatal(err)
	}
	pool.Close()
	s := &Server{audit: audit.New(pool, slog.New(slog.NewTextHandler(io.Discard, nil)))}
	for _, method := range []string{http.MethodGet, http.MethodPost} {
		w := httptest.NewRecorder()
		handler := s.handleUserAvatar
		if method == http.MethodPost {
			handler = s.handleUploadUserAvatar
		}
		s.requireAuth(http.HandlerFunc(handler)).ServeHTTP(w, httptest.NewRequest(method, "/api/v1/users/1/avatar", nil))
		if w.Code != http.StatusUnauthorized {
			t.Fatalf("%s returned %d", method, w.Code)
		}
	}
}

func TestUserAvatarRejectsNonImageAttachment(t *testing.T) {
	s := &Server{cfg: config.Config{StaffDocsDir: t.TempDir()}}
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	part, _ := writer.CreateFormFile("file", "avatar.png")
	part.Write([]byte("<html>not an image</html>"))
	writer.Close()
	r := httptest.NewRequest(http.MethodPost, "/api/v1/users/1/avatar", &body)
	r.Header.Set("Content-Type", writer.FormDataContentType())
	r.SetPathValue("user_id", "1")
	w := httptest.NewRecorder()
	s.handleUploadUserAvatar(w, r)
	if w.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("expected unsupported image, got %d", w.Code)
	}
}
