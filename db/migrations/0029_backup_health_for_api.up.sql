-- =====================================================================
-- Hand By Hand (new) - migration 0029: backup health, for the owner's
-- screen only
--
-- hbh.backup_runs has no policy and no GRANT, and it stays that way.
-- The API session asked for v_backup_health on the owner's dashboard,
-- which is the right thing to want: "when did a backup last actually
-- work" is a question the person responsible should be able to answer
-- without asking anybody.
--
-- So the ANSWER is exposed, not the table.
--
-- WHAT THIS FUNCTION DELIBERATELY DOES NOT RETURN:
--   file_name  - a dump's name and path describe the host's filesystem
--   sha256_hex - useful only to somebody holding the file
--   detail     - it carries pg_restore's own error text, which can
--                quote a row value
--
-- A screen that says "last verified 4 hours ago, not stale" needs none
-- of those, and each of them turns an operational reassurance into a
-- description of the server. Adding them later means changing this
-- function, which is exactly the review that should have to happen.
--
-- Error classes reused here:
--   HB130  not permitted
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0029') THEN
    RAISE EXCEPTION 'migration 0029 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0025') THEN
    RAISE EXCEPTION 'migration 0025 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.backup_health()
RETURNS TABLE (
  last_verified_at     timestamptz,
  last_attempt_at      timestamptz,
  hours_since_verified numeric,
  failures_this_week   bigint,
  is_stale             boolean,
  never_verified       boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  -- Fails closed. No identity is not "show me the public answer", and
  -- backup health tells an unauthenticated caller how long this system
  -- has been running unprotected.
  IF hbh.current_center_id() IS NULL THEN
    RAISE EXCEPTION 'backup health needs an identity' USING ERRCODE = 'HB130';
  END IF;

  IF NOT hbh.has_permission('OPS.VIEW') THEN
    RAISE EXCEPTION 'reading backup health needs OPS.VIEW' USING ERRCODE = 'HB130';
  END IF;

  RETURN QUERY
  SELECT h.last_verified_at,
         h.last_attempt_at,
         round(extract(epoch FROM (now() - h.last_verified_at)) / 3600.0, 1),
         h.failures_this_week,
         h.is_stale,
         h.last_verified_at IS NULL
  FROM   hbh.v_backup_health h;
END
$$;

COMMENT ON FUNCTION hbh.backup_health() IS
  'Backup health for the owner screen. Returns the answer, never the dump file name, digest or restore error text.';

REVOKE ALL ON FUNCTION hbh.backup_health() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.backup_health() TO hbh_app;

-- hbh.backup_runs itself stays ungranted. Deliberately.

INSERT INTO hbh.schema_migrations (version) VALUES ('0029');
