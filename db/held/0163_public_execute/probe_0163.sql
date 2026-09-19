-- Rolled-back proof of 0163. Expects /tmp/0163_up.sql and /tmp/0163_down.sql.
--
-- The property that matters is not "PUBLIC lost something" - it is that
-- hbh_app's REACH is unchanged except for the five internal helpers. So the
-- probe captures every function hbh_app can execute, before and after, and
-- diffs the two sets. Reasoning about fourteen ACLs by eye is how a grant
-- goes missing and a live route starts answering 42501 next Tuesday.
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
CREATE TEMP TABLE r (n serial, what text, got text, want text);

CREATE TEMP TABLE before_reach AS
SELECT p.oid, p.proname
FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE  n.nspname = 'hbh' AND p.prokind = 'f'
AND    has_function_privilege('hbh_app', p.oid, 'EXECUTE');

INSERT INTO r (what, got, want)
SELECT 'before: PUBLIC can execute 19 callable SECURITY DEFINER functions',
       (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'hbh' AND p.prokind = 'f' AND p.prosecdef
           AND p.prorettype <> 'trigger'::regtype
           AND has_function_privilege('public', p.oid, 'EXECUTE')), '19';

INSERT INTO r (what, got, want)
SELECT 'before: the API role can run the maintenance task that notifies families',
       has_function_privilege('hbh_app', 'hbh.mark_installment_dues()', 'EXECUTE')::text, 'true';

\i /tmp/0163_up.sql
;

INSERT INTO r (what, got, want)
SELECT 'after: no callable SECURITY DEFINER function is executable by PUBLIC',
       (SELECT coalesce(string_agg(p.proname, ',' ORDER BY p.proname), '')
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'hbh' AND p.prokind = 'f' AND p.prosecdef
           AND p.prorettype <> 'trigger'::regtype
           AND has_function_privilege('public', p.oid, 'EXECUTE')), '';

-- The whole point: what hbh_app lost, by name.
INSERT INTO r (what, got, want)
SELECT 'after: hbh_app lost exactly the five internal helpers and nothing else',
       (SELECT coalesce(string_agg(b.proname, ',' ORDER BY b.proname), '')
          FROM before_reach b
         WHERE NOT has_function_privilege('hbh_app', b.oid, 'EXECUTE')),
       'center_today,check_installments_total,mark_installment_dues,payment_plan_problem,settle_installments';

INSERT INTO r (what, got, want)
SELECT 'after: and it gained nothing it did not have',
       (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'hbh' AND p.prokind = 'f'
           AND has_function_privilege('hbh_app', p.oid, 'EXECUTE')
           AND NOT EXISTS (SELECT 1 FROM before_reach b WHERE b.oid = p.oid)), '0';

-- Spot-checks in both directions, because a set difference of zero can
-- also mean the query is asking nothing.
INSERT INTO r (what, got, want)
SELECT 'after: hbh_app still runs the fourteen it was meant to run',
       has_function_privilege('hbh_app', 'hbh.create_user(text,text,text,text,integer)', 'EXECUTE')::text || ' ' ||
       has_function_privilege('hbh_app', 'hbh.issue_invoice(integer,integer)', 'EXECUTE')::text || ' ' ||
       has_function_privilege('hbh_app', 'hbh.set_user_roles(integer,text[])', 'EXECUTE')::text, 'true true true';

INSERT INTO r (what, got, want)
SELECT 'after: and no longer the maintenance task',
       has_function_privilege('hbh_app', 'hbh.mark_installment_dues()', 'EXECUTE')::text, 'false';

-- The owner still runs everything: these are its functions, and
-- run_maintenance calls the helpers as the owner.
INSERT INTO r (what, got, want)
SELECT 'after: the owner is untouched, so run_maintenance still works',
       has_function_privilege('hbh_owner', 'hbh.mark_installment_dues()', 'EXECUTE')::text || ' ' ||
       (SELECT (hbh.run_maintenance() IS NOT NULL)::text), 'true true';

-- Trigger functions are deliberately left alone.
INSERT INTO r (what, got, want)
SELECT 'after: trigger functions keep PUBLIC, and calling one directly still refuses',
       (SELECT has_function_privilege('public', p.oid, 'EXECUTE')::text
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'hbh' AND p.proname = 'trg_touch'), 'true';

\i /tmp/0163_down.sql
;
INSERT INTO r (what, got, want)
SELECT 'down: PUBLIC has them back, all nineteen',
       (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'hbh' AND p.prokind = 'f' AND p.prosecdef
           AND p.prorettype <> 'trigger'::regtype
           AND has_function_privilege('public', p.oid, 'EXECUTE')), '19';

INSERT INTO r (what, got, want)
SELECT 'down: and hbh_app is back to exactly what it could run before',
       (SELECT count(*)::text FROM before_reach b WHERE NOT has_function_privilege('hbh_app', b.oid, 'EXECUTE')), '0';

\i /tmp/0163_up.sql
;
INSERT INTO r (what, got, want)
SELECT 'up again', (SELECT count(*) FROM hbh.schema_migrations WHERE version = '0163')::text, '1';

SELECT n, CASE WHEN got IS NOT DISTINCT FROM want THEN 'ok  ' ELSE 'FAIL' END AS v, what, got, want FROM r ORDER BY n;
SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) || ' ok, ' || count(*) FILTER (WHERE got IS DISTINCT FROM want) || ' failed' FROM r;
ROLLBACK;
