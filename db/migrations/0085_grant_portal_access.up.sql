-- =====================================================================
-- Hand By Hand (new) - migration 0085: HBH-010
-- the family we enrolled can actually log in
--
-- THE BROKEN LOOP. hbh.convert_enrolment turns an application into a
-- child, a guardian and the link between them - and creates no account.
-- So a family that came in through the ONLY official door reaches the
-- login screen, types the mobile they gave us, and is told the system
-- does not know them.
--
-- And D-11 is what makes it invisible: NOT_REGISTERED never reaches the
-- screen, because telling a stranger which numbers are registered is
-- the thing D-11 exists to prevent. That decision is right and stays.
-- Its cost is that this particular failure looks, from the outside,
-- exactly like a family mistyping their number - so nobody reports it
-- as a bug, and the centre concludes the parent is confused.
--
-- WHY THIS IS AN EXPLICIT STEP AND NOT PART OF convert_enrolment
--
-- Because an account is a credential, and credentials are granted by
-- somebody, on a date, with a name attached. Folding it into conversion
-- makes every enrolment silently mint a login - including the ones
-- entered to correct a mistake, and the ones for a child whose file is
-- being set up before the family has agreed to anything. The audit row
-- for "who let this family into the portal" would then say "the
-- enrolment did", which is not an answer.
--
-- WHY GUARDIAN.MANAGE AND NOT USER.MANAGE
--
-- Reception enrols families and holds GUARDIAN.MANAGE; USER.MANAGE
-- belongs to the centre administrator alone, because it creates STAFF
-- accounts. Gating this on USER.MANAGE would mean reception enrols the
-- family and an administrator must then notice and follow up - which
-- rebuilds the same broken loop one step further along, where it is
-- harder to see. hbh.create_user is therefore NOT reused here: its gate
-- is a different, stricter one, on purpose.
--
-- Error classes added here:
--   HB200  not permitted
--   HB201  no such guardian / not in this centre
--   HB202  the guardian has no mobile, and the mobile IS the login
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0085') THEN
    RAISE EXCEPTION 'migration 0085 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0084') THEN
    RAISE EXCEPTION 'migration 0084 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.grant_portal_access(p_guardian_id integer)
RETURNS TABLE (user_id integer, username text, created boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_g      hbh.guardians%ROWTYPE;
  l_uid    integer;
  l_new    boolean := false;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'granting portal access needs GUARDIAN.MANAGE' USING ERRCODE = 'HB200';
  END IF;

  -- FOR UPDATE: two receptionists clicking the same button on the same
  -- family must not produce two accounts. The partial unique index on
  -- guardians.user_id is the backstop; this is the lock that means the
  -- backstop is never reached.
  SELECT * INTO l_g FROM hbh.guardians g
  WHERE  g.guardian_id = p_guardian_id AND g.center_id = l_center AND g.active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian % in this centre', p_guardian_id USING ERRCODE = 'HB201';
  END IF;

  -- Already has one. Calling again is not an error - reception cannot
  -- tell from the screen whether the last click landed, and a function
  -- that punishes the second click teaches people to avoid the first.
  IF l_g.user_id IS NOT NULL THEN
    RETURN QUERY
      SELECT u.user_id, u.username, false FROM hbh.users u WHERE u.user_id = l_g.user_id;
    RETURN;
  END IF;

  IF coalesce(trim(l_g.mobile), '') = '' THEN
    RAISE EXCEPTION 'guardian % has no mobile, and the mobile is how they sign in',
                    p_guardian_id
      USING ERRCODE = 'HB202';
  END IF;

  -- An account on this mobile may already exist - the same person can
  -- have been a guardian in another capacity, or a previous record was
  -- linked and unlinked. request_otp looks families up BY MOBILE and
  -- takes the lowest user_id, so minting a second account on the same
  -- number creates a login that silently resolves to the wrong one.
  -- Link the existing account rather than add a rival to it.
  SELECT u.user_id INTO l_uid
  FROM   hbh.users u
  WHERE  u.mobile = l_g.mobile AND u.center_id = l_center AND u.active_flg
    AND  u.user_type = 'GUARDIAN'
  ORDER  BY u.user_id
  LIMIT  1;

  IF l_uid IS NULL THEN
    INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar,
                           user_type, mobile, status)
    VALUES (l_center, l_g.branch_id, lower(l_g.mobile), l_g.full_name_ar,
            'GUARDIAN', l_g.mobile, 'ACTIVE')
    RETURNING hbh.users.user_id INTO l_uid;

    l_new := true;

    -- Without the role the account exists and can sign in and sees
    -- nothing, which reads to the family as a broken portal rather than
    -- a missing grant.
    INSERT INTO hbh.user_roles (user_id, role_id)
    SELECT l_uid, r.role_id FROM hbh.roles r
    WHERE  r.code = 'GUARDIAN' AND r.center_id = l_center
    ON CONFLICT DO NOTHING;
  END IF;

  UPDATE hbh.guardians g SET user_id = l_uid WHERE g.guardian_id = p_guardian_id;

  -- Who let this family in, and when. The whole reason this is its own
  -- step rather than a side effect of enrolment.
  INSERT INTO hbh.audit_log (center_id, table_name, row_pk, action, new_data, changed_by, detail)
  VALUES (l_center, 'guardians', p_guardian_id::text, 'GRANT',
          jsonb_build_object('user_id', l_uid, 'created', l_new),
          hbh.current_app_user(), 'portal access granted');

  RETURN QUERY SELECT l_uid, lower(l_g.mobile), l_new;
END
$$;

COMMENT ON FUNCTION hbh.grant_portal_access(integer) IS
  'Gives an enrolled family a portal login. Explicit and idempotent: the second call returns the existing account with created=false. HBH-010.';

-- A derived flag, not a stored one. "Has this family got a login" is
-- answerable from guardians.user_id, and a column that repeats it is a
-- column that can disagree with it.
CREATE OR REPLACE VIEW hbh.v_guardian_portal_status
WITH (security_invoker = true)
AS
SELECT g.guardian_id, g.center_id, g.branch_id, g.full_name_ar, g.mobile,
       g.user_id IS NOT NULL AS has_portal_access,
       u.username, u.status AS account_status, u.active_flg AS account_active
FROM   hbh.guardians g
LEFT   JOIN hbh.users u ON u.user_id = g.user_id
WHERE  g.active_flg;

COMMENT ON VIEW hbh.v_guardian_portal_status IS
  'Which families can reach the portal. has_portal_access is derived from guardians.user_id - never stored, so it cannot drift from the truth.';

REVOKE ALL ON FUNCTION hbh.grant_portal_access(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.grant_portal_access(integer) TO hbh_app;
GRANT SELECT ON hbh.v_guardian_portal_status TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0085');
