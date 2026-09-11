-- =====================================================================
-- Hand By Hand (new) - API phase 8 fixture: the centre's own settings
--
-- WHAT THIS FIXTURE DELIBERATELY DOES NOT CREATE: a centre override for
-- DATE_DISPLAY_FORMAT.
--
-- "There is no override yet" is the starting state of every test in the
-- write group, and it is a state that must be MADE, not assumed. Three
-- things break the assumption: a previous run that was interrupted
-- between its write and its reset, a hand edit from the settings screen
-- during development, and the reset itself - which deactivates the row
-- and leaves it in the table. The teardown runs before this file for
-- exactly that reason, and the assertion at the bottom proves it
-- worked rather than hoping.
--
-- THREE ACCOUNTS, and the receptionist is not padding:
--
--   a8_admin      CENTER_ADMIN - holds SETTINGS.MANAGE
--   a8_reception  RECEPTION    - signed in, and does NOT hold it.
--                                Without this account, "an administrator
--                                may write a parameter" and "anybody
--                                signed in may write a parameter" are
--                                indistinguishable, and the suite would
--                                pass on either.
--   a8_parent     GUARDIAN     - the read is open to any signed-in
--                                caller and the write is not, so the
--                                two halves need a caller who is
--                                neither staff nor anonymous.
--
-- The receptionist's LACK of the permission is asserted by name below.
-- A negative test whose subject quietly gains the right it is supposed
-- to lack goes green and stays green.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS a8_fx;
CREATE TEMP TABLE a8_fx (k text PRIMARY KEY, v integer);

INSERT INTO a8_fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO a8_fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT (SELECT v FROM a8_fx WHERE k='center'), (SELECT v FROM a8_fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile, 'ACTIVE'
FROM (VALUES
       ('a8_admin',     'مديرة المركز — ثمانية',   'STAFF',    '+201500000080'),
       ('a8_reception', 'موظّفة الاستقبال — ثمانية', 'STAFF',    '+201500000081'),
       ('a8_parent',    'وليّ الأمر — ثمانية',      'GUARDIAN', '+201500000082')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u JOIN hbh.roles r ON r.center_id = u.center_id
WHERE (u.username = 'a8_admin'     AND r.code = 'CENTER_ADMIN')
   OR (u.username = 'a8_reception' AND r.code = 'RECEPTION')
   OR (u.username = 'a8_parent'    AND r.code = 'GUARDIAN');

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
SELECT u.center_id, u.branch_id, u.user_id, u.full_name_ar, u.mobile
FROM   hbh.users u WHERE u.username = 'a8_parent';

SELECT set_config('hbh.user_id', 'a8_admin', false);
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a8_admin'),     'a8-admin-pw-123456');
SELECT hbh.set_password((SELECT user_id FROM hbh.users WHERE username='a8_reception'), 'a8-reception-pw-123456');
SELECT set_config('hbh.user_id', '', false);

DO $assert$
DECLARE n integer; v text;
BEGIN
  SELECT count(*) INTO n FROM hbh.users WHERE username LIKE 'a8\_%';
  IF n <> 3 THEN RAISE EXCEPTION 'fixture: expected 3 accounts, found %', n; END IF;

  SELECT count(*) INTO n FROM hbh.users
   WHERE username IN ('a8_admin','a8_reception') AND password_hash IS NOT NULL;
  IF n <> 2 THEN RAISE EXCEPTION 'fixture: a staff password was not set (% of 2)', n; END IF;

  -- The administrator must HOLD the permission the write group asks for.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a8_admin' AND p.code = 'SETTINGS.MANAGE';
  IF n = 0 THEN RAISE EXCEPTION 'fixture: a8_admin does not hold SETTINGS.MANAGE - every write test would fail for the wrong reason'; END IF;

  -- And the receptionist must NOT hold it, or the refusal proves nothing.
  SELECT count(*) INTO n
  FROM   hbh.users u
  JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id
  JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id
  JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
  WHERE  u.username = 'a8_reception' AND p.code = 'SETTINGS.MANAGE';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a8_reception holds SETTINGS.MANAGE - the refusal check proves nothing'; END IF;

  -- No override may exist for the parameter the suite moves. This is the
  -- state under test, not a convenience.
  SELECT count(*) INTO n FROM hbh.sys_params
   WHERE center_id IS NOT NULL AND param_code = 'DATE_DISPLAY_FORMAT';
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a centre override for DATE_DISPLAY_FORMAT already exists - the write group would start mid-way'; END IF;

  -- The global row must be there and editable, or the write is refused
  -- by a rule the suite is not testing.
  SELECT param_value INTO v FROM hbh.sys_params
   WHERE center_id IS NULL AND param_code = 'DATE_DISPLAY_FORMAT' AND active_flg AND editable_flg;
  IF v IS NULL THEN RAISE EXCEPTION 'fixture: DATE_DISPLAY_FORMAT is missing or not editable globally'; END IF;

  -- And the two the suite proves are NOT editable must really not be.
  SELECT count(*) INTO n FROM hbh.sys_params
   WHERE center_id IS NULL AND editable_flg
     AND param_code IN ('RECORDING_ENABLED','STREAM_TOKEN_TTL_MIN');
  IF n <> 0 THEN RAISE EXCEPTION 'fixture: a parameter this suite expects to be locked is marked editable'; END IF;
END
$assert$;

\echo 'fixture a8: ready'
