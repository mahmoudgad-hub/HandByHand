-- =====================================================================
-- Hand By Hand (new) - PHASE 14 acceptance suite: the tenant boundary
--
-- Must print:  PHASE 14 ACCEPTED
--
-- Three claims, and the third is the one that makes the first two worth
-- anything:
--
--   1. NO STAFF ACCOUNT CAN WRITE INTO ANOTHER CENTRE. Eight functions
--      took a raw identifier and asked only "may you do this kind of
--      thing", never "is this row yours". Two were proven first
--      (0099), six more after (0101) - including set_password, which is
--      account takeover, and grant_consent, which decides who may watch
--      a child during a therapy session.
--   2. AND NOTHING IS LEFT BEHIND WHEN THEY TRY. Authorization runs
--      before the first write, so a refused attempt creates no child, no
--      guardian, no package, no consent event, no notification - and
--      burns no number out of another centre's series.
--   3. AND THE SAME-CENTRE PATH STILL WORKS. A guard proved only by its
--      refusals is a guard with no key. This project shipped one of
--      those - a photograph consent asking for a type the schema never
--      had, refusing every upload for a fortnight while its first
--      assertion stayed green.
--
-- WHY THE REFUSALS ARE ASSERTED BY SQLSTATE. An earlier proof harness
-- inferred "denied" from the absence of a success row and reported six
-- open functions as all closed - because convert_enrolment was being
-- turned away by a business rule about application status and that
-- looked identical to the security refusal. Every negative check here
-- names HB232.
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

-- THE ONE THAT MATTERS HERE: a refusal is asserted BY ITS CODE.
CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', THE CALL SUCCEEDED');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || left(SQLERRM, 60));
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE: a complete SECOND CENTRE, and one row of our own to compare
--
-- The second centre needs its own NUMBER SERIES. Without it
-- convert_enrolment fails with HB010 before it reaches anything worth
-- testing - which is exactly how the first proof run mistook a missing
-- sequence for a working security guard.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.centers (code, name_ar) VALUES ('P14C', 'مركز اختبار ١٤');
INSERT INTO hbh_test.fx (k, v) SELECT 'fcenter', center_id FROM hbh.centers WHERE code = 'P14C';
INSERT INTO hbh.branches (center_id, code, name_ar)
 VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), 'P14B', 'فرع اختبار ١٤');
INSERT INTO hbh_test.fx (k, v) SELECT 'fbranch', branch_id FROM hbh.branches WHERE code = 'P14B';

INSERT INTO hbh.number_series (center_id, code, prefix, next_value)
SELECT (SELECT v FROM hbh_test.fx WHERE k='fcenter'), s.code, s.px, 1
FROM (VALUES ('CHILD','P14C-'),('APPT','P14A-'),('REQUEST','P14R-')) AS s(code, px);

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
       u.un, u.nm, u.ut, u.mb
FROM (VALUES ('p14.fparent','ولي أمر المركز الآخر','GUARDIAN','+201944000001'),
             ('p14.fstaff', 'موظّف المركز الآخر',  'STAFF',   '+201944000002')) AS u(un,nm,ut,mb);
INSERT INTO hbh_test.fx (k, v) SELECT 'fuser_parent', user_id FROM hbh.users WHERE username='p14.fparent';
INSERT INTO hbh_test.fx (k, v) SELECT 'fuser_staff',  user_id FROM hbh.users WHERE username='p14.fstaff';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM hbh.users u WHERE u.username = 'p14.fparent';
INSERT INTO hbh_test.fx (k, v) SELECT 'fguardian', guardian_id FROM hbh.guardians WHERE mobile='+201944000001';

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        'P14F-1', 'طفل المركز الآخر', DATE '2020-04-04', 'M');
INSERT INTO hbh_test.fx (k, v) SELECT 'fchild', child_id FROM hbh.children WHERE child_no='P14F-1';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fguardian'),
        (SELECT v FROM hbh_test.fx WHERE k='fchild'), 'FATHER', true);

INSERT INTO hbh.enrolment_applications
  (center_id, branch_id, application_no, parent_name_ar, parent_mobile,
   child_name_ar, child_birth_date, child_gender, relationship_code, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        'P14-APP-1', 'أب المركز الآخر', '+201944000003',
        'طفل جديد', DATE '2021-05-05', 'F', 'FATHER', 'CONTACTED');
INSERT INTO hbh_test.fx (k, v) SELECT 'fapp', application_id FROM hbh.enrolment_applications
  WHERE application_no='P14-APP-1';

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        'P14-SVC', 'خدمة المركز الآخر', 'SPEECH');
INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        'P14-RM', 'غرفة المركز الآخر');
INSERT INTO hbh.therapists (center_id, branch_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        'أخصائي المركز الآخر');

INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id, therapist_id,
                              room_id, service_id, starts_at, ends_at, status)
SELECT c.center_id, b.branch_id, 'P14-APT-1', ch.child_id, t.therapist_id, r.room_id, s.service_id,
       now() - interval '3 hours', now() - interval '2 hours', 'BOOKED'
FROM hbh.centers c JOIN hbh.branches b ON b.center_id=c.center_id
JOIN hbh.children ch ON ch.center_id=c.center_id
JOIN hbh.therapists t ON t.center_id=c.center_id
JOIN hbh.rooms r ON r.center_id=c.center_id
JOIN hbh.services s ON s.center_id=c.center_id
WHERE c.code='P14C';

INSERT INTO hbh.therapy_sessions (center_id, branch_id, appointment_id, child_id, therapist_id,
                                  room_id, service_id, started_at, ended_at, status)
SELECT a.center_id, a.branch_id, a.appointment_id, a.child_id, a.therapist_id, a.room_id,
       a.service_id, now() - interval '3 hours', now() - interval '2 hours', 'COMPLETED'
FROM hbh.appointments a WHERE a.appointment_no='P14-APT-1';

INSERT INTO hbh.session_notes (center_id, session_id, child_id, author_user_id,
                               body_ar, visibility, is_draft_flg)
SELECT s.center_id, s.session_id, s.child_id,
       (SELECT v FROM hbh_test.fx WHERE k='fuser_staff'),
       'ملاحظة سريرية للمركز الآخر', 'STAFF', true
FROM hbh.therapy_sessions s
JOIN hbh.appointments a ON a.appointment_id = s.appointment_id
WHERE a.appointment_no='P14-APT-1';
INSERT INTO hbh_test.fx (k, v) SELECT 'fnote', note_id FROM hbh.session_notes
  WHERE body_ar='ملاحظة سريرية للمركز الآخر';

-- An invoice in the other centre, so the 0099 check has something to aim at.
INSERT INTO hbh.invoices (center_id, branch_id, child_id, invoice_no, issue_date, due_date,
                          status, currency_code, total_amt)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='fcenter'), (SELECT v FROM hbh_test.fx WHERE k='fbranch'),
        (SELECT v FROM hbh_test.fx WHERE k='fchild'), 'P14-INV-1', current_date, current_date+7,
        'DRAFT', 'EGP', 0);
INSERT INTO hbh_test.fx (k, v) SELECT 'finvoice', invoice_id FROM hbh.invoices WHERE invoice_no='P14-INV-1';

-- THE FIXTURE ITSELF NOTIFIES. trg_appt_notify_booked fires on the BOOKED
-- appointment above, so the other centre already has notifications before
-- a single attack runs. The check below counts the CHANGE, not the total -
-- an absolute count here would fail on the suite's own setup and read as
-- a security breach.
INSERT INTO hbh_test.fx (k, v) SELECT 'ntf_baseline', count(*)::integer FROM hbh.notifications
  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');

INSERT INTO hbh_test.fx (k, v) SELECT 'mypkg', package_id FROM hbh.service_packages
  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND active_flg
  ORDER BY package_id LIMIT 1;
INSERT INTO hbh_test.fx (k, v) SELECT 'mychild', child_id FROM hbh.children
  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND active_flg
  ORDER BY child_id LIMIT 1;

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migrations 0099 and 0101 are recorded',
  $q$ SELECT count(*) = 2 FROM hbh.schema_migrations WHERE version IN ('0099','0101') $q$);
CALL hbh_test.chk('fixture', 'the centre guard exists',
  $q$ SELECT to_regprocedure('hbh.assert_same_center(text,bigint,integer)') IS NOT NULL $q$);
CALL hbh_test.chk('fixture', 'the second centre is a DIFFERENT centre',
  $q$ SELECT (SELECT v FROM hbh_test.fx WHERE k='fcenter')
          <> (SELECT v FROM hbh_test.fx WHERE k='center') $q$);
CALL hbh_test.chk('fixture', 'it has its own number series, so nothing fails for the wrong reason',
  $q$ SELECT count(*) = 3 FROM hbh.number_series
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);
CALL hbh_test.chk('fixture', 'and its application is in a convertible state',
  $q$ SELECT status = 'CONTACTED' FROM hbh.enrolment_applications
      WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='fapp') $q$);

-- =====================================================================
-- 1. THE REFUSALS - every one by HB232, from a real staff account
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'dev_admin';
CALL hbh_test.chk_raises('cross', 'issue_invoice refuses another centre (0099 holds)',
  $q$ SELECT hbh.issue_invoice((SELECT v FROM hbh_test.fx WHERE k='finvoice')) $q$, 'HB232');

CALL hbh_test.chk_raises('cross', 'sell_package refuses another centre child',
  $q$ SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='fchild'),
                              (SELECT v FROM hbh_test.fx WHERE k='mypkg')) $q$, 'HB232');

CALL hbh_test.chk_raises('cross', 'set_password refuses another centre account',
  $q$ SELECT hbh.set_password((SELECT v FROM hbh_test.fx WHERE k='fuser_staff'),
                              'a-password-only-the-attacker-knows') $q$, 'HB232');

SET hbh.user_id = 'dev_reception';
CALL hbh_test.chk_raises('cross', 'convert_enrolment refuses another centre application',
  $q$ SELECT * FROM hbh.convert_enrolment((SELECT v FROM hbh_test.fx WHERE k='fapp'), NULL) $q$,
  'HB232');

CALL hbh_test.chk_raises('cross', 'grant_consent refuses another centre guardian',
  $q$ SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='fguardian'),
                               'LIVE_VIEW',
                               (SELECT v FROM hbh_test.fx WHERE k='fchild')) $q$, 'HB232');

CALL hbh_test.chk_raises('cross', 'withdraw_consent refuses another centre guardian',
  $q$ SELECT hbh.withdraw_consent((SELECT v FROM hbh_test.fx WHERE k='fguardian'),
                                  'SMS_NOTIFY') $q$, 'HB232');

SET hbh.user_id = 'dev_therapist';
CALL hbh_test.chk_raises('cross', 'publish_session_note refuses another centre note',
  $q$ SELECT hbh.publish_session_note((SELECT v FROM hbh_test.fx WHERE k='fnote')) $q$, 'HB232');

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 2. AND NOTHING WAS LEFT BEHIND
--
-- Authorization before mutation. If any of these functions wrote first
-- and raised afterwards, the raise would unwind it - but the shape is
-- what is being asserted, not the rescue.
-- =====================================================================
CALL hbh_test.chk('nowrite', 'no child was created in the other centre',
  $q$ SELECT count(*) = 1 FROM hbh.children
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);

CALL hbh_test.chk('nowrite', 'no guardian was created there',
  $q$ SELECT count(*) = 1 FROM hbh.guardians
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);

CALL hbh_test.chk('nowrite', 'the application is untouched',
  $q$ SELECT status = 'CONTACTED' AND converted_child_id IS NULL AND decided_by IS NULL
      FROM hbh.enrolment_applications
      WHERE application_id = (SELECT v FROM hbh_test.fx WHERE k='fapp') $q$);

-- THE SEQUENCE WAS NOT BURNED. convert_enrolment allocates a child
-- number before it inserts; a guard placed below that line would refuse
-- the write and still leave a permanent gap in another centre's series.
CALL hbh_test.chk('nowrite', 'and no number was taken out of their CHILD series',
  $q$ SELECT next_value = 1 FROM hbh.number_series
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') AND code = 'CHILD' $q$);

CALL hbh_test.chk('nowrite', 'no package was sold there',
  $q$ SELECT count(*) = 0 FROM hbh.child_packages
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);

CALL hbh_test.chk('nowrite', 'and no package ledger entry either',
  $q$ SELECT count(*) = 0 FROM hbh.package_ledger
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);

CALL hbh_test.chk('nowrite', 'no consent was recorded for their guardian',
  $q$ SELECT count(*) = 0 FROM hbh.consents
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='fguardian') $q$);

CALL hbh_test.chk('nowrite', 'and no consent EVENT - the append-only record is clean',
  $q$ SELECT count(*) = 0 FROM hbh.consent_events
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='fguardian') $q$);

CALL hbh_test.chk('nowrite', 'their clinical note is still staff-only',
  $q$ SELECT visibility = 'INTERNAL' AND is_draft_flg AND approved_by IS NULL
      FROM hbh.session_notes WHERE note_id = (SELECT v FROM hbh_test.fx WHERE k='fnote') $q$);

CALL hbh_test.chk('nowrite', 'their staff password was not set',
  $q$ SELECT password_hash IS NULL FROM hbh.users
      WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k='fuser_staff') $q$);

CALL hbh_test.chk('nowrite', 'and NO notification reached the other centre family',
  $q$ SELECT count(*) = (SELECT v FROM hbh_test.fx WHERE k='ntf_baseline') FROM hbh.notifications
      WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter') $q$);

-- =====================================================================
-- 3. THE SAME-CENTRE PATH STILL WORKS
--
-- Without this group the whole suite proves only that a door is shut.
-- =====================================================================
SET ROLE hbh_app;
SET hbh.user_id = 'dev_admin';

CALL hbh_test.chk('same', 'selling a package to OUR OWN child succeeds',
  $q$ SELECT hbh.sell_package((SELECT v FROM hbh_test.fx WHERE k='mychild'),
                              (SELECT v FROM hbh_test.fx WHERE k='mypkg')) > 0 $q$);

SET hbh.user_id = 'dev_reception';
CALL hbh_test.chk('same', 'granting consent to OUR OWN guardian succeeds',
  $q$ SELECT hbh.grant_consent(
        (SELECT g.guardian_id FROM hbh.guardians g
          WHERE g.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
            AND g.active_flg ORDER BY g.guardian_id LIMIT 1),
        'SMS_NOTIFY') > 0 $q$);

RESET hbh.user_id;
RESET ROLE;

-- =====================================================================
-- 4. C1 AND C2 STILL HOLD
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'dev_parent';
CALL hbh_test.chk_raises('c1', 'a guardian still cannot start a session',
  $q$ SELECT hbh.start_session((SELECT appointment_id FROM hbh.appointments
      WHERE active_flg ORDER BY appointment_id DESC LIMIT 1)) $q$, 'HB028');

CALL hbh_test.chk('c2', 'a guardian still sees no DRAFT report',
  $q$ SELECT count(*) = 0 FROM hbh.progress_reports WHERE status = 'DRAFT' $q$);

SET hbh.user_id = 'dev_therapist';
CALL hbh_test.chk('c2', 'a therapist still authors reports',
  $q$ SELECT hbh.has_permission('REPORT.WRITE') $q$);

RESET hbh.user_id;
RESET ROLE;

CALL hbh_test.chk('guard', 'every SECURITY DEFINER mutator now asks about the row',
  $q$ WITH f AS (
        SELECT p.proname, pg_get_functiondef(p.oid) AS def,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='hbh' AND p.prosecdef AND p.prokind='f'
          AND p.prorettype <> 'trigger'::regtype)
      SELECT count(*) = 0 FROM f
      WHERE def ~* '\m(INSERT|UPDATE|DELETE)\M'
        AND args ~ 'p_[a-z_]*id\s+(integer|bigint)' AND args !~ '^p_center_id'
        AND def ~ 'has_permission'
        AND def !~ 'assert_same_center|can_access_child|can_close_session'
                   '|can_start_session|check_session_edit|current_center_id' $q$);

-- =====================================================================
-- CLEANUP - by identity, and a recorded check like any other
-- =====================================================================
ALTER TABLE hbh.session_status_history DISABLE TRIGGER trg_ssh_append_only;
DELETE FROM hbh.session_status_history h USING hbh.therapy_sessions s
 WHERE s.session_id = h.session_id
   AND s.center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
ALTER TABLE hbh.session_status_history ENABLE TRIGGER trg_ssh_append_only;

ALTER TABLE hbh.consent_events DISABLE TRIGGER trg_cev_append_only;
DELETE FROM hbh.consent_events WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k='fguardian');
DELETE FROM hbh.consents       WHERE guardian_id IN (SELECT v FROM hbh_test.fx WHERE k='fguardian');
ALTER TABLE hbh.consent_events ENABLE TRIGGER trg_cev_append_only;

DELETE FROM hbh.notifications  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.invoices       WHERE invoice_no = 'P14-INV-1';
DELETE FROM hbh.package_ledger  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.child_packages  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.session_notes   WHERE note_id   = (SELECT v FROM hbh_test.fx WHERE k='fnote');
DELETE FROM hbh.therapy_sessions WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
DELETE FROM hbh.appointment_status_history WHERE appointment_id IN
  (SELECT appointment_id FROM hbh.appointments WHERE appointment_no='P14-APT-1');
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
DELETE FROM hbh.appointments   WHERE appointment_no='P14-APT-1';

DELETE FROM hbh.enrolment_applications WHERE application_no='P14-APP-1';
DELETE FROM hbh.guardian_children WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='fchild');
DELETE FROM hbh.guardians  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.children   WHERE child_no  = 'P14F-1';
DELETE FROM hbh.therapists WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.rooms      WHERE code = 'P14-RM';
DELETE FROM hbh.services   WHERE code = 'P14-SVC';
DELETE FROM hbh.number_series WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='fcenter');
DELETE FROM hbh.users      WHERE username LIKE 'p14.%';
DELETE FROM hbh.branches   WHERE code = 'P14B';
DELETE FROM hbh.centers    WHERE code = 'P14C';

-- The same-centre package this suite sold, and only that one.
DELETE FROM hbh.package_ledger pl USING hbh.child_packages cp
 WHERE cp.child_package_id = pl.child_package_id
   AND cp.child_id = (SELECT v FROM hbh_test.fx WHERE k='mychild')
   AND cp.created_at >= (SELECT started FROM hbh_test.run);
DELETE FROM hbh.child_packages
 WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='mychild')
   AND created_at >= (SELECT started FROM hbh_test.run);

CALL hbh_test.chk('cleanup', 'the second centre is gone',
  $q$ SELECT count(*) = 0 FROM hbh.centers WHERE code = 'P14C' $q$);
CALL hbh_test.chk('cleanup', 'its users are gone',
  $q$ SELECT count(*) = 0 FROM hbh.users WHERE username LIKE 'p14.%' $q$);
CALL hbh_test.chk('cleanup', 'every append-only guard is enabled again',
  $q$ SELECT count(*) = 3 FROM pg_trigger
      WHERE tgname IN ('trg_cev_append_only','trg_ash_append_only','trg_ssh_append_only')
        AND tgenabled = 'O' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 14 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 14 NOT ACCEPTED'; END IF;
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
