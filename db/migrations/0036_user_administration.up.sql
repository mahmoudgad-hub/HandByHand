-- =====================================================================
-- Hand By Hand (new) - migration 0036: administering users and roles
--
-- This migration opens the mechanism by which every other permission in
-- the system is handed out. It is the privilege escalation surface, and
-- each decision below is written down because a reader a year from now
-- will need to know it was a decision.
--
-- =====================================================================
-- WHAT WAS ACTUALLY IN THE WAY
--
-- The console asked for user and role screens and reported "five tables,
-- zero endpoints". The endpoints were the smaller half:
--
--   1. All five tables are SELECT-only for hbh_app. Creating a user or
--      granting a role was not a missing handler, it was a missing write
--      path.
--
--   2. hbh.user_roles could not be READ by an administrator at all:
--
--        p_user_roles_select  (active_flg AND user_id = current_user_id())
--
--      Everybody sees their own roles and nobody else's. So even listing
--      users with their roles was impossible - not an absent endpoint, a
--      read model that had to widen.
--
-- =====================================================================
-- THE OWNER'S DECISION: AN ADMINISTRATOR MAY CREATE ANOTHER
--
-- Asked explicitly, because there is no safe default. Granting
-- CENTER_ADMIN from the screen means one compromised administrator
-- account can entrench itself behind a second. Refusing it means a
-- centre can never appoint its second manager without somebody opening
-- a database console.
--
-- The owner chose: the centre appoints its own. So the accountability
-- has to come from the record instead - see granted_by below.
--
-- =====================================================================
-- THE THREE RULES CHOSEN HERE, NOT ASKED
--
-- 1. NOBODY CHANGES THEIR OWN ROLES. Not even an administrator holding
--    every permission. Today it is redundant - a CENTER_ADMIN already
--    has everything, so self-promotion gains nothing. It stops mattering
--    the day USER.MANAGE is granted to a narrower role, which is exactly
--    when nobody will be thinking about this file.
--
-- 2. A ROLE IS GRANTED WITHIN ONE CENTRE. The role and the user must
--    belong to the caller's centre. Three checks rather than trusting
--    the policy, because this is the one table where a mistake hands
--    somebody another tenant.
--
-- 3. GRANTING IS A RECORDED ACT. granted_by and granted_at, like
--    consent_by and consent_at on a therapist's profile. "Who gave this
--    person billing access, and when" is the first question asked after
--    something goes wrong, and a plain UPDATE cannot answer it.
--
-- WHAT IS NOT HERE, DELIBERATELY: a password. Creating a user does not
-- set one. A password field on a creation screen is a password read
-- aloud, written on paper, and handed over - so the account is created
-- without one and hbh.set_password remains the only way in. The login
-- screen already tells people their password is reset by the centre.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0036') THEN
    RAISE EXCEPTION 'migration 0036 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0031') THEN
    RAISE EXCEPTION 'migration 0031 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- 1. THE GRANT BECOMES A RECORD
-- =====================================================================
ALTER TABLE hbh.user_roles
  ADD COLUMN granted_by integer REFERENCES hbh.users(user_id),
  ADD COLUMN granted_at timestamptz;

CREATE INDEX ix_ur_granted_by ON hbh.user_roles (granted_by)
  WHERE granted_by IS NOT NULL;

COMMENT ON COLUMN hbh.user_roles.granted_by IS
  'Who granted this role. The first question asked after something goes wrong, and a plain UPDATE cannot answer it (0036).';

-- =====================================================================
-- 2. AN ADMINISTRATOR CAN SEE WHO HOLDS WHAT
--
-- A SECOND permissive policy. The existing one stays exactly as it is:
-- everybody keeps seeing their own roles, which is what /me is built on.
-- =====================================================================
CREATE POLICY p_user_roles_select_admin ON hbh.user_roles
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND hbh.has_permission('USER.MANAGE')
         AND EXISTS (SELECT 1 FROM hbh.users u
                      WHERE u.user_id = user_roles.user_id
                      AND   u.center_id = hbh.current_center_id()));

-- Archived users, so a management screen can show who was removed. The
-- existing p_users_select ends with AND active_flg, which is also why
-- archiving a user would otherwise be impossible - Postgres applies the
-- SELECT policy to the NEW row of an UPDATE, the trap migrations 0013
-- and 0035 both paid for.
CREATE POLICY p_users_select_admin ON hbh.users
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('USER.MANAGE'));

-- =====================================================================
-- 3. CREATING AND EDITING A USER
--
-- Functions rather than policies, for the reason migration 0035 spelled
-- out: RLS grants rows and not columns. An UPDATE policy on hbh.users
-- would hand an administrator username, user_type, center_id,
-- password_hash and locked_until along with the name and the telephone
-- number. These name what may change.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.create_user(
  p_username     text,
  p_full_name_ar text,
  p_user_type    text,
  p_mobile       text DEFAULT NULL,
  p_branch_id    integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_id     integer;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'creating a user needs USER.MANAGE' USING ERRCODE = 'HB150';
  END IF;

  IF p_user_type NOT IN ('STAFF', 'THERAPIST', 'GUARDIAN') THEN
    RAISE EXCEPTION 'unknown user type %', p_user_type USING ERRCODE = 'HB151';
  END IF;

  -- Usernames are compared in lower case throughout this schema, so the
  -- collision check is too. Two accounts differing only in case is a
  -- support call nobody can diagnose from the screen.
  IF EXISTS (SELECT 1 FROM hbh.users u WHERE lower(u.username) = lower(p_username)) THEN
    RAISE EXCEPTION 'the username % is taken', p_username USING ERRCODE = 'HB152';
  END IF;

  -- NO PASSWORD. The account is created without one and hbh.set_password
  -- is the only way it gets one. See the header.
  INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
  VALUES (l_center, p_branch_id, lower(p_username), p_full_name_ar, p_user_type,
          nullif(p_mobile, ''), 'ACTIVE')
  RETURNING user_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.update_user(
  p_user_id      integer,
  p_full_name_ar text DEFAULT NULL,
  p_mobile       text DEFAULT NULL,
  p_status       text DEFAULT NULL,
  p_clear_mobile boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF hbh.current_center_id() IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'editing a user needs USER.MANAGE' USING ERRCODE = 'HB150';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.users u
                  WHERE u.user_id = p_user_id AND u.center_id = hbh.current_center_id()) THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB153';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('ACTIVE', 'SUSPENDED', 'LOCKED') THEN
    RAISE EXCEPTION 'unknown status %', p_status USING ERRCODE = 'HB151';
  END IF;

  -- username, user_type, center_id and password_hash are absent on
  -- purpose. Changing a username breaks every audit row that names it;
  -- changing user_type turns a family into staff.
  UPDATE hbh.users
     SET full_name_ar = coalesce(p_full_name_ar, full_name_ar),
         mobile = CASE WHEN p_clear_mobile THEN NULL ELSE coalesce(p_mobile, mobile) END,
         status = coalesce(p_status, status)
   WHERE user_id = p_user_id;
END
$$;

-- Archiving. Soft, like everything, and it refuses the caller's own
-- account: an administrator who archives themselves has locked the
-- centre out of its own user management with no way back through the
-- interface.
CREATE OR REPLACE FUNCTION hbh.archive_user(p_user_id integer, p_restore boolean DEFAULT false)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF hbh.current_center_id() IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'archiving a user needs USER.MANAGE' USING ERRCODE = 'HB150';
  END IF;

  IF p_user_id = hbh.current_user_id() THEN
    RAISE EXCEPTION 'an account cannot archive itself' USING ERRCODE = 'HB154';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.users u
                  WHERE u.user_id = p_user_id AND u.center_id = hbh.current_center_id()) THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB153';
  END IF;

  UPDATE hbh.users
     SET active_flg = NOT p_restore,
         deleted_at = CASE WHEN p_restore THEN NULL ELSE now() END
   WHERE user_id = p_user_id;
END
$$;

-- =====================================================================
-- 4. SETTING SOMEBODY'S ROLES
--
-- THE WHOLE SET, NOT ONE ROLE AT A TIME. The screen shows a final state,
-- and sending additions and removals separately means a request that
-- fails halfway leaves an account in a state nobody chose.
--
-- Roles no longer named are ARCHIVED rather than deleted: who used to
-- hold what is exactly the history this table exists to keep.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.set_user_roles(p_user_id integer, p_role_codes text[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_actor  integer := hbh.current_user_id();
  l_bad    text;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'granting a role needs USER.MANAGE' USING ERRCODE = 'HB150';
  END IF;

  -- RULE 1. Redundant today and not tomorrow: a CENTER_ADMIN already
  -- holds everything, so this gains them nothing - and the day
  -- USER.MANAGE reaches a narrower role, this is the line that stops
  -- them writing themselves a promotion.
  IF p_user_id = l_actor THEN
    RAISE EXCEPTION 'an account cannot change its own roles' USING ERRCODE = 'HB155';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.users u
                  WHERE u.user_id = p_user_id AND u.center_id = l_center) THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB153';
  END IF;

  -- RULE 2. Every named role must exist IN THIS CENTRE. Named
  -- explicitly rather than silently skipped: a screen that asked for
  -- four roles and got three has to be told which one it did not get.
  SELECT string_agg(c, ', ') INTO l_bad
  FROM   unnest(coalesce(p_role_codes, '{}')) AS c
  WHERE  NOT EXISTS (SELECT 1 FROM hbh.roles r
                      WHERE r.code = c AND r.center_id = l_center AND r.active_flg);
  IF l_bad IS NOT NULL THEN
    RAISE EXCEPTION 'no such role in this centre: %', l_bad USING ERRCODE = 'HB156';
  END IF;

  -- Archive what is no longer named.
  UPDATE hbh.user_roles ur
     SET active_flg = false, deleted_at = now()
   WHERE ur.user_id = p_user_id
     AND ur.active_flg
     AND NOT EXISTS (SELECT 1 FROM hbh.roles r
                      WHERE r.role_id = ur.role_id
                      AND   r.code = ANY(coalesce(p_role_codes, '{}')));

  -- Add or revive what is. RULE 3: the grant is stamped.
  INSERT INTO hbh.user_roles (user_id, role_id, granted_by, granted_at)
  SELECT p_user_id, r.role_id, l_actor, now()
  FROM   hbh.roles r
  WHERE  r.code = ANY(coalesce(p_role_codes, '{}'))
  AND    r.center_id = l_center
  ON CONFLICT (user_id, role_id) DO UPDATE
     SET active_flg = true,
         deleted_at = NULL,
         granted_by = excluded.granted_by,
         granted_at = excluded.granted_at;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.create_user(text, text, text, text, integer)            TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.update_user(integer, text, text, text, boolean)          TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.archive_user(integer, boolean)                           TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.set_user_roles(integer, text[])                          TO hbh_app;

-- The tables themselves stay closed to writing. Every route in is one of
-- the functions above, so there is no second path that skips the centre
-- check, the self-grant rule or the stamp.
DO $verify$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   information_schema.role_table_grants
  WHERE  grantee = 'hbh_app' AND table_schema = 'hbh'
  AND    table_name IN ('users','roles','permissions','role_permissions','user_roles')
  AND    privilege_type IN ('INSERT','UPDATE','DELETE');
  IF n <> 0 THEN
    RAISE EXCEPTION 'an identity table was granted directly (% grant(s)) - the functions are the only way in', n;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0036');
