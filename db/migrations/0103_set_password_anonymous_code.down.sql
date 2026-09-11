-- =====================================================================
-- 0103 down - set_password goes back to answering HB232 for an
-- anonymous caller.
--
-- This restores 0101's version, NOT the pre-0101 one. The centre guard
-- stays: this migration only ever changed which of two refusals an
-- anonymous caller hears, and rolling it back must not also roll back
-- the cross-tenant protection that 0101 added.
--
-- After running this, phase 8's "nobody anonymous can set any" check
-- fails again - expecting HB073 and receiving HB232. That failure is
-- the point of the check and the reason 0103 exists.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.set_password(p_user_id integer, p_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_min  integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users WHERE user_id = p_user_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB073';
  END IF;

  -- ADDED IN 0101. Skipped when the caller is setting their OWN password,
  -- because current_center_id() is derived from that same user - the
  -- check would be comparing a row to itself, and change_own_password
  -- would depend on a session lookup it does not need.
  IF hbh.current_user_id() IS DISTINCT FROM p_user_id THEN
    PERFORM hbh.assert_same_center('user', p_user_id, l_user.center_id);
  END IF;

  -- Your own, or somebody holding USER.MANAGE. Nothing else.
  IF hbh.current_user_id() IS DISTINCT FROM p_user_id
     AND NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to set the password of user %', p_user_id
      USING ERRCODE = 'HB073';
  END IF;

  IF l_user.user_type NOT IN ('STAFF','THERAPIST') THEN
    RAISE EXCEPTION 'user % signs in with a one-time code, not a password', p_user_id
      USING ERRCODE = 'HB071';
  END IF;

  l_min := hbh.param(l_user.center_id, 'MIN_PASSWORD_LENGTH', '10')::integer;
  IF length(coalesce(p_password, '')) < l_min THEN
    RAISE EXCEPTION 'the password must be at least % characters', l_min
      USING ERRCODE = 'HB072';
  END IF;

  UPDATE hbh.users
     SET password_hash    = public.crypt(p_password, public.gen_salt('bf', 10)),
         password_set_at  = now(),
         failed_login_cnt = 0,
         locked_until     = NULL
   WHERE user_id = p_user_id;
END
$fn$;

DELETE FROM hbh.schema_migrations WHERE version = '0103';
