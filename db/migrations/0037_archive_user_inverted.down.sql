-- =====================================================================
-- Hand By Hand (new) - migration 0037 rollback
--
-- Restores the inverted version from 0036, in which archiving an account
-- ACTIVATES it. Rolling this back reintroduces a bug whose failure mode
-- is a dismissed employee who can still sign in. There is no reason to
-- run this that is better than that risk.
-- =====================================================================

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

DELETE FROM hbh.schema_migrations WHERE version = '0037';
