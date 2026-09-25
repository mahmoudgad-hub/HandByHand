-- =====================================================================
-- 0125 down - restores conversion WITHOUT the portal account
--
-- READ THIS BEFORE RUNNING IT. This down migration REINTRODUCES THE
-- DEFECT 0125 was written to end. After it, a family put through the
-- official enrolment door is created as a guardian and a child with
-- guardians.user_id NULL, reaches the login screen, types the mobile
-- they gave the centre, and is not recognised.
--
-- And the failure is invisible from outside: D-11 means the screen
-- never says "not registered", so it looks exactly like a family
-- mistyping their number. Nobody reports it; the centre concludes the
-- parent is confused. That is how the defect survived this long.
--
-- It also does NOT undo what the forward migration did to data:
-- accounts already created by a conversion stay, and guardians.user_id
-- stays filled. That is correct - those families can sign in, and
-- taking that away would be a second defect rather than a rollback.
-- Only the future behaviour reverts.
--
-- If the reason for rolling back is that conversion is being refused
-- with HB200, the cause is a role holding ENROLMENT.MANAGE without
-- GUARDIAN.MANAGE. Granting that permission to the role fixes it
-- forward; this file fixes it by making the loop silent again.
--
-- The body below is the pre-0125 definition, rebuilt from the live
-- function as it stood after 0101 - including the assert_same_center
-- line, which must not be lost on the way back.
-- =====================================================================

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
BEGIN
  SELECT * INTO l_app FROM hbh.enrolment_applications
  WHERE application_id = p_application_id AND active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such application %', p_application_id USING ERRCODE = 'HB091';
  END IF;

  PERFORM hbh.assert_same_center('application', p_application_id, l_app.center_id);

  IF NOT hbh.has_permission('ENROLMENT.MANAGE') THEN
    RAISE EXCEPTION 'converting an application needs ENROLMENT.MANAGE' USING ERRCODE = 'HB092';
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

COMMENT ON FUNCTION hbh.convert_enrolment(integer, text) IS
  'Turns an application into a guardian and a child. Does NOT create the portal account - see 0125 for why that is a defect.';

DELETE FROM hbh.schema_migrations WHERE version = '0125';
