package store

import (
	"context"
	"errors"

	"github.com/handbyhand/hbh/api/internal/domain"
	"github.com/jackc/pgx/v5"
)

// Billing, read-only.
//
// Every amount is cast to text in SQL and carried as a string. numeric holds
// the exact decimal; float64 does not, and money is the one thing in this
// service that gets added up and compared against a payment. The percentages
// in clinical.go are floats for exactly the opposite reason.
//
// The DRAFT rule is the policy's, not this file's: a guardian without
// BILLING.VIEW sees only invoices that have left DRAFT. An invoice still being
// assembled is not a bill, and putting one in front of a family asks them to
// pay a number that is still moving.

// Invoices lists a child's invoices, newest first.
func (d *DB) Invoices(ctx context.Context, ident string, childID int) ([]domain.Invoice, error) {
	out := []domain.Invoice{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT invoice_id, invoice_no, issue_date, due_date, currency_code,
			       subtotal_amt::text, tax_rate::text, tax_amt::text,
			       total_amt::text, paid_amt::text, status
			FROM   hbh.invoices
			WHERE  child_id = $1
			ORDER  BY issue_date DESC, invoice_id DESC`, childID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var i domain.Invoice
			if err := rows.Scan(&i.InvoiceID, &i.InvoiceNo, &i.IssueDate, &i.DueDate, &i.CurrencyCode,
				&i.SubtotalAmt, &i.TaxRate, &i.TaxAmt, &i.TotalAmt, &i.PaidAmt, &i.Status); err != nil {
				return err
			}
			out = append(out, i)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// Invoice returns one invoice with its lines and payments, or ErrNotFound.
//
// Three queries, one transaction: an invoice read from one snapshot with
// payments from another could show a total that its own lines do not add up
// to, which is the one thing a bill must never do.
func (d *DB) Invoice(ctx context.Context, ident string, invoiceID int) (domain.Invoice, int, error) {
	var (
		inv     domain.Invoice
		childID int
	)
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		err := tx.QueryRow(ctx, `
			SELECT invoice_id, invoice_no, issue_date, due_date, currency_code,
			       subtotal_amt::text, tax_rate::text, tax_amt::text,
			       total_amt::text, paid_amt::text, status, child_id
			FROM   hbh.invoices
			WHERE  invoice_id = $1`, invoiceID).
			Scan(&inv.InvoiceID, &inv.InvoiceNo, &inv.IssueDate, &inv.DueDate, &inv.CurrencyCode,
				&inv.SubtotalAmt, &inv.TaxRate, &inv.TaxAmt, &inv.TotalAmt, &inv.PaidAmt,
				&inv.Status, &childID)
		if err != nil {
			return noRows(err)
		}

		lines, err := tx.Query(ctx, `
			SELECT line_id, description_ar, qty::text, unit_amt::text, line_amt::text, sort_order
			FROM   hbh.invoice_lines
			WHERE  invoice_id = $1
			ORDER  BY sort_order, line_id`, invoiceID)
		if err != nil {
			return err
		}
		inv.Lines = []domain.InvoiceLine{}
		for lines.Next() {
			var l domain.InvoiceLine
			if err := lines.Scan(&l.LineID, &l.DescriptionAr, &l.Qty, &l.UnitAmt, &l.LineAmt, &l.SortOrder); err != nil {
				lines.Close()
				return err
			}
			inv.Lines = append(inv.Lines, l)
		}
		lines.Close()
		if err := lines.Err(); err != nil {
			return err
		}

		pays, err := tx.Query(ctx, `
			SELECT payment_id, amount::text, method_code, paid_at
			FROM   hbh.payments
			WHERE  invoice_id = $1
			ORDER  BY paid_at, payment_id`, invoiceID)
		if err != nil {
			return err
		}
		defer pays.Close()
		inv.Payments = []domain.Payment{}
		for pays.Next() {
			var p domain.Payment
			if err := pays.Scan(&p.PaymentID, &p.Amount, &p.MethodCode, &p.PaidAt); err != nil {
				return err
			}
			inv.Payments = append(inv.Payments, p)
		}
		return pays.Err()
	})
	if err != nil {
		return domain.Invoice{}, 0, err
	}
	return inv, childID, nil
}

// Packages lists a child's prepaid session blocks.
func (d *DB) Packages(ctx context.Context, ident string, childID int) ([]domain.Package, error) {
	out := []domain.Package{}
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		rows, err := tx.Query(ctx, `
			SELECT cp.child_package_id, cp.package_id, sp.name_ar, cp.purchased_on, cp.expires_on,
			       cp.sessions_total, cp.sessions_used, cp.price_amt::text, cp.status
			FROM   hbh.child_packages cp
			LEFT   JOIN hbh.service_packages sp ON sp.package_id = cp.package_id
			WHERE  cp.child_id = $1
			ORDER  BY cp.purchased_on DESC, cp.child_package_id DESC`, childID)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var (
				p    domain.Package
				name *string
			)
			if err := rows.Scan(&p.ChildPackageID, &p.PackageID, &name, &p.PurchasedOn, &p.ExpiresOn,
				&p.SessionsTotal, &p.SessionsUsed, &p.PriceAmt, &p.Status); err != nil {
				return err
			}
			p.NameAr = deref(name)
			// Computed here rather than in SQL because it is presentation:
			// the two counts are the record, and the difference is what a
			// family actually wants to read.
			p.SessionsLeft = p.SessionsTotal - p.SessionsUsed
			out = append(out, p)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return out, nil
}

// Balance returns what the family owes for one child.
//
// A child with no invoices has no row in the view, which is not an error - it
// is a family that owes nothing. Zeroes are returned, with the centre's own
// currency rather than an assumed one.
func (d *DB) Balance(ctx context.Context, ident string, childID int) (domain.Balance, error) {
	var b domain.Balance
	err := d.childScoped(ctx, ident, childID, func(ctx context.Context, tx pgx.Tx) error {
		var err error
		b, err = balanceTx(ctx, tx, childID)
		return err
	})
	if err != nil {
		return domain.Balance{}, err
	}
	return b, nil
}

func balanceTx(ctx context.Context, tx pgx.Tx, childID int) (domain.Balance, error) {
	b := domain.Balance{OutstandingAmt: "0", InvoicedAmt: "0", PaidAmt: "0"}
	{
		err := tx.QueryRow(ctx, `
			SELECT currency_code, open_invoice_cnt,
			       outstanding_amt::text, invoiced_amt::text, paid_amt::text
			FROM   hbh.v_child_balance
			WHERE  child_id = $1`, childID).
			Scan(&b.CurrencyCode, &b.OpenInvoiceCnt, &b.OutstandingAmt, &b.InvoicedAmt, &b.PaidAmt)
		if err == nil {
			return b, nil
		}
		if !errors.Is(noRows(err), ErrNotFound) {
			return domain.Balance{}, err
		}
	}
	// No row in the view means no invoices, which is a family that
	// owes nothing - not a missing child. The centre still has to name
	// its own currency; EGP is the first tenant, not a fact.
	if err := tx.QueryRow(ctx, `SELECT currency_code FROM hbh.centers WHERE center_id = hbh.current_center_id()`).
		Scan(&b.CurrencyCode); err != nil {
		return domain.Balance{}, err
	}
	return b, nil
}
