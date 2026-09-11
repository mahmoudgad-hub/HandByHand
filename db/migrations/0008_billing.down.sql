-- =====================================================================
-- Hand By Hand (new) - migration 0008 DOWN
-- Development convenience only. View and tables before functions.
-- =====================================================================

DROP VIEW  IF EXISTS hbh.v_child_balance;

DROP TABLE IF EXISTS hbh.payments;
DROP TABLE IF EXISTS hbh.invoice_lines;
DROP TABLE IF EXISTS hbh.invoices;
DROP TABLE IF EXISTS hbh.package_ledger;
DROP TABLE IF EXISTS hbh.child_packages;
DROP TABLE IF EXISTS hbh.service_packages;

DROP FUNCTION IF EXISTS hbh.expire_packages(integer);
DROP FUNCTION IF EXISTS hbh.issue_invoice(integer);
DROP FUNCTION IF EXISTS hbh.consume_package_session(integer, integer);
DROP FUNCTION IF EXISTS hbh.sell_package(integer, integer);
DROP FUNCTION IF EXISTS hbh.trg_payment_recalc();
DROP FUNCTION IF EXISTS hbh.trg_payment_guard();
DROP FUNCTION IF EXISTS hbh.trg_line_recalc();
DROP FUNCTION IF EXISTS hbh.trg_line_guard();
DROP FUNCTION IF EXISTS hbh.trg_invoice_status();
DROP FUNCTION IF EXISTS hbh.trg_invoice_guard();
DROP FUNCTION IF EXISTS hbh.legal_invoice_transition(text, text);
DROP FUNCTION IF EXISTS hbh.recalc_invoice(integer);

DELETE FROM hbh.convention_exemptions WHERE table_name = 'package_ledger';

DELETE FROM hbh.schema_migrations WHERE version = '0008';
