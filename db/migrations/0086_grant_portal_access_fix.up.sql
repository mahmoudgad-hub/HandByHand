-- =====================================================================
-- Hand By Hand (new) - migration 0086: two things 0085 got wrong, both
-- found by its own acceptance suite on the first run
--
-- 1. IT WROTE AN AUDIT ROW THE TABLE ALREADY WRITES.
--
--    hbh.guardians carries trg_guardians_audit. The UPDATE that sets
--    guardians.user_id therefore ALREADY produces an audit row saying
--    user_id went from null to a number, attributed to whoever called.
--    That is precisely "who let this family into the portal" - the very
--    thing 0085 said it was adding a row for.
--
--    So 0085 wrote a second, hand-made row. It also used action =
--    'GRANT', which ck_audit_log_action does not allow (INSERT, UPDATE,
--    DELETE, READ, LOGIN, DENY), so every call raised 23514 and the
--    function was unusable. The suite caught it on the first run.
--
--    The lesson is not "use a valid action". It is that the audit was
--    already there and I did not look. A hand-written audit row beside
--    a trigger that fires on the same statement is duplication at best
--    and, when the two disagree, an argument with no referee.
--
-- 2. IT GUARDED A STATE THE SCHEMA FORBIDS.
--
--    hbh.grant_portal_access refused a guardian with no mobile - HB202.
--    But guardians.mobile is NOT NULL and constrained to
--    '^[0-9+]{6,20}$', so a guardian without a mobile cannot exist. The
--    branch was unreachable, and unreachable guards are worse than
--    absent ones: they tell the next reader that the case happens, and
--    the test written for them can only pass by faking it.
--
--    The suite could not even reach it - the fixture INSERT that tried
--    to build such a guardian was itself rejected by the constraint.
--
-- HB202 is retired and not reused. A retired code that comes back
-- meaning something else makes every old log line ambiguous.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0086') THEN
    RAISE EXCEPTION 'migration 0086 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0085') THEN
    RAISE EXCEPTION 'migration 0085 must be applied first';
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

  -- No mobile check. guardians.mobile is NOT NULL and must match
  -- '^[0-9+]{6,20}$', so there is no such guardian to guard against.

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

  -- This UPDATE is the audit record. trg_guardians_audit turns it into
  -- a row saying user_id went from null to l_uid, and who did it - no
  -- hand-written row needed, and none wanted.
  UPDATE hbh.guardians g SET user_id = l_uid WHERE g.guardian_id = p_guardian_id;

  RETURN QUERY SELECT l_uid, lower(l_g.mobile), l_new;
END
$$;

COMMENT ON FUNCTION hbh.grant_portal_access(integer) IS
  'Gives an enrolled family a portal login. Explicit and idempotent: the second call returns the existing account with created=false. The grant is audited by trg_guardians_audit on the UPDATE. HBH-010.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0086');
