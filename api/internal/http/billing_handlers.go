package http

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"github.com/handbyhand/hbh/api/internal/audit"
	"github.com/handbyhand/hbh/api/internal/auth"
	"github.com/handbyhand/hbh/api/internal/store"
)

func (s *Server) handleInvoices(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_INVOICES", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Invoices(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"invoices": rows}, nil
	})
}

func (s *Server) handlePackages(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_PACKAGES", func(ctx context.Context, ident string, childID int) (any, error) {
		rows, err := s.db.Packages(ctx, ident, childID)
		if err != nil {
			return nil, err
		}
		return map[string]any{"packages": rows}, nil
	})
}

func (s *Server) handleBalance(w http.ResponseWriter, r *http.Request) {
	s.childRead(w, r, "CHILD_BALANCE", func(ctx context.Context, ident string, childID int) (any, error) {
		return s.db.Balance(ctx, ident, childID)
	})
}

// handleInvoice reads one invoice by its own identifier.
//
// Like the report endpoint, it carries no child in the path and needs no
// ownership check: the policy on hbh.invoices requires can_access_child, and
// for a guardian without BILLING.VIEW it also requires the invoice to have
// left DRAFT. A draft bill for the caller's own child answers exactly like an
// invoice that does not exist.
func (s *Server) handleInvoice(w http.ResponseWriter, r *http.Request) {
	ident, _ := auth.FromContext(r.Context())

	invoiceID, err := strconv.Atoi(r.PathValue("invoice_id"))
	if err != nil || invoiceID <= 0 {
		writeError(w, r, http.StatusNotFound, CodeNotFound)
		return
	}

	invoice, childID, err := s.db.Invoice(r.Context(), ident.Username, invoiceID)
	if err != nil {
		if errors.Is(err, store.ErrNotFound) {
			s.audit.Record(r.Context(), audit.Event{
				Action: audit.ActionDeny, Actor: ident.Username, CenterID: &ident.CenterID,
				Detail:   "INVOICE_NOT_VISIBLE invoice_id=" + strconv.Itoa(invoiceID),
				ClientIP: s.clientIP(r),
			})
			writeError(w, r, http.StatusNotFound, CodeNotFound)
			return
		}
		writeInternal(w, r, s.log, err)
		return
	}

	s.audit.Record(r.Context(), audit.Event{
		Action: audit.ActionRead, Actor: ident.Username, CenterID: &ident.CenterID,
		Detail:   "INVOICE invoice_id=" + strconv.Itoa(invoiceID) + " child_id=" + strconv.Itoa(childID),
		ClientIP: s.clientIP(r),
	})

	writeJSON(w, http.StatusOK, invoice)
}
