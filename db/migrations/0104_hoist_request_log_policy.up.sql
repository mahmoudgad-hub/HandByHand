-- =====================================================================
-- Hand By Hand (new) - migration 0104: the request-log policy is
-- evaluated once instead of thirty-four thousand times
--
-- MEASURED, not guessed. The operations screens were taking seconds and
-- the phase-6 suite was failing with 000 - no reply at all. tester - dev
-- timed the three endpoints and found 11.0s, 7.4s and 3.2s against a
-- single day of development traffic.
--
--   as hbh_owner (RLS bypassed)        29 ms
--   as hbh_app   (policy applied)   5,260 ms
--
--   Index Only Scan on request_log  (actual rows=34,884)
--     Filter: ((hbh.current_center_id() IS NOT NULL)
--              AND hbh.has_permission('OPS.VIEW'::text))
--
-- Two SECURITY DEFINER functions, each reading tables, called once per
-- row - and both answer the same thing for every row in the scan.
--
-- =====================================================================
-- WHY IT IS NOT WHAT IT LOOKS LIKE
--
-- The obvious suspect is VOLATILE, and it is wrong: all five identity
-- functions are already STABLE. Checking that first would have been the
-- whole fix if it were true, and it saved nothing to assume.
--
-- The real cause is that an RLS qual is a SECURITY BARRIER qual, and the
-- planner deliberately will not hoist it out of the scan the way it
-- hoists an ordinary WHERE. Proved by writing the identical predicate as
-- a plain WHERE: both forms collapse to a One-Time Filter and finish in
-- milliseconds. Inside a policy, neither does.
--
-- A scalar subquery with no outer reference becomes an InitPlan, which
-- the executor evaluates ONCE - and that is legal inside a security qual
-- because it cannot leak anything: it reads no column of the row.
--
--   USING (hbh.has_permission('OPS.VIEW'))            5,832 ms
--   USING ((SELECT hbh.has_permission('OPS.VIEW')))       4.6 ms
--
-- Measured on two scratch tables of 35,000 rows carrying policies of
-- identical MEANING - built and dropped in one file, touching nothing.
--
-- =====================================================================
-- WHY ONLY THIS ONE POLICY
--
-- 184 of the schema's 188 policies call one of these functions, so this
-- is a SHAPE and not a defect in one place. It is deliberately not fixed
-- everywhere here:
--
--   The cost is linear in rows scanned, and today exactly two tables in
--   the schema exceed 400 rows. hbh.audit_log carries no policy at all -
--   it is owner-only, correctly - which leaves hbh.request_log as the
--   only table where the shape currently costs anything.
--
--   The other 183 are the database owner's to change, with the
--   measurement in hand, when their tables approach the same size. A
--   sweeping edit across every policy in the schema deserves the eye of
--   the person who wrote them.
--
-- The meaning is unchanged. Same functions, same arguments, same answer.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0104') THEN
    RAISE EXCEPTION 'migration 0104 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0020') THEN
    RAISE EXCEPTION 'migration 0020 must be applied first - it creates p_rlog_select';
  END IF;
END
$guard$;

DROP POLICY IF EXISTS p_rlog_select ON hbh.request_log;

CREATE POLICY p_rlog_select ON hbh.request_log
  FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND (SELECT hbh.has_permission('OPS.VIEW')));

COMMENT ON TABLE hbh.request_log IS
  'One row per finished HTTP request. Its SELECT policy wraps each identity call in a scalar subquery so the planner evaluates it once rather than per row - 5,260ms to single digits at 34k rows (0104).';

-- =====================================================================
-- IT MUST STILL REFUSE
--
-- A policy that got faster by admitting everybody is not a fix, and a
-- timing comparison is exactly the measurement that would not show it.
-- So the check that runs here is the REFUSAL, not the speed.
--
-- It runs as hbh_app, because a check for a closed door run as the owner
-- proves only that the owner walks through it - a lesson this project
-- has already paid for once.
-- =====================================================================
-- Taken as the OWNER, before the role changes, because inside hbh_app
-- this very count is subject to the policy being tested. A policy that
-- refused everybody would make its own acceptance check read zero and
-- pass - the failure hiding itself inside the thing that looks for it.
SELECT set_config('hbh.probe_rows',
                  (SELECT count(*)::text FROM hbh.request_log), true);

SET LOCAL ROLE hbh_app;

DO $refuses$
DECLARE
  l_with    text;
  l_without text;
  n         bigint;
BEGIN
  -- Found by permission rather than by name: a migration that depended
  -- on dev_admin existing would silently skip its own check on any
  -- install that never created one.
  SELECT u.username INTO l_with
  FROM   hbh.users u
  JOIN   hbh.user_roles ur ON ur.user_id = u.user_id AND ur.active_flg
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
  JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
  WHERE  p.code = 'OPS.VIEW' AND u.active_flg
  LIMIT  1;

  SELECT u.username INTO l_without
  FROM   hbh.users u
  WHERE  u.active_flg
  AND    NOT EXISTS (
           SELECT 1 FROM hbh.user_roles ur
           JOIN hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
           JOIN hbh.permissions p ON p.permission_id = rp.permission_id
           WHERE ur.user_id = u.user_id AND ur.active_flg AND p.code = 'OPS.VIEW')
  LIMIT  1;

  -- No identity at all must see nothing. This one needs no accounts and
  -- so always runs.
  PERFORM set_config('hbh.user_id', '', true);
  SELECT count(*) INTO n FROM hbh.request_log;
  IF n <> 0 THEN
    RAISE EXCEPTION 'an unauthenticated connection can read % request-log row(s)', n;
  END IF;

  IF l_without IS NULL THEN
    RAISE WARNING 'no account without OPS.VIEW exists, so the refusal was only checked for an anonymous caller';
  ELSE
    PERFORM set_config('hbh.user_id', l_without, true);
    SELECT count(*) INTO n FROM hbh.request_log;
    IF n <> 0 THEN
      RAISE EXCEPTION 'user % has no OPS.VIEW and can read % request-log row(s) - the policy was made fast and open', l_without, n;
    END IF;
  END IF;

  -- And the other half: a policy nobody can pass is not a policy either.
  -- A refusal check with no matching acceptance check proves the door is
  -- shut, never that it opens.
  IF l_with IS NULL THEN
    RAISE WARNING 'no account holds OPS.VIEW, so the ACCEPTING half was not exercised';
  ELSE
    PERFORM set_config('hbh.user_id', l_with, true);
    SELECT count(*) INTO n FROM hbh.request_log;
    IF n = 0 AND coalesce(current_setting('hbh.probe_rows', true), '0')::bigint > 0 THEN
      RAISE EXCEPTION 'user % holds OPS.VIEW and sees none of the % rows that exist - the policy now refuses everybody',
                      l_with, current_setting('hbh.probe_rows', true);
    END IF;
  END IF;

  PERFORM set_config('hbh.user_id', '', true);
END
$refuses$;

RESET ROLE;

INSERT INTO hbh.schema_migrations (version) VALUES ('0104');
