package domain

import "time"

// Money is an exact decimal amount, carried as the string Postgres printed.
//
// It is NOT a float, and the contrast with Goal.LatestPct is the point. A
// progress percentage is a reading for a chart: nothing sums it and nothing
// compares it for equality, so float64 is harmless. An invoice total is added
// up, subtracted from, and compared against a payment - and 0.1 + 0.2 is not
// 0.3 in binary floating point. The database holds numeric; casting to text in
// the query hands the exact digits to the client, and the client formats them.
//
// The currency is on the invoice, never assumed. EGP is the first centre's
// currency, not a fact about the system.
type Money = string

// Invoice as a family sees it.
//
// A guardian without BILLING.VIEW reaches only invoices that have left DRAFT -
// the policy says so. An invoice still being assembled is not a bill, and
// showing one to a family would be asking them to pay a number that is still
// moving.
type Invoice struct {
	InvoiceID    int    `json:"invoice_id"`
	InvoiceNo    string `json:"invoice_no"`
	IssueDate    Date   `json:"issue_date"`
	DueDate      Date   `json:"due_date"`
	CurrencyCode string `json:"currency_code"`
	SubtotalAmt  Money  `json:"subtotal_amt"`
	TaxRate      Money  `json:"tax_rate"`
	TaxAmt       Money  `json:"tax_amt"`
	TotalAmt     Money  `json:"total_amt"`
	PaidAmt      Money  `json:"paid_amt"`
	Status       string `json:"status"`

	// Present only on the single-invoice read.
	Lines    []InvoiceLine `json:"lines,omitempty"`
	Payments []Payment     `json:"payments,omitempty"`
}

// InvoiceLine is one charge.
//
// note_ar on the invoice and the internal references (einv_ref, einv_status)
// are not exposed: they are the centre's own bookkeeping with the tax
// authority, not part of what the family was charged.
type InvoiceLine struct {
	LineID        int    `json:"line_id"`
	DescriptionAr string `json:"description_ar"`
	Qty           Money  `json:"qty"`
	UnitAmt       Money  `json:"unit_amt"`
	LineAmt       Money  `json:"line_amt"`
	SortOrder     int    `json:"sort_order"`
}

// Payment is money received against an invoice.
//
// `reference` is deliberately absent. It is a transfer or card reference the
// centre records for reconciliation, and it is the sort of value that turns
// out to contain part of a card number.
type Payment struct {
	PaymentID  int       `json:"payment_id"`
	Amount     Money     `json:"amount"`
	MethodCode string    `json:"method_code"`
	PaidAt     time.Time `json:"paid_at"`
}

// Package is a block of prepaid sessions.
type Package struct {
	ChildPackageID int    `json:"child_package_id"`
	PackageID      int    `json:"package_id"`
	NameAr         string `json:"name_ar"`
	PurchasedOn    Date   `json:"purchased_on"`
	ExpiresOn      Date   `json:"expires_on"`
	SessionsTotal  int    `json:"sessions_total"`
	SessionsUsed   int    `json:"sessions_used"`
	SessionsLeft   int    `json:"sessions_left"`
	PriceAmt       Money  `json:"price_amt"`
	Status         string `json:"status"`
}

// Balance is what the family owes, from hbh.v_child_balance.
type Balance struct {
	CurrencyCode   string `json:"currency_code"`
	OpenInvoiceCnt int64  `json:"open_invoice_count"`
	OutstandingAmt Money  `json:"outstanding_amt"`
	InvoicedAmt    Money  `json:"invoiced_amt"`
	PaidAmt        Money  `json:"paid_amt"`
}
