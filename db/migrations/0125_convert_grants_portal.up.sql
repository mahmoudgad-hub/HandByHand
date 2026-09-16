-- =====================================================================
-- Hand By Hand (new) - migration 0125: HBH-010, second half
-- conversion now grants the portal account it always implied
--
-- WHAT WAS MEASURED, BEFORE ANYTHING WAS CHANGED
--
-- A family was put through the only official door end to end:
--
--   POST /api/v1/enrolments                  -> ENR-2026-01029  (anonymous)
--   PATCH .../1256   NEW -> CONTACTED        -> 204
--   POST  .../1256/convert                   -> 201
--     guardian 3711 created, mobile +201500009912
--     child    4304 created
--     guardians.user_id                      -> NULL
--     rows in hbh.users on that mobile       -> none
--     the parent identity lookup             -> does not know this number
--
-- Then hbh.grant_portal_access(3711) was called by hand: user 7099 was
-- created, the GUARDIAN role granted, guardians.user_id filled, and the
-- SAME raw number the family types - 01500009912 - resolved through
-- hbh.canonical_mobile to that account and answered 202.
--
-- So the database half of HBH-010 was already finished and correct in
-- 0085. Nothing above it ever called it: there was no API route and no
-- control on any screen - `grep -rn grant_portal_access api/ web/`
-- returned nothing at all. The loop was not broken in the schema. It
-- was broken one layer up, which is where 0085 predicted it would move.
--
-- THE DECISION THIS REVERSES, AND WHY
--
-- 0085 chose deliberately NOT to fold this into conversion, and gave
-- three reasons. They are quoted here because a reader who meets only
-- this file would otherwise think nobody had considered the question:
--
--   1. "an account is a credential, and credentials are granted by
--      somebody, on a date, with a name attached"
--   2. folding it in "makes every enrolment silently mint a login -
--      including the ones entered to correct a mistake, and the ones
--      for a child whose file is being set up before the family has
--      agreed to anything"
--   3. the audit row for "who let this family into the portal" would
--      "say the enrolment did, which is not an answer"
--
-- The owner has since asked for the account to exist after conversion.
-- That instruction outranks a prior design note, and two of the three
-- reasons do not survive contact with the state machine as it actually
-- stands:
--
--   Reason 2 assumes conversion is reachable from a fresh application.
--   It is not. Conversion refuses from any status but CONTACTED or
--   ASSESSMENT_BOOKED - a human has already rung the family and moved
--   the row by hand. A correction entered in error never reaches here,
--   and neither does a file opened before the family agreed.
--
--   Reason 3 assumes the grant would be anonymous. It is not.
--   hbh.grant_portal_access writes its own audit row stamped with
--   hbh.current_app_user(), which inside this transaction is the member
--   of staff who pressed Convert - not "the enrolment". The question
--   "who let this family in, and when" still has a name and a date.
--
--   Reason 1 stands, and is honoured rather than overruled: the grant
--   is still a named, dated, audited act. What changes is only that the
--   member of staff performs it in the same breath as the conversion
--   instead of having to remember a second step that no screen offered.
--
-- WHY IN THE FUNCTION AND NOT IN Go
--
-- Rule 2. Sequencing the two calls in ConvertEnrolment's transaction
-- would work today and would be a second copy of a business rule living
-- in the transport layer: a psql session, a future job, or any caller
-- that is not this one handler would still produce a family that cannot
-- log in. One function answers for every caller.
--
-- WHAT IS REUSED AND NOT REWRITTEN
--
-- hbh.grant_portal_access is called, not copied. It already:
--   - links an existing GUARDIAN account on the same mobile instead of
--     minting a rival to it (request_otp takes the lowest user_id, so a
--     second account silently resolves to the wrong one),
--   - is idempotent: the second call returns created=false,
--   - grants the GUARDIAN role, without which the family signs in and
--     sees an empty portal,
--   - takes FOR UPDATE on the guardian row.
-- None of that is re-implemented here. No password is created, no
-- plaintext exists, and the guardian sign-in model is untouched.
--
-- THE COST, STATED PLAINLY
--
-- Conversion now needs GUARDIAN.MANAGE as well as ENROLMENT.MANAGE.
-- Measured before writing this: the only two roles holding
-- ENROLMENT.MANAGE are CENTER_ADMIN and RECEPTION, and both already
-- hold GUARDIAN.MANAGE - so nobody who can convert today loses the
-- ability. A future role given ENROLMENT.MANAGE alone would find
-- conversion refused with HB200, and that refusal is correct: the
-- alternative is a family enrolled with no way in, which is the defect
-- this migration exists to end. It fails closed and loudly rather than
-- open and silently.
--
-- AND IT FAILS WHOLE OR NOT AT ALL. The grant runs inside the same
-- transaction and the same statement chain as the child, the guardian
-- and the link. There is no path that commits a converted family whose
-- account was not created - which was the half-converted state the
-- request asked to make impossible.
--
-- ORDER OF DEPLOYMENT: THIS MIGRATION MAY GO FIRST.
-- It raises no new SQLSTATE the API does not already map: HB200/HB201/
-- HB202 were added by 0085 and are handled. The API change that follows
-- adds a route; it does not depend on this one.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0125') THEN
    RAISE EXCEPTION 'migration 0125 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0085') THEN
    RAISE EXCEPTION 'migration 0085 must be applied first - it defines hbh.grant_portal_access';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'hbh' AND p.proname = 'grant_portal_access'
  ) THEN
    RAISE EXCEPTION 'hbh.grant_portal_access is missing - 0125 calls it rather than copying it';
  END IF;
END
$guard$;

-- Rebuilt from the LIVE definition (pg_get_functiondef), not from 0018:
-- 0101 added the assert_same_center line and rebuilding from the older
-- file would have quietly dropped the cross-centre guard.
CREATE OR REPLACE FUNCTION hbh.convert_enrolment(
  p_application_id integer,
  p_note_ar        text DEFAULT NULL
)
RETURNS TABLE (guardian_id integer, child_id integer, child_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_app hbh.enrolment_applications%ROWTYPE;
  l_g   integer;
  l_c   integer;
  l_no  text;
  l_uid integer;
BEGIN
  SELECT * INTO l_app FROM hbh.enrolment_applications
  WHERE application_id = p_application_id AND active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such application %', p_application_id USING ERRCODE = 'HB091';
  END IF;

  -- ADDED IN 0101, and placed above every check that follows: before the
  -- permission, before the state machine, and a long way before
  -- next_number. Kept in exactly that position.
  PERFORM hbh.assert_same_center('application', p_application_id, l_app.center_id);

  IF NOT hbh.has_permission('ENROLMENT.MANAGE') THEN
    RAISE EXCEPTION 'converting an application needs ENROLMENT.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  -- Converting twice would produce a second child for one family.
  IF l_app.status = 'ENROLLED' THEN
    RAISE EXCEPTION 'application % is already enrolled as child %',
                    p_application_id, l_app.converted_child_id
      USING ERRCODE = 'HB091';
  END IF;

  IF l_app.status NOT IN ('CONTACTED','ASSESSMENT_BOOKED') THEN
    RAISE EXCEPTION 'application % is % - contact the family before enrolling them',
                    p_application_id, l_app.status
      USING ERRCODE = 'HB091';
  END IF;

  l_no := hbh.next_number(l_app.center_id, 'CHILD');

  INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar,
                            birth_date, gender, national_id)
  VALUES (l_app.center_id, l_app.branch_id, l_no, l_app.child_name_ar,
          l_app.child_birth_date, l_app.child_gender, l_app.child_national_id)
  RETURNING hbh.children.child_id INTO l_c;

  SELECT g.guardian_id INTO l_g FROM hbh.guardians g
  WHERE g.center_id = l_app.center_id AND g.mobile = l_app.parent_mobile AND g.active_flg
  LIMIT 1;

  IF l_g IS NULL THEN
    INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile, national_id)
    VALUES (l_app.center_id, l_app.branch_id, l_app.parent_name_ar,
            l_app.parent_mobile, l_app.parent_national_id)
    RETURNING hbh.guardians.guardian_id INTO l_g;
  END IF;

  -- can_view_live_flg is NOT set here. Watching a child in therapy needs
  -- a recorded consent (D-24), and an enrolment form is not one.
  INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
  VALUES (l_g, l_c, l_app.relationship_code, true);

  -- ---------------------------------------------------------------
  -- THE ACCOUNT. New in 0125; everything above is unchanged.
  --
  -- A separate statement, and after the family exists: the guardian row
  -- has to be there for grant_portal_access to lock and update, and a
  -- row is only updated once per statement in this engine.
  --
  -- Not wrapped in an exception handler. A handler here would turn a
  -- refused grant into a converted family with no way in - silently -
  -- which is the exact state this migration exists to make impossible.
  -- If the grant raises, the whole conversion goes with it: no child, no
  -- guardian, no number consumed, application still unconverted.
  --
  -- HB202 ("no mobile") is reachable in principle and not in practice:
  -- the enrolment form refuses an empty parent_mobile, so a row that
  -- reached CONTACTED has one. If it ever does raise, refusing the
  -- conversion is the right answer - the mobile IS the login, and a
  -- family enrolled without one cannot sign in whatever we do here.
  -- ---------------------------------------------------------------
  SELECT gpa.user_id INTO l_uid FROM hbh.grant_portal_access(l_g) AS gpa;

  IF l_uid IS NULL THEN
    -- Defensive: the function returns a row on every success path, so
    -- reaching this means it returned none - and a conversion that
    -- reports success with no account is the defect, not the recovery.
    RAISE EXCEPTION 'portal access was not granted for guardian %', l_g
      USING ERRCODE = 'HB200';
  END IF;

  UPDATE hbh.enrolment_applications
     SET status = 'ENROLLED',
         converted_guardian_id = l_g,
         converted_child_id    = l_c,
         decided_by = hbh.current_user_id(),
         decided_at = now(),
         decision_note_ar = coalesce(p_note_ar, decision_note_ar)
   WHERE application_id = p_application_id;

  RETURN QUERY SELECT l_g, l_c, l_no;
END
$fn$;

COMMENT ON FUNCTION hbh.convert_enrolment(integer, text) IS
  'Turns an application into a child, a guardian, the link between them, and the portal account the family signs in with. Atomic: nothing commits unless all of it does. Needs ENROLMENT.MANAGE and GUARDIAN.MANAGE. HBH-010.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0125');
