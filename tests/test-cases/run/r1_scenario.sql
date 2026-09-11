-- =====================================================================
-- Role-journey scenario  (R1)
--
-- Two families that must never see each other, two staff accounts with
-- deliberately different permissions, and one running session with a
-- note on it. Everything named r1_ / R1- so it can be found.
--
-- Built as hbh_owner, which bypasses RLS - which is exactly why the
-- journeys below are driven as the app's own roles instead.
-- =====================================================================
\set ON_ERROR_STOP on

DROP TABLE IF EXISTS r1_fx;
CREATE TEMP TABLE r1_fx (k text PRIMARY KEY, v integer);

SELECT set_config('hbh.user_id', 'admin', false);

INSERT INTO r1_fx SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO r1_fx SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- ---- accounts -------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM r1_fx WHERE k='center'), (SELECT v FROM r1_fx WHERE k='branch'),
       v.u, v.n, v.t, v.m
FROM (VALUES
  ('r1_admin', 'مديرة المركز',        'STAFF',     '01700000001'),
  ('r1_recep', 'موظفة الاستقبال',     'STAFF',     '01700000002'),
  ('r1_ther',  'أ. سارة عبد الرحمن',  'THERAPIST', '01700000003'),
  ('r1_pa',    'والد الطفل أحمد',      'GUARDIAN',  '01700000010'),
  ('r1_pb',    'والدة الطفلة ليلى',    'GUARDIAN',  '01700000020')
) AS v(u, n, t, m);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id
WHERE  (u.username = 'r1_admin' AND r.code = 'CENTER_ADMIN')
   OR  (u.username = 'r1_recep' AND r.code = 'RECEPTION')
   OR  (u.username = 'r1_ther'  AND r.code = 'THERAPIST')
   OR  (u.username IN ('r1_pa','r1_pb') AND r.code = 'GUARDIAN');

SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='r1_admin'), 'r1-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='r1_recep'), 'r1-recep-pw-123456');

-- ---- clinical scaffolding ------------------------------------------
INSERT INTO hbh.services (center_id, code, name_ar, kind_code, default_duration_min)
SELECT (SELECT v FROM r1_fx WHERE k='center'), 'R1SVC', 'تخاطب وتنمية لغة', 'SPEECH', 45;
INSERT INTO r1_fx SELECT 'svc', service_id FROM hbh.services WHERE code='R1SVC';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
SELECT (SELECT v FROM r1_fx WHERE k='center'), (SELECT v FROM r1_fx WHERE k='branch'), 'R1ROOM', 'غرفة التخاطب';
INSERT INTO r1_fx SELECT 'room', room_id FROM hbh.rooms WHERE code='R1ROOM';

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
SELECT (SELECT v FROM r1_fx WHERE k='center'), (SELECT v FROM r1_fx WHERE k='branch'),
       user_id, 'أ. سارة عبد الرحمن' FROM hbh.users WHERE username='r1_ther';
INSERT INTO r1_fx SELECT 'ther', therapist_id FROM hbh.therapists
 WHERE user_id = (SELECT user_id FROM hbh.users WHERE username='r1_ther');

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM r1_fx WHERE k='ther'), (SELECT v FROM r1_fx WHERE k='svc'));

-- ---- guardians ------------------------------------------------------
INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username IN ('r1_pa','r1_pb');
INSERT INTO r1_fx SELECT 'g_a', guardian_id FROM hbh.guardians WHERE mobile='01700000010';
INSERT INTO r1_fx SELECT 'g_b', guardian_id FROM hbh.guardians WHERE mobile='01700000020';

-- ---- children -------------------------------------------------------
-- Literal child_no: consuming the real series would move the counter and
-- leave a hole in front of the next child reception registers.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM r1_fx WHERE k='center'), (SELECT v FROM r1_fx WHERE k='branch'), v.no, v.n, v.b::date, v.g
FROM (VALUES ('R1-A','أحمد محمود','2019-06-15','M'),
             ('R1-B','ليلى حسن','2020-02-20','F')) AS v(no, n, b, g);
INSERT INTO r1_fx SELECT 'ch_a', child_id FROM hbh.children WHERE child_no='R1-A';
INSERT INTO r1_fx SELECT 'ch_b', child_id FROM hbh.children WHERE child_no='R1-B';

-- Live viewing now needs a recorded consent before the flag may be set
-- (migration 0015). Record it first, then link with the flag on.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg,
                                   can_view_live_flg, can_view_reports_flg)
VALUES ((SELECT v FROM r1_fx WHERE k='g_a'), (SELECT v FROM r1_fx WHERE k='ch_a'), 'FATHER', true, false, true),
       ((SELECT v FROM r1_fx WHERE k='g_b'), (SELECT v FROM r1_fx WHERE k='ch_b'), 'MOTHER', true, false, true);

SELECT hbh.grant_consent((SELECT v FROM r1_fx WHERE k='g_a'), 'LIVE_VIEW', (SELECT v FROM r1_fx WHERE k='ch_a'));

UPDATE hbh.guardian_children SET can_view_live_flg = true
 WHERE guardian_id = (SELECT v FROM r1_fx WHERE k='g_a')
   AND child_id   = (SELECT v FROM r1_fx WHERE k='ch_a');

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
SELECT (SELECT v FROM r1_fx WHERE k='center'), (SELECT v FROM r1_fx WHERE k='ther'), f.v, (SELECT v FROM r1_fx WHERE k='svc')
FROM   r1_fx f WHERE f.k IN ('ch_a','ch_b');

-- ---- one appointment and one running session for family A -----------
INSERT INTO hbh.appointments (center_id, appointment_no, child_id, therapist_id, room_id, service_id,
                              starts_at, ends_at, status)
VALUES ((SELECT v FROM r1_fx WHERE k='center'), 'R1-APT-A', (SELECT v FROM r1_fx WHERE k='ch_a'),
        (SELECT v FROM r1_fx WHERE k='ther'), (SELECT v FROM r1_fx WHERE k='room'), (SELECT v FROM r1_fx WHERE k='svc'),
        date_trunc('hour', now()), date_trunc('hour', now()) + interval '45 minutes', 'BOOKED');
INSERT INTO r1_fx SELECT 'apt_a', appointment_id FROM hbh.appointments WHERE appointment_no='R1-APT-A';

INSERT INTO hbh.therapy_sessions (center_id, appointment_id, child_id, therapist_id, room_id, service_id)
SELECT (SELECT v FROM r1_fx WHERE k='center'), a.appointment_id, a.child_id, a.therapist_id, a.room_id, a.service_id
FROM   hbh.appointments a WHERE a.appointment_no = 'R1-APT-A';
INSERT INTO r1_fx SELECT 'ses_a', session_id FROM hbh.therapy_sessions
 WHERE appointment_id = (SELECT v FROM r1_fx WHERE k='apt_a');

-- Two notes written by the clinician who ran the session, through the
-- real function - a note inserted straight into the table can never be
-- PARENT-visible, so a direct insert would prove nothing.
SELECT set_config('hbh.user_id', 'r1_ther', false);
SELECT hbh.write_session_note((SELECT v FROM r1_fx WHERE k='ses_a'),
       'ملاحظة داخلية: يحتاج متابعة مع الأسرة قبل تغيير الخطة.');
SELECT hbh.write_session_note((SELECT v FROM r1_fx WHERE k='ses_a'),
       'أحمد نطق ثلاث كلمات جديدة اليوم، والتجاوب ممتاز.');

INSERT INTO r1_fx SELECT 'note_internal', note_id FROM hbh.session_notes
 WHERE body_ar LIKE 'ملاحظة داخلية%';
INSERT INTO r1_fx SELECT 'note_toshare', note_id FROM hbh.session_notes
 WHERE body_ar LIKE 'أحمد نطق%';

SELECT set_config('hbh.user_id', 'admin', false);

-- ---- assert the whole shape by name, before any journey runs --------
DO $$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'r1\_%';
  IF n <> 5 THEN RAISE EXCEPTION 'scenario: expected 5 users, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'R1-%';
  IF n <> 2 THEN RAISE EXCEPTION 'scenario: expected 2 children, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.guardian_children gc
   JOIN hbh.children c ON c.child_id = gc.child_id AND c.child_no LIKE 'R1-%';
  IF n <> 2 THEN RAISE EXCEPTION 'scenario: expected 2 links, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.session_notes
   WHERE session_id = (SELECT v FROM r1_fx WHERE k='ses_a');
  IF n <> 2 THEN RAISE EXCEPTION 'scenario: expected 2 notes, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.session_notes
   WHERE session_id = (SELECT v FROM r1_fx WHERE k='ses_a') AND visibility = 'INTERNAL';
  IF n <> 2 THEN RAISE EXCEPTION 'scenario: both notes must start INTERNAL, found % internal', n; END IF;

  SELECT count(*) INTO n FROM hbh.users u
   WHERE u.username IN ('r1_admin','r1_recep') AND u.password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'scenario: both staff need a password, found %', n; END IF;
END $$;

SELECT 'scenario r1: ready  child_a=' || (SELECT v FROM r1_fx WHERE k='ch_a')
    || '  child_b=' || (SELECT v FROM r1_fx WHERE k='ch_b')
    || '  session=' || (SELECT v FROM r1_fx WHERE k='ses_a')
    || '  note_internal=' || (SELECT v FROM r1_fx WHERE k='note_internal')
    || '  note_toshare=' || (SELECT v FROM r1_fx WHERE k='note_toshare') AS ready;
