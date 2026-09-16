-- =====================================================================
-- 0122 - the per-mobile flood limit on the public form counts the
--        number the way the table STORES it
--
-- WHAT WAS WRONG. trg_enr_mobile_canon rewrites parent_mobile to E.164
-- on the way in, so a form that sends 01500000063 is stored as
-- +201500000063. The guard inside hbh.submit_enrolment kept comparing
-- against the RAW argument:
--
--     WHERE a.parent_mobile = p_parent_mobile
--
-- which, after canonicalisation, matches nothing - ever. The count is
-- always zero, so TOO_MANY_FOR_MOBILE can never be reached and
-- ENROLMENT_MAX_PER_MOBILE_DAY is not enforced at all.
--
-- This is the ONLY endpoint in the service that answers a caller with no
-- token, so it is the only place where a limit is the whole of the
-- protection. The hourly IP limit still worked - client_ip is not
-- canonicalised - so the door was not wide open; the per-mobile rule was
-- simply off, silently, and nothing raised.
--
-- HOW IT WAS FOUND, AND WHAT NEARLY HID IT. api phase 6 failed 49
-- checks. Forty-six were harmless: the suite looked its own rows up by
-- the number it had SENT, found nothing, and carried an empty id into
-- every later path - so /api/v1/enrolments//convert was cleaned by
-- ServeMux and answered 301, and the suite reported redirects where it
-- expected refusals. It read exactly like a broken route. The three
-- checks that mattered were in that noise, and they said what was true
-- by name: "the fourth is refused: expected 429, got 201".
--
-- THE CALL RAISES, IT DOES NOT RETURN NULL. hbh.canonical_mobile raises
-- HB173 on a number it cannot parse, so there is no null to fall back to
-- and no coalesce worth writing. A malformed submission is therefore
-- refused HERE rather than by the trigger a few lines later: the same
-- refusal, the same code, reached before hbh.next_number has burned an
-- application number on a row that was never going to exist.
--
-- Nothing else in the function changes. The body below is the live
-- definition with that single comparison rewritten.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.submit_enrolment(p_center_code text, p_parent_name_ar text, p_parent_mobile text, p_child_name_ar text, p_child_birth_date date, p_child_gender character, p_parent_email text DEFAULT NULL::text, p_relationship_code text DEFAULT 'FATHER'::text, p_main_concern_ar text DEFAULT NULL::text, p_preferred_service_id integer DEFAULT NULL::integer, p_address_ar text DEFAULT NULL::text, p_preferred_contact_time text DEFAULT NULL::text, p_previous_therapy_ar text DEFAULT NULL::text, p_source_code text DEFAULT 'WEB'::text, p_client_ip inet DEFAULT NULL::inet)
 RETURNS TABLE(ok boolean, reason text, application_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_center   hbh.centers%ROWTYPE;
  l_per_mob  integer;
  l_per_ip   integer;
  l_no       text;
BEGIN
  SELECT * INTO l_center FROM hbh.centers c
  WHERE c.code = p_center_code AND c.active_flg;
  IF NOT FOUND THEN
    -- Deliberately vague. A caller with no identity learns nothing
    -- about which centre codes exist.
    RETURN QUERY SELECT false, 'REJECTED', NULL::text; RETURN;
  END IF;

  l_per_mob := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_MOBILE_DAY', '3')::integer;
  l_per_ip  := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_IP_HOUR',   '10')::integer;

  IF (SELECT count(*) FROM hbh.enrolment_applications a
      WHERE a.parent_mobile = hbh.canonical_mobile(p_parent_mobile, l_center.country_code)
        AND a.submitted_at > now() - interval '1 day') >= l_per_mob THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_MOBILE', NULL::text; RETURN;
  END IF;

  IF p_client_ip IS NOT NULL
     AND (SELECT count(*) FROM hbh.enrolment_applications a
          WHERE a.client_ip = p_client_ip
            AND a.submitted_at > now() - interval '1 hour') >= l_per_ip THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_IP', NULL::text; RETURN;
  END IF;

  l_no := hbh.next_number(l_center.center_id, 'ENROL');

  INSERT INTO hbh.enrolment_applications (
    center_id, application_no, parent_name_ar, parent_mobile, parent_email,
    relationship_code, address_ar, preferred_contact_time,
    child_name_ar, child_birth_date, child_gender, main_concern_ar,
    previous_therapy_ar, preferred_service_id, source_code, client_ip)
  VALUES (
    l_center.center_id, l_no, p_parent_name_ar, p_parent_mobile, p_parent_email,
    p_relationship_code, p_address_ar, p_preferred_contact_time,
    p_child_name_ar, p_child_birth_date, p_child_gender, p_main_concern_ar,
    p_previous_therapy_ar, p_preferred_service_id, p_source_code, p_client_ip);

  -- Written outside the transaction, so a submission that later rolls
  -- back still leaves a trace of having been attempted.
  PERFORM hbh.audit_attempt('READ', l_center.center_id, 'anonymous',
                            'enrolment application ' || l_no || ' submitted', p_client_ip);

  RETURN QUERY SELECT true, 'OK', l_no;
END
$function$


;

-- ---------------------------------------------------------------------
-- Verification.
--
-- IT DOES NOT CALL submit_enrolment, ON PURPOSE. That function writes an
-- audit row through hbh.audit_attempt, and hbh.audit_log is append-only:
-- four calls here would leave four permanent records saying families
-- applied to this centre when nobody did, on every rebuild. A migration
-- that proves itself by faking product events puts a falsehood in the one
-- table meant to be the truth - the same trap as a fixture calling
-- withdraw_consent to reach "no consent here".
--
-- So this checks the two facts that make the guard sound, both read-only.
-- The BEHAVIOUR is proved by api phase 6, which asserts the refusal by
-- name: "the fourth is refused" expects 429, and "the refusal was
-- recorded with its real reason" expects TOO_MANY_FOR_MOBILE rather than
-- a refusal for any reason at all.
-- ---------------------------------------------------------------------
DO $verify$
DECLARE
  l_src    text;
  l_moved  integer;
  l_legacy integer;
BEGIN
  -- 1. The guard asks for the stored shape, not the raw argument.
  SELECT p.prosrc INTO l_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'hbh' AND p.proname = 'submit_enrolment';

  IF l_src !~ 'a\.parent_mobile\s*=\s*hbh\.canonical_mobile\(p_parent_mobile' THEN
    RAISE EXCEPTION
      '0122: the per-mobile guard does not canonicalise - it counts rows that cannot exist';
  END IF;

  -- 2. Canonicalising what is already stored does not MOVE it. That is
  --    what makes (1) enough: the trigger writes canon, the guard asks
  --    for canon, and the two meet on the same string.
  --
  --    Only rows the trigger actually wrote are asked - the ones already
  --    in E.164, which is the '+' test below. Rows written BEFORE the
  --    trigger existed are counted and reported, not canonicalised: one
  --    exists today, a ten-digit number, and hbh.canonical_mobile RAISES
  --    on it rather than returning null, so asking would abort this
  --    migration over a row it cannot affect. Nothing can be inserted in
  --    that shape any more - the trigger would raise first - and a
  --    migration that failed here would only teach the next person to
  --    delete data to make a migration pass.
  SELECT count(*) INTO l_legacy
    FROM hbh.enrolment_applications WHERE parent_mobile NOT LIKE '+%';

  SELECT count(*) INTO l_moved
    FROM hbh.enrolment_applications a
    JOIN hbh.centers c ON c.center_id = a.center_id
   WHERE a.parent_mobile LIKE '+%'
     AND hbh.canonical_mobile(a.parent_mobile, c.country_code) IS DISTINCT FROM a.parent_mobile;

  IF l_moved > 0 THEN
    RAISE EXCEPTION
      '0122: % stored mobiles canonicalise to something else - the guard would still miss them',
      l_moved;
  END IF;

  RAISE NOTICE '0122 verified: the guard counts the stored form (% pre-trigger rows skipped)', l_legacy;
END
$verify$;

INSERT INTO hbh.schema_migrations (version)
VALUES ('0122')
ON CONFLICT (version) DO NOTHING;
