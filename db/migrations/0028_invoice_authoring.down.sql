-- =====================================================================
-- Hand By Hand (new) - migration 0028 rollback
--
-- The invoices already created are left exactly where they are. Removing
-- the way to make one is not a reason to unmake the ones that exist -
-- and hbh.issue_invoice and the payment path still read them.
--
-- INVOICE_DUE_DAYS is left too: a centre may have overridden it, and
-- deleting a parameter row on rollback would throw away that decision.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.remove_invoice_line(integer);
DROP FUNCTION IF EXISTS hbh.add_invoice_line(integer, text, numeric, numeric, integer, integer);
DROP FUNCTION IF EXISTS hbh.create_invoice(integer, integer, date, text);

DELETE FROM hbh.schema_migrations WHERE version = '0028';
