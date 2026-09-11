-- =====================================================================
-- 0101 down - six centre guards come back off.
--
-- READ THIS BEFORE RUNNING IT. Running this file restores five PROVEN
-- cross-tenant write defects and one that was stopped only by accident:
--
--   set_password          account takeover. A USER.MANAGE holder in one
--                         centre can set another centre's staff password
--                         and then sign in as them.
--   grant_consent         can grant LIVE_VIEW on another centre's child -
--                         permission to WATCH THAT CHILD during a therapy
--                         session.
--   withdraw_consent      can revoke another centre's consents silently.
--   publish_session_note  can push another centre's clinical note to that
--                         family.
--   sell_package          can file a package and a ledger entry under
--                         another centre.
--   convert_enrolment     can create a child, a guardian and a family link
--                         inside another centre. In the proof run this one
--                         reached the line that allocates a child number
--                         and was stopped by a missing sequence, not by
--                         any check.
--
-- It exists because every migration in this project has a down, and a
-- down that quietly differs from its up is worse than one that is
-- dangerous and says so. It should not be run.
--
-- ORDER. Nothing here drops a type or a table, so the usual "children
-- before parents" problem does not arise. assert_same_center is left in
-- place: 0099 created it and still uses it.
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

CREATE OR REPLACE FUNCTION hbh.grant_consent(
  p_guardian_id integer, p_consent_type text, p_child_id integer DEFAULT NULL,
  p_text_version text DEFAULT 'v1', p_note_ar text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_g  hbh.guardians%ROWTYPE;
  l_id integer;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

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
    UPDATE hbh.guardian_children SET can_view_live_flg = true
     WHERE guardian_id = p_guardian_id AND child_id = p_child_id;
  END IF;

  RETURN l_id;
END
$fn$;

CREATE OR REPLACE FUNCTION hbh.withdraw_consent(
  p_guardian_id integer, p_consent_type text,
  p_child_id integer DEFAULT NULL, p_note_ar text DEFAULT NULL)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_g hbh.guardians%ROWTYPE;
  l_c hbh.consents%ROWTYPE;
BEGIN
  SELECT * INTO l_g FROM hbh.guardians WHERE guardian_id = p_guardian_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB082';
  END IF;

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

  IF p_consent_type = 'LIVE_VIEW' THEN
    UPDATE hbh.guardian_children SET can_view_live_flg = false
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
$fn$;

CREATE OR REPLACE FUNCTION hbh.publish_session_note(p_note_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE l_note hbh.session_notes%ROWTYPE;
BEGIN
  SELECT * INTO l_note FROM hbh.session_notes WHERE note_id = p_note_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such note %', p_note_id USING ERRCODE = 'HB032';
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

  PERFORM hbh.audit_attempt('READ', l_note.center_id, hbh.current_app_user(),
                            'note ' || p_note_id || ' published to guardian');
END
$fn$;

CREATE OR REPLACE FUNCTION hbh.convert_enrolment(
  p_application_id integer, p_note_ar text DEFAULT NULL)
RETURNS TABLE(guardian_id integer, child_id integer, child_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_app hbh.enrolment_applications%ROWTYPE;
  l_g   integer;
  l_c   integer;
  l_no  text;
BEGIN
  IF NOT hbh.has_permission('ENROLMENT.MANAGE') THEN
    RAISE EXCEPTION 'converting an application needs ENROLMENT.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  SELECT * INTO l_app FROM hbh.enrolment_applications
  WHERE application_id = p_application_id AND active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such application %', p_application_id USING ERRCODE = 'HB091';
  END IF;

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
$fn$;

CREATE OR REPLACE FUNCTION hbh.sell_package(p_child_id integer, p_package_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_pkg   hbh.service_packages%ROWTYPE;
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'selling a package needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  SELECT * INTO l_pkg   FROM hbh.service_packages WHERE package_id = p_package_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such package %', p_package_id USING ERRCODE = 'HB051';
  END IF;
  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id;

  INSERT INTO hbh.child_packages (center_id, branch_id, child_id, package_id, expires_on,
                                  sessions_total, price_amt)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_package_id,
          current_date + l_pkg.validity_days, l_pkg.sessions_cnt, l_pkg.price_amt)
  RETURNING child_package_id INTO l_id;

  INSERT INTO hbh.package_ledger (center_id, child_package_id, delta, balance_after, reason)
  VALUES (l_child.center_id, l_id, l_pkg.sessions_cnt, l_pkg.sessions_cnt, 'PURCHASE');

  RETURN l_id;
END
$fn$;

CREATE OR REPLACE FUNCTION hbh.publish_assessment(p_assessment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE l_a hbh.assessments%ROWTYPE;
BEGIN
  IF NOT hbh.has_permission('ASSESSMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing an assessment needs ASSESSMENT.PUBLISH' USING ERRCODE = 'HB111';
  END IF;

  SELECT * INTO l_a FROM hbh.assessments
  WHERE assessment_id = p_assessment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such assessment %', p_assessment_id USING ERRCODE = 'HB111';
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
$fn$;

CREATE OR REPLACE FUNCTION hbh.publish_attachment(p_attachment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NOT hbh.has_permission('ATTACHMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a file to a guardian needs ATTACHMENT.PUBLISH'
      USING ERRCODE = 'HB120';
  END IF;

  UPDATE hbh.attachments
     SET visibility = 'PARENT', approved_by = hbh.current_user_id(), approved_at = now()
   WHERE attachment_id = p_attachment_id;
END
$fn$;

DELETE FROM hbh.schema_migrations WHERE version = '0101';
