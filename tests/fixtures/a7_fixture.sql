-- =====================================================================
-- Hand By Hand (new) - API phase 7 fixture: the therapist's profile
--
-- WHAT THIS FIXTURE DELIBERATELY DOES NOT CREATE: a consent, or a
-- published profile.
--
-- Consenting and publishing are the two acts under test, and the whole
-- point of migration 0033 is that the second cannot happen without the
-- first. A fixture that pre-consented would let every publication test
-- pass while the guard was missing.
--
-- FOUR ACCOUNTS, and the second therapist is not padding:
--
--   a7_admin      CENTER_ADMIN - STAFF.MANAGE, edits anybody's profile
--   a7_therapist  THERAPIST    - the profile under test
--   a7_other      THERAPIST    - a colleague. Without them, "a therapist
--                                may edit their own profile" and "a
--                                therapist may edit any profile" are
--                                indistinguishable, and the suite would
--                                pass on either.
--   a7_parent     GUARDIAN     - the family who reads the published page
--
-- The colleague is the same lesson the phase-5 suite learned an hour
-- earlier: a fixture that cannot produce both refusals cannot tell them
-- apart.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a7_fx;
CREATE TEMP TABLE a7_fx (k text PRIMARY KEY, v integer);

INSERT INTO a7_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a7_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a7_fx WHERE k='center'), (SELECT v FROM a7_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a7_admin',     'مديرة المركز — سبعة', 'STAFF',     '+201500000070'),
       ('a7_therapist', 'أخصائية التخاطب — سبعة', 'THERAPIST', '+201500000071'),
       ('a7_other',     'زميلة — سبعة',        'THERAPIST', '+201500000072'),
       ('a7_parent',    'وليّ الأمر — سبعة',    'GUARDIAN',  '+201500000073')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a7_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a7_therapist' AND r.code = 'THERAPIST')
   OR (u.username = 'a7_other'     AND r.code = 'THERAPIST')
   OR (u.username = 'a7_parent'    AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar, mobile, title_ar)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile, 'أخصائي أول'
FROM   hbh.users u WHERE u.username IN ('a7_therapist', 'a7_other');

INSERT INTO a7_fx (k, v) SELECT 'th', t.therapist_id FROM hbh.therapists t
 JOIN hbh.users u ON u.user_id = t.user_id WHERE u.username = 'a7_therapist';
INSERT INTO a7_fx (k, v) SELECT 'other', t.therapist_id FROM hbh.therapists t
 JOIN hbh.users u ON u.user_id = t.user_id WHERE u.username = 'a7_other';

-- A child and a link, so the guardian is a real family of this centre
-- rather than an account with nothing behind it.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM a7_fx WHERE k='center'), (SELECT v FROM a7_fx WHERE k='branch'),
        'A7-A', 'طفل الدفعة السابعة', DATE '2021-01-01', 'M');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'a7_parent';

INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
SELECT g.guardian_id, c.child_id, 'FATHER', true
FROM   hbh.users u
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = 'A7-A'
WHERE  u.username = 'a7_parent';

SELECT set_config('hbh.user_id', 'a7_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a7_admin'),     'a7-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a7_therapist'), 'a7-therapist-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a7_other'),     'a7-other-pw-123456');
SELECT set_config('hbh.user_id', '', false);

DO $assert$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a7\_%';
  IF n <> 4 THEN RAISE EXCEPTION 'fixture: expected 4 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a7_admin','a7_therapist','a7_other') AND password_hash IS NOT NULL;
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 3)', n; END IF;

  SELECT count(*) INTO n FROM hbh.therapists t JOIN hbh.users u ON u.user_id = t.user_id
   WHERE u.username LIKE 'a7\_%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 therapist rows, found %', n; END IF;

  -- The profile must start unconsented and unpublished, or the two
  -- checks this suite exists for prove nothing.
  SELECT count(*) INTO n FROM hbh.therapists t JOIN hbh.users u ON u.user_id = t.user_id
   WHERE u.username LIKE 'a7\_%' AND (t.consent_at IS NOT NULL OR t.profile_status <> 'DRAFT');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a profile is already consented or published - the guard would be untested'; END IF;

  -- The colleague must be a THERAPIST who is NOT staff-with-STAFF.MANAGE,
  -- or "may not edit a colleague" would pass for the wrong reason.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a7_other' AND p.code = 'STAFF.MANAGE';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a7_other holds STAFF.MANAGE - the colleague check proves nothing'; END IF;
END
$assert$;

\echo 'fixture a7: ready'
