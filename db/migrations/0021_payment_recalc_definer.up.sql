-- =====================================================================
-- Hand By Hand (new) - migration 0021: the payment recalculation runs
-- as the system
--
-- The third and last instance of one pattern, and the pattern is worth
-- naming because it will recur the next time a table is opened:
--
--   A TRIGGER RUNS AS THE CALLER. Everything it touches - a table, a
--   function - is reached with the CALLER's rights, not the schema
--   owner's. While hbh_app could not write, no trigger ever fired as
--   hbh_app and none of this was visible.
--
-- Migration 0016 let hbh_app insert a payment. trg_payment_recalc then
-- fired as hbh_app and called hbh.recalc_invoice, which is SECURITY
-- DEFINER but carries no EXECUTE grant for hbh_app - correctly, because
-- nothing outside a trigger should recalculate an invoice. The insert
-- failed with "permission denied for function recalc_invoice".
--
-- Rejected: GRANT EXECUTE on recalc_invoice. That hands the API a way
-- to rewrite an invoice's totals directly, which is precisely what the
-- absent grant was preventing.
--
-- Taken: the trigger becomes SECURITY DEFINER, as 0017 did for the two
-- history triggers. The recalculation happens with the system's rights,
-- and recalc_invoice keeps no grant at all.
--
-- The other non-definer triggers on writable tables were checked and
-- need nothing: trg_appointment_status, trg_request_status and
-- trg_plan_status only raise, and the legal_*_transition functions they
-- call are already granted; trg_live_flag_needs_consent calls
-- has_consent, which is granted; trg_payment_guard only reads
-- hbh.invoices, which hbh_app may select.
--
-- The phase-5 API suite now asserts this structurally rather than one
-- discovery at a time.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0021') THEN
    RAISE EXCEPTION 'migration 0021 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0017') THEN
    RAISE EXCEPTION 'migration 0017 must be applied first';
  END IF;
END
$guard$;

-- Body unchanged from migration 0008. Only SECURITY DEFINER and the
-- pinned search_path are added.
CREATE OR REPLACE FUNCTION hbh.trg_payment_recalc()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.recalc_invoice(coalesce(NEW.invoice_id, OLD.invoice_id));
  RETURN NULL;
END
$$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0021');
