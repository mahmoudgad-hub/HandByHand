-- =====================================================================
-- Hand By Hand (new) - migration 0101: the rest of the raw identifiers.
--
-- NUMBER RESERVED BEFORE WRITING. 0098 (users_mobile_unique) and 0100
-- (available_slots) belong to another session working in this same tree;
-- both were applied while this work was in progress. 0100 was already
-- taken on disk AND in hbh.schema_migrations when this file was started,
-- so 0101 was claimed first - an empty file with a RESERVED header -
-- and only then written. Two files on one number is a migration that
-- vanishes without a word, and this tree has no version control to
-- recover it from.
--
-- NO NEW SQLSTATE, SO THE API DOES NOT HAVE TO GO FIRST. Everything
-- here raises HB232, which 0099 introduced and ops_handlers.go already
-- maps to 403 FORBIDDEN.
--
-- ---------------------------------------------------------------------
-- WHAT 0099 LEFT, AND WHAT PROVING IT COST
--
-- 0099 fixed the two defects that had been demonstrated. The systemic
-- check it shipped with - tests/db/p00_center_ownership.sql - then named
-- eight more. This migration closes them.
--
-- THE FIRST PROOF HARNESS REPORTED ALL SIX AS ALREADY DENIED. It ran
-- each call in a savepoint and inferred "denied" from the absence of a
-- success row, so a refusal for ANY reason looked like the refusal under
-- test. convert_enrolment was being turned away by a business rule about
-- application status and counted as a security pass. Rewritten to record
-- the SQLSTATE rather than the mere fact of an exception, the same
-- database answered:
--
--   sell_package             SUCCEEDED
--   publish_session_note     SUCCEEDED
--   grant_consent LIVE_VIEW  SUCCEEDED
--   withdraw_consent         SUCCEEDED
--   set_password             SUCCEEDED
--   convert_enrolment        HB010 - stopped by a missing number series,
--                            having passed every authorization check
--
-- Five proven, one that got as far as creating a child and was saved by
-- an unrelated accident. "Assert the error code itself" is the first
-- line of CLAUDE.md's testing section and it was worth the rewrite.
--
-- ---------------------------------------------------------------------
-- WHAT EACH ONE COULD DO ACROSS A TENANT BOUNDARY
--
--   set_password          ACCOUNT TAKEOVER. A USER.MANAGE holder in one
--                         centre could set the password of another
--                         centre's staff account, then sign in as them.
--                         The worst of the six.
--   grant_consent         LIVE_VIEW decides who may WATCH A CHILD DURING
--                         A THERAPY SESSION. A stranger could grant it.
--   withdraw_consent      and revoke it - including SMS_NOTIFY, silently
--                         stopping another centre's family being told
--                         anything.
--   publish_session_note  a clinical note about another centre's child,
--                         pushed to that family.
--   convert_enrolment     a child, a guardian and a family link created
--                         inside another centre.
--   sell_package          a package and a ledger entry filed under
--                         another centre, where the caller cannot see or
--                         undo them.
--
-- ---------------------------------------------------------------------
-- THE ORDER INSIDE EVERY FUNCTION, and it is the point of the exercise:
--
--     1. read the row          (FOR UPDATE where it will be written)
--     2. does it exist         (the pre-existing NOT FOUND answer)
--     3. IS IT MINE            <- assert_same_center / can_access_child
--     4. may I do this         has_permission
--     5. is this state legal   the existing business rule
--     6. ONLY THEN mutate
--
-- Authorization before mutation, always. Not one of these functions may
-- write and then raise: an exception unwinds the transaction and takes
-- the write with it, but this project has twice shipped a function that
-- counted on that and twice been wrong (verify_otp, consume_package_session).
-- The shape is avoided rather than reasoned about.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0101') THEN
    RAISE EXCEPTION 'migration 0101 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0100') THEN
    RAISE EXCEPTION 'migration 0100 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- 1. set_password  - ACCOUNT TAKEOVER, and the reason this is first
--
-- WHY GUARDING IT IS SAFE, checked before writing rather than hoped:
-- hbh.redeem_password_setup does NOT call this function. It writes
-- password_hash directly, which is the one path that runs with no
-- identity at all - a person setting their first password has no
-- session yet. Had it called set_password, a centre guard here would
-- have locked every new member of staff out of the product.
--
-- The two real callers are hbh.change_own_password (self, therefore the
-- same centre by construction) and hbh.create_user (a user it has just
-- created in the caller's own centre). Both pass.
--
-- THE CENTRE CHECK SITS AFTER THE "no such user" ANSWER AND BEFORE THE
-- PERMISSION CHECK. After, because a caller who names a user id that
-- does not exist should hear the same thing they always have. Before,
-- because a cross-tenant attempt by somebody who genuinely holds
-- USER.MANAGE must be recorded as a tenant violation, not as a
-- permission they in fact have.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.set_password(p_user_id integer, p_password text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
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
$$;

-- =====================================================================
-- 2. grant_consent  - WHO MAY WATCH A CHILD IN THERAPY
--
-- The existing self-or-GUARDIAN.MANAGE test is kept exactly. What is
-- added is the question it never asked: whose guardian is this.
--
-- The guardian's OWN centre is the subject, not the child's. They are
-- the same centre in every well-formed row - guardian_children cannot
-- span centres - but the guardian is what the caller named, so the
-- guardian is what is checked. Checking the derived thing instead would
-- be a guess about an invariant rather than a test of the input.
--
-- SELF-SERVICE IS UNAFFECTED. A guardian recording their own consent
-- through the portal is in their own centre by construction.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.grant_consent(
  p_guardian_id  integer,
  p_consent_type text,
  p_child_id     integer DEFAULT NULL,
  p_text_version text    DEFAULT 'v1',
  p_note_ar      text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_g   hbh.guardians%ROWTYPE;
  l_id  integer;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('guardian', p_guardian_id, l_g.center_id);

  IF l_g.user_id IS DISTINCT FROM hbh.current_user_id()
     AND NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to record a consent for guardian %', p_guardian_id
      USING ERRCODE = 'HB082';
  END IF;

  IF p_consent_type IN ('LIVE_VIEW','PHOTO_USE') THEN
    IF p_child_id IS NULL THEN
      RAISE EXCEPTION '% is a consent about a child and needs one', p_consent_type
        USING ERRCODE = 'HB080';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM hbh.guardian_children gc
                   WHERE gc.guardian_id = p_guardian_id AND gc.child_id = p_child_id
                     AND gc.active_flg) THEN
      RAISE EXCEPTION 'guardian % is not linked to child %', p_guardian_id, p_child_id
        USING ERRCODE = 'HB082';
    END IF;
  ELSIF p_child_id IS NOT NULL THEN
    RAISE EXCEPTION '% is a consent about the guardian and takes no child', p_consent_type
      USING ERRCODE = 'HB080';
  END IF;

  INSERT INTO hbh.consents (center_id, guardian_id, child_id, consent_type,
                            granted_flg, granted_at, withdrawn_at,
                            recorded_by, text_version, note_ar)
  VALUES (l_g.center_id, p_guardian_id, p_child_id, p_consent_type,
          true, now(), NULL, hbh.current_user_id(), p_text_version, p_note_ar)
  ON CONFLICT (guardian_id, coalesce(child_id, 0), consent_type) WHERE active_flg
  DO UPDATE SET granted_flg  = true,
                granted_at   = now(),
                withdrawn_at = NULL,
                recorded_by  = hbh.current_user_id(),
                text_version = excluded.text_version,
                note_ar      = excluded.note_ar
  RETURNING consent_id INTO l_id;

  INSERT INTO hbh.consent_events (center_id, consent_id, guardian_id, child_id, consent_type,
                                  action, text_version, note_ar, recorded_by)
  VALUES (l_g.center_id, l_id, p_guardian_id, p_child_id, p_consent_type,
          'GRANTED', p_text_version, p_note_ar, hbh.current_user_id());

  IF p_consent_type = 'LIVE_VIEW' THEN
    UPDATE hbh.guardian_children
       SET can_view_live_flg = true
     WHERE guardian_id = p_guardian_id AND child_id = p_child_id;
  END IF;

  RETURN l_id;
END
$$;

-- =====================================================================
-- 3. withdraw_consent
--
-- The mirror, and it matters as much as the grant: withdrawing
-- SMS_NOTIFY for another centre's family stops them being told anything,
-- silently, with a consent event on the record saying they asked for it.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.withdraw_consent(
  p_guardian_id  integer,
  p_consent_type text,
  p_child_id     integer DEFAULT NULL,
  p_note_ar      text    DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_g  hbh.guardians%ROWTYPE;
  l_c  hbh.consents%ROWTYPE;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('guardian', p_guardian_id, l_g.center_id);

  IF l_g.user_id IS DISTINCT FROM hbh.current_user_id()
     AND NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'not permitted to withdraw a consent for guardian %', p_guardian_id
      USING ERRCODE = 'HB082';
  END IF;

  SELECT * INTO l_c FROM hbh.consents
  WHERE guardian_id = p_guardian_id
    AND coalesce(child_id, 0) = coalesce(p_child_id, 0)
    AND consent_type = p_consent_type
    AND active_flg
  FOR UPDATE;

  IF NOT FOUND OR NOT l_c.granted_flg THEN
    RETURN false;
  END IF;

  -- The switch closes FIRST. If anything below failed, a family that
  -- said no would not be left watchable for the rest of the transaction.
  IF p_consent_type = 'LIVE_VIEW' THEN
    UPDATE hbh.guardian_children
       SET can_view_live_flg = false
     WHERE guardian_id = p_guardian_id AND child_id = p_child_id;
  END IF;

  UPDATE hbh.consents
     SET granted_flg  = false,
         withdrawn_at = now(),
         recorded_by  = hbh.current_user_id(),
         note_ar      = coalesce(p_note_ar, note_ar)
   WHERE consent_id = l_c.consent_id;

  INSERT INTO hbh.consent_events (center_id, consent_id, guardian_id, child_id, consent_type,
                                  action, text_version, note_ar, recorded_by)
  VALUES (l_g.center_id, l_c.consent_id, p_guardian_id, p_child_id, p_consent_type,
          'WITHDRAWN', l_c.text_version, p_note_ar, hbh.current_user_id());

  RETURN true;
END
$$;

-- =====================================================================
-- 4. publish_session_note  - A CLINICAL NOTE REACHING A FAMILY
--
-- BOTH questions, because the row answers both. session_notes carries a
-- center_id AND a child_id, so the centre check and the child-access
-- check are each available and each says something the other does not:
-- the centre stops a stranger, and can_access_child stops a colleague
-- inside this centre who has no business with this child.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.publish_session_note(p_note_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_note hbh.session_notes%ROWTYPE;
BEGIN
  SELECT * INTO l_note FROM hbh.session_notes WHERE note_id = p_note_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such note %', p_note_id USING ERRCODE = 'HB032';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('note', p_note_id, l_note.center_id);

  IF NOT hbh.can_access_child(l_note.child_id) THEN
    RAISE EXCEPTION 'note % is about a child you may not act for', p_note_id
      USING ERRCODE = 'HB232';
  END IF;

  IF NOT hbh.has_permission('NOTE.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a note to a guardian needs NOTE.PUBLISH'
      USING ERRCODE = 'HB032';
  END IF;

  UPDATE hbh.session_notes
     SET visibility   = 'PARENT',
         is_draft_flg = false,
         approved_by  = hbh.current_user_id(),
         approved_at  = now()
   WHERE note_id = p_note_id;

  -- Logged as an attempt-class record so it survives a rollback: a
  -- clinical note reaching a family is not something the log may lose.
  PERFORM hbh.audit_attempt('READ', l_note.center_id, hbh.current_app_user(),
                            'note ' || p_note_id || ' published to guardian');
END
$$;

-- =====================================================================
-- 5. convert_enrolment  - A CHILD, A GUARDIAN AND A LINK IN SOMEBODY
--                         ELSE'S CENTRE
--
-- The guard goes in BEFORE the first INSERT and before next_number, so
-- nothing is created and no number is consumed. next_number advances a
-- sequence: had the check sat lower down, a refused cross-tenant attempt
-- would still have burned a child number out of another centre's series,
-- leaving a permanent gap nobody could explain.
--
-- This is the one the proof harness could not complete, and the reason
-- is worth recording: it failed with HB010 because the test centre had
-- no CHILD number series. It had already passed ENROLMENT.MANAGE, read
-- the application, and reached the line that allocates the number. An
-- accident of fixture construction stood between it and a child record
-- in another centre.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.convert_enrolment(
  p_application_id integer,
  p_note_ar        text DEFAULT NULL)
RETURNS TABLE(guardian_id integer, child_id integer, child_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_app hbh.enrolment_applications%ROWTYPE;
  l_g   integer;
  l_c   integer;
  l_no  text;
BEGIN
  SELECT * INTO l_app FROM hbh.enrolment_applications
  WHERE application_id = p_application_id AND active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such application %', p_application_id USING ERRCODE = 'HB091';
  END IF;

  -- ADDED IN 0101, and placed above every check that follows: before the
  -- permission, before the state machine, and a long way before
  -- next_number.
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
$$;

-- =====================================================================
-- 6. sell_package
--
-- can_access_child rather than assert_same_center, because the caller
-- named a CHILD and that helper is what this schema uses for that
-- question everywhere else. It is centre-bound for staff, so it answers
-- the tenant question too.
--
-- AND THE MISSING "no such child" ANSWER IS ADDED. The function read the
-- child into a row variable and never checked FOUND; a caller naming a
-- child that does not exist got a NULL row, and the INSERT then failed
-- on a NOT NULL constraint with a message about center_id. The check
-- has to be there anyway for the access test below it to mean anything.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.sell_package(p_child_id integer, p_package_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_pkg   hbh.service_packages%ROWTYPE;
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB051';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('child', p_child_id, l_child.center_id);

  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'child % is not one you may act for', p_child_id
      USING ERRCODE = 'HB232';
  END IF;

  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'selling a package needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_pkg FROM hbh.service_packages WHERE package_id = p_package_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such package %', p_package_id USING ERRCODE = 'HB051';
  END IF;

  -- The package catalogue is the centre's own, so a package from another
  -- centre sold to a child of this one would be just as wrong in the
  -- other direction.
  PERFORM hbh.assert_same_center('package', p_package_id, l_pkg.center_id);

  INSERT INTO hbh.child_packages (center_id, branch_id, child_id, package_id, expires_on,
                                  sessions_total, price_amt)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_package_id,
          current_date + l_pkg.validity_days, l_pkg.sessions_cnt, l_pkg.price_amt)
  RETURNING child_package_id INTO l_id;

  INSERT INTO hbh.package_ledger (center_id, child_package_id, delta, balance_after, reason)
  VALUES (l_child.center_id, l_id, l_pkg.sessions_cnt, l_pkg.sessions_cnt, 'PURCHASE');

  RETURN l_id;
END
$$;

-- =====================================================================
-- 7 and 8. publish_assessment, publish_attachment  - NO ROUTE TODAY
--
-- Hardened anyway. "Not reachable" is a property of the router, and the
-- router changes far more often than the schema does; a function that is
-- safe only because nothing calls it is a defect with a timer on it.
--
-- publish_assessment NOTIFIES GUARDIANS, so an unguarded one would have
-- delivered a message about another centre's child the moment a route
-- appeared.
--
-- publish_attachment did not read its row at all - it was a blind UPDATE
-- keyed on the caller's number. It now reads the attachment, establishes
-- the child, and asks both questions. An attachment may hang off things
-- other than a child, so the child test is applied only when there is
-- one; the centre test always applies.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.publish_assessment(p_assessment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_a hbh.assessments%ROWTYPE;
BEGIN
  SELECT * INTO l_a FROM hbh.assessments
  WHERE assessment_id = p_assessment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such assessment %', p_assessment_id USING ERRCODE = 'HB111';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('assessment', p_assessment_id, l_a.center_id);

  IF NOT hbh.can_access_child(l_a.child_id) THEN
    RAISE EXCEPTION 'assessment % is about a child you may not act for', p_assessment_id
      USING ERRCODE = 'HB232';
  END IF;

  IF NOT hbh.has_permission('ASSESSMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing an assessment needs ASSESSMENT.PUBLISH' USING ERRCODE = 'HB111';
  END IF;

  IF l_a.status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'assessment % is % - only a COMPLETED one may be published',
                    p_assessment_id, l_a.status
      USING ERRCODE = 'HB110';
  END IF;

  UPDATE hbh.assessments
     SET status = 'PUBLISHED', published_by = hbh.current_user_id(), published_at = now()
   WHERE assessment_id = p_assessment_id;

  PERFORM hbh.notify_guardians(l_a.child_id, 'ASSESSMENT_PUBLISHED',
                               'نتيجة تقييم جديدة', NULL, 'ASSESSMENT', p_assessment_id);

  PERFORM hbh.audit_attempt('READ', l_a.center_id, hbh.current_app_user(),
                            'assessment ' || p_assessment_id || ' published to guardian');
END
$$;

CREATE OR REPLACE FUNCTION hbh.publish_attachment(p_attachment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_att hbh.attachments%ROWTYPE;
BEGIN
  SELECT * INTO l_att FROM hbh.attachments
  WHERE attachment_id = p_attachment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such attachment %', p_attachment_id USING ERRCODE = 'HB120';
  END IF;

  -- ADDED IN 0101.
  PERFORM hbh.assert_same_center('attachment', p_attachment_id, l_att.center_id);

  IF l_att.child_id IS NOT NULL AND NOT hbh.can_access_child(l_att.child_id) THEN
    RAISE EXCEPTION 'attachment % is about a child you may not act for', p_attachment_id
      USING ERRCODE = 'HB232';
  END IF;

  IF NOT hbh.has_permission('ATTACHMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a file to a guardian needs ATTACHMENT.PUBLISH'
      USING ERRCODE = 'HB120';
  END IF;

  UPDATE hbh.attachments
     SET visibility = 'PARENT', approved_by = hbh.current_user_id(), approved_at = now()
   WHERE attachment_id = p_attachment_id;
END
$$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0101');
