-- =====================================================================
-- Hand By Hand (new) - migration 0103: an anonymous caller is not in
-- the wrong centre. They are in no centre.
--
-- NUMBER RESERVED BEFORE WRITING, checked against the filesystem and
-- hbh.schema_migrations. 0098 and 0100 belong to another session in this
-- same tree.
--
-- ---------------------------------------------------------------------
-- WHAT THIS CORRECTS, AND WHAT FOUND IT
--
-- 0101 put a centre guard at the top of hbh.set_password. Phase 8 then
-- failed one check:
--
--   password | and nobody anonymous can set any
--            | expected HB073, got HB232 user 4731 does not belong to
--            | this centre
--
-- THE SECURITY PROPERTY WAS NEVER IN DOUBT. An anonymous caller was
-- refused before 0101 and is refused after it. What changed is the
-- sentence they are refused with, and the new one is wrong: a caller
-- with no identity does not belong to the WRONG centre, they belong to
-- no centre at all. "user 4731 does not belong to this centre" invites
-- the reader to go and look for which centre that would be.
--
-- WHY THE FUNCTION IS CHANGED AND NOT THE TEST. Editing p8 to expect
-- HB232 would have been one line and would have made the product worse:
-- it would freeze an inaccurate message into the acceptance suite and
-- teach the next reader that this is the intended answer. The test was
-- right.
--
-- ---------------------------------------------------------------------
-- THE FIX, AND WHY IT IS NOT A HOLE
--
-- The centre check now applies only to a caller who HAS an identity.
-- An anonymous caller falls through to the permission check immediately
-- below it, which is where they were always refused:
--
--     IF current_user_id() IS DISTINCT FROM p_user_id
--        AND NOT has_permission('USER.MANAGE')   <- false with no identity
--
-- has_permission cannot be true without an identity - hbh.current_user_id()
-- fails closed, which is the rule the whole schema is built on - so the
-- anonymous path is refused by that line exactly as it was before 0101.
-- Verified by the check that found this, which goes back to HB073.
--
-- hbh.assert_same_center IS NOT CHANGED. It still fails closed on a NULL
-- centre, and that matters: a future function that calls it WITHOUT a
-- permission check after it would then still refuse an anonymous caller.
-- Weakening the helper to fix one caller's error code would have moved
-- the risk from a message to a mechanism.
--
-- The same pattern - guard the centre check on having an identity -
-- appears in hbh.assert_center_argument (0102) for the same reason:
-- fixtures and seeds legitimately run with no identity at all.
--
-- NO OTHER 0101 FUNCTION NEEDS THIS. Checked, not assumed: in
-- issue_invoice, decide_request, sell_package, convert_enrolment,
-- publish_session_note, grant_consent and withdraw_consent an anonymous
-- caller is refused by has_permission anyway, and no acceptance check
-- asserts the code they refuse with. They are left alone rather than
-- edited speculatively.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0103') THEN
    RAISE EXCEPTION 'migration 0103 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0102') THEN
    RAISE EXCEPTION 'migration 0102 must be applied first';
  END IF;
END
$guard$;

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

  -- ADDED IN 0101, CORRECTED IN 0103.
  --
  -- Two conditions, and both are load-bearing:
  --   current_user_id() IS NOT NULL   an anonymous caller is refused by
  --                                   the permission check below, with
  --                                   the code it has always used
  --   IS DISTINCT FROM p_user_id      somebody setting their OWN password
  --                                   is in their own centre by
  --                                   construction; comparing the row to
  --                                   itself would make change_own_password
  --                                   depend on a session lookup it does
  --                                   not need
  IF hbh.current_user_id() IS NOT NULL
     AND hbh.current_user_id() IS DISTINCT FROM p_user_id THEN
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

INSERT INTO hbh.schema_migrations (version) VALUES ('0103');
