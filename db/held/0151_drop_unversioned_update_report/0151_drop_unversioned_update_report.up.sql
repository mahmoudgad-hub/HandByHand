-- 0151 - the unversioned update_report goes.
--
-- Backlog #14, second step. 0141 added hbh.update_report with a required
-- expected version and left the six-argument original in place because the
-- API of that day still called it. While both exist the check is optional:
-- any caller can pick the old signature and write over a colleague's draft.
--
-- ORDER: apply only once the API that calls the seven-argument function is
-- deployed. Applied early, every draft save from the old API is 42883.
-- The guard cannot see which image is running; it can refuse the one order
-- that is certainly wrong - dropping the old function with no new one.
DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0141')
     OR to_regprocedure('hbh.update_report(integer, timestamptz, text, text, date, date, integer)') IS NULL THEN
    RAISE EXCEPTION 'migration 0141 (the versioned update_report) must be applied first';
  END IF;
END
$guard$;

DROP FUNCTION hbh.update_report(integer, text, text, date, date, integer);

INSERT INTO hbh.schema_migrations (version) VALUES ('0151');
