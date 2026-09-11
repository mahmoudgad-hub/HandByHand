package http

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

// The centre's own billing figures.
//
// NO STATUS CODE IS WRITTEN AS A NUMBER HERE, and the reason is not
// tidiness. A bare integer is accepted by the compiler whatever it is, so
// writeError(w, r, 304, CodeForbidden) builds and ships and answers a
// refusal with "not modified". The named constants are the only spelling
// the compiler can check. Half this file used them and half did not.
//
// AND THE PERMISSION IS NOT ASKED HERE. It used to be: a separate
// s.db.HasPermission call, in its own transaction, before the read in
// another. What it asked was right - hbh.has_permission, the same
// function the policies call - but two transactions mean the permission
// was true under one snapshot and the data read under a second. The ask
// now happens at the door of the transaction that does the reading, and
// store.ErrForbidden comes back. See store.requireBillingView.

func (s *Server) handleBillingSummary(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())
	rows, err := s.db.BillingSummary(r.Context(), ident.Username)
	if err != nil {
		s.billingError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"currencies": rows})
}

// handleBillingLedger returns one page of payments, packages or balances.
//
// The page size is fixed by the server rather than taken from the query.
// A caller that could name it could ask for the whole ledger in one
// request, which is a different endpoint with different costs than the
// one anybody reviewed.
func (s *Server) handleBillingLedger(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	// The kind is an allow list, not a parameter: it selects one of three
	// queries written in this repository, and anything else is a 400
	// rather than a name that reaches SQL.
	kind := r.URL.Query().Get("kind")
	if kind != "payments" && kind != "packages" && kind != "balances" {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"kind": "payments|packages|balances"})
		return
	}

	page := 1
	if raw := r.URL.Query().Get("page"); raw != "" {
		n, err := strconv.Atoi(raw)
		if err != nil || n < 1 || n > 100000 {
			badQuery(w, r, errBadPage)
			return
		}
		page = n
	}

	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if len(q) > 400 {
		writeErrorFields(w, r, http.StatusBadRequest, CodeValidation,
			map[string]any{"field": "q"})
		return
	}

	rows, total, err := s.db.BillingLedger(r.Context(), ident.Username, kind, q, (page-1)*ledgerPageSize)
	if err != nil {
		s.billingError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"rows": rows, "total": total, "limit": ledgerPageSize,
	})
}

// ledgerPageSize is the server's, not the caller's. See handleBillingLedger.
const ledgerPageSize = 25

// billingError maps the two answers these reads can give.
//
// ErrForbidden is answered as a refusal rather than as an empty list -
// the shape used elsewhere in this service - because an empty billing
// screen reads as "the centre is owed nothing". Telling somebody a
// number they may not have is worse than telling them they may not have
// it, and refusing discloses nothing: every centre has billing.
func (s *Server) billingError(w http.ResponseWriter, r *http.Request, err error) {
	if errors.Is(err, store.ErrForbidden) {
		writeError(w, r, http.StatusForbidden, CodeForbidden)
		return
	}
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}
	writeInternal(w, r, s.log, err)
}
