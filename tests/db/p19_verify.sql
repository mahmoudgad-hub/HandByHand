-- =====================================================================
-- Hand By Hand (new) - PHASE 19 acceptance suite: message templates
--
-- Must print:  PHASE 19 ACCEPTED
--
-- Migration 0153. HELD with it: moves to tests/db/ when 0153 moves to
-- db/migrations/, because db.sh verify runs every tests/db/p*_verify.sql
-- and this one needs the table.
--
-- Five claims:
--
--   1. ONLY SOMEBODY WHO MAY MANAGE TEMPLATES CHANGES ONE, AND ONLY IN
--      THEIR OWN CENTRE. Permission is asked before the row is read, and
--      "no such template" and "another centre's template" are one answer.
--   2. THE TEXT KEEPS THE CONTRACT WITH THE CODE. Exactly {{1}}..{{n}},
--      neither first nor last; an AUTHENTICATION template has no text.
--   3. THE STATE MACHINE HOLDS, EVEN FOR THE OWNER. APPROVED needs a Meta
--      id; an edit sends the row back to DRAFT; the contract fields cannot
--      be rewritten by a direct UPDATE.
--   4. AN EDIT KEEPS THE APPROVED ID. The template Meta approved goes on
--      being sent until the new text is approved - the property that stops
--      a typo fix from silencing a whole kind of message.
--   5. THE HISTORY IS APPEND-ONLY AND COMPLETE, and the lookups the Go
--      transport uses answer for the right centre and the right code.
--
-- EVERY REFUSAL NAMES ITS SQLSTATE, and every refusal on a grant or a
-- policy is run as hbh_app: a refusal check run as the owner proves only
-- that the owner walks through.
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
-- FIXTURE - its own centre, an administrator who holds the permission, a
-- clerk who does not, and two templates made directly (the seed ran before
-- this centre existed, so it gave it none).
-- =====================================================================
INSERT INTO hbh.centers (code, name_ar, time_zone)
VALUES ('P19', 'مركز اختبار المرحلة ١٩', 'Africa/Cairo')
ON CONFLICT (code) DO NOTHING;
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers WHERE code = 'P19';
INSERT INTO hbh_test.fx (k, v) SELECT 'other_center', center_id FROM hbh.centers WHERE code = 'HBH';

INSERT INTO hbh.branches (center_id, code, name_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'P19-MAIN', 'الفرع الرئيسي'
WHERE NOT EXISTS (SELECT 1 FROM hbh.branches WHERE code = 'P19-MAIN');
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'P19-MAIN';

INSERT INTO hbh.roles (center_id, code, name_ar, name_en, is_system_flg)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'CENTER_ADMIN', 'مدير المركز', 'Centre administrator', true
ON CONFLICT (center_id, code) DO NOTHING;
INSERT INTO hbh_test.fx (k, v)
SELECT 'role', role_id FROM hbh.roles
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND code = 'CENTER_ADMIN';

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT (SELECT v FROM hbh_test.fx WHERE k='role'), p.permission_id
FROM hbh.permissions p WHERE p.code = 'MESSAGE_TEMPLATE.EDIT'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'), u.n, u.a, 'STAFF'
FROM (VALUES ('p19.admin', 'p19 مدير'), ('p19.clerk', 'p19 موظف')) u(n, a)
WHERE NOT EXISTS (SELECT 1 FROM hbh.users WHERE username = u.n);
INSERT INTO hbh_test.fx (k, v) SELECT 'admin', user_id FROM hbh.users WHERE username = 'p19.admin';
INSERT INTO hbh_test.fx (k, v) SELECT 'clerk', user_id FROM hbh.users WHERE username = 'p19.clerk';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT (SELECT v FROM hbh_test.fx WHERE k='admin'), (SELECT v FROM hbh_test.fx WHERE k='role')
ON CONFLICT (user_id, role_id) DO NOTHING;

INSERT INTO hbh.message_templates (center_id, template_key, category, var_count, var_labels_ar,
                                   body_ar, button_text_ar, button_url)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'PORTAL_UPDATE', 'UTILITY', 1, ARRAY['عنوان الإشعار'],
       E'مركز الاختبار:\nلديكم تحديث جديد: {{1}}.\nتابعوا البوابة.', 'افتح البوابة', 'https://portal.hbhskills.com/'
WHERE NOT EXISTS (SELECT 1 FROM hbh.message_templates
                   WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND template_key = 'PORTAL_UPDATE');
INSERT INTO hbh.message_templates (center_id, template_key, category, var_count, var_labels_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'OTP_LOGIN', 'AUTHENTICATION', 1, ARRAY['رمز الدخول']
WHERE NOT EXISTS (SELECT 1 FROM hbh.message_templates
                   WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND template_key = 'OTP_LOGIN');
INSERT INTO hbh_test.fx (k, v)
SELECT 'tpl', template_id FROM hbh.message_templates
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND template_key = 'PORTAL_UPDATE';
INSERT INTO hbh_test.fx (k, v)
SELECT 'otp', template_id FROM hbh.message_templates
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') AND template_key = 'OTP_LOGIN';
INSERT INTO hbh_test.fx (k, v)
SELECT 'other_tpl', template_id FROM hbh.message_templates
WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='other_center') AND template_key = 'PORTAL_UPDATE' AND active_flg;

-- =====================================================================
-- THE FIXTURE IS CONFIRMED BY NAME
-- =====================================================================
CALL hbh_test.chk('fixture', 'every piece was made, including a template in another centre',
  $q$ SELECT count(*) = 9 FROM hbh_test.fx
       WHERE k IN ('center','other_center','branch','role','admin','clerk','tpl','otp','other_tpl')
         AND v IS NOT NULL $q$);

-- The two identities must differ in exactly the permission, or the refusal
-- below proves nothing.
SET ROLE hbh_app;
SET hbh.user_id = 'p19.admin';
CALL hbh_test.chk('fixture', 'the administrator holds MESSAGE_TEMPLATE.EDIT in P19',
  $q$ SELECT hbh.has_permission('MESSAGE_TEMPLATE.EDIT')
         AND hbh.current_center_id() = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);
SET hbh.user_id = 'p19.clerk';
CALL hbh_test.chk('fixture', 'the clerk, in the same centre, does not',
  $q$ SELECT NOT hbh.has_permission('MESSAGE_TEMPLATE.EDIT')
         AND hbh.current_center_id() = (SELECT v FROM hbh_test.fx WHERE k='center') $q$);

-- =====================================================================
-- CLAIM 1 - who, and where
-- =====================================================================
CALL hbh_test.chk_raises('who', 'the clerk may not edit - HB300',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'نصّ {{1}} جديد.') $q$, 'HB300');
CALL hbh_test.chk_raises('who', 'nor change a status - HB300',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'), 'SUBMITTED') $q$,
  'HB300');
CALL hbh_test.chk('who', 'and cannot read the templates at all',
  $q$ SELECT count(*) = 0 FROM hbh.message_templates $q$);

SET hbh.user_id = 'p19.admin';
CALL hbh_test.chk_raises('who', 'another centre''s template is "no such template" - HB301',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='other_tpl'),
                                       E'نصّ {{1}} جديد.') $q$, 'HB301');
CALL hbh_test.chk_raises('who', 'and so is an id that does not exist - the same HB301',
  $q$ SELECT hbh.edit_message_template(2147483000, E'نصّ {{1}} جديد.') $q$, 'HB301');
CALL hbh_test.chk('who', 'the administrator reads their own centre''s two templates and nobody else''s',
  $q$ SELECT count(*) = 2
         AND bool_and(center_id = (SELECT v FROM hbh_test.fx WHERE k='center'))
      FROM hbh.message_templates $q$);

-- =====================================================================
-- CLAIM 2 - the contract with the code
-- =====================================================================
CALL hbh_test.chk_raises('text', 'a variable the code does not send is refused - HB302',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'نصّ {{1}} و{{2}} هنا.') $q$, 'HB302');
CALL hbh_test.chk_raises('text', 'a text that ends with the variable is refused - HB302',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'لديكم تحديث: {{1}}') $q$, 'HB302');
CALL hbh_test.chk_raises('text', 'a malformed placeholder is refused - HB302',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'نصّ {{ 1}} هنا.') $q$, 'HB302');
CALL hbh_test.chk_raises('text', 'an AUTHENTICATION template has no text to edit - HB304',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='otp'),
                                       E'رمزك {{1}} هنا.') $q$, 'HB304');

-- AND THE ACCEPTANCE: without it, a contract that refused every text would
-- pass the four checks above.
CALL hbh_test.chk('text', 'a text that keeps the contract is accepted',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'مركز الاختبار:\nتحديث: {{1}}.\nالتفاصيل في البوابة.',
                                       'افتح البوابة', 'https://portal.hbhskills.com/')
             = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$);
CALL hbh_test.chk('text', 'and it is stored, still DRAFT',
  $q$ SELECT body_ar LIKE '%تحديث: {{1}}.%' AND status = 'DRAFT'
      FROM hbh.message_templates WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$);

-- =====================================================================
-- CLAIM 3 - the state machine
-- =====================================================================
CALL hbh_test.chk_raises('state', 'DRAFT cannot jump to APPROVED - HB303',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                             'APPROVED', 'HX00000000000000000000000000000019') $q$, 'HB303');
CALL hbh_test.chk('state', 'DRAFT to SUBMITTED is accepted',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'), 'SUBMITTED')
             IS NOT NULL $q$);
CALL hbh_test.chk_raises('state', 'APPROVED without a Meta id is refused - HB306',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'), 'APPROVED') $q$,
  'HB306');
CALL hbh_test.chk_raises('state', 'nor with something that is not one - HB306',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                             'APPROVED', 'SM00000000000000000000000000000019') $q$, 'HB306');
CALL hbh_test.chk('state', 'SUBMITTED to APPROVED with the id is accepted',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                             'APPROVED', 'HX00000000000000000000000000000019') IS NOT NULL $q$);
CALL hbh_test.chk_raises('state', 'DRAFT is reached by editing, not by a status call - HB303',
  $q$ SELECT hbh.set_message_template_status((SELECT v FROM hbh_test.fx WHERE k='tpl'), 'DRAFT') $q$,
  'HB303');

RESET hbh.user_id;
RESET ROLE;
-- As the OWNER, deliberately: RLS and grants do not stop the owner, and
-- these rules are the ones that must hold anyway.
CALL hbh_test.chk_raises('state', 'even the owner cannot change how many variables the code sends - HB305',
  $q$ UPDATE hbh.message_templates SET var_count = 2, var_labels_ar = ARRAY['a','b']
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$, 'HB305');
CALL hbh_test.chk_raises('state', 'nor move a status off the machine - HB303',
  $q$ UPDATE hbh.message_templates SET status = 'REJECTED'
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$, 'HB303');
CALL hbh_test.chk_raises('state', 'nor change an approved text without it going back to DRAFT - HB303',
  $q$ UPDATE hbh.message_templates SET body_ar = E'نصّ {{1}} آخر.'
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$, 'HB303');

-- =====================================================================
-- CLAIM 4 - an edit keeps the approved id
-- =====================================================================
SET ROLE hbh_app;
RESET hbh.user_id;
CALL hbh_test.chk('keep', 'the approved id is what a REQUEST_DECIDED message is sent under',
  $q$ SELECT hbh.message_template_sid((SELECT v FROM hbh_test.fx WHERE k='center'), 'REQUEST_DECIDED')
             = 'HX00000000000000000000000000000019' $q$);

SET hbh.user_id = 'p19.admin';
CALL hbh_test.chk('keep', 'an approved template can be edited',
  $q$ SELECT hbh.edit_message_template((SELECT v FROM hbh_test.fx WHERE k='tpl'),
                                       E'مركز الاختبار:\nجديد: {{1}}.\nالتفاصيل في البوابة.',
                                       'افتح البوابة', 'https://portal.hbhskills.com/') IS NOT NULL $q$);
CALL hbh_test.chk('keep', 'which puts it back in DRAFT and keeps the id',
  $q$ SELECT status = 'DRAFT' AND content_sid = 'HX00000000000000000000000000000019'
      FROM hbh.message_templates WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$);

RESET hbh.user_id;
CALL hbh_test.chk('keep', 'so the approved template is still the one sent',
  $q$ SELECT hbh.message_template_sid((SELECT v FROM hbh_test.fx WHERE k='center'), 'APPOINTMENT_CANCELLED')
             = 'HX00000000000000000000000000000019' $q$);
CALL hbh_test.chk('keep', 'and a code with no approved template in this centre has none',
  $q$ SELECT hbh.message_template_sid((SELECT v FROM hbh_test.fx WHERE k='center'), 'OTP_LOGIN') IS NULL $q$);

-- =====================================================================
-- CLAIM 5 - the history, and the worker's lookup
-- =====================================================================
RESET ROLE;
CALL hbh_test.chk('history', 'every change was recorded, with the text and id as they became',
  $q$ SELECT array_agg(to_status ORDER BY event_id) = ARRAY['DRAFT','DRAFT','SUBMITTED','APPROVED','DRAFT']
         AND (SELECT content_sid FROM hbh.message_template_events
               WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') AND to_status = 'APPROVED')
             = 'HX00000000000000000000000000000019'
      FROM hbh.message_template_events
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$);
CALL hbh_test.chk_raises('history', 'the history cannot be rewritten - HB001',
  $q$ UPDATE hbh.message_template_events SET note_ar = 'x'
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$, 'HB001');
CALL hbh_test.chk_raises('history', 'nor deleted - HB001',
  $q$ DELETE FROM hbh.message_template_events
      WHERE template_id = (SELECT v FROM hbh_test.fx WHERE k='tpl') $q$, 'HB001');

INSERT INTO hbh.sms_outbox (center_id, purpose, template_code, destination, dedupe_key, body_ar)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), 'NOTIFICATION', 'REQUEST_DECIDED',
       '+201599950001', 'P19-SMS', 'p19'
WHERE NOT EXISTS (SELECT 1 FROM hbh.sms_outbox WHERE dedupe_key = 'P19-SMS');
INSERT INTO hbh_test.fx (k, v) SELECT 'sms', sms_id FROM hbh.sms_outbox WHERE dedupe_key = 'P19-SMS';

SET ROLE hbh_app;
SET hbh.user_id = 'p19.admin';
CALL hbh_test.chk_raises('worker', 'a user session cannot use the worker''s lookup - HB230',
  $q$ SELECT hbh.sms_template_sid((SELECT v FROM hbh_test.fx WHERE k='sms')) $q$, 'HB230');
RESET hbh.user_id;
CALL hbh_test.chk('worker', 'the worker gets the centre''s approved id for a claimed message',
  $q$ SELECT hbh.sms_template_sid((SELECT v FROM hbh_test.fx WHERE k='sms'))
             = 'HX00000000000000000000000000000019' $q$);
RESET ROLE;

-- =====================================================================
-- CLEANUP - by identity, children before parents
-- =====================================================================
CALL hbh_test.chk('cleanup', 'the outbox row is gone',
  $q$ WITH d AS (DELETE FROM hbh.sms_outbox WHERE sms_id = (SELECT v FROM hbh_test.fx WHERE k='sms') RETURNING 1)
      SELECT count(*) = 1 FROM d $q$);

ALTER TABLE hbh.message_template_events DISABLE TRIGGER trg_mte_append_only;
CALL hbh_test.chk('cleanup', 'the template history is gone',
  $q$ WITH d AS (DELETE FROM hbh.message_template_events
                  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);
ALTER TABLE hbh.message_template_events ENABLE TRIGGER trg_mte_append_only;
CALL hbh_test.chk('cleanup', 'and its append-only guard is back on',
  $q$ SELECT tgenabled = 'O' FROM pg_trigger
      WHERE tgrelid = 'hbh.message_template_events'::regclass AND tgname = 'trg_mte_append_only' $q$);

CALL hbh_test.chk('cleanup', 'the templates are gone',
  $q$ WITH d AS (DELETE FROM hbh.message_templates
                  WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);
CALL hbh_test.chk('cleanup', 'the role grant and the role are gone',
  $q$ WITH ur AS (DELETE FROM hbh.user_roles WHERE role_id = (SELECT v FROM hbh_test.fx WHERE k='role') RETURNING 1)
      SELECT count(*) = 1 FROM ur $q$);
CALL hbh_test.chk('cleanup', 'the role permissions are gone',
  $q$ WITH rp AS (DELETE FROM hbh.role_permissions WHERE role_id = (SELECT v FROM hbh_test.fx WHERE k='role') RETURNING 1)
      SELECT count(*) >= 1 FROM rp $q$);
CALL hbh_test.chk('cleanup', 'the role is gone',
  $q$ WITH r AS (DELETE FROM hbh.roles WHERE role_id = (SELECT v FROM hbh_test.fx WHERE k='role') RETURNING 1)
      SELECT count(*) = 1 FROM r $q$);
CALL hbh_test.chk('cleanup', 'the accounts are gone',
  $q$ WITH u AS (DELETE FROM hbh.users WHERE user_id IN (SELECT v FROM hbh_test.fx WHERE k IN ('admin','clerk')) RETURNING 1)
      SELECT count(*) = 2 FROM u $q$);

-- Rows the seeds give every centre if a migrate lands while this runs - the
-- lesson p18 paid for. Deleted by this centre's id; the last check asserts
-- none remain.
ALTER TABLE hbh.payment_plan_installments DISABLE TRIGGER trg_ppi_frozen;
DELETE FROM hbh.payment_plan_installments WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
ALTER TABLE hbh.payment_plan_installments ENABLE TRIGGER trg_ppi_frozen;
DELETE FROM hbh.payment_plans       WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
DELETE FROM hbh.profile_field_rules WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');
DELETE FROM hbh.number_series       WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center');

CALL hbh_test.chk('cleanup', 'the branch and the centre are gone',
  $q$ WITH b AS (DELETE FROM hbh.branches WHERE branch_id = (SELECT v FROM hbh_test.fx WHERE k='branch') RETURNING 1)
      SELECT count(*) = 1 FROM b $q$);
CALL hbh_test.chk('cleanup', 'and the centre itself',
  $q$ WITH c AS (DELETE FROM hbh.centers WHERE center_id = (SELECT v FROM hbh_test.fx WHERE k='center') RETURNING 1)
      SELECT count(*) = 1 FROM c $q$);
CALL hbh_test.chk('cleanup', 'nothing of this suite is left, and both guards it touched are on',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.centers WHERE code = 'P19')
         AND NOT EXISTS (SELECT 1 FROM hbh.users WHERE username IN ('p19.admin','p19.clerk'))
         AND NOT EXISTS (SELECT 1 FROM hbh.sms_outbox WHERE dedupe_key = 'P19-SMS')
         AND (SELECT tgenabled FROM pg_trigger WHERE tgname = 'trg_ppi_frozen') = 'O' $q$);

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
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 19 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 19 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;
