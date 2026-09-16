-- =====================================================================
-- Hand By Hand (new) - PHASE 17 acceptance suite: payment plans (0142)
--
-- Must print:  PHASE 17 ACCEPTED
--
-- OD-33 · 11-FEAT §15 and §17.4-17.5 · PP-AC-01..07. Five claims:
--
--   1. A PLAN IS A TEMPLATE THAT FREEZES. It is drafted, completed and
--      activated; once active its terms and rows cannot move, so an
--      invoice issued yesterday and one issued today on "the same plan"
--      mean the same thing.
--   2. ISSUING WRITES THE SCHEDULE, AND IT ADDS UP. The deposit is due at
--      once, the last instalment carries the remainder, fixed amounts
--      that do not fit are refused by name.
--   3. MONEY SETTLES IN ORDER. A payment covers seq 1 first; 40% of a 50%
--      deposit is not a paid deposit.
--   4. AN OVERRIDE REPLACES, NEVER EDITS. Unpaid rows are SUPERSEDED, the
--      new rows add up to what is still owed, the paid ones are not
--      touched, and who and why is stamped on the invoice.
--   5. THE CLOCK TELLS EACH PERSON ONCE. DUE on the date, OVERDUE after
--      the grace days, one notice per instalment, staff of that centre
--      only.
--
-- EVERY REFUSAL NAMES ITS SQLSTATE, and a constraint refusal names its
-- CONSTRAINT (D-40): two CHECKs raising 23514 look identical to a harness
-- that only reads the code.
--
-- THE CLOCK RUNS INSIDE A SUB-BLOCK THAT ROLLS ITSELF BACK. mark_
-- installment_dues walks every centre's open instalments, and this is a
-- shared database: committing it here would move somebody else's
-- schedule and notify somebody else's family. The block measures, raises
-- its findings as the message of an exception it then catches, and
-- records them - so the numbers survive and the effects do not.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp text NOT NULL, name text NOT NULL, ok boolean NOT NULL, detail text);
CREATE TABLE hbh_test.fx (k text PRIMARY KEY, v integer);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL' ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text,
                                     p_constraint text DEFAULT NULL)
LANGUAGE plpgsql AS $$
DECLARE v_state text; v_con text; v_msg text;
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', THE CALL SUCCEEDED');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE, v_con = CONSTRAINT_NAME, v_msg = MESSAGE_TEXT;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name,
            v_state = p_sqlstate AND (p_constraint IS NULL OR v_con IS NOT DISTINCT FROM p_constraint),
            'expected ' || p_sqlstate || coalesce(' on ' || p_constraint, '')
            || ', got ' || v_state || coalesce(' on ' || nullif(v_con, ''), '') || ' ' || left(v_msg, 60));
  END;
END $$;

-- Does this user hold this permission through an active role? Asked of
-- the tables, not of has_permission, which answers only for the caller.
CREATE FUNCTION hbh_test.has(p_username text, p_code text) RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT EXISTS (SELECT 1 FROM hbh.users u
                 JOIN hbh.user_roles ur       ON ur.user_id = u.user_id AND ur.active_flg
                 JOIN hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
                 JOIN hbh.permissions p       ON p.permission_id = rp.permission_id AND p.active_flg
                 WHERE u.username = p_username AND u.active_flg AND p.code = p_code)
$$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT, INSERT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- Its own reception, guardian and child; 'admin' as the centre
-- administrator, as p6 does. Every row is found again and removed BY ITS
-- KEY at the bottom - P17- codes, p17. usernames, +2017000000xx mobiles.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p17.reception', 'استقبال اختبار ١٧', 'STAFF',    '+201700000001'),
       ('p17.guardian',  'ولي أمر اختبار ١٧', 'GUARDIAN', '+201700000002')
     ) AS u(username, name, utype, mobile);
INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc', user_id FROM hbh.users WHERE username = 'p17.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd', user_id FROM hbh.users WHERE username = 'p17.guardian';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id FROM hbh_test.fx f
JOIN hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE (f.k = 'user_rc' AND r.code = 'RECEPTION') OR (f.k = 'user_gd' AND r.code = 'GUARDIAN');

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P17-A', 'طفل اختبار ١٧', DATE '2020-04-04', 'M');
INSERT INTO hbh_test.fx (k, v) SELECT 'child', child_id FROM hbh.children WHERE child_no = 'P17-A';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'), 'ولي أمر اختبار ١٧', '+201700000002');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd', guardian_id FROM hbh.guardians WHERE mobile = '+201700000002';
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'), (SELECT v FROM hbh_test.fx WHERE k='child'), 'FATHER', true);

-- A second centre, so "another centre's plan" is a case the fixture can
-- actually produce rather than one it can only assert.
INSERT INTO hbh.centers (code, name_ar) VALUES ('P17-ELSEWHERE', 'مركز آخر اختبار ١٧');
INSERT INTO hbh_test.fx (k, v) SELECT 'center2', center_id FROM hbh.centers WHERE code = 'P17-ELSEWHERE';
INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center2'), 'P17_FOREIGN', 'خطّة مركز آخر', 'FULL');
INSERT INTO hbh_test.fx (k, v) SELECT 'plan_foreign', plan_id FROM hbh.payment_plans WHERE code = 'P17_FOREIGN';

-- Asserted BY NAME, before anything is tested.
CALL hbh_test.chk('fixture', 'migration 0142 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0142') $q$);
CALL hbh_test.chk('fixture', 'every fixture key is present',
  $q$ SELECT count(*) = 7 FROM hbh_test.fx
      WHERE k IN ('center','branch','user_rc','user_gd','child','gd','center2') AND v IS NOT NULL $q$);
CALL hbh_test.chk('fixture', 'the seeded FULL plan is the centre''s only default, and active',
  $q$ SELECT count(*) = 1 AND bool_and(code = 'FULL' AND status = 'ACTIVE')
      FROM hbh.payment_plans WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND is_default_flg $q$);
CALL hbh_test.chk('fixture', 'the seeded DEPOSIT_50 is active: 50 now, 50 after 6 sessions (OD-38)',
  $q$ SELECT p.status = 'ACTIVE' AND p.deposit_pct = 50
             AND (SELECT count(*) FROM hbh.payment_plan_installments i WHERE i.plan_id = p.plan_id AND i.active_flg) = 1
             AND EXISTS (SELECT 1 FROM hbh.payment_plan_installments i WHERE i.plan_id = p.plan_id
                         AND i.amount_kind = 'PERCENT' AND i.amount_value = 50
                         AND i.due_kind = 'AFTER_SESSIONS' AND i.due_value = 6)
      FROM hbh.payment_plans p
      WHERE p.center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND p.code = 'DEPOSIT_50' AND p.active_flg $q$);
CALL hbh_test.chk('fixture', 'the administrator overrides schedules; reception does not',
  $q$ SELECT hbh_test.has('admin', 'BILLING.SCHEDULE_OVERRIDE') AND hbh_test.has('admin', 'BILLING.MANAGE')
             AND NOT hbh_test.has('p17.reception', 'BILLING.SCHEDULE_OVERRIDE')
             AND NOT hbh_test.has('p17.reception', 'BILLING.MANAGE')
             AND hbh_test.has('p17.reception', 'BILLING.VIEW') $q$);
CALL hbh_test.chk('fixture', 'INSTALLMENT_GRACE_DAYS is a global 0',
  $q$ SELECT param_value = '0' FROM hbh.sys_params WHERE center_id IS NULL AND param_code = 'INSTALLMENT_GRACE_DAYS' $q$);

-- =====================================================================
-- 1. THE TEMPLATE
-- =====================================================================
SET hbh.user_id = 'admin';
SET ROLE hbh_app;

CALL hbh_test.chk('plan', 'an administrator drafts a deposit plan',
  $q$ WITH p AS (INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind, deposit_pct)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P17_DEP', 'مقدَّم اختبار ١٧', 'DEPOSIT_PERCENT', 50)
                 RETURNING plan_id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'plan_dep', plan_id FROM p RETURNING 1)
      SELECT (SELECT count(*) FROM f) = 1 $q$);

CALL hbh_test.chk_raises('plan', 'with no instalments it cannot be activated - HB267',
  $q$ UPDATE hbh.payment_plans SET status = 'ACTIVE' WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') $q$,
  'HB267');

CALL hbh_test.chk_raises('plan', 'a deposit plan cannot be born ACTIVE - HB267',
  $q$ INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind, deposit_pct, status)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P17_BORN', 'x', 'DEPOSIT_PERCENT', 30, 'ACTIVE') $q$,
  'HB267');

CALL hbh_test.chk('plan', 'two instalments of 40% are drafted',
  $q$ WITH i AS (INSERT INTO hbh.payment_plan_installments (plan_id, center_id, seq, amount_kind, amount_value, due_kind, due_value)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='plan_dep'), (SELECT v FROM hbh_test.fx WHERE k='center'), 1, 'PERCENT', 40, 'DAYS_AFTER_ISSUE', 30),
                        ((SELECT v FROM hbh_test.fx WHERE k='plan_dep'), (SELECT v FROM hbh_test.fx WHERE k='center'), 2, 'PERCENT', 40, 'DAYS_AFTER_ISSUE', 60)
                 RETURNING 1)
      SELECT count(*) = 2 FROM i $q$);

CALL hbh_test.chk_raises('plan', 'and 50 + 80 cannot be activated - HB267',
  $q$ UPDATE hbh.payment_plans SET status = 'ACTIVE' WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') $q$,
  'HB267');

CALL hbh_test.chk_raises('plan', 'a percentage above 100 is refused by its own CHECK',
  $q$ UPDATE hbh.payment_plan_installments SET amount_value = 120
      WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') AND seq = 1 $q$,
  '23514', 'ck_ppi_amount');

CALL hbh_test.chk('plan', '25 / 25 after the deposit activates',
  $q$ WITH u AS (UPDATE hbh.payment_plan_installments SET amount_value = 25
                 WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') RETURNING 1)
      SELECT count(*) = 2 FROM u $q$);
CALL hbh_test.chk('plan', '...and the plan is ACTIVE',
  $q$ WITH a AS (UPDATE hbh.payment_plans SET status = 'ACTIVE'
                 WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') RETURNING status)
      SELECT status = 'ACTIVE' FROM a $q$);

CALL hbh_test.chk_raises('plan', 'an active template row cannot change - HB266',
  $q$ UPDATE hbh.payment_plan_installments SET amount_value = 20
      WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') AND seq = 1 $q$, 'HB266');
CALL hbh_test.chk_raises('plan', 'nor its deposit - HB266',
  $q$ UPDATE hbh.payment_plans SET deposit_pct = 40 WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') $q$, 'HB266');
CALL hbh_test.chk_raises('plan', 'ACTIVE does not go back to DRAFT - HB265',
  $q$ UPDATE hbh.payment_plans SET status = 'DRAFT' WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') $q$, 'HB265');
CALL hbh_test.chk_raises('plan', 'the default cannot be retired - HB266',
  $q$ UPDATE hbh.payment_plans SET status = 'RETIRED'
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND is_default_flg $q$, 'HB266');
CALL hbh_test.chk_raises('plan', 'PP-AC-07: a second default is refused by the index, by name',
  $q$ UPDATE hbh.payment_plans SET is_default_flg = true WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep') $q$,
  '23505', 'uix_payment_plans_default');

-- A plan whose fixed amounts will not fit a small invoice.
CALL hbh_test.chk('plan', 'a plan with a fixed 5000 and a 10% after 6 sessions is built and activated',
  $q$ WITH p AS (INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind, deposit_pct)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P17_BIG', 'مبلغ ثابت اختبار ١٧', 'DEPOSIT_PERCENT', 10)
                 RETURNING plan_id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'plan_big', plan_id FROM p RETURNING 1)
      SELECT (SELECT count(*) FROM f) = 1 $q$);
CALL hbh_test.chk('plan', '...its rows',
  $q$ WITH i AS (INSERT INTO hbh.payment_plan_installments (plan_id, center_id, seq, amount_kind, amount_value, due_kind, due_value)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='plan_big'), (SELECT v FROM hbh_test.fx WHERE k='center'), 1, 'AMOUNT', 5000, 'DAYS_AFTER_ISSUE', 30),
                        ((SELECT v FROM hbh_test.fx WHERE k='plan_big'), (SELECT v FROM hbh_test.fx WHERE k='center'), 2, 'PERCENT', 10, 'AFTER_SESSIONS', 6)
                 RETURNING 1)
      SELECT count(*) = 2 FROM i $q$);
CALL hbh_test.chk('plan', '...activated',
  $q$ WITH a AS (UPDATE hbh.payment_plans SET status = 'ACTIVE'
                 WHERE plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_big') RETURNING 1)
      SELECT count(*) = 1 FROM a $q$);

RESET ROLE;
SET hbh.user_id = 'p17.reception';
SET ROLE hbh_app;
CALL hbh_test.chk_raises('plan', 'reception cannot create a plan - the policy refuses',
  $q$ INSERT INTO hbh.payment_plans (center_id, code, name_ar, kind)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), 'P17_REC', 'x', 'FULL') $q$, '42501');
CALL hbh_test.chk('plan', 'but reception reads the plans it sells on',
  $q$ SELECT count(*) >= 3 FROM hbh.payment_plans $q$);
CALL hbh_test.chk('plan', 'and never another centre''s',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.payment_plans WHERE code = 'P17_FOREIGN') $q$);
RESET hbh.user_id;
CALL hbh_test.chk('plan', 'no identity reads no plan',
  $q$ SELECT (SELECT count(*) FROM hbh.payment_plans) = 0
         AND (SELECT count(*) FROM hbh.payment_plan_installments) = 0 $q$);
RESET ROLE;

-- =====================================================================
-- 2. ISSUING WRITES THE SCHEDULE
-- =====================================================================
SET hbh.user_id = 'admin';
SET ROLE hbh_app;

CALL hbh_test.chk('issue', 'a draft of 1000 is prepared',
  $q$ WITH i AS (SELECT hbh.create_invoice((SELECT v FROM hbh_test.fx WHERE k='child'), NULL, NULL, 'p17 deposit') AS id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'inv_dep', id FROM i RETURNING v),
           l AS (SELECT hbh.add_invoice_line((SELECT v FROM f), 'p17', 1, 1000))
      SELECT (SELECT count(*) FROM l) = 1 $q$);

CALL hbh_test.chk_raises('issue', 'on another centre''s plan: no such plan - HB051',
  $q$ SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_dep'), (SELECT v FROM hbh_test.fx WHERE k='plan_foreign')) $q$,
  'HB051');
CALL hbh_test.chk_raises('issue', 'on a plan that does not exist: the same answer - HB051',
  $q$ SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_dep'), 999999999) $q$, 'HB051');

CALL hbh_test.chk('issue', 'issued on the 50 + 25/25 plan',
  $q$ WITH s AS (SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_dep'), (SELECT v FROM hbh_test.fx WHERE k='plan_dep')))
      SELECT (SELECT count(*) FROM s) = 1 $q$);

RESET ROLE;
CALL hbh_test.chk('issue', 'PP-AC-01: three instalments, the deposit due, the rest pending, adding up',
  $q$ SELECT string_agg(seq || ':' || amount || ':' || status, ' ' ORDER BY seq) = '1:500.00:DUE 2:250.00:PENDING 3:250.00:PENDING'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
CALL hbh_test.chk('issue', 'the plan is stamped on the invoice',
  $q$ SELECT payment_plan_id = (SELECT v FROM hbh_test.fx WHERE k='plan_dep')
      FROM hbh.invoices WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
CALL hbh_test.chk('issue', 'and every row has a history line',
  $q$ SELECT count(*) = 3 FROM hbh.invoice_installment_status_history h
      JOIN hbh.invoice_installments x USING (installment_id)
      WHERE x.invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') AND h.from_status IS NULL $q$);
SET ROLE hbh_app;

CALL hbh_test.chk_raises('issue', 'issuing it again is refused - HB050',
  $q$ SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_dep')) $q$, 'HB050');

CALL hbh_test.chk('issue', 'a draft of 300 issued with no plan named',
  $q$ WITH i AS (SELECT hbh.create_invoice((SELECT v FROM hbh_test.fx WHERE k='child'), NULL, NULL, 'p17 full') AS id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'inv_full', id FROM i RETURNING v),
           l AS (SELECT hbh.add_invoice_line((SELECT v FROM f), 'p17', 1, 300))
      SELECT (SELECT count(*) FROM l) = 1 $q$);
CALL hbh_test.chk('issue', '...issued',
  $q$ WITH s AS (SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_full'))) SELECT (SELECT count(*) FROM s) = 1 $q$);

CALL hbh_test.chk('issue', 'a draft of 1200 on the seeded DEPOSIT_50',
  $q$ WITH i AS (SELECT hbh.create_invoice((SELECT v FROM hbh_test.fx WHERE k='child'), NULL, NULL, 'p17 seeded') AS id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'inv_seed', id FROM i RETURNING v),
           l AS (SELECT hbh.add_invoice_line((SELECT v FROM f), 'p17', 1, 1200))
      SELECT (SELECT count(*) FROM l) = 1 $q$);
CALL hbh_test.chk('issue', '...issued',
  $q$ WITH s AS (SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_seed'),
                   (SELECT plan_id FROM hbh.payment_plans WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
                    AND code = 'DEPOSIT_50' AND active_flg)))
      SELECT (SELECT count(*) FROM s) = 1 $q$);

CALL hbh_test.chk('issue', 'a draft of 100 for the fixed-amount plan',
  $q$ WITH i AS (SELECT hbh.create_invoice((SELECT v FROM hbh_test.fx WHERE k='child'), NULL, NULL, 'p17 small') AS id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'inv_small', id FROM i RETURNING v),
           l AS (SELECT hbh.add_invoice_line((SELECT v FROM f), 'p17', 1, 100))
      SELECT (SELECT count(*) FROM l) = 1 $q$);
CALL hbh_test.chk_raises('issue', 'a fixed 5000 on an invoice of 100 is refused, not trimmed - HB268',
  $q$ SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_small'), (SELECT v FROM hbh_test.fx WHERE k='plan_big')) $q$,
  'HB268');

CALL hbh_test.chk('issue', 'a draft of 10000 on the fixed-amount plan',
  $q$ WITH i AS (SELECT hbh.create_invoice((SELECT v FROM hbh_test.fx WHERE k='child'), NULL, NULL, 'p17 big') AS id),
           f AS (INSERT INTO hbh_test.fx (k, v) SELECT 'inv_big', id FROM i RETURNING v),
           l AS (SELECT hbh.add_invoice_line((SELECT v FROM f), 'p17', 1, 10000))
      SELECT (SELECT count(*) FROM l) = 1 $q$);
CALL hbh_test.chk('issue', '...issued',
  $q$ WITH s AS (SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_big'), (SELECT v FROM hbh_test.fx WHERE k='plan_big')))
      SELECT (SELECT count(*) FROM s) = 1 $q$);

RESET ROLE;
CALL hbh_test.chk('issue', 'FULL follows the invoice''s own due date',
  $q$ SELECT count(*) = 1 AND bool_and(x.seq = 1 AND x.amount = 300 AND x.due_date = i.due_date
                                        AND x.status = CASE WHEN i.due_date <= hbh.center_today(i.center_id) THEN 'DUE' ELSE 'PENDING' END)
      FROM hbh.invoice_installments x JOIN hbh.invoices i USING (invoice_id)
      WHERE x.invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_full') $q$);
CALL hbh_test.chk('issue', 'OD-38: the seeded plan gives 600 now and 600 after 6 sessions',
  $q$ SELECT string_agg(seq || ':' || amount || ':' || status || ':' || coalesce(due_after_sessions::text, '-'), ' ' ORDER BY seq)
             = '1:600.00:DUE:- 2:600.00:PENDING:6'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_seed') $q$);
CALL hbh_test.chk('issue', 'the last instalment carries the remainder',
  $q$ SELECT string_agg(seq || ':' || amount || ':' || coalesce(due_after_sessions::text, '-'), ' ' ORDER BY seq)
             = '1:1000.00:- 2:5000.00:- 3:4000.00:6'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') $q$);
CALL hbh_test.chk('issue', 'and the refused one wrote nothing and is still a draft',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_small'))
         AND (SELECT status FROM hbh.invoices WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_small')) = 'DRAFT' $q$);

-- =====================================================================
-- 3. MONEY SETTLES IN ORDER
-- =====================================================================
SET ROLE hbh_app;
CALL hbh_test.chk('settle', 'a payment of 400 is taken',
  $q$ WITH p AS (INSERT INTO hbh.payments (center_id, invoice_id, amount)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='inv_dep'), 400) RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);
RESET ROLE;
CALL hbh_test.chk('settle', 'PP-AC-02: 400 of a 500 deposit leaves it DUE',
  $q$ SELECT status = 'DUE' AND paid_at IS NULL FROM hbh.invoice_installments
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') AND seq = 1 $q$);
SET ROLE hbh_app;
CALL hbh_test.chk('settle', 'another 100',
  $q$ WITH p AS (INSERT INTO hbh.payments (center_id, invoice_id, amount)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='inv_dep'), 100) RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);
RESET ROLE;
CALL hbh_test.chk('settle', 'PP-AC-02: now the deposit is PAID, stamped, and seq 2 untouched',
  $q$ SELECT string_agg(seq || ':' || status || ':' || (paid_at IS NOT NULL), ' ' ORDER BY seq) = '1:PAID:true 2:PENDING:false 3:PENDING:false'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);

-- The family sees its own schedule; the app writes none.
SET hbh.user_id = 'p17.guardian';
SET ROLE hbh_app;
CALL hbh_test.chk('settle', 'the family reads its own schedule',
  $q$ SELECT count(*) = 3 FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
CALL hbh_test.chk_raises('settle', 'and no one writes an instalment directly',
  $q$ INSERT INTO hbh.invoice_installments (center_id, invoice_id, seq, amount, due_date, status)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='inv_dep'), 99, 1, CURRENT_DATE, 'DUE') $q$,
  '42501');
RESET hbh.user_id;
CALL hbh_test.chk('settle', 'no identity reads no schedule',
  $q$ SELECT (SELECT count(*) FROM hbh.invoice_installments) = 0
         AND (SELECT count(*) FROM hbh.invoice_installment_status_history) = 0 $q$);
RESET ROLE;

-- =====================================================================
-- 4. THE OVERRIDE
-- =====================================================================
SET hbh.user_id = 'p17.reception';
SET ROLE hbh_app;
CALL hbh_test.chk_raises('override', 'PP-AC-05: without BILLING.SCHEDULE_OVERRIDE - HB270',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":500,"due_date":"2026-12-01"}]', 'x') $q$, 'HB270');
RESET ROLE;
SET hbh.user_id = 'admin';
SET ROLE hbh_app;
CALL hbh_test.chk_raises('override', 'PP-AC-05: with it but no reason - HB271',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":500,"due_date":"2026-12-01"}]', '   ') $q$, 'HB271');
CALL hbh_test.chk_raises('override', 'PP-AC-05: a total that is not what is owed - HB272',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":400,"due_date":"2026-12-01"}]', 'p17 asked') $q$, 'HB272');
CALL hbh_test.chk_raises('override', 'an amount written as a word - HB273, not 22P02',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":"lots","due_date":"2026-12-01"}]', 'p17 asked') $q$, 'HB273');
CALL hbh_test.chk_raises('override', 'a date that does not exist - HB273',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":500,"due_date":"2026-02-30"}]', 'p17 asked') $q$, 'HB273');
CALL hbh_test.chk_raises('override', 'both a date and a session count - HB273',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":500,"due_date":"2026-12-01","due_after_sessions":3}]', 'p17 asked') $q$, 'HB273');
CALL hbh_test.chk_raises('override', 'on a draft invoice - HB050',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_small'),
                                               '[{"amount":100,"due_date":"2026-12-01"}]', 'p17 asked') $q$, 'HB050');
CALL hbh_test.chk('override', 'PP-AC-05: the valid one is accepted',
  $q$ SELECT hbh.override_installment_schedule((SELECT v FROM hbh_test.fx WHERE k='inv_dep'),
                                               '[{"amount":500,"due_date":"2026-12-01"}]', 'p17 asked') = 1 $q$);
RESET ROLE;
CALL hbh_test.chk('override', 'the paid row stands, the unpaid are SUPERSEDED, the new one follows',
  $q$ SELECT string_agg(seq || ':' || amount || ':' || status, ' ' ORDER BY seq)
             = '1:500.00:PAID 2:250.00:SUPERSEDED 3:250.00:SUPERSEDED 4:500.00:PENDING'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
CALL hbh_test.chk('override', 'who, why and when are stamped on the invoice',
  $q$ SELECT schedule_override_reason_ar = 'p17 asked' AND schedule_overridden_at IS NOT NULL
             AND schedule_overridden_by = (SELECT user_id FROM hbh.users WHERE username = 'admin')
      FROM hbh.invoices WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
CALL hbh_test.chk('override', 'history: 3 issued + seq 1 paid + 2 superseded + 1 new',
  $q$ SELECT count(*) = 7 FROM hbh.invoice_installment_status_history h
      JOIN hbh.invoice_installments x USING (installment_id)
      WHERE x.invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') $q$);
SET ROLE hbh_app;
CALL hbh_test.chk('override', 'paying the rest settles the new row',
  $q$ WITH p AS (INSERT INTO hbh.payments (center_id, invoice_id, amount)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='inv_dep'), 500) RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);
RESET ROLE;
CALL hbh_test.chk('override', '...every live row PAID',
  $q$ SELECT string_agg(status, ' ' ORDER BY seq) = 'PAID PAID'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_dep') AND status <> 'SUPERSEDED' $q$);
RESET hbh.user_id;

-- The owner can reach what the app cannot; the schema still says no.
CALL hbh_test.chk_raises('override', 'an instalment''s amount cannot be rewritten - HB269',
  $q$ UPDATE hbh.invoice_installments SET amount = amount + 1
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') AND seq = 3 $q$, 'HB269');
CALL hbh_test.chk_raises('override', 'nor its due date - HB269',
  $q$ UPDATE hbh.invoice_installments SET due_date = due_date - 1
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') AND seq = 2 $q$, 'HB269');

-- =====================================================================
-- 5. THE CLOCK - measured inside a sub-block that rolls itself back
-- =====================================================================
DO $clock$
DECLARE
  l_found text;
BEGIN
  BEGIN
    DECLARE
      l_inv   integer := (SELECT v FROM hbh_test.fx WHERE k='inv_big');
      l_child integer := (SELECT v FROM hbh_test.fx WHERE k='child');
      l_today date    := hbh.center_today((SELECT v FROM hbh_test.fx WHERE k='center'));
      a text; b text; c text; d text; e text; g text; h text;
    BEGIN
      -- A schedule due three days ago, built the way the product builds it.
      PERFORM set_config('hbh.user_id', 'admin', true);
      -- The whole of what is owed (nothing is paid on this invoice), in one row.
      PERFORM hbh.override_installment_schedule(l_inv,
        jsonb_build_array(jsonb_build_object(
          'amount', (SELECT total_amt FROM hbh.invoices WHERE invoice_id = l_inv),
          'due_date', to_char(l_today - 3, 'YYYY-MM-DD'))), 'p17 clock');
      PERFORM set_config('hbh.user_id', '', true);

      UPDATE hbh.sys_params SET param_value = '5' WHERE center_id IS NULL AND param_code = 'INSTALLMENT_GRACE_DAYS';
      PERFORM hbh.mark_installment_dues();
      SELECT string_agg(status, ',') INTO a FROM hbh.invoice_installments WHERE invoice_id = l_inv AND seq > 3;
      SELECT count(*)::text INTO b FROM hbh.notifications WHERE link_kind = 'INVOICE' AND link_id = l_inv
        AND kind_code IN ('INSTALLMENT_OVERDUE', 'STAFF_INSTALLMENT_OVERDUE');

      UPDATE hbh.sys_params SET param_value = '0' WHERE center_id IS NULL AND param_code = 'INSTALLMENT_GRACE_DAYS';
      PERFORM hbh.mark_installment_dues();
      PERFORM hbh.mark_installment_dues();
      SELECT string_agg(status, ',') INTO c FROM hbh.invoice_installments WHERE invoice_id = l_inv AND seq > 3;
      SELECT count(*)::text INTO d FROM hbh.notifications n WHERE n.link_kind = 'INVOICE' AND n.link_id = l_inv
        AND n.kind_code = 'INSTALLMENT_OVERDUE'
        AND n.user_id = (SELECT v FROM hbh_test.fx WHERE k='user_gd');
      SELECT (count(*) >= 1 AND bool_and(u.center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND u.user_type = 'STAFF')
              AND count(*) = count(DISTINCT n.user_id))::text
        INTO e
      FROM hbh.notifications n JOIN hbh.users u ON u.user_id = n.user_id
      WHERE n.link_kind = 'INVOICE' AND n.link_id = l_inv AND n.kind_code = 'STAFF_INSTALLMENT_OVERDUE';
      SELECT string_agg(status, ',' ORDER BY seq) INTO g FROM hbh.invoice_installments
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_seed') AND seq = 2;
      SELECT (count(*) = 0)::text INTO h FROM hbh.notifications
      WHERE link_kind = 'INVOICE' AND link_id = l_inv AND kind_code = 'INSTALLMENT_DUE';

      RAISE EXCEPTION USING ERRCODE = 'HB999',
        MESSAGE = concat_ws('|', a, b, c, d, e, g, h);
    END;
  EXCEPTION WHEN SQLSTATE 'HB999' THEN
    l_found := SQLERRM;
  END;

  INSERT INTO hbh_test.results (grp, name, ok, detail) VALUES
    ('clock', 'grace 5, three days past: DUE, nobody told it is late',
     split_part(l_found, '|', 1) = 'DUE' AND split_part(l_found, '|', 2) = '0', l_found),
    ('clock', 'grace 0: OVERDUE',
     split_part(l_found, '|', 3) = 'OVERDUE', l_found),
    ('clock', 'the family told once across two runs',
     split_part(l_found, '|', 4) = '1', l_found),
    ('clock', 'staff of this centre only, each once',
     split_part(l_found, '|', 5) = 'true', l_found),
    ('clock', 'the after-sessions instalment is left to layer B',
     split_part(l_found, '|', 6) = 'PENDING', l_found),
    ('clock', 'a row that jumps DUE -> OVERDUE in the rolled-back pass is not also told "due"',
     split_part(l_found, '|', 7) = 'true', l_found);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO hbh_test.results (grp, name, ok, detail)
  VALUES ('clock', 'the clock block ran', false, SQLSTATE || ' ' || SQLERRM);
END
$clock$;

CALL hbh_test.chk('clock', 'and the pass left nothing behind',
  $q$ SELECT (SELECT param_value FROM hbh.sys_params WHERE center_id IS NULL AND param_code = 'INSTALLMENT_GRACE_DAYS') = '0'
         AND NOT EXISTS (SELECT 1 FROM hbh.invoice_installments
                         WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') AND seq > 3)
         AND NOT EXISTS (SELECT 1 FROM hbh.notifications WHERE link_kind = 'INVOICE'
                         AND link_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big')
                         AND kind_code LIKE '%INSTALLMENT%') $q$);

-- A cancelled invoice cancels what it still asked for.
CALL hbh_test.chk('clock', 'cancelling the invoice cancels its unpaid instalments',
  $q$ WITH u AS (UPDATE hbh.invoices SET status = 'CANCELLED'
                 WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') RETURNING 1)
      SELECT (SELECT count(*) FROM u) = 1 $q$);
CALL hbh_test.chk('clock', '...all three',
  $q$ SELECT string_agg(status, ' ' ORDER BY seq) = 'CANCELLED CANCELLED CANCELLED'
      FROM hbh.invoice_installments WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv_big') $q$);

-- =====================================================================
-- CLEANUP - by key, each level its own statement, guards back on.
-- =====================================================================
RESET ROLE;
RESET hbh.user_id;

CALL hbh_test.chk('cleanup', 'notices about this suite''s invoices removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications
                 WHERE (link_kind = 'INVOICE' AND link_id IN
                         (SELECT invoice_id FROM hbh.invoices WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')))
                    OR user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p17.%')
                 RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

ALTER TABLE hbh.invoice_installment_status_history DISABLE TRIGGER trg_iish_append_only;
CALL hbh_test.chk('cleanup', 'schedule history removed',
  $q$ WITH d AS (DELETE FROM hbh.invoice_installment_status_history WHERE installment_id IN
                   (SELECT x.installment_id FROM hbh.invoice_installments x JOIN hbh.invoices i USING (invoice_id)
                    WHERE i.child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);
ALTER TABLE hbh.invoice_installment_status_history ENABLE TRIGGER trg_iish_append_only;

CALL hbh_test.chk('cleanup', 'schedules removed',
  $q$ WITH d AS (DELETE FROM hbh.invoice_installments WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

-- Several data-modifying CTEs have no order between them. A PAID or
-- CANCELLED invoice refuses changes to its lines (trg_line_guard), and
-- a deleted payment recalculates an invoice that may already be gone -
-- so whether this one statement passes depends on a plan. It failed
-- that way cleaning p6's leftovers on 2026-09-13. The guards step aside
-- for this one statement and are asserted back on below.
ALTER TABLE hbh.invoice_lines DISABLE TRIGGER trg_line_guard;
ALTER TABLE hbh.invoice_lines DISABLE TRIGGER trg_line_recalc;
ALTER TABLE hbh.payments      DISABLE TRIGGER trg_pay_recalc;
CALL hbh_test.chk('cleanup', 'payments, lines and invoices removed',
  $q$ WITH p AS (DELETE FROM hbh.payments WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1),
           l AS (DELETE FROM hbh.invoice_lines WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child')) RETURNING 1),
           i AS (DELETE FROM hbh.invoices WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 5 $q$);
ALTER TABLE hbh.invoice_lines ENABLE TRIGGER trg_line_guard;
ALTER TABLE hbh.invoice_lines ENABLE TRIGGER trg_line_recalc;
ALTER TABLE hbh.payments      ENABLE TRIGGER trg_pay_recalc;

ALTER TABLE hbh.payment_plan_installments DISABLE TRIGGER trg_ppi_frozen;
CALL hbh_test.chk('cleanup', 'this suite''s template rows removed',
  $q$ WITH d AS (DELETE FROM hbh.payment_plan_installments WHERE plan_id IN
                   (SELECT plan_id FROM hbh.payment_plans WHERE code LIKE 'P17\_%') RETURNING 1)
      SELECT count(*) = 4 FROM d $q$);
ALTER TABLE hbh.payment_plan_installments ENABLE TRIGGER trg_ppi_frozen;

CALL hbh_test.chk('cleanup', 'this suite''s plans removed',
  $q$ WITH d AS (DELETE FROM hbh.payment_plans WHERE code LIKE 'P17\_%' RETURNING 1)
      SELECT count(*) = 3 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the second centre removed',
  $q$ WITH d AS (DELETE FROM hbh.centers WHERE code = 'P17-ELSEWHERE' RETURNING 1) SELECT count(*) = 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the family links removed',
  $q$ WITH d AS (DELETE FROM hbh.guardian_children WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);
CALL hbh_test.chk('cleanup', 'the child removed',
  $q$ WITH d AS (DELETE FROM hbh.children WHERE child_no = 'P17-A' RETURNING 1) SELECT count(*) = 1 FROM d $q$);
CALL hbh_test.chk('cleanup', 'the guardian removed',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);
CALL hbh_test.chk('cleanup', 'the roles removed',
  $q$ WITH d AS (DELETE FROM hbh.user_roles WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p17.%') RETURNING 1)
      SELECT count(*) = 2 FROM d $q$);
CALL hbh_test.chk('cleanup', 'the accounts removed',
  $q$ WITH d AS (DELETE FROM hbh.users WHERE username LIKE 'p17.%' RETURNING 1) SELECT count(*) = 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'every guard this cleanup stepped around is enabled again, by name',
  $q$ SELECT count(*) = 5 AND bool_and(tgenabled = 'O') FROM pg_trigger
      WHERE tgname IN ('trg_iish_append_only', 'trg_ppi_frozen', 'trg_line_guard', 'trg_line_recalc', 'trg_pay_recalc') $q$);
CALL hbh_test.chk('cleanup', 'and nothing of this suite is left behind',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.users WHERE username LIKE 'p17.%')
         AND NOT EXISTS (SELECT 1 FROM hbh.children WHERE child_no LIKE 'P17-%')
         AND NOT EXISTS (SELECT 1 FROM hbh.payment_plans WHERE code LIKE 'P17\_%')
         AND NOT EXISTS (SELECT 1 FROM hbh.centers WHERE code = 'P17-ELSEWHERE')
         AND NOT EXISTS (SELECT 1 FROM hbh.guardians WHERE mobile LIKE '+2017000000%') $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة", count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM hbh_test.results GROUP BY grp ORDER BY min(seq);

\echo ''
SELECT seq, grp, name, detail FROM hbh_test.results WHERE NOT ok ORDER BY seq;

DO $verdict$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 17 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 17 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
