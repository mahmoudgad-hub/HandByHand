-- =====================================================================
-- Hand By Hand (new) - migration 0126: HBH-010, the refusal says why
--
-- WHAT RECEPTION SEES TODAY, MEASURED
--
-- A member of staff enrols her own child, so the application's
-- parent_mobile is a number that already belongs to a STAFF account.
-- hbh.grant_portal_access looks for an existing GUARDIAN on that
-- mobile, finds none, tries to insert, and uix_users_mobile_active
-- refuses with 23505. Through the API that becomes:
--
--   400  {"code":"VALIDATION","fields":{"constraint":"DUPLICATE"}}
--
-- which the console renders as "هذه القيمة مستعملة بالفعل." - no field,
-- no reason, on a screen with a dozen values. It is the same defect
-- class as the national id refusal repaired earlier today: a true
-- statement that leaves the reader with nowhere to go.
--
-- And the underlying situation is not an error at all. It is a centre
-- with a small staff whose own families are clients - ordinary in a
-- children's therapy centre, and the reason this is worth a sentence of
-- its own rather than a generic uniqueness complaint.
--
-- WHAT THIS CHANGES
--
-- The conflict is detected BEFORE the insert and refused with its own
-- code, naming what is in the way. Nothing else moves: the same
-- conversions succeed, the same ones fail, and the transaction still
-- unwinds whole. Only the sentence changes - and a caller that was
-- reading 23505 now reads HB204, which is why the API mapping ships
-- with this.
--
-- ORDER OF DEPLOYMENT: THE API GOES FIRST.
-- HB204 is a new SQLSTATE. A service that has not learned it drops into
-- its default branch and answers 500 - "حدث خطأ غير متوقَّع" over a
-- business rule that refused on purpose. That trap has been sprung in
-- this project before, by 0053.
--
-- WHY NOT A HARDER FIX
--
-- The tempting move is to link the STAFF account to the guardian and be
-- done. It is refused here and left to a human: a staff login carries
-- staff permissions, and a guardian row pointing at it would hand a
-- parent portal session to an account that can read other families'
-- children the moment anything resolves permissions through it. One
-- person, two capacities, two accounts - and the second number is a
-- decision for the centre, not for this function.
--
-- Error class added here:
--   HB204  the mobile already belongs to an account that is not a guardian
--
-- NOT HB202 and NOT HB203, and the two exclusions are different:
--   HB202 was "the guardian has no mobile". The branch is gone but
--     0085's header still documents the number with that meaning, and a
--     number that means two things reads confidently wrong.
--   HB203 is LIVE and taken - ops_handlers maps it to TEXT_LOCKED for a
--     site text that refuses rewording. Reusing it would answer a
--     portal-access conflict with 409 TEXT_LOCKED.
-- Measured before choosing: every HBxxx in db/migrations and api/internal
-- was listed, and 204 is unused.
--
-- AND A CORRECTION TO 0125's HEADER, which is applied and therefore not
-- edited: it says HB202 ("the guardian has no mobile") is "reachable in
-- principle and not in practice". It is not reachable at all.
-- guardians.mobile is NOT NULL with a format CHECK, and the HB202 branch
-- was removed from grant_portal_access by a later migration for exactly
-- that reason. Conversion cannot fail that way.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0126') THEN
    RAISE EXCEPTION 'migration 0126 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0125') THEN
    RAISE EXCEPTION 'migration 0125 must be applied first';
  END IF;
END
$guard$;

-- Rebuilt from the live definition. Everything above and below the new
-- block is 0085's, unchanged - including the FOR UPDATE lock, the
-- reuse-don't-mint lookup, and the idempotent early return.
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
  l_other  text;
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
  -- (0085 raised HB202 here; a later migration removed it with that
  -- reason written in. The first draft of THIS file restored it from
  -- 0085's text, which would have put back a guard its author had
  -- deliberately taken out. Rebuild from pg_get_functiondef, never
  -- from the migration that first created a function.)

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
    -- NEW IN 0126. The lookup above is narrowed to GUARDIAN, so an
    -- account of any other type on this number falls through it and
    -- into the insert, where the index refuses with a bare 23505.
    -- Asked here instead, the answer can say what is in the way.
    --
    -- The type is named and the username is NOT: the caller already
    -- knows the mobile they typed, and which member of staff owns it
    -- is not something a refusal needs to disclose to answer the
    -- question "why can this family not be given a login".
    SELECT u.user_type INTO l_other
    FROM   hbh.users u
    WHERE  u.mobile = l_g.mobile AND u.active_flg
    ORDER  BY u.user_id
    LIMIT  1;

    IF l_other IS NOT NULL THEN
      RAISE EXCEPTION
        'the mobile of guardian % already belongs to a % account, not a guardian',
        p_guardian_id, l_other
        USING ERRCODE = 'HB204',
              HINT = 'one person in two capacities needs two numbers - the centre decides the second';
    END IF;

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

  RETURN QUERY SELECT l_uid, lower(l_g.mobile), l_new;
END
$$;

COMMENT ON FUNCTION hbh.grant_portal_access(integer) IS
  'Gives an enrolled family a portal login. Explicit and idempotent: the second call returns the existing account with created=false. Refuses HB204 when the mobile already belongs to a non-guardian account. HBH-010.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0126');
