-- =====================================================================
-- Hand By Hand (new) - migration 0138: withdraw two parameters the owner
-- cancelled an hour after they shipped
--
-- 0137 added PACKAGE_DEPOSIT_PCT = 50 (OD-31) and
-- PACKAGE_ACTIVATION_KIND = FULL (OD-28). OD-33 replaced both the same
-- evening: an instalment is a PAYMENT PLAN, and the amount that
-- activates a package is the plan's first instalment - "one source of
-- truth: the activation amount IS the plan's deposit, not a parameter
-- beside it".
--
-- WHY THEY GO NOW RATHER THAN WITH THE PLANS
--
-- Nothing reads them - measured: no function in pg_proc, nothing in
-- api/ or web/. That is exactly what makes them dangerous rather than
-- harmless. A parameter that exists, holds a plausible value, and is
-- read by nothing is a second source of truth waiting for its first
-- reader: the day somebody writes PK-03 and finds PACKAGE_DEPOSIT_PCT
-- sitting in sys_params with 50 in it, they will read it - and the
-- deposit will then live in two places that can disagree. Leaving them
-- until payment_plans exists would be leaving that trap armed for
-- however long that takes.
--
-- They were global rows (center_id NULL) with no per-centre override,
-- so there is nothing else to clean.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0138') THEN
    RAISE EXCEPTION 'migration 0138 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0137') THEN
    RAISE EXCEPTION 'migration 0137 must be applied first';
  END IF;
  -- The premise. If something started reading them in the meantime,
  -- deleting the rows would change behaviour, and that is a conversation.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh'
               AND p.prosrc ~ 'PACKAGE_DEPOSIT_PCT|PACKAGE_ACTIVATION_KIND') THEN
    RAISE EXCEPTION 'a function now reads PACKAGE_DEPOSIT_PCT or PACKAGE_ACTIVATION_KIND - withdrawing them is no longer inert';
  END IF;
END
$guard$;

DELETE FROM hbh.sys_params
 WHERE param_code IN ('PACKAGE_DEPOSIT_PCT', 'PACKAGE_ACTIVATION_KIND');

DO $verify$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.sys_params
             WHERE param_code IN ('PACKAGE_DEPOSIT_PCT', 'PACKAGE_ACTIVATION_KIND')) THEN
    RAISE EXCEPTION 'a cancelled package parameter survived - one source of truth is the whole point of OD-33';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0138');
