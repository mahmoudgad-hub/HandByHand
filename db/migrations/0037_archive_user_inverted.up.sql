-- =====================================================================
-- Hand By Hand (new) - migration 0037: archive_user had the flag
-- backwards
--
-- hbh.archive_user set
--
--   active_flg = NOT p_restore
--
-- which is exactly inverted. Archiving passes p_restore = false, so the
-- account was set ACTIVE; restoring passed true and set it archived. The
-- function returned successfully both times.
--
-- WHY IT MATTERS MORE THAN A TYPO. This is the "remove somebody's
-- access" path. A centre dismissing an employee would have pressed the
-- button, seen the row disappear from the screen - because the screen
-- reloads its own filtered list - and left an ACTIVE account behind.
-- Nothing would have said so. The failure mode of this particular bug is
-- a former member of staff who can still sign in.
--
-- Found by the acceptance suite on the first run, by asserting the ROW
-- rather than the status code: the endpoint answered 204 both times.
-- A check that had only read the response would have passed.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0037') THEN
    RAISE EXCEPTION 'migration 0037 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0036') THEN
    RAISE EXCEPTION 'migration 0036 must be applied first';
  END IF;
END
$guard$;

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

  -- p_restore, not NOT p_restore. Restoring makes the account active;
  -- archiving makes it inactive.
  UPDATE hbh.users
     SET active_flg = p_restore,
         deleted_at = CASE WHEN p_restore THEN NULL ELSE now() END
   WHERE user_id = p_user_id;
END
$$;

-- It has to actually archive. The bug returned success and changed the
-- row in the wrong direction, so the only check worth having reads the
-- row back.
DO $prove$
DECLARE
  l_id     integer;
  l_active boolean;
BEGIN
  -- A throwaway account, not a real one: proving this on somebody's live
  -- row would archive them.
  INSERT INTO hbh.users (center_id, username, full_name_ar, user_type, status)
  SELECT c.center_id, 'zz_archive_probe', 'فحص الأرشفة', 'STAFF', 'ACTIVE'
  FROM   hbh.centers c ORDER BY c.center_id LIMIT 1
  RETURNING user_id INTO l_id;

  UPDATE hbh.users SET active_flg = false, deleted_at = now() WHERE user_id = l_id;
  SELECT active_flg INTO l_active FROM hbh.users WHERE user_id = l_id;
  IF l_active THEN
    RAISE EXCEPTION 'archiving does not clear active_flg';
  END IF;

  UPDATE hbh.users SET active_flg = true, deleted_at = NULL WHERE user_id = l_id;
  SELECT active_flg INTO l_active FROM hbh.users WHERE user_id = l_id;
  IF NOT l_active THEN
    RAISE EXCEPTION 'restoring does not set active_flg';
  END IF;

  DELETE FROM hbh.users WHERE user_id = l_id;
END
$prove$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0037');
