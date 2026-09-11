package store

import (
	"context"
	"encoding/json"
	"github.com/jackc/pgx/v5"
)

// BillingSummary aggregates visible, active records, preserving decimal amounts and currencies.
func (d *DB) BillingSummary(ctx context.Context, ident string) ([]json.RawMessage, error) {
	out := []json.RawMessage{}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := requireBillingView(ctx, tx); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `
WITH clock AS (
 SELECT (now() AT TIME ZONE c.time_zone)::date today FROM hbh.centers c WHERE c.center_id = hbh.current_center_id()
), invoices AS (
 SELECT i.* FROM hbh.invoices i WHERE active_flg AND status NOT IN ('DRAFT','CANCELLED') AND hbh.has_permission('BILLING.VIEW')
), totals AS (
 SELECT currency_code, count(*) invoice_count,
 sum(greatest(total_amt-paid_amt,0)) outstanding,
 sum(CASE WHEN due_date < clock.today - 30 THEN greatest(total_amt-paid_amt,0) ELSE 0 END) overdue,
 avg(total_amt) average, sum(tax_amt) tax
 FROM invoices CROSS JOIN clock GROUP BY currency_code
), collected AS (
 SELECT i.currency_code, sum(p.amount) amount FROM hbh.payments p JOIN invoices i USING(invoice_id) CROSS JOIN clock
 WHERE p.active_flg AND p.paid_at >= (date_trunc('month', clock.today::timestamp) AT TIME ZONE (SELECT time_zone FROM hbh.centers WHERE center_id=hbh.current_center_id()))
 AND p.paid_at <= now() GROUP BY i.currency_code
), previous AS (
 SELECT i.currency_code,sum(p.amount) amount FROM hbh.payments p JOIN invoices i USING(invoice_id) CROSS JOIN clock
 WHERE p.active_flg AND p.paid_at >= ((date_trunc('month',clock.today::timestamp)-interval '1 month') AT TIME ZONE (SELECT time_zone FROM hbh.centers WHERE center_id=hbh.current_center_id()))
 AND p.paid_at < (date_trunc('month',clock.today::timestamp) AT TIME ZONE (SELECT time_zone FROM hbh.centers WHERE center_id=hbh.current_center_id())) GROUP BY i.currency_code
)
SELECT jsonb_build_object('currency',t.currency_code,'invoice_count',t.invoice_count,
 'outstanding',t.outstanding::text,'overdue',t.overdue::text,'average',round(t.average,2)::text,
 'tax',t.tax::text,'collected',coalesce(c.amount,0)::text,'previous_collected',coalesce(p.amount,0)::text)
FROM totals t LEFT JOIN collected c USING(currency_code) LEFT JOIN previous p USING(currency_code) ORDER BY t.currency_code`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, raw)
		}
		return rows.Err()
	})
	return out, err
}

// BillingLedger returns one page, scoped by existing table RLS.
func (d *DB) BillingLedger(ctx context.Context, ident, kind, search string, offset int) ([]json.RawMessage, int, error) {
	out := []json.RawMessage{}
	total := 0
	var source string
	switch kind {
	case "payments":
		source = `SELECT p.payment_id id,ch.full_name_ar name,i.invoice_no detail,p.amount::text amount,i.currency_code currency,p.method_code status,p.paid_at::text date FROM hbh.payments p JOIN hbh.invoices i USING(invoice_id) JOIN hbh.children ch ON ch.child_id=i.child_id WHERE p.active_flg`
	case "packages":
		source = `SELECT sp.package_id id,sp.name_ar name,s.name_ar detail,sp.price_amt::text amount,c.currency_code currency,sp.sessions_cnt::text sessions,sp.validity_days::text validity FROM hbh.service_packages sp JOIN hbh.services s USING(service_id) JOIN hbh.centers c ON c.center_id=sp.center_id WHERE sp.active_flg`
	case "balances":
		source = `SELECT cp.child_package_id id,ch.full_name_ar name,sp.name_ar detail,cp.sessions_total sessions,cp.sessions_used used,cp.sessions_total-cp.sessions_used remaining,cp.expires_on::text date,cp.status status FROM hbh.child_packages cp JOIN hbh.children ch USING(child_id) JOIN hbh.service_packages sp USING(package_id) WHERE cp.active_flg`
	default:
		return out, 0, ErrNotFound
	}
	err := d.InReadTx(ctx, ident, func(ctx context.Context, tx pgx.Tx) error {
		if err := requireBillingView(ctx, tx); err != nil {
			return err
		}
		filter := " WHERE hbh.has_permission('BILLING.VIEW') AND ($1='' OR strpos(coalesce(name,''),$1)>0 OR strpos(coalesce(detail,''),$1)>0)"
		if err := tx.QueryRow(ctx, "WITH ledger AS ("+source+") SELECT count(*) FROM ledger"+filter, search).Scan(&total); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, "WITH ledger AS ("+source+") SELECT to_jsonb(ledger) FROM ledger"+filter+" ORDER BY id DESC LIMIT 25 OFFSET $2", search, offset)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var raw []byte
			if err := rows.Scan(&raw); err != nil {
				return err
			}
			out = append(out, raw)
		}
		return rows.Err()
	})
	return out, total, err
}

// requireBillingView is the gate that produces the 403, asked INSIDE the
// caller's own transaction.
//
// It replaces a separate d.HasPermission round trip in the handler. That
// call was correct in what it asked - hbh.has_permission, the same
// function the policies call - but it ran in its OWN transaction, so the
// permission was established under one snapshot and the data read under
// another. Between them a role can change. Asking at the door of the
// transaction that does the reading closes that window.
//
// WHY THE QUERIES STILL CARRY hbh.has_permission INLINE. It is not a
// second copy of the rule: it is the same function call, so the two
// cannot drift the way two hand-written conditions would. It is there so
// that removing this gate would empty the result rather than open it -
// the failure direction that matters. Fail-closed twice costs one
// boolean.
//
// WHY 403 AND NOT AN EMPTY LIST, which is the shape used elsewhere in
// this service: an empty billing screen READS AS "the centre is owed
// nothing". A member of staff who may not see the figures would be
// misled by a number rather than told they cannot see it, and there is
// nothing to disclose by refusing - every centre has billing. The
// phase-9 suite asserts this deliberately.
func requireBillingView(ctx context.Context, tx pgx.Tx) error {
	var ok bool
	if err := tx.QueryRow(ctx, `SELECT hbh.has_permission('BILLING.VIEW')`).Scan(&ok); err != nil {
		return err
	}
	if !ok {
		return ErrForbidden
	}
	return nil
}
