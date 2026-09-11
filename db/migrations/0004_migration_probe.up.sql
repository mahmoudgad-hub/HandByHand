-- =====================================================================
-- Hand By Hand (new) - migration 0004: the schema version probe
--
-- Why this exists, in one sentence: the API refuses to start against a
-- database older than itself, and it had no way to ask.
--
-- The obvious fix - GRANT SELECT ON hbh.schema_migrations TO hbh_app -
-- is the wrong one. That table has no row level security and no policy,
-- so a grant on it would be the first read in this schema that is not
-- filtered by anything, and the rule that every table the API reads is
-- policy-filtered would stop being true. Once it stops being true it
-- stops being checkable.
--
-- So the same shape the schema already uses for otp_codes and
-- auth_sessions: no grant on the table, one narrow SECURITY DEFINER
-- function, and that function is all the API can reach. It answers
-- exactly one question - "is version N applied" - and returns a boolean,
-- so it cannot become a way to enumerate anything.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0004') THEN
    RAISE EXCEPTION 'migration 0004 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0003') THEN
    RAISE EXCEPTION 'migration 0003 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.migration_applied(p_version text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = p_version)
$$;

COMMENT ON FUNCTION hbh.migration_applied(text) IS
  'Boot-time probe. Answers whether one migration is applied, and nothing else. The API has no read on hbh.schema_migrations itself.';

REVOKE ALL ON FUNCTION hbh.migration_applied(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.migration_applied(text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0004');
