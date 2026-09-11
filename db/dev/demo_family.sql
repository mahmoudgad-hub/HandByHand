-- =====================================================================
-- Hand By Hand (new) - DEVELOPMENT family, with a portal to look at
--
-- WHY THIS EXISTS. The parent portal could not be opened by anybody.
-- Not "was hard to test" - could not be opened: there were zero users
-- of type GUARDIAN on this database, and the two guardians on file came
-- from enrolment testing and carry no account. Every screen behind the
-- family login was therefore unreachable, and the console session had
-- been walking the operations app only.
--
-- Families sign in with a one-time code, not a password, so this file
-- has no secret in it and needs none. In development OTP_ECHO returns
-- the code in the response; there is no SMS gateway yet.
--
-- READ THIS BEFORE MOVING THE FILE. Like db/dev/staff_accounts.sql it
-- is in db/dev/ and NOT in db/seed/, and that is the whole safety
-- design: scripts/db.sh migrate runs every file in db/seed/, so a demo
-- family placed there would be created on every database this project
-- is ever installed on, production included. Nothing runs this
-- automatically:
--
--   bash scripts/db.sh dev-family
--
-- =====================================================================
-- THE PART THAT MATTERS: THE DATA IS MADE BY THE REAL FUNCTIONS.
--
-- Not one row below is assembled by hand where a rule exists to make
-- it. The appointment goes through hbh.book_appointment, the session
-- through start_session and close_session, the note through
-- write_session_note, the report through publish_report, the invoice
-- through create_invoice and add_invoice_line and issue_invoice.
--
-- A fixture that INSERTed these directly would produce rows that look
-- right and are shaped wrong: no appointment number from the series, a
-- currency somebody typed, totals that no arithmetic supports, a
-- session with no history row. The front end would then map its screens
-- against data production will never produce - which is the exact
-- failure this is meant to prevent, in a more convincing disguise.
--
-- So this file is slow and long, and every line of it is a shape the
-- portal will really receive.
-- =====================================================================
-- WHAT IS DELIBERATELY WITHHELD.
--
--   can_view_live_flg stays FALSE. Watching a child in a therapy
--   session is the most sensitive thing this system does, and it needs
--   a recorded consent (D-24). A demo file that switched it on would
--   teach everyone who reads it that the flag is scenery. Grant it by
--   hand when testing the stream:
--
--     SELECT hbh.grant_consent(<guardian_id>, 'LIVE_VIEW', <child_id>);
--
--   The second session note stays INTERNAL. The portal must have one
--   note it CANNOT see, or the visibility ladder is untested by the
--   only people who look at these screens.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS dev_fx;
CREATE TEMP TABLE dev_fx (k text PRIMARY KEY, v integer);

INSERT INTO dev_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO dev_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

DO $need$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dev_fx WHERE k = 'center') THEN
    RAISE EXCEPTION 'centre HBH is missing - run: bash scripts/db.sh migrate';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.users WHERE username = 'dev_admin') THEN
    RAISE EXCEPTION 'dev_admin is missing - run: DEV_STAFF_PASSWORD=... bash scripts/db.sh dev-user first. This file acts as the centre, and the centre has to exist.';
  END IF;
  -- Named explicitly, because the failure otherwise arrives fifty lines
  -- later as a NOT NULL violation on therapist_services - which reads as
  -- a broken script rather than a missing prerequisite.
  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                 JOIN hbh.users u ON u.user_id = t.user_id
                 WHERE u.username = 'dev_therapist' AND t.active_flg) THEN
    RAISE EXCEPTION 'dev_therapist has no row in hbh.therapists - re-run: DEV_STAFF_PASSWORD=... bash scripts/db.sh dev-user. Sessions and appointments point at a therapist_id, not at a user.';
  END IF;
  -- Named separately from the first, because a database built before
  -- dev_therapist2 existed has one therapist and not the other, and the
  -- failure would otherwise be a NULL therapist_id in the off-site
  -- booking a hundred lines down.
  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                 JOIN hbh.users u ON u.user_id = t.user_id
                 WHERE u.username = 'dev_therapist2' AND t.active_flg) THEN
    RAISE EXCEPTION 'dev_therapist2 has no row in hbh.therapists - re-run: DEV_STAFF_PASSWORD=... bash scripts/db.sh dev-user. This file needs a SECOND therapist: language routing and the off-site venue both need two.';
  END IF;
END
$need$;

-- ---------------------------------------------------------------------
-- The family
-- ---------------------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
       'dev_parent', 'سارة عبد الرحمن — تطوير', 'GUARDIAN', '+201500000093', 'ACTIVE'
WHERE NOT EXISTS (SELECT 1 FROM hbh.users WHERE username = 'dev_parent');

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE  u.username = 'dev_parent' AND r.code = 'GUARDIAN'
ON CONFLICT (user_id, role_id) DO NOTHING;

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u
WHERE  u.username = 'dev_parent'
AND NOT EXISTS (SELECT 1 FROM hbh.guardians g WHERE g.user_id = u.user_id);

INSERT INTO dev_fx (k, v)
SELECT 'guardian', g.guardian_id FROM hbh.guardians g
JOIN   hbh.users u ON u.user_id = g.user_id WHERE u.username = 'dev_parent';

-- Two children, because one child hides every list that should be a
-- list: a portal tested with a single child cannot show whether the
-- child switcher works, and cannot show a family choosing between them.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
       c.no, c.name, c.dob, c.g
FROM (VALUES
       ('DEV-CH1', 'يوسف — تطوير', DATE '2020-03-15', 'M'),
       ('DEV-CH2', 'ملك — تطوير',  DATE '2022-11-02', 'F')
     ) AS c(no, name, dob, g)
WHERE NOT EXISTS (SELECT 1 FROM hbh.children x WHERE x.child_no = c.no);

INSERT INTO dev_fx (k, v) SELECT 'child1', child_id FROM hbh.children WHERE child_no='DEV-CH1';
INSERT INTO dev_fx (k, v) SELECT 'child2', child_id FROM hbh.children WHERE child_no='DEV-CH2';

-- can_view_reports true, can_view_live FALSE. See the header.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg, can_view_reports_flg)
SELECT (SELECT v FROM dev_fx WHERE k='guardian'), c.child_id, 'MOTHER', true, true
FROM   hbh.children c
WHERE  c.child_no IN ('DEV-CH1','DEV-CH2')
AND NOT EXISTS (SELECT 1 FROM hbh.guardian_children gc
                 WHERE gc.guardian_id = (SELECT v FROM dev_fx WHERE k='guardian')
                 AND   gc.child_id = c.child_id);

-- ---------------------------------------------------------------------
-- The centre around them.
--
-- THE CATALOGUE IS FOUR SERVICES, NOT ONE, AND THAT IS DELIBERATE.
--
-- It used to be a single row, DEV-SPEECH. Every screen built against it
-- was therefore built against a centre that offers one thing, where a
-- service picker is a formality, a therapist never has to be matched to
-- a skill, and THERAPIST_SERVICE_MISMATCH is a branch of validate_slot
-- that no fixture on this database has ever taken.
--
-- The real centre offers four, and the owner names them himself
-- (docs/06-owner-brief-whatsapp-2026-09-03.md): speech, music therapy
-- under a visiting consultant, sensory integration, and academic support
-- in English. Art therapy is NOT here - he says he intends to add it,
-- and an intention is not a service.
--
-- DEV-SPEECH keeps its code and stays the fixture everything downstream
-- points at, so the plan, the invoice, the package and the home activity
-- are untouched by this.
-- ---------------------------------------------------------------------
INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code, default_duration_min, color_hex)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
       s.code, s.name, s.kind, s.mins, s.colour
FROM (VALUES
       ('DEV-SPEECH',   'تخاطب',                 'SPEECH',   45, '#2E6F8E'),
       ('DEV-MUSIC',    'علاج بالموسيقى',        'MUSIC',    45, '#7B4FA3'),
       ('DEV-SENSORY',  'تكامل حسي',             'SENSORY',  45, '#C2683A'),
       ('DEV-ACADEMIC', 'أكاديمي وصعوبات تعلّم',  'ACADEMIC', 60, '#3E7C5A')
     ) AS s(code, name, kind, mins, colour)
WHERE NOT EXISTS (SELECT 1 FROM hbh.services x WHERE x.code = s.code);

INSERT INTO dev_fx (k, v) SELECT 'svc',     service_id FROM hbh.services WHERE code='DEV-SPEECH';
INSERT INTO dev_fx (k, v) SELECT 'svc_aca', service_id FROM hbh.services WHERE code='DEV-ACADEMIC';

-- The kind codes above are lookup values, not free text, and three of
-- the four arrived with this file. Named here because a missing lookup
-- surfaces later as a service nobody can filter, not as an error.
DO $kinds$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   hbh.lookup_values lv
  JOIN   hbh.lookup_types  lt ON lt.lookup_type_id = lv.lookup_type_id
  WHERE  lt.code = 'SERVICE_KIND' AND lv.active_flg
  AND    lv.code IN ('SPEECH','MUSIC','SENSORY','ACADEMIC');
  IF n <> 4 THEN
    RAISE EXCEPTION 'SERVICE_KIND is missing % of the four kinds this file uses - run: bash scripts/db.sh seed', 4 - n;
  END IF;
END
$kinds$;

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar, notes_ar)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
       'DEV-R1', 'غرفة ١', 'ملاحظة داخلية لا يراها وليّ الأمر'
WHERE NOT EXISTS (SELECT 1 FROM hbh.rooms WHERE code = 'DEV-R1');
INSERT INTO dev_fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='DEV-R1';

-- ---------------------------------------------------------------------
-- AN OFF-SITE VENUE, WHICH THE SCHEMA HAS NO WORD FOR.
--
-- The centre contracts with three outside places - a soft-play hall in a
-- mall, a gym and a pool - and the owner says the results there beat the
-- closed room (docs/06). So this is not an edge case to be handled one
-- day; it is a normal Tuesday, and no fixture on this database has ever
-- shown one.
--
-- There is nowhere else to put it: appointments.room_id is NOT NULL and
-- points at hbh.rooms. branch_id is left NULL because it is true - the
-- hall is not part of a branch - and the policies on rooms filter by
-- centre, never by branch, so nothing hides because of it.
--
-- IT IS THE WRONG SHAPE AND THE FILE SAYS SO. A 5000 m2 hall is not a
-- room, and ex_appointments_room refuses two overlapping appointments in
-- one room - correct for a room, wrong for a hall the centre sends two
-- therapists to at once. The block near the end of this file
-- demonstrates that refusal rather than describing it. Options are in
-- docs/07-domain-from-owner-brief.md, section 2; nothing here decides
-- between them.
-- ---------------------------------------------------------------------
INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar, notes_ar)
SELECT (SELECT v FROM dev_fx WHERE k='center'), NULL,
       'DEV-VENUE1', 'صالة ألعاب — مكان خارجي متعاقَد معه',
       'مكان خارجي، لا غرفة. يتّسع لأكثر من جلسة في الوقت نفسه — والمخطّط لا يعرف ذلك بعد.'
WHERE NOT EXISTS (SELECT 1 FROM hbh.rooms WHERE code = 'DEV-VENUE1');
INSERT INTO dev_fx (k, v) SELECT 'venue', room_id FROM hbh.rooms WHERE code='DEV-VENUE1';

INSERT INTO dev_fx (k, v)
SELECT 'th', t.therapist_id FROM hbh.therapists t
JOIN   hbh.users u ON u.user_id = t.user_id WHERE u.username = 'dev_therapist';

INSERT INTO dev_fx (k, v)
SELECT 'th2', t.therapist_id FROM hbh.therapists t
JOIN   hbh.users u ON u.user_id = t.user_id WHERE u.username = 'dev_therapist2';

-- ---------------------------------------------------------------------
-- REVIVE BEFORE INSERT, BECAUSE DELETION HERE IS SOFT.
--
-- Every guard below asks "does this row exist", and an archived row
-- exists. So on a database where somebody has soft-deleted one of these
-- links - which is what the archive screens are for - the insert finds
-- it, declines to write, and leaves active_flg false. The row is then
-- invisible to validate_slot, which reads only live ones.
--
-- FOUND BY THE VENUE PROBE, NOT BY READING. This database had
-- dev_therapist -> DEV-SPEECH archived from earlier profile work. The
-- catalogue looked complete, the therapist looked staffed, and the
-- booking was refused with THERAPIST_SERVICE_MISMATCH: a therapist who
-- offers nothing, from a file that reported success. Re-running
-- dev-family could not fix it, because re-running was the thing that
-- could not fix it.
--
-- It NOTICEs what it revived. A fixture that silently repairs its own
-- database teaches nobody why the last run was broken.
-- ---------------------------------------------------------------------
DO $revive$
DECLARE n integer; total integer := 0;
BEGIN
  UPDATE hbh.services
  SET    active_flg = true, deleted_at = NULL
  WHERE  code IN ('DEV-SPEECH','DEV-MUSIC','DEV-SENSORY','DEV-ACADEMIC')
  AND    NOT active_flg;
  GET DIAGNOSTICS n = ROW_COUNT; total := total + n;

  UPDATE hbh.rooms
  SET    active_flg = true, deleted_at = NULL
  WHERE  code IN ('DEV-R1','DEV-VENUE1') AND NOT active_flg;
  GET DIAGNOSTICS n = ROW_COUNT; total := total + n;

  UPDATE hbh.therapist_services ts
  SET    active_flg = true, deleted_at = NULL
  FROM  (SELECT f1.v AS th, f2.v AS svc
         FROM   dev_fx f1, dev_fx f2
         WHERE (f1.k, f2.k) IN (('th','svc'), ('th2','svc'), ('th2','svc_aca'))) AS p
  WHERE  ts.therapist_id = p.th AND ts.service_id = p.svc AND NOT ts.active_flg;
  GET DIAGNOSTICS n = ROW_COUNT; total := total + n;

  UPDATE hbh.therapist_working_hours w
  SET    active_flg = true, deleted_at = NULL
  FROM   dev_fx f
  WHERE  f.k IN ('th','th2') AND w.therapist_id = f.v
  AND    w.weekday = ANY (ARRAY[7,1,2,3,4]::smallint[]) AND NOT w.active_flg;
  GET DIAGNOSTICS n = ROW_COUNT; total := total + n;

  UPDATE hbh.therapist_languages tl
  SET    active_flg = true, deleted_at = NULL
  FROM   dev_fx f
  WHERE  f.k IN ('th','th2') AND tl.therapist_id = f.v
  AND    tl.lang_code IN ('ar','en') AND NOT tl.active_flg;
  GET DIAGNOSTICS n = ROW_COUNT; total := total + n;

  IF total > 0 THEN
    RAISE NOTICE 'revived % archived fixture row(s). Something had soft-deleted them, and the guards below - which test existence, not liveness - would have skipped every one.', total;
  END IF;
END
$revive$;

-- Who offers what. dev_therapist does not offer the academic service and
-- dev_therapist2 does: with one therapist offering everything,
-- THERAPIST_SERVICE_MISMATCH could not be reached from this database.
INSERT INTO hbh.therapist_services (therapist_id, service_id)
SELECT p.th, p.svc
FROM (SELECT f1.v AS th, f2.v AS svc
      FROM   dev_fx f1, dev_fx f2
      WHERE (f1.k, f2.k) IN (('th','svc'), ('th2','svc'), ('th2','svc_aca'))) AS p
WHERE NOT EXISTS (SELECT 1 FROM hbh.therapist_services ts
                   WHERE ts.therapist_id = p.th AND ts.service_id = p.svc);

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM dev_fx WHERE k='center'), f.v, d, TIME '09:00', TIME '17:00'
FROM   dev_fx f
CROSS  JOIN unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d
WHERE  f.k IN ('th', 'th2')
AND NOT EXISTS (SELECT 1 FROM hbh.therapist_working_hours w
                 WHERE w.therapist_id = f.v AND w.weekday = d);

-- ---------------------------------------------------------------------
-- LANGUAGE, WHICH THE CENTRE ROUTES BY AND THE SCHEDULER DOES NOT.
--
-- hbh.therapist_languages has existed since 0033 and carries
-- runs_sessions_flg - "can hold a session in this language" - but
-- nothing reads it: not book_appointment, not the waiting list. It is a
-- profile field.
--
-- At the real centre it is the assignment rule. One specialist speaks
-- English, so every international-school referral lands on her, and her
-- queue IS the capacity for those families (docs/06). Two therapists who
-- differ ONLY in language are what makes that visible on a screen.
--
-- Deliberately asymmetric: dev_therapist has Arabic alone.
-- ---------------------------------------------------------------------
INSERT INTO hbh.therapist_languages (therapist_id, lang_code, level_code, is_native_flg, runs_sessions_flg)
SELECT f.v, p.lang, p.lvl, p.native, p.runs
FROM   dev_fx f
JOIN  (VALUES
        ('th',  'ar', 'NATIVE', true,  true),
        ('th2', 'ar', 'NATIVE', true,  true),
        ('th2', 'en', 'FLUENT', false, true)
      ) AS p(fx, lang, lvl, native, runs) ON p.fx = f.k
WHERE NOT EXISTS (SELECT 1 FROM hbh.therapist_languages tl
                   WHERE tl.therapist_id = f.v AND tl.lang_code = p.lang);

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='th'),
       c.child_id, (SELECT v FROM dev_fx WHERE k='svc'), true
FROM   hbh.children c WHERE c.child_no IN ('DEV-CH1','DEV-CH2')
AND NOT EXISTS (SELECT 1 FROM hbh.caseload cl WHERE cl.child_id = c.child_id);

-- The older child sees BOTH therapists: speech with one, academic with
-- the other. A child on exactly one caseload cannot show a case
-- conference, a second opinion, or a handover - and every child at a
-- centre with four services is on more than one.
--
-- Guarded on the three columns and not on the child, unlike the insert
-- above: a guard that asks "does this child appear at all" would find
-- the row it just wrote and never add the second.
INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id, is_primary_flg)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='th2'),
       (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='svc_aca'), false
WHERE NOT EXISTS (SELECT 1 FROM hbh.caseload cl
                   WHERE cl.therapist_id = (SELECT v FROM dev_fx WHERE k='th2')
                   AND   cl.child_id     = (SELECT v FROM dev_fx WHERE k='child1')
                   AND   cl.service_id   = (SELECT v FROM dev_fx WHERE k='svc_aca'));

-- ---------------------------------------------------------------------
-- From here on the centre is ACTING, so it needs an identity. Every
-- call below runs the same rule a real request would.
-- ---------------------------------------------------------------------
SELECT set_config('hbh.user_id', 'dev_admin', false);

-- A plan and a goal for the older child, so a report has a subject and
-- the progress screen has a bar to draw.
INSERT INTO hbh.treatment_plans (center_id, branch_id, child_id, service_id, therapist_id, title_ar, status, start_date)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
       (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='svc'),
       (SELECT v FROM dev_fx WHERE k='th'), 'خطة النطق — الفصل الأول', 'ACTIVE', current_date - 60
WHERE NOT EXISTS (SELECT 1 FROM hbh.treatment_plans WHERE title_ar = 'خطة النطق — الفصل الأول');
INSERT INTO dev_fx (k, v) SELECT 'plan', plan_id FROM hbh.treatment_plans WHERE title_ar='خطة النطق — الفصل الأول';

INSERT INTO hbh.plan_goals (center_id, plan_id, title_ar, description_ar, baseline_pct, target_pct, sort_order)
SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='plan'),
       g.t, g.d, g.b, g.g, g.s
FROM (VALUES
       ('نطق حرف الراء', 'يُنطق الحرف في بداية الكلمة ووسطها.', 20, 80, 10),
       ('جملة من ثلاث كلمات', 'يكوّن جملة مفيدة من ثلاث كلمات.', 35, 90, 20)
     ) AS g(t, d, b, g, s)
WHERE NOT EXISTS (SELECT 1 FROM hbh.plan_goals x
                   WHERE x.plan_id = (SELECT v FROM dev_fx WHERE k='plan') AND x.title_ar = g.t);

-- ---------------------------------------------------------------------
-- A FINISHED session, yesterday.
--
-- THE ONE ROW THIS FILE INSERTS BY HAND, AND EXACTLY WHY.
--
-- hbh.book_appointment refuses a slot in the past - validate_slot
-- answers IN_THE_PAST - and it is right to. Nobody books yesterday.
-- But a portal with no history has no completed session, no note, no
-- report about anything, and no invoice for work done: every screen
-- worth checking would be empty.
--
-- So the appointment row is inserted directly, and NOTHING ELSE is.
-- The number still comes from hbh.next_number, the exclusion
-- constraints still refuse a double booking, and the history trigger
-- still writes its row. The single rule skipped is slot validation -
-- the one rule that exists to refuse this on purpose.
--
-- Everything downstream is the real path: start_session, the notes,
-- close_session. If any of those refuse, this file stops, and that is
-- the point of running them.
-- ---------------------------------------------------------------------
DO $past$
DECLARE
  l_start timestamptz;
  l_appt  integer;
  l_sess  integer;
  l_note  integer;
  l_day   date := (now() AT TIME ZONE 'Africa/Cairo')::date - 1;
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.appointments a
             JOIN hbh.children c ON c.child_id = a.child_id
             WHERE c.child_no = 'DEV-CH1') THEN
    RETURN;  -- already built
  END IF;

  -- Back a day at a time to a working day. Friday and Saturday are the
  -- weekend in Egypt, and a demo that fell over every weekend would be
  -- reported as a bug in the code rather than in the date.
  WHILE extract(isodow FROM l_day) IN (5, 6) LOOP
    l_day := l_day - 1;
  END LOOP;
  l_start := (l_day + TIME '10:00') AT TIME ZONE 'Africa/Cairo';

  INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                therapist_id, room_id, service_id, starts_at, ends_at)
  VALUES ((SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
          hbh.next_number((SELECT v FROM dev_fx WHERE k='center'), 'APPT'),
          (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='th'),
          (SELECT v FROM dev_fx WHERE k='room'),   (SELECT v FROM dev_fx WHERE k='svc'),
          l_start, l_start + interval '45 minutes')
  RETURNING appointment_id INTO l_appt;

  -- One statement per transition. A single UPDATE walking a row through
  -- two states silently keeps only the first: a row is updated once per
  -- statement, with no error and no warning.
  UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = l_appt;
  UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = l_appt;

  -- THE THERAPIST RUNS THE SESSION, NOT THE ADMINISTRATOR, and this file
  -- had to change to say so. Written first as dev_admin, it was refused:
  -- SESSION.NOTES.EDIT and NOTE.PUBLISH belong to THERAPIST alone,
  -- because writing a clinical note is clinical work and not
  -- administration. The seed withholds them from the centre manager
  -- deliberately.
  --
  -- Left as it was, this file would have needed those rights granted to
  -- an administrator to make a demo convenient - which is how a
  -- permission model gets widened by test data.
  PERFORM set_config('hbh.user_id', 'dev_therapist', false);

  l_sess := hbh.start_session(l_appt);

  -- A note is BORN INTERNAL and reaching a family is a separate act.
  -- Both notes are written the same way; only one is published, which
  -- is the whole shape of the ladder and the reason there are two.
  l_note := hbh.write_session_note(l_sess, 'تجاوب جيد اليوم، وتحسّن واضح في نطق الراء.');
  PERFORM hbh.publish_session_note(l_note);

  PERFORM hbh.write_session_note(l_sess, 'ملاحظة داخلية للفريق فقط — لا تظهر لوليّ الأمر.');

  PERFORM hbh.close_session(l_sess, 'COMPLETED', NULL);

  -- Back to the centre for the billing and the report.
  PERFORM set_config('hbh.user_id', 'dev_admin', false);

  INSERT INTO dev_fx (k, v) VALUES ('appt', l_appt), ('sess', l_sess);
END
$past$;

-- A future appointment, so the diary is not only history.
DO $future$
DECLARE
  l_start timestamptz;
  l_day   date := (now() AT TIME ZONE 'Africa/Cairo')::date + 2;
BEGIN
  IF (SELECT count(*) FROM hbh.appointments a
      JOIN hbh.children c ON c.child_id = a.child_id
      WHERE c.child_no = 'DEV-CH2') > 0 THEN
    RETURN;
  END IF;
  WHILE extract(isodow FROM l_day) IN (5, 6) LOOP
    l_day := l_day + 1;
  END LOOP;
  l_start := (l_day + TIME '11:00') AT TIME ZONE 'Africa/Cairo';

  PERFORM hbh.book_appointment(
    (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
    (SELECT v FROM dev_fx WHERE k='child2'), (SELECT v FROM dev_fx WHERE k='th'),
    (SELECT v FROM dev_fx WHERE k='room'),   (SELECT v FROM dev_fx WHERE k='svc'),
    l_start, l_start + interval '45 minutes');
END
$future$;

-- ---------------------------------------------------------------------
-- AN OFF-SITE SESSION, BOOKED BY THE REAL FUNCTION.
--
-- The English-speaking therapist, the academic service, and the outside
-- venue - the combination the centre actually runs and no fixture here
-- has ever produced. It goes through hbh.book_appointment like any
-- other: if the schema cannot express an off-site session, this file
-- stops, which is the point of booking it rather than describing it.
--
-- Four working days out, to stay clear of the appointment above rather
-- than depend on the hour being different.
-- ---------------------------------------------------------------------
DO $offsite$
DECLARE
  l_start timestamptz;
  l_day   date := (now() AT TIME ZONE 'Africa/Cairo')::date + 4;
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.appointments
             WHERE room_id = (SELECT v FROM dev_fx WHERE k='venue')) THEN
    RETURN;
  END IF;

  WHILE extract(isodow FROM l_day) IN (5, 6) LOOP
    l_day := l_day + 1;
  END LOOP;
  l_start := (l_day + TIME '12:00') AT TIME ZONE 'Africa/Cairo';

  PERFORM hbh.book_appointment(
    (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
    (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='th2'),
    (SELECT v FROM dev_fx WHERE k='venue'),  (SELECT v FROM dev_fx WHERE k='svc_aca'),
    l_start, l_start + interval '60 minutes',
    'جلسة خارجية — أكاديمي بالإنجليزية');
END
$offsite$;

-- ---------------------------------------------------------------------
-- THE LIMIT, DEMONSTRATED RATHER THAN DESCRIBED.
--
-- The centre sends two therapists to that hall at the same hour. This
-- asks the scheduler whether it would allow the second one, and the
-- answer is no: ex_appointments_room, and validate_slot ahead of it,
-- treat a venue as a room, and a room holds one appointment at a time.
--
-- It ASKS rather than books, because validate_slot returns a reason
-- instead of raising - so this needs no exception handler, and cannot
-- leave a half-built row behind.
--
-- IT ASSERTS THE REASON BY NAME. A refusal for some other cause -
-- THERAPIST_SERVICE_MISMATCH, OUTSIDE_WORKING_HOURS - would look like
-- the same red light and prove nothing about the venue. So the probe is
-- built to differ from the booking above in the room ALONE: a different
-- child and a different therapist, both free at that hour, and a service
-- dev_therapist really offers.
--
-- A WARNING and not an exception: the schema is not broken, it is
-- narrower than the business. Deciding what to do about it is
-- docs/07-domain-from-owner-brief.md, section 2 - not this file.
-- ---------------------------------------------------------------------
DO $venue_limit$
DECLARE
  l_start timestamptz;
  l_end   timestamptz;
  l_ok    boolean;
  l_why   text;
BEGIN
  -- Read the window off the booking itself rather than recomputing the
  -- date. On a re-run the block above returns early, and a probe that
  -- recomputed "four working days out" would then be asking about an
  -- empty afternoon and reporting OK from a stale calendar.
  SELECT a.starts_at, a.ends_at INTO l_start, l_end
  FROM   hbh.appointments a
  WHERE  a.room_id = (SELECT v FROM dev_fx WHERE k='venue')
  AND    a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
  ORDER  BY a.starts_at
  LIMIT  1;

  IF l_start IS NULL THEN
    RAISE EXCEPTION 'no off-site appointment to probe - the venue block above did not build one';
  END IF;

  SELECT ok, reason INTO l_ok, l_why
  FROM hbh.validate_slot(
         (SELECT v FROM dev_fx WHERE k='center'),
         (SELECT v FROM dev_fx WHERE k='child2'),
         (SELECT v FROM dev_fx WHERE k='th'),
         (SELECT v FROM dev_fx WHERE k='venue'),
         (SELECT v FROM dev_fx WHERE k='svc'),
         l_start, l_end);

  IF l_ok THEN
    RAISE WARNING 'the off-site venue now accepts a second overlapping session. If that was deliberate, docs/07 section 2 is answered and this block should be rewritten to assert the new rule.';
  ELSIF l_why = 'ROOM_BUSY' THEN
    RAISE WARNING 'off-site venue DEV-VENUE1 behaves as a single-occupancy room: a second overlapping session is refused with ROOM_BUSY. The centre runs two therapists there at once. See docs/07-domain-from-owner-brief.md section 2.';
  ELSE
    RAISE EXCEPTION 'the venue probe was refused with % instead of ROOM_BUSY - it now differs from the off-site booking in more than the room, so it no longer tests the venue at all', l_why;
  END IF;
END
$venue_limit$;

-- A published report, and a draft one the family must not see.
-- ONE GUARD PER STATE, NOT ONE GUARD FOR THE BLOCK.
--
-- This used to return early if the child had ANY report, then assert at
-- the end that it had a PUBLISHED one and a DRAFT one - a guard and an
-- assertion asking different questions, which is the same fault the
-- revive block above exists for.
--
-- It broke exactly as you would expect: somebody published the draft
-- while testing the publish button, so the child had two reports and
-- both were PUBLISHED. The guard saw reports and returned; the check
-- demanded a draft and found none; and re-running the file could not
-- mend it, because returning early was the whole problem. Their rows are
-- untouched - the fixture supplies what is MISSING, and nothing else.
DO $reports$
DECLARE l_pub integer;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.progress_reports r
                 JOIN hbh.children c ON c.child_id = r.child_id
                 WHERE c.child_no = 'DEV-CH1' AND r.status = 'PUBLISHED' AND r.active_flg) THEN
    INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                      title_ar, period_start, period_end, summary_ar, status)
    VALUES ((SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
            (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='plan'),
            hbh.next_number((SELECT v FROM dev_fx WHERE k='center'), 'REPORT'),
            'تقرير الشهر الأول', current_date - 60, current_date - 30,
            'تحسّن ملحوظ في وضوح النطق، مع استمرار العمل على حرف الراء.', 'DRAFT')
    RETURNING report_id INTO l_pub;

    PERFORM hbh.publish_report(l_pub);
  END IF;

  -- The one that stays a draft. Without it the portal shows a list that
  -- happens to be complete, and nobody learns that it is filtered.
  IF NOT EXISTS (SELECT 1 FROM hbh.progress_reports r
                 JOIN hbh.children c ON c.child_id = r.child_id
                 WHERE c.child_no = 'DEV-CH1' AND r.status = 'DRAFT' AND r.active_flg) THEN
    INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                      title_ar, period_start, period_end, summary_ar, status)
    VALUES ((SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='branch'),
            (SELECT v FROM dev_fx WHERE k='child1'), (SELECT v FROM dev_fx WHERE k='plan'),
            hbh.next_number((SELECT v FROM dev_fx WHERE k='center'), 'REPORT'),
            'تقرير الشهر الثاني — مسوّدة', current_date - 30, current_date,
            'قيد الكتابة.', 'DRAFT');
  END IF;
END
$reports$;

-- An issued invoice with a part payment, and a draft one that must not
-- reach the family. Every amount is computed by the database.
DO $billing$
DECLARE l_inv integer;
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.invoices i
             JOIN hbh.children c ON c.child_id = i.child_id WHERE c.child_no = 'DEV-CH1') THEN
    RETURN;
  END IF;

  l_inv := hbh.create_invoice((SELECT v FROM dev_fx WHERE k='child1'));
  PERFORM hbh.add_invoice_line(l_inv, 'أربع جلسات تخاطب', 4, 250.00,
                               (SELECT v FROM dev_fx WHERE k='svc'));
  PERFORM hbh.issue_invoice(l_inv);

  INSERT INTO hbh.payments (center_id, branch_id, invoice_id, amount, method_code, note_ar)
  SELECT i.center_id, i.branch_id, i.invoice_id, 400.00, 'CASH', 'دفعة أولى'
  FROM   hbh.invoices i WHERE i.invoice_id = l_inv;

  -- Still a draft: a family must not be shown a number that is moving.
  PERFORM hbh.add_invoice_line(
            hbh.create_invoice((SELECT v FROM dev_fx WHERE k='child2')),
            'جلستا تقييم', 2, 300.00, (SELECT v FROM dev_fx WHERE k='svc'));
END
$billing$;

-- A home activity and a package, so those two screens are not empty.
DO $home$
DECLARE l_act integer;
BEGIN
  INSERT INTO hbh.activity_library (center_id, code, title_ar, how_to_ar, service_id)
  SELECT (SELECT v FROM dev_fx WHERE k='center'), 'DEV-ACT1', 'تمرين نطق الراء',
         'كرّري الكلمات العشر مع الطفل مرّتين يوميًا، خمس دقائق في كل مرة.',
         (SELECT v FROM dev_fx WHERE k='svc')
  WHERE NOT EXISTS (SELECT 1 FROM hbh.activity_library WHERE code = 'DEV-ACT1');

  SELECT activity_id INTO l_act FROM hbh.activity_library WHERE code = 'DEV-ACT1';

  INSERT INTO hbh.child_activities (center_id, child_id, activity_id, plan_id, assigned_by,
                                    times_per_week, minutes_each, instructions_ar, start_date)
  SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='child1'),
         l_act, (SELECT v FROM dev_fx WHERE k='plan'),
         (SELECT user_id FROM hbh.users WHERE username='dev_therapist'),
         5, 10, 'قبل النوم، وبمكافأة صغيرة عند الإتمام.', current_date - 20
  WHERE NOT EXISTS (SELECT 1 FROM hbh.child_activities
                     WHERE child_id = (SELECT v FROM dev_fx WHERE k='child1'));
END
$home$;

DO $package$
BEGIN
  INSERT INTO hbh.service_packages (center_id, service_id, code, name_ar, sessions_cnt, price_amt, validity_days)
  SELECT (SELECT v FROM dev_fx WHERE k='center'), (SELECT v FROM dev_fx WHERE k='svc'),
         'DEV-PKG8', 'باقة ٨ جلسات', 8, 1800.00, 120
  WHERE NOT EXISTS (SELECT 1 FROM hbh.service_packages WHERE code = 'DEV-PKG8');

  IF NOT EXISTS (SELECT 1 FROM hbh.child_packages
                  WHERE child_id = (SELECT v FROM dev_fx WHERE k='child1')) THEN
    PERFORM hbh.sell_package((SELECT v FROM dev_fx WHERE k='child1'),
                             (SELECT package_id FROM hbh.service_packages WHERE code='DEV-PKG8'));
  END IF;
END
$package$;

SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- It asserts itself, by name. A demo that half-built leaves somebody
-- debugging an empty screen against correct code.
-- ---------------------------------------------------------------------
DO $verify$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username = 'dev_parent' AND status = 'ACTIVE';
  IF n <> 1 THEN RAISE EXCEPTION 'the family account was not created'; END IF;

  SELECT count(*) INTO n FROM hbh.guardian_children
   WHERE guardian_id = (SELECT v FROM dev_fx WHERE k='guardian');
  IF n <> 2 THEN RAISE EXCEPTION 'expected 2 children linked, found %', n; END IF;

  -- D-24, STATED AS THE RULE AND NOT AS A VALUE.
  --
  -- This began as "the live flag must be off", and it was wrong within
  -- the hour: somebody followed the instruction in this file's own
  -- header, granted LIVE_VIEW for one child to test the stream, and the
  -- next run of this file refused the exact state it had told them to
  -- create.
  --
  -- The rule was never "off". It is that the flag may be on ONLY where a
  -- recorded consent explains it - which is what the trigger on the
  -- table enforces, and what this now checks. A demo that has been used
  -- for what it is for still passes.
  SELECT count(*) INTO n
  FROM   hbh.guardian_children gc
  WHERE  gc.guardian_id = (SELECT v FROM dev_fx WHERE k='guardian')
  AND    gc.can_view_live_flg
  AND NOT EXISTS (SELECT 1 FROM hbh.consents c
                   WHERE c.guardian_id = gc.guardian_id
                   AND   c.child_id = gc.child_id
                   AND   c.consent_type = 'LIVE_VIEW'
                   AND   c.granted_flg AND c.active_flg AND c.withdrawn_at IS NULL);
  IF n <> 0 THEN
    RAISE EXCEPTION 'the live flag is on for % child(ren) with no recorded consent behind it (D-24)', n;
  END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports r
   JOIN hbh.children c ON c.child_id = r.child_id
   WHERE c.child_no = 'DEV-CH1' AND r.status = 'PUBLISHED';
  IF n < 1 THEN RAISE EXCEPTION 'no published report - the reports screen would be empty'; END IF;

  SELECT count(*) INTO n FROM hbh.progress_reports r
   JOIN hbh.children c ON c.child_id = r.child_id
   WHERE c.child_no = 'DEV-CH1' AND r.status = 'DRAFT';
  IF n < 1 THEN RAISE EXCEPTION 'no draft report - nothing would prove the list is filtered'; END IF;

  SELECT count(*) INTO n FROM hbh.session_notes sn
   JOIN hbh.therapy_sessions s ON s.session_id = sn.session_id
   JOIN hbh.children c ON c.child_id = s.child_id
   WHERE c.child_no = 'DEV-CH1' AND sn.visibility = 'INTERNAL';
  IF n < 1 THEN RAISE EXCEPTION 'no internal note - the visibility ladder would be invisible on screen'; END IF;

  SELECT count(*) INTO n FROM hbh.invoices i
   JOIN hbh.children c ON c.child_id = i.child_id
   WHERE c.child_no = 'DEV-CH1' AND i.status <> 'DRAFT' AND i.total_amt > 0;
  IF n < 1 THEN RAISE EXCEPTION 'no issued invoice with a total - the billing screen would be empty'; END IF;

  -- The centre, not just the family. Each of these was absent from this
  -- database until now, and each hides a whole class of screen.
  SELECT count(*) INTO n FROM hbh.services
   WHERE code IN ('DEV-SPEECH','DEV-MUSIC','DEV-SENSORY','DEV-ACADEMIC') AND active_flg;
  IF n <> 4 THEN
    RAISE EXCEPTION 'expected 4 catalogue services, found % - a one-service centre makes the service picker a formality', n;
  END IF;

  -- Asserted as an asymmetry, not as a count. Two therapists who both
  -- speak English prove nothing about routing by language: what the
  -- screens need is one who does and one who does not.
  SELECT count(*) INTO n
  FROM   hbh.therapist_languages tl
  JOIN   hbh.therapists t ON t.therapist_id = tl.therapist_id
  JOIN   hbh.users u      ON u.user_id = t.user_id
  WHERE  u.username = 'dev_therapist2' AND tl.lang_code = 'en'
  AND    tl.runs_sessions_flg AND tl.active_flg;
  IF n <> 1 THEN
    RAISE EXCEPTION 'dev_therapist2 does not hold English as a session language - nothing distinguishes the two therapists';
  END IF;

  SELECT count(*) INTO n
  FROM   hbh.therapist_languages tl
  JOIN   hbh.therapists t ON t.therapist_id = tl.therapist_id
  JOIN   hbh.users u      ON u.user_id = t.user_id
  WHERE  u.username = 'dev_therapist' AND tl.lang_code = 'en' AND tl.active_flg;
  IF n <> 0 THEN
    RAISE EXCEPTION 'dev_therapist has English too - the two therapists no longer differ by language, and the routing screen has nothing to route';
  END IF;

  SELECT count(*) INTO n FROM hbh.appointments a
   JOIN hbh.rooms r ON r.room_id = a.room_id
   WHERE r.code = 'DEV-VENUE1';
  IF n < 1 THEN
    RAISE EXCEPTION 'no off-site appointment - the venue exists but nothing was ever booked into it';
  END IF;
END
$verify$;

\echo ''
\echo 'development family ready.  sign in at POST /api/v1/auth/otp/request  with mobile 01500000093'
\echo 'the code comes back in the response while OTP_ECHO is on.'
\echo ''
\echo '  DEV-CH1  a past session with a parent note and an internal one, a published report, a draft report, an issued invoice part paid, a home activity, a package'
\echo '           and an OFF-SITE academic session in English with dev_therapist2'
\echo '  DEV-CH2  a future appointment and a DRAFT invoice the family must not see'
\echo ''
\echo 'the centre around them is no longer one service and one room:'
\echo ''
\echo '  catalogue   DEV-SPEECH  DEV-MUSIC  DEV-SENSORY  DEV-ACADEMIC'
\echo '  therapists  dev_therapist  (Arabic, speech only)'
\echo '              dev_therapist2 (Arabic + English, speech and academic)'
\echo '  places      DEV-R1      a room'
\echo '              DEV-VENUE1  a contracted venue outside the centre'
\echo ''
\echo 'A WARNING about DEV-VENUE1 above this line is EXPECTED, not a fault:'
\echo 'the venue is modelled as a room, so it takes one session at a time'
\echo 'while the real hall takes several.  docs/07-domain-from-owner-brief.md'
\echo 'section 2 has the two ways out; this file only demonstrates the limit.'
\echo ''
\echo 'this file grants NO live-stream consent.  to give one for a child:'
\echo ''
\echo '  SELECT set_config(''hbh.user_id'', ''dev_admin'', false);'
\echo '  SELECT hbh.grant_consent(<guardian_id>, ''LIVE_VIEW'', <child_id>);'
\echo ''
\echo 'the identity line is not optional: grant_consent needs GUARDIAN.MANAGE,'
\echo 'and the owner has no user_id - it refuses, correctly, for a caller it'
\echo 'cannot name.  grant it for ONE child and not the other: a family with'
\echo 'consent for one sibling must see that door open and the other shut.'
