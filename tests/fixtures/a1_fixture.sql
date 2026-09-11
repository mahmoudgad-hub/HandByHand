-- =====================================================================
-- Hand By Hand (new) - API phase 1 fixture
--
-- Two families that must never see each other, and one locked account.
-- That is the entire shape of it, because that is what the phase has to
-- prove: parent A asking for child B by identifier is refused by the
-- database, not by a hidden button.
--
-- Run as hbh_owner. The owner bypasses row level security, which is
-- exactly why the API does not connect as the owner (D-2) - and exactly
-- why a fixture can be built at all.
--
-- Every row is named a1_ or A1- so the teardown can find it.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Accounts
-- ---------------------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT c.center_id, b.branch_id, v.username, v.full_name_ar, 'GUARDIAN', v.mobile, v.status
FROM   hbh.centers c
JOIN   hbh.branches b ON b.center_id = c.center_id AND b.code = 'MAIN'
CROSS  JOIN (VALUES
        ('a1_parent_a', 'والد الطفل الأول', '+201500000001', 'ACTIVE'),
        ('a1_parent_b', 'والد الطفل الثاني', '+201500000002', 'ACTIVE'),
        -- A suspended account. request_otp must refuse it, and it must
        -- refuse it with USER_LOCKED and not with NOT_REGISTERED.
        ('a1_locked',   'حساب موقوف',       '+201500000003', 'LOCKED')
      ) AS v(username, full_name_ar, mobile, status)
WHERE  c.code = 'HBH';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id AND r.code = 'GUARDIAN'
WHERE  u.username IN ('a1_parent_a', 'a1_parent_b');

-- ---------------------------------------------------------------------
-- Guardian records
-- ---------------------------------------------------------------------
INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u
WHERE  u.username IN ('a1_parent_a', 'a1_parent_b');

-- ---------------------------------------------------------------------
-- Children
--
-- child_no is written literally rather than drawn from next_number().
-- A fixture that consumed the real series would move the counter every
-- run, and the first child registered by reception afterwards would
-- carry a number with a hole in front of it.
-- ---------------------------------------------------------------------
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT c.center_id, b.branch_id, v.child_no, v.full_name_ar, v.birth_date::date, v.gender
FROM   hbh.centers c
JOIN   hbh.branches b ON b.center_id = c.center_id AND b.code = 'MAIN'
CROSS  JOIN (VALUES
        ('A1-A', 'طفل العائلة الأولى',  '2020-03-15', 'M'),
        ('A1-B', 'طفل العائلة الثانية', '2019-11-02', 'F')
      ) AS v(child_no, full_name_ar, birth_date, gender)
WHERE  c.code = 'HBH';

-- ---------------------------------------------------------------------
-- TWO APPLICATIONS, NEITHER WITH AN ACCOUNT
--
-- One is live and must produce ENROLMENT_PENDING. The other was rejected
-- and must produce NOT_REGISTERED like any stranger.
--
-- Without the second, "a pending application is named" would pass on a
-- rule that named EVERY application - and telling somebody the centre
-- considered them and said no is exactly what migration 0083 refuses to
-- do. One row cannot tell those two rules apart.
-- ---------------------------------------------------------------------
-- The reference number is written here rather than left to the sequence
-- the submit path uses. Two reasons: it is NOT NULL with no default, and
-- a fixed A1- prefix makes these rows removable by identity in the
-- teardown instead of by "recently created", which is how a cleanup
-- reaches somebody else's application.
INSERT INTO hbh.enrolment_applications
       (center_id, branch_id, application_no, parent_name_ar, parent_mobile,
        relationship_code, child_name_ar, child_birth_date, child_gender, status)
SELECT c.center_id, b.branch_id, v.ref, v.parent, v.mobile, 'MOTHER',
       v.child, DATE '2021-04-04', 'F', v.status
FROM   hbh.centers c
JOIN   hbh.branches b ON b.center_id = c.center_id AND b.code = 'MAIN'
CROSS  JOIN (VALUES
        ('A1-ENR-PENDING',  'مقدّمة طلب — قيد النظر', '+201599990001', 'طفلة قيد النظر', 'NEW'),
        ('A1-ENR-REJECTED', 'مقدّمة طلب — مرفوضة',   '+201599990002', 'طفلة مرفوضة',    'REJECTED')
      ) AS v(ref, parent, mobile, child, status)
WHERE  c.code = 'HBH';

-- ---------------------------------------------------------------------
-- The links, and the one switch that matters
--
-- Family A may watch the live stream; family B may not. Both flags are
-- set explicitly here so the suite reads a decision rather than a
-- default - the schema defaults can_view_live_flg to false, and the
-- test would pass on that default without proving anything was applied.
-- ---------------------------------------------------------------------
INSERT INTO hbh.guardian_children
       (guardian_id, child_id, relationship_code, is_primary_flg, can_view_reports_flg)
SELECT g.guardian_id, c.child_id, v.relationship_code, true, true
FROM  (VALUES
        ('a1_parent_a', 'A1-A', 'FATHER'),
        ('a1_parent_b', 'A1-B', 'MOTHER')
      ) AS v(username, child_no, relationship_code)
JOIN   hbh.users u     ON u.username = v.username
JOIN   hbh.guardians g ON g.user_id = u.user_id
JOIN   hbh.children c  ON c.child_no = v.child_no AND c.center_id = u.center_id;

-- Family A may watch the live stream; family B may not - and since
-- migration 0015 that difference is a RECORDED CONSENT, not a boolean
-- somebody set. Writing can_view_live_flg directly now raises HB081.
--
-- The rule is the right one and worth stating: setting a flag was never
-- the same thing as somebody having said yes, with a date against it.
-- grant_consent needs the guardian themselves or GUARDIAN.MANAGE, so
-- the seeded administrator records it, as happens in the centre.
SELECT set_config('hbh.user_id', 'admin', false);

SELECT hbh.grant_consent(
  (SELECT g.guardian_id FROM hbh.guardians g
    JOIN hbh.users u ON u.user_id = g.user_id WHERE u.username = 'a1_parent_a'),
  'LIVE_VIEW',
  (SELECT child_id FROM hbh.children WHERE child_no = 'A1-A'));

SELECT set_config('hbh.user_id', '', false);

-- ---------------------------------------------------------------------
-- The fixture asserts itself, by name, before any test runs
--
-- Three phases of the Oracle project lost a full round trip to a
-- missing fixture row that surfaced fifty tests later as a confusing
-- refusal from correct code. This block is the answer to that.
-- ---------------------------------------------------------------------
DO $assert$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a1\_%';
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: expected 3 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.children WHERE child_no LIKE 'A1-%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 children, found %', n; END IF;

  SELECT count(*) INTO n
  FROM   hbh.guardian_children gc
  JOIN   hbh.children c ON c.child_id = gc.child_id AND c.child_no LIKE 'A1-%';
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 links, found %', n; END IF;

  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur ON ur.user_id = u.user_id
  JOIN   hbh.roles r ON r.role_id = ur.role_id AND r.code = 'GUARDIAN'
  WHERE  u.username IN ('a1_parent_a', 'a1_parent_b');
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: expected 2 guardian role grants, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users WHERE username = 'a1_locked' AND status = 'LOCKED';
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the locked account is not locked'; END IF;

  -- Not a fixture row, but the suite cannot mean anything without it.
  SELECT count(*) INTO n FROM hbh.sys_params WHERE param_code = 'MOBILE_PATTERN' AND active_flg;
  IF n < 1 THEN RAISE EXCEPTION 'fixture: MOBILE_PATTERN is not seeded'; END IF;

  -- TWO APPLICATIONS AND NO ACCOUNT FOR EITHER. Migration 0083 answers
  -- ENROLMENT_PENDING only when the mobile is on a live application AND
  -- on no user, so an account here would send both checks down the
  -- ordinary send path and they would prove nothing.
  SELECT count(*) INTO n FROM hbh.users
   WHERE mobile IN ('+201599990001', '+201599990002') AND active_flg;
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: % account(s) hold the applicant mobiles - the pending checks would test the send path instead', n; END IF;

  SELECT count(*) INTO n FROM hbh.enrolment_applications
   WHERE parent_mobile = '+201599990001' AND status = 'NEW' AND active_flg;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the pending application is missing'; END IF;

  SELECT count(*) INTO n FROM hbh.enrolment_applications
   WHERE parent_mobile = '+201599990002' AND status = 'REJECTED' AND active_flg;
  IF n <> 1 THEN RAISE EXCEPTION 'fixture: the rejected application is missing'; END IF;
END
$assert$;

\echo 'fixture a1: ready'
