-- =====================================================================
-- Hand By Hand (new) - PHASE 6 acceptance suite
--
-- Must print:  PHASE 6 ACCEPTED
--
-- Money is the part of the system a family checks line by line, so the
-- claims here are arithmetic ones and they are tested as arithmetic:
--   * a total is derived from the lines and cannot be typed;
--   * a package balance cannot go negative, and every session it lost
--     is named in the ledger;
--   * a settled invoice is finished.
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
GRANT SELECT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P6-SPEECH', 'تخاطب — اختبار ٦', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P6-SPEECH';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p6.reception', 'استقبال اختبار ٦', 'STAFF',    '+201600000001'),
       ('p6.guardian',  'ولي أمر اختبار ٦', 'GUARDIAN', '+201600000002'),
       ('p6.other_gd',  'ولي أمر آخر ٦',    'GUARDIAN', '+201600000003')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_rc',  user_id FROM hbh.users WHERE username='p6.reception';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd',  user_id FROM hbh.users WHERE username='p6.guardian';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_gd2', user_id FROM hbh.users WHERE username='p6.other_gd';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_rc' AND r.code = 'RECEPTION')
   OR  (f.k IN ('user_gd','user_gd2') AND r.code = 'GUARDIAN');

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P6-A', 'طفل اختبار ٦ أ', DATE '2020-03-03', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P6-B', 'طفل اختبار ٦ ب', DATE '2021-09-09', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='P6-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P6-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd'),  'ولي أمر اختبار ٦', '+201600000002'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_gd2'), 'ولي أمر آخر ٦',    '+201600000003');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd',  guardian_id FROM hbh.guardians WHERE mobile='+201600000002';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd2', guardian_id FROM hbh.guardians WHERE mobile='+201600000003';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd'),  (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER', true),
       ((SELECT v FROM hbh_test.fx WHERE k='gd2'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'MOTHER', true);

INSERT INTO hbh.service_packages (center_id, service_id, code, name_ar, sessions_cnt, price_amt, validity_days)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='svc'),
        'P6-PKG3', 'باقة تخاطب — ٣ جلسات', 3, 1500.00, 90);
INSERT INTO hbh_test.fx (k, v) SELECT 'pkg', package_id FROM hbh.service_packages WHERE code='P6-PKG3';

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0008 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0008') $q$);

CALL hbh_test.chk('fixture', 'the package definition exists with three sessions',
  $q$ SELECT sessions_cnt = 3 AND price_amt = 1500.00 FROM hbh.service_packages
      WHERE package_id = (SELECT v FROM hbh_test.fx WHERE k='pkg') $q$);

CALL hbh_test.chk('fixture', 'reception holds BILLING.VIEW but not BILLING.MANAGE',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'RECEPTION' AND p.code = 'BILLING.VIEW')
      AND NOT EXISTS (SELECT 1 FROM hbh.roles r
        JOIN hbh.role_permissions rp ON rp.role_id = r.role_id
        JOIN hbh.permissions p ON p.permission_id = rp.permission_id
        WHERE r.code = 'RECEPTION' AND p.code = 'BILLING.MANAGE') $q$);

CALL hbh_test.chk('fixture', 'the two guardians are linked to different children',
  $q$ SELECT count(DISTINCT child_id) = 2 FROM hbh.guardian_children
      WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('gd','gd2')) $q$);

CALL hbh_test.chk('fixture', 'the INVOICE number series is defined',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.number_series WHERE code = 'INVOICE') $q$);

-- =====================================================================
-- 1. SELLING AND SPENDING A PACKAGE
-- =====================================================================
SET hbh.user_id = 'p6.reception';
CALL hbh_test.chk_raises('package', 'reception cannot sell a package - no BILLING.MANAGE',
  $q$ SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='child_a'),
                              (SELECT v FROM hbh_test.fx WHERE k='pkg')) $q$, 'HB052');

SET hbh.user_id = 'admin';
CALL hbh_test.chk('package', 'an administrator sells it',
  $q$ WITH s AS (SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='child_a'),
                                         (SELECT v FROM hbh_test.fx WHERE k='pkg')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'cpkg', id FROM s RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('package', 'the balance starts at three of three',
  $q$ SELECT sessions_total = 3 AND sessions_used = 0 AND status = 'ACTIVE'
      FROM hbh.child_packages WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$);

CALL hbh_test.chk('package', 'and the purchase is the first ledger entry',
  $q$ SELECT delta = 3 AND balance_after = 3 AND reason = 'PURCHASE'
      FROM hbh.package_ledger WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$);

CALL hbh_test.chk('package', 'spending one leaves two',
  $q$ SELECT hbh.consume_package_session((SELECT v FROM hbh_test.fx WHERE k='cpkg')) = 2 $q$);

CALL hbh_test.chk('package', 'spending a second leaves one',
  $q$ SELECT hbh.consume_package_session((SELECT v FROM hbh_test.fx WHERE k='cpkg')) = 1 $q$);

CALL hbh_test.chk('package', 'spending the third leaves none',
  $q$ SELECT hbh.consume_package_session((SELECT v FROM hbh_test.fx WHERE k='cpkg')) = 0 $q$);

CALL hbh_test.chk('package', 'and the package is now EXHAUSTED',
  $q$ SELECT status = 'EXHAUSTED' AND sessions_used = 3 FROM hbh.child_packages
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$);

-- The rule the whole table exists for.
CALL hbh_test.chk_raises('package', 'a fourth session is refused - HB051',
  $q$ SELECT hbh.consume_package_session((SELECT v FROM hbh_test.fx WHERE k='cpkg')) $q$, 'HB051');

CALL hbh_test.chk('package', 'the ledger explains every one of the three',
  $q$ SELECT count(*) = 3 FROM hbh.package_ledger
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') AND reason = 'SESSION' $q$);

CALL hbh_test.chk('package', 'and its running balance descends 2, 1, 0',
  $q$ SELECT array_agg(balance_after ORDER BY ledger_id) = ARRAY[2,1,0]::smallint[]
      FROM hbh.package_ledger
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') AND reason = 'SESSION' $q$);

CALL hbh_test.chk_raises('package', 'the ledger cannot be rewritten',
  $q$ UPDATE hbh.package_ledger SET balance_after = 9
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$, 'HB001');

-- Belt and braces: even a direct UPDATE cannot take the balance under.
CALL hbh_test.chk_raises('package', 'a direct UPDATE cannot overdraw the balance',
  $q$ UPDATE hbh.child_packages SET sessions_used = 4
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg') $q$, '23514');

-- An expired package is refused for expiry, not for an empty balance.
CALL hbh_test.chk('package', 'a second package is sold and then back-dated past its expiry',
  $q$ WITH s AS (SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='child_a'),
                                         (SELECT v FROM hbh_test.fx WHERE k='pkg')) AS id),
           i AS (INSERT INTO hbh_test.fx (k, v) SELECT 'cpkg2', id FROM s RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('package', 'its expiry is moved into the past',
  $q$ WITH u AS (UPDATE hbh.child_packages
                    SET purchased_on = current_date - 200, expires_on = current_date - 1
                  WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg2') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk_raises('package', 'and it is then refused with HB051',
  $q$ SELECT hbh.consume_package_session((SELECT v FROM hbh_test.fx WHERE k='cpkg2')) $q$, 'HB051');

-- And it did NOT change the status on its way out.
--
-- It used to try. An UPDATE followed by a RAISE in the same function
-- loses the UPDATE, because the exception unwinds the transaction and
-- takes the status change with it - the same shape as the attempt
-- counter in verify_otp. A function either changes state or refuses,
-- never both.
CALL hbh_test.chk('package', 'the refusal changed no state - it only raised',
  $q$ SELECT status = 'ACTIVE' FROM hbh.child_packages
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg2') $q$);

CALL hbh_test.chk('package', 'expire_packages is the call that changes it, and raises nothing',
  $q$ SELECT hbh.expire_packages() >= 1 $q$);

CALL hbh_test.chk('package', 'and NOW it is EXPIRED',
  $q$ SELECT status = 'EXPIRED' FROM hbh.child_packages
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg2') $q$);

-- A family asking what happened to their three remaining sessions gets
-- a row that says so.
CALL hbh_test.chk('package', 'the forfeited three sessions are named in the ledger',
  $q$ SELECT delta = -3 AND balance_after = 0 FROM hbh.package_ledger
      WHERE child_package_id = (SELECT v FROM hbh_test.fx WHERE k='cpkg2')
        AND reason = 'EXPIRY' $q$);

CALL hbh_test.chk('package', 'and calling it again changes nothing',
  $q$ SELECT hbh.expire_packages() = 0 $q$);

-- =====================================================================
-- 2. A TOTAL IS DERIVED, NEVER ENTERED
-- =====================================================================
INSERT INTO hbh_test.fx (k, v)
SELECT 'inv', invoice_id FROM (
  SELECT 1) z, LATERAL (
  SELECT invoice_id FROM hbh.invoices WHERE false) y
WHERE false;

WITH i AS (
  INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id,
                            currency_code, tax_rate, due_date)
  SELECT c.center_id, (SELECT v FROM hbh_test.fx WHERE k='branch'),
         hbh.next_number(c.center_id, 'INVOICE'),
         (SELECT v FROM hbh_test.fx WHERE k='child_a'),
         (SELECT v FROM hbh_test.fx WHERE k='gd'),
         c.currency_code,
         hbh.param(c.center_id, 'DEFAULT_TAX_RATE', '0')::numeric,
         current_date + 14
  FROM hbh.centers c WHERE c.code = 'HBH'
  RETURNING invoice_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'inv', invoice_id FROM i;

CALL hbh_test.chk('invoice', 'a new invoice is a DRAFT worth nothing',
  $q$ SELECT status = 'DRAFT' AND subtotal_amt = 0 AND total_amt = 0 AND paid_amt = 0
      FROM hbh.invoices WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

CALL hbh_test.chk('invoice', 'it carries the centre currency, not a hardcoded one',
  $q$ SELECT i.currency_code = c.currency_code FROM hbh.invoices i, hbh.centers c
      WHERE i.invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') AND c.code = 'HBH' $q$);

CALL hbh_test.chk('invoice', 'two lines are added',
  $q$ WITH l AS (INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar,
                                                service_id, qty, unit_amt, line_amt)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='inv'), 'باقة تخاطب — ٣ جلسات',
                         (SELECT v FROM hbh_test.fx WHERE k='svc'), 1, 1500.00, 1500.00),
                        ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='inv'), 'جلسة تقييم',
                         (SELECT v FROM hbh_test.fx WHERE k='svc'), 2, 125.00, 250.00)
                 RETURNING 1)
      SELECT count(*) = 2 FROM l $q$);

-- 1500 + 250, computed by the trigger and by nobody else.
CALL hbh_test.chk('invoice', 'the subtotal followed the lines by itself',
  $q$ SELECT subtotal_amt = 1750.00 AND total_amt = 1750.00 FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

CALL hbh_test.chk_raises('invoice', 'a line whose amount does not follow from qty by unit is refused',
  $q$ INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, qty, unit_amt, line_amt)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 'سطر ملفّق', 2, 100.00, 999.00) $q$,
  '23514');

-- Typing over the total is pointless: the next recalculation restores
-- it from the lines.
-- Two statements. Updating a row and then calling a function that
-- updates the same row inside ONE statement raises 27000, "tuple to be
-- updated was already modified by an operation triggered by the current
-- command" - a real limit, not a fault in the rule under test.
CALL hbh_test.chk('invoice', 'somebody types over the total by hand',
  $q$ WITH u AS (UPDATE hbh.invoices SET subtotal_amt = 5, tax_amt = 0, total_amt = 5
                  WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('invoice', 'a recalculation puts it back',
  $q$ WITH r AS (SELECT hbh.recalc_invoice((SELECT v FROM hbh_test.fx WHERE k='inv')))
      SELECT count(*) = 1 FROM r $q$);

CALL hbh_test.chk('invoice', 'and it is 1750 again',
  $q$ SELECT total_amt = 1750.00 FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

-- =====================================================================
-- 3. PAYING
-- =====================================================================
SET hbh.user_id = 'admin';

CALL hbh_test.chk_raises('pay', 'a draft invoice cannot take a payment - HB052',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 100) $q$, 'HB052');

CALL hbh_test.chk('pay', 'the invoice is issued',
  $q$ WITH i AS (SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv')))
      SELECT count(*) = 1 FROM i $q$);

CALL hbh_test.chk('pay', 'and is now ISSUED',
  $q$ SELECT status = 'ISSUED' FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

CALL hbh_test.chk_raises('pay', 'a payment larger than the total is refused - HB053',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 2000) $q$, 'HB053');

CALL hbh_test.chk('pay', 'a part payment of 750 is taken',
  $q$ WITH p AS (INSERT INTO hbh.payments (center_id, invoice_id, amount, method_code)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='inv'), 750.00, 'CASH') RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('pay', 'the invoice became PARTIALLY_PAID with 750 against it',
  $q$ SELECT status = 'PARTIALLY_PAID' AND paid_amt = 750.00 FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

CALL hbh_test.chk_raises('pay', 'a second payment over the remaining 1000 is refused',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 1000.01) $q$, 'HB053');

CALL hbh_test.chk('pay', 'settling the remaining 1000 is accepted',
  $q$ WITH p AS (INSERT INTO hbh.payments (center_id, invoice_id, amount, method_code)
                 VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
                         (SELECT v FROM hbh_test.fx WHERE k='inv'), 1000.00, 'TRANSFER') RETURNING 1)
      SELECT count(*) = 1 FROM p $q$);

CALL hbh_test.chk('pay', 'and the invoice is PAID in full',
  $q$ SELECT status = 'PAID' AND paid_amt = total_amt FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

-- =====================================================================
-- 4. A SETTLED INVOICE IS FINISHED
-- =====================================================================
CALL hbh_test.chk_raises('settled', 'a line cannot be added to a paid invoice - HB052',
  $q$ INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, qty, unit_amt, line_amt)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 'سطر متأخر', 1, 50.00, 50.00) $q$, 'HB052');

CALL hbh_test.chk_raises('settled', 'an existing line cannot be changed either',
  $q$ UPDATE hbh.invoice_lines SET unit_amt = 1, line_amt = 1
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$, 'HB052');

CALL hbh_test.chk_raises('settled', 'and the amounts on the header cannot be edited',
  $q$ UPDATE hbh.invoices SET subtotal_amt = 1, tax_amt = 0, total_amt = 1
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$, 'HB052');

CALL hbh_test.chk_raises('settled', 'a paid invoice cannot be cancelled - HB050',
  $q$ UPDATE hbh.invoices SET status = 'CANCELLED'
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$, 'HB050');

CALL hbh_test.chk_raises('settled', 'and a paid invoice takes no further payment',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv'), 1) $q$, 'HB053');

-- =====================================================================
-- 5. WHAT THE FAMILY SEES
-- =====================================================================
-- A second invoice, left as a draft, must stay invisible to them.
WITH i AS (
  INSERT INTO hbh.invoices (center_id, branch_id, invoice_no, child_id, guardian_id, currency_code)
  SELECT c.center_id, (SELECT v FROM hbh_test.fx WHERE k='branch'),
         hbh.next_number(c.center_id, 'INVOICE'),
         (SELECT v FROM hbh_test.fx WHERE k='child_a'),
         (SELECT v FROM hbh_test.fx WHERE k='gd'), c.currency_code
  FROM hbh.centers c WHERE c.code = 'HBH'
  RETURNING invoice_id)
INSERT INTO hbh_test.fx (k, v) SELECT 'inv_draft', invoice_id FROM i;

SET ROLE hbh_app;
SET hbh.user_id = 'p6.guardian';

CALL hbh_test.chk('visible', 'the guardian sees the issued invoice and not the draft',
  $q$ SELECT count(*) = 1 FROM hbh.invoices $q$);

CALL hbh_test.chk('visible', 'and the one they see is the paid one',
  $q$ SELECT (SELECT invoice_id FROM hbh.invoices) = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

CALL hbh_test.chk('visible', 'they see its lines',
  $q$ SELECT count(*) = 2 FROM hbh.invoice_lines $q$);

CALL hbh_test.chk('visible', 'and both payments',
  $q$ SELECT count(*) = 2 FROM hbh.payments $q$);

CALL hbh_test.chk('visible', 'their package balance is visible with its ledger',
  $q$ SELECT count(*) = 2 FROM hbh.child_packages $q$);

CALL hbh_test.chk('visible', 'the balance view says nothing is outstanding',
  $q$ SELECT outstanding_amt = 0 AND paid_amt = 1750.00 FROM hbh.v_child_balance
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

SET hbh.user_id = 'p6.other_gd';
CALL hbh_test.chk('visible', 'the other family sees none of it',
  $q$ SELECT count(*) = 0 FROM hbh.invoices $q$);

CALL hbh_test.chk('visible', 'not the packages either',
  $q$ SELECT count(*) = 0 FROM hbh.child_packages $q$);

CALL hbh_test.chk('visible', 'and cannot fetch the invoice BY ID',
  $q$ SELECT count(*) = 0 FROM hbh.invoices
      WHERE invoice_id = (SELECT v FROM hbh_test.fx WHERE k='inv') $q$);

SET hbh.user_id = 'p6.reception';
CALL hbh_test.chk('visible', 'reception with BILLING.VIEW sees the draft too',
  $q$ SELECT count(*) = 2 FROM hbh.invoices
      WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

-- Two refusals in a row, and the ORDER of them is the point.
--
-- A BEFORE trigger runs before the row level security WITH CHECK, so a
-- business rule answers first and can mask a permission refusal
-- entirely. Paying a DRAFT invoice is refused by trg_payment_guard
-- (HB052) whoever asks - reception never reaches the policy at all.
CALL hbh_test.chk_raises('visible', 'a draft invoice refuses a payment before permissions are even asked',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv_draft'), 1) $q$, 'HB052');

RESET ROLE;
-- So the policy needs an invoice the business rule is happy with: one
-- that is ISSUED and still owed. Only then does the refusal come from
-- the permission, which is what this suite means to prove.
INSERT INTO hbh.invoice_lines (center_id, invoice_id, description_ar, qty, unit_amt, line_amt)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
        (SELECT v FROM hbh_test.fx WHERE k='inv_draft'), 'جلسة إضافية', 1, 300.00, 300.00);

SET hbh.user_id = 'admin';
SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='inv_draft'));
RESET hbh.user_id;

SET ROLE hbh_app;
SET hbh.user_id = 'p6.reception';

CALL hbh_test.chk_raises('visible', 'and on an ISSUED invoice reception is refused for the real reason',
  $q$ INSERT INTO hbh.payments (center_id, invoice_id, amount)
      VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'),
              (SELECT v FROM hbh_test.fx WHERE k='inv_draft'), 1) $q$, '42501');

RESET hbh.user_id;
CALL hbh_test.chk('visible', 'no identity sees no money at all',
  $q$ SELECT (SELECT count(*) FROM hbh.invoices) = 0
         AND (SELECT count(*) FROM hbh.payments) = 0
         AND (SELECT count(*) FROM hbh.child_packages) = 0 $q$);

RESET ROLE;

CALL hbh_test.chk('visible', 'the balance view is declared security_invoker',
  $q$ SELECT 'security_invoker=true' = ANY (c.reloptions) FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relname = 'v_child_balance' $q$);

-- =====================================================================
-- CLEANUP
-- =====================================================================
CALL hbh_test.chk('cleanup', 'notifications removed',
  $q$ WITH d AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p6.%') RETURNING 1)
      SELECT count(*) >= 0 FROM d $q$);

-- 0142: issuing an invoice now writes its payment schedule, and the
-- schedule's history is append-only. Both go before the invoices do -
-- the history first, then the instalments, each its own statement -
-- and the guard comes straight back on, checked by name below.
ALTER TABLE hbh.invoice_installment_status_history DISABLE TRIGGER trg_iish_append_only;
CALL hbh_test.chk('cleanup', 'the payment schedule history of this suite''s invoices removed',
  $q$ WITH h AS (DELETE FROM hbh.invoice_installment_status_history WHERE installment_id IN
                   (SELECT x.installment_id FROM hbh.invoice_installments x
                    JOIN hbh.invoices i ON i.invoice_id = x.invoice_id
                    WHERE i.child_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')))
                 RETURNING 1)
      SELECT count(*) >= 1 FROM h $q$);
ALTER TABLE hbh.invoice_installment_status_history ENABLE TRIGGER trg_iish_append_only;

CALL hbh_test.chk('cleanup', 'and the schedules themselves',
  $q$ WITH x AS (DELETE FROM hbh.invoice_installments WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1)
      SELECT count(*) >= 1 FROM x $q$);

CALL hbh_test.chk('cleanup', 'the schedule history append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger WHERE tgname = 'trg_iish_append_only' $q$);

CALL hbh_test.chk('cleanup', 'payments, lines and invoices removed',
  $q$ WITH p AS (DELETE FROM hbh.payments WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           l AS (DELETE FROM hbh.invoice_lines WHERE invoice_id IN
                   (SELECT invoice_id FROM hbh.invoices WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           i AS (DELETE FROM hbh.invoices WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 2 $q$);

ALTER TABLE hbh.package_ledger DISABLE TRIGGER trg_led_append_only;
CALL hbh_test.chk('cleanup', 'the ledger and package balances removed',
  $q$ WITH l AS (DELETE FROM hbh.package_ledger WHERE child_package_id IN
                   (SELECT child_package_id FROM hbh.child_packages WHERE child_id IN
                      (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b'))) RETURNING 1),
           c AS (DELETE FROM hbh.child_packages WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 2 AND (SELECT count(*) FROM l) = 6 $q$);
ALTER TABLE hbh.package_ledger ENABLE TRIGGER trg_led_append_only;

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH g AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE child_no LIKE 'P6-%' RETURNING 1),
           q AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2016000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p6.%') RETURNING 1),
           sp AS (DELETE FROM hbh.service_packages WHERE code LIKE 'P6-%' RETURNING 1),
           sv AS (DELETE FROM hbh.services WHERE code LIKE 'P6-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p6.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p6.%' RETURNING 1)
      SELECT (SELECT count(*) FROM k) = 2 AND (SELECT count(*) FROM u) = 3 $q$);

CALL hbh_test.chk('cleanup', 'the ledger append-only trigger is enabled again',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger WHERE tgname = 'trg_led_append_only' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 6 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 6 NOT ACCEPTED'; END IF;
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
