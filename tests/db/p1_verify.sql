-- =====================================================================
-- Hand By Hand (new) - PHASE 1 acceptance suite
--
-- Must print:  PHASE 1 ACCEPTED
--
-- Four rules this file exists to obey, each bought with a lost round
-- trip in the Oracle system:
--
--   1. The verdict always prints. A suite that dies before its verdict
--      reads as a pass, so every probe runs inside its own exception
--      handler and records a failure instead of aborting the run.
--   2. A negative test names the SQLSTATE it expects. A refusal for the
--      wrong reason proves nothing and looks green.
--   3. The fixture is asserted before the tests, by name - not through
--      them, where a missing prerequisite surfaces fifty tests later as
--      a confusing refusal from correct code.
--   4. A uniqueness rule is tested with two rows on the SAME side of
--      the rule. One row of each never collides.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

-- ---------------------------------------------------------------------
-- Harness
-- ---------------------------------------------------------------------
DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

-- When this run began.
--
-- The audit log is append-only by design, so it still holds every row
-- the previous run wrote. Any check that counts audit rows must be
-- scoped to this run, or the suite passes once and fails for ever
-- after - which looks like a regression and is not one.
CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq     integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp     text    NOT NULL,
  name    text    NOT NULL,
  ok      boolean NOT NULL,
  detail  text
);

-- Expects p_sql to return TRUE. Anything else - false, null, or an
-- error - is a failure, recorded rather than raised.
CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL'
                 ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

-- Expects p_sql to RAISE, with exactly p_sqlstate. A different code is
-- a failure: the statement was refused, but not for the reason claimed.
CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE - asserted by name, before any test runs
-- =====================================================================
CALL hbh_test.chk('fixture', 'schema hbh exists',
  $q$ SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'hbh') $q$);

CALL hbh_test.chk('fixture', 'migration 0001 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0001') $q$);

CALL hbh_test.chk('fixture', 'role hbh_app exists',
  $q$ SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hbh_app') $q$);

CALL hbh_test.chk('fixture', 'centre HBH seeded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.centers WHERE code = 'HBH') $q$);

CALL hbh_test.chk('fixture', 'branch MAIN seeded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.branches WHERE code = 'MAIN') $q$);

CALL hbh_test.chk('fixture', 'user admin seeded and ACTIVE',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.users WHERE lower(username) = 'admin' AND status = 'ACTIVE' AND active_flg) $q$);

CALL hbh_test.chk('fixture', 'global sys_params present',
  $q$ SELECT count(*) >= 10 FROM hbh.sys_params WHERE center_id IS NULL $q$);

CALL hbh_test.chk('fixture', 'lookup values present',
  $q$ SELECT count(*) >= 14 FROM hbh.lookup_values $q$);

-- =====================================================================
-- 1. THE APPLICATION ROLE
--
-- Policies only bind a role that cannot step around them. If any of
-- these three fails, every policy in the schema is decorative and the
-- rest of this suite proves nothing.
-- =====================================================================
CALL hbh_test.chk('role', 'hbh_app is NOT superuser',
  $q$ SELECT NOT rolsuper FROM pg_roles WHERE rolname = 'hbh_app' $q$);

CALL hbh_test.chk('role', 'hbh_app does NOT bypass RLS',
  $q$ SELECT NOT rolbypassrls FROM pg_roles WHERE rolname = 'hbh_app' $q$);

CALL hbh_test.chk('role', 'hbh_app owns no table in hbh',
  $q$ SELECT count(*) = 0 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relkind = 'r'
        AND pg_get_userbyid(c.relowner) = 'hbh_app' $q$);

-- Schema-wide rules - RLS everywhere, audit columns, soft delete,
-- foreign key indexes, UTC, no recording column - moved to
-- tests/db/p00_verify.sql. They describe the schema as it stands, so a
-- rule broken by a later migration has to fail in a suite that grows
-- with the schema, not inside the phase that happened to come first.

-- =====================================================================
-- 2. IDENTITY FAILS CLOSED
--
-- The single most important property in the schema. With no identity
-- set, the identity function returns NULL, the centre derivation
-- returns NULL, and every policy comparison yields NULL - which is not
-- true, so nothing is returned.
-- =====================================================================
RESET hbh.user_id;

CALL hbh_test.chk('identity', 'current_portal_user() is NULL when unset',
  $q$ SELECT hbh.current_portal_user() IS NULL $q$);

CALL hbh_test.chk('identity', 'current_center_id() is NULL when unset',
  $q$ SELECT hbh.current_center_id() IS NULL $q$);

CALL hbh_test.chk('identity', 'empty identity is treated as absent',
  $q$ SELECT set_config('hbh.user_id', '', true) IS NOT NULL
             AND hbh.current_portal_user() IS NULL $q$);

CALL hbh_test.chk('identity', 'unknown user resolves to no centre',
  $q$ SELECT set_config('hbh.user_id', 'nobody-at-all', true) IS NOT NULL
             AND hbh.current_center_id() IS NULL $q$);

CALL hbh_test.chk('identity', 'known user resolves to their centre',
  $q$ SELECT set_config('hbh.user_id', 'admin', true) IS NOT NULL
             AND hbh.current_center_id() = (SELECT center_id FROM hbh.centers WHERE code = 'HBH') $q$);

CALL hbh_test.chk('identity', 'identity is matched case-insensitively',
  $q$ SELECT set_config('hbh.user_id', 'ADMIN', true) IS NOT NULL
             AND hbh.current_center_id() IS NOT NULL $q$);

-- current_app_user is the audit variant and DOES fall back. The two
-- must not be confused: one is attribution, the other is access.
CALL hbh_test.chk('identity', 'current_app_user falls back to the database user',
  $q$ SELECT set_config('hbh.user_id', '', true) IS NOT NULL
             AND hbh.current_app_user() = session_user $q$);

CALL hbh_test.chk('identity', 'current_center_id is SECURITY DEFINER',
  $q$ SELECT p.prosecdef FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.proname = 'current_center_id' $q$);

CALL hbh_test.chk('identity', 'current_center_id has a pinned search_path',
  $q$ SELECT p.proconfig IS NOT NULL AND EXISTS (
        SELECT 1 FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search\_path=%')
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.proname = 'current_center_id' $q$);

-- =====================================================================
-- 3. ROW LEVEL SECURITY, EXERCISED AS THE APPLICATION ROLE
--
-- SET ROLE makes current_user hbh_app, and RLS binds current_user - so
-- from here to RESET ROLE the policies are actually in force. Running
-- these as the owner would prove nothing at all.
-- =====================================================================
RESET hbh.user_id;
SET ROLE hbh_app;

CALL hbh_test.chk('rls', 'the tests are running as hbh_app',
  $q$ SELECT current_user = 'hbh_app' $q$);

-- The headline test.
CALL hbh_test.chk('rls', 'centres: no identity returns ZERO rows',
  $q$ SELECT count(*) = 0 FROM hbh.centers $q$);

CALL hbh_test.chk('rls', 'branches: no identity returns ZERO rows',
  $q$ SELECT count(*) = 0 FROM hbh.branches $q$);

CALL hbh_test.chk('rls', 'users: no identity returns ZERO rows',
  $q$ SELECT count(*) = 0 FROM hbh.users $q$);

-- The subtle one. Global rows carry center_id IS NULL, so a policy
-- written only as "center_id IS NULL OR center_id = current_center_id()"
-- would hand every system parameter to an unauthenticated connection.
CALL hbh_test.chk('rls', 'sys_params: global rows are NOT visible without identity',
  $q$ SELECT count(*) = 0 FROM hbh.sys_params $q$);

CALL hbh_test.chk('rls', 'lookup_values: global rows are NOT visible without identity',
  $q$ SELECT count(*) = 0 FROM hbh.lookup_values $q$);

CALL hbh_test.chk('rls', 'lookup_types: NOT visible without identity',
  $q$ SELECT count(*) = 0 FROM hbh.lookup_types $q$);

-- And it cannot WRITE one either. Migration 0051 gave hbh_app a
-- column-level UPDATE on the six centre settings, so this is no longer
-- a privilege refusal - the grant exists and the policy decides. That
-- changes the SHAPE of the refusal and not its existence: the statement
-- now matches zero rows and reports success, so the assertion counts
-- rows instead of catching an exception. Written the other way it would
-- go green the day somebody widens the policy to let everybody through.
--
-- The update is deliberately a no-op on the value (name_en = name_en).
-- A check that proves a write is refused must not be able to perform
-- one if it ever stops being refused: the version this replaced set the
-- name to 'x', and would have renamed the centre on every database it
-- ran against from 0051 onward.
CALL hbh_test.chk('rls', 'centres: no identity writes ZERO rows',
  $q$ WITH u AS (UPDATE hbh.centers SET name_en = name_en RETURNING 1)
      SELECT count(*) = 0 FROM u $q$);

-- Now with an identity.
--
-- Set at SESSION level, not with set_config(..., true). The third
-- argument of set_config means "this transaction only", and every CALL
-- below is its own transaction under autocommit - so a transaction-local
-- identity is gone before the next check begins, and the check reads as
-- a policy failure when the policy is in fact correct.
--
-- The API does the opposite, and rightly: it uses SET LOCAL so an
-- identity can never leak from one pooled request into the next.
SET hbh.user_id = 'admin';

CALL hbh_test.chk('rls', 'the identity survives into the next transaction',
  $q$ SELECT hbh.current_center_id() IS NOT NULL $q$);

CALL hbh_test.chk('rls', 'centres: identity returns exactly one centre',
  $q$ SELECT count(*) = 1 FROM hbh.centers $q$);

CALL hbh_test.chk('rls', 'centres: it is the right centre',
  $q$ SELECT (SELECT code FROM hbh.centers) = 'HBH' $q$);

CALL hbh_test.chk('rls', 'sys_params: identity sees the global defaults',
  $q$ SELECT count(*) >= 10 FROM hbh.sys_params $q$);

CALL hbh_test.chk('rls', 'lookup_values: identity sees the reference data',
  $q$ SELECT count(*) >= 14 FROM hbh.lookup_values $q$);

-- The portal never reads the audit log. No SELECT was granted, so this
-- is a privilege refusal - 42501 - and not an empty result.
CALL hbh_test.chk_raises('rls', 'audit_log: the app role cannot read it',
  $q$ SELECT count(*) FROM hbh.audit_log $q$, '42501');

-- Reference data is read-only to the portal EXCEPT for the six centre
-- settings that migration 0051 opened, and this identity holds
-- SETTINGS.MANAGE - so the question is no longer "can it write" but
-- "how far".
--
-- The answer is a column-level grant, which is a harder ceiling than a
-- policy: no identity and no permission can move a column outside the
-- list, because the engine refuses before any policy is consulted. That
-- is what this asserts, and it is why the grant was written per-column
-- rather than per-table. hbh.centers.code is on the far side of it -
-- the centre's identifier, which nothing may edit, ever.
CALL hbh_test.chk_raises('rls', 'centres: a column outside the settings grant is still refused',
  $q$ UPDATE hbh.centers SET code = 'x' $q$, '42501');

RESET hbh.user_id;
RESET ROLE;

CALL hbh_test.chk('rls', 'RESET ROLE restored the owner',
  $q$ SELECT current_user <> 'hbh_app' $q$);

-- =====================================================================
-- 4. APPEND-ONLY AUDIT
--
-- The insert and the assertion are two separate statements on purpose.
-- A data-modifying CTE is invisible to the rest of its own statement -
-- both halves read the snapshot taken when the statement began - so
-- counting the audit log alongside the INSERT that should have grown it
-- always compares a number with itself.
-- =====================================================================
CALL hbh_test.chk('audit', 'inserting a parameter succeeds',
  $q$ WITH ins AS (INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type)
                   VALUES (NULL, 'TEST_AUDIT_PROBE', '1', 'NUMBER') RETURNING 1)
      SELECT count(*) = 1 FROM ins $q$);

CALL hbh_test.chk('audit', 'that insert wrote exactly one audit row in THIS run',
  $q$ SELECT count(*) = 1 FROM hbh.audit_log
      WHERE table_name = 'sys_params' AND action = 'INSERT'
        AND new_data ->> 'param_code' = 'TEST_AUDIT_PROBE'
        AND changed_at >= (SELECT started FROM hbh_test.run) $q$);

CALL hbh_test.chk('audit', 'the audit row is attributed and timestamped',
  $q$ SELECT changed_by IS NOT NULL AND changed_at IS NOT NULL
      FROM hbh.audit_log
      WHERE table_name = 'sys_params' AND action = 'INSERT'
        AND new_data ->> 'param_code' = 'TEST_AUDIT_PROBE'
        AND changed_at >= (SELECT started FROM hbh_test.run) $q$);

-- The log keeps history the cleanup cannot remove - that is the point
-- of an append-only table, and the reason the check above is scoped.
CALL hbh_test.chk('audit', 'earlier runs are still in the log',
  $q$ SELECT count(*) >= 1 FROM hbh.audit_log $q$);

CALL hbh_test.chk_raises('audit', 'audit_log refuses UPDATE with HB001',
  $q$ UPDATE hbh.audit_log SET detail = 'tampered' WHERE audit_id = (SELECT min(audit_id) FROM hbh.audit_log) $q$,
  'HB001');

CALL hbh_test.chk_raises('audit', 'audit_log refuses DELETE with HB001',
  $q$ DELETE FROM hbh.audit_log WHERE audit_id = (SELECT min(audit_id) FROM hbh.audit_log) $q$,
  'HB001');

-- =====================================================================
-- 5. THE NULL-KEY TRAP
--
-- Two rows on the SAME side of the rule: both global, same code. One
-- row with a centre and one without would never collide, which is
-- exactly how this defect survived 73 tests in the Oracle system.
-- =====================================================================
CALL hbh_test.chk_raises('unique', 'two GLOBAL params with the same code are refused',
  $q$ INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type)
      VALUES (NULL, 'TEST_AUDIT_PROBE', '2', 'NUMBER') $q$,
  '23505');

CALL hbh_test.chk('unique', 'a centre override of the same code IS allowed',
  $q$ WITH ins AS (
        INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type)
        SELECT center_id, 'TEST_AUDIT_PROBE', '3', 'NUMBER' FROM hbh.centers WHERE code = 'HBH'
        RETURNING 1)
      SELECT count(*) = 1 FROM ins $q$);

CALL hbh_test.chk_raises('unique', 'two users with the same username are refused',
  $q$ INSERT INTO hbh.users (center_id, username, full_name_ar, user_type)
      SELECT center_id, 'ADMIN', 'مكرر', 'STAFF' FROM hbh.centers WHERE code = 'HBH' $q$,
  '23505');

-- =====================================================================
-- 6. ARABIC NORMALISATION
-- =====================================================================
CALL hbh_test.chk('arabic', 'alef variants fold together',
  $q$ SELECT hbh.normalize_arabic('أحمد') = hbh.normalize_arabic('احمد')
         AND hbh.normalize_arabic('إبراهيم') = hbh.normalize_arabic('ابراهيم') $q$);

CALL hbh_test.chk('arabic', 'ta marbuta folds to ha',
  $q$ SELECT hbh.normalize_arabic('فاطمة') = hbh.normalize_arabic('فاطمه') $q$);

CALL hbh_test.chk('arabic', 'diacritics are stripped',
  $q$ SELECT hbh.normalize_arabic('مُحَمَّد') = hbh.normalize_arabic('محمد') $q$);

CALL hbh_test.chk('arabic', 'tatweel is stripped',
  $q$ SELECT hbh.normalize_arabic('محـــمد') = hbh.normalize_arabic('محمد') $q$);

CALL hbh_test.chk('arabic', 'whitespace is collapsed and trimmed',
  $q$ SELECT hbh.normalize_arabic('  علي   محمود ') = 'علي محمود' $q$);

CALL hbh_test.chk('arabic', 'distinct names stay distinct',
  $q$ SELECT hbh.normalize_arabic('يوسف') <> hbh.normalize_arabic('يونس') $q$);

CALL hbh_test.chk('arabic', 'the function is IMMUTABLE, so it can be indexed',
  $q$ SELECT p.provolatile = 'i' FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.proname = 'normalize_arabic' $q$);

CALL hbh_test.chk('arabic', 'the name search index exists',
  $q$ SELECT EXISTS (SELECT 1 FROM pg_indexes
                     WHERE schemaname = 'hbh' AND indexname = 'ix_users_name_srch') $q$);

-- =====================================================================
-- =====================================================================
-- CLEANUP
--
-- A cleanup that swallows its failure is worse than no cleanup: the run
-- reports success, leaves its rows behind, and kills the NEXT run for a
-- reason unrelated to the real cause. So it is a recorded check.
-- =====================================================================
CALL hbh_test.chk('cleanup', 'probe rows removed',
  $q$ WITH d AS (DELETE FROM hbh.sys_params WHERE param_code = 'TEST_AUDIT_PROBE' RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة",
       count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM   hbh_test.results
GROUP  BY grp
ORDER  BY min(seq);

\echo ''
SELECT seq, grp, name, detail
FROM   hbh_test.results
WHERE  NOT ok
ORDER  BY seq;

DO $verdict$
DECLARE
  v_total integer;
  v_fail  integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN
    RAISE NOTICE '  PHASE 1 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** PHASE 1 NOT ACCEPTED';
  END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

-- Non-zero exit for CI. This runs AFTER the verdict, so the verdict is
-- never the thing that gets skipped.
DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
