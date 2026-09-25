-- =====================================================================
-- Hand By Hand (new) - migration 0144: an enrolment request from a
-- verified mobile creates the family; conversion only confirms it
-- (HBH-058 · 10-FEAT §7.1 EN-D3, §7.2 EN-04 and EN-05, OD-01, OD-32)
--
-- Until now an enrolment request was a row in ONE table, and the guardian
-- and the child were born when reception converted it (K-03). OD-01 moves
-- that birth to the moment of submission - but only for a caller who has
-- PROVED they own the mobile (0131's verify_mobile). The verified writer
-- is not anonymous: their identity is the number they proved.
--
-- ---------------------------------------------------------------------
-- WHAT CHANGES
--
--   EN-D3  enrolment_applications.guardian_id · child_id · verification_id,
--          filled at submission. converted_guardian_id/converted_child_id
--          STAY: they explain every row from before this migration and
--          are not backfilled. A v2 conversion fills them too, because
--          ck_enr_converted ties ENROLLED to them and they are true.
--
--   EN-04  submit_enrolment v2 - three optional parameters appended:
--          p_verification_id, p_guardian_id, p_child_id, p_child_is_new;
--          two result columns appended: result, candidates.
--
--   EN-05  convert_enrolment v3 - a linked request creates nothing: it is
--          confirmed ENROLLED and the family gets its portal account in
--          the same transaction. An unlinked (historic or anonymous)
--          request takes the existing creation branch, marked as such.
--
-- ---------------------------------------------------------------------
-- WHY IT IS SAFE TO LAND BEFORE THE ROUTES (EN-07) AND THE SCREENS
--
-- ENROLMENT_REQUIRE_VERIFICATION = false. With no p_verification_id the
-- function is v1, line for line: an unlinked row, rate-limited, converted
-- later by the historic branch. That is exactly what the website does
-- today, so today's form keeps working the minute this lands. When the
-- API and the web send a verification, the centre turns the parameter to
-- true and an unverified submission is refused. The same shape the owner
-- accepted for INVOICE_REQUIRE_CATALOGUE_PRICE.
--
-- A verification that is SENT but does not hold never falls back to v1.
-- Falling back would let anybody bypass the proof by sending a bad one.
--
-- NO NEW SQLSTATE. submit_enrolment answers in band, as it always has -
-- a refusal to an anonymous caller is data for the server (store/
-- enrolment.go: "Reason is for the SERVER"), not an exception. New
-- reasons, all returned, never raised:
--
--   VERIFICATION_REQUIRED  the proof is missing (when required), or does
--                          not hold: unknown, another centre, another
--                          purpose, another mobile, not verified, expired,
--                          or already used by a different submission. ONE
--                          answer for all of them - telling "not found"
--                          from "not for this mobile" is an oracle.
--   AMBIGUOUS              nothing written, the proof NOT consumed;
--                          result says which (AMBIGUOUS_GUARDIAN /
--                          AMBIGUOUS_CHILD) and candidates lists the
--                          choices. Resubmit with the same verification
--                          and p_guardian_id, or p_child_id, or
--                          p_child_is_new.
--   NO_SUCH_CHOICE         a p_guardian_id or p_child_id that is not this
--                          number's guardian / this guardian's child. One
--                          answer, not "missing" vs "not yours".
--   ALREADY_OPEN           OD-32, UC-18: this guardian already has an open
--                          request (NEW, CONTACTED, ASSESSMENT_BOOKED) for
--                          this child. No second row; the existing number
--                          and ok = true. The same answer to a retry of a
--                          submission that already succeeded.
--   CONTACT_CENTER         the latest request for this child was REJECTED
--                          or DUPLICATE. No detail of the decision.
--
-- The API reads ok, reason, application_no by name, so the appended
-- columns and parameters change nothing for the call it makes today.
--
-- ---------------------------------------------------------------------
-- TWO DEPARTURES FROM THE HAND-OFF, EACH SAID TO BUSINESS ANALYSIS
--
-- 1. origin_reference_id is written AFTER the application exists, in the
--    same transaction, not taken from nextval first. trg_origin_immutable
--    refuses CHANGING a recorded value and allows recording one where
--    there was none (its own comment: "allowed, once"), and
--    application_id is GENERATED ALWAYS - reserving it would need
--    OVERRIDING SYSTEM VALUE. The child is born with NULL and receives
--    the number once; the trigger then freezes it.
--
-- 2. convert_enrolment keeps its order: read, assert_same_center,
--    permission. 0101 placed the centre check above everything on
--    purpose and its comment says to keep it there; x2's cross-centre
--    proof reads HB232 from it. Moving the permission first is a change
--    of refusal for callers that exist today and is not needed for EN-05.
--
-- ---------------------------------------------------------------------
-- RACE. Two verified submissions for one new number in the same second
-- would both see NONE and both create a guardian - there is no unique
-- index on guardians.mobile any more (OD-26 withdrew EN-D5). A
-- transaction-scoped advisory lock on (centre, mobile) serialises them;
-- the second then finds the first one's guardian.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0144') THEN
    RAISE EXCEPTION 'migration 0144 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0143') THEN
    RAISE EXCEPTION 'migration 0143 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'hbh' AND table_name = 'enrolment_applications'
               AND column_name IN ('guardian_id', 'child_id', 'verification_id')) THEN
    RAISE EXCEPTION 'enrolment_applications already has a link column - somebody built this elsewhere';
  END IF;
END
$guard$;

-- =====================================================================
-- EN-D3
-- =====================================================================
ALTER TABLE hbh.enrolment_applications
  ADD COLUMN guardian_id     integer REFERENCES hbh.guardians (guardian_id),
  ADD COLUMN child_id        integer REFERENCES hbh.children (child_id),
  ADD COLUMN verification_id bigint  REFERENCES hbh.mobile_verifications (verification_id),
  ADD CONSTRAINT ck_enr_linked CHECK ((guardian_id IS NULL) = (child_id IS NULL)),
  -- A linked request was verified; an unlinked one was not. The two
  -- never mix, so the conversion branch can trust guardian_id alone.
  ADD CONSTRAINT ck_enr_linked_verified CHECK ((guardian_id IS NULL) = (verification_id IS NULL));

CREATE INDEX ix_enr_linked_guardian ON hbh.enrolment_applications (guardian_id);
CREATE INDEX ix_enr_linked_child    ON hbh.enrolment_applications (child_id);
-- One proof, one request.
CREATE UNIQUE INDEX uix_enr_verification ON hbh.enrolment_applications (verification_id)
  WHERE verification_id IS NOT NULL;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'ENROLMENT_REQUIRE_VERIFICATION', 'false', 'BOOLEAN',
   'false = طلب الالتحاق بلا تحقّق من الجوال يُقبل بالشكل القديم (بلا إنشاء) · true = يُرفض. يُقلب بعد أن ترسل الواجهة التحقّق (OD-01 · EN-04).')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- =====================================================================
-- EN-04 · submit_enrolment v2
-- =====================================================================
DROP FUNCTION hbh.submit_enrolment(text, text, text, text, date, character, text, text, text,
                                   integer, text, text, text, text, inet);

CREATE FUNCTION hbh.submit_enrolment(
  p_center_code            text,
  p_parent_name_ar         text,
  p_parent_mobile          text,
  p_child_name_ar          text,
  p_child_birth_date       date,
  p_child_gender           character,
  p_parent_email           text    DEFAULT NULL,
  p_relationship_code      text    DEFAULT 'FATHER',
  p_main_concern_ar        text    DEFAULT NULL,
  p_preferred_service_id   integer DEFAULT NULL,
  p_address_ar             text    DEFAULT NULL,
  p_preferred_contact_time text    DEFAULT NULL,
  p_previous_therapy_ar    text    DEFAULT NULL,
  p_source_code            text    DEFAULT 'WEB',
  p_client_ip              inet    DEFAULT NULL,
  p_verification_id        bigint  DEFAULT NULL,
  p_guardian_id            integer DEFAULT NULL,
  p_child_id               integer DEFAULT NULL,
  p_child_is_new           boolean DEFAULT false)
RETURNS TABLE (ok boolean, reason text, application_no text, result text, candidates jsonb)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center   hbh.centers%ROWTYPE;
  l_per_mob  integer;
  l_per_ip   integer;
  l_no       text;
  l_mobile   text;
  l_v        hbh.mobile_verifications%ROWTYPE;
  l_app      hbh.enrolment_applications%ROWTYPE;
  l_g        integer;
  l_gmatch   text;
  l_c        integer;
  l_cmatch   text;
  l_new_g    boolean := false;
  l_new_c    boolean := false;
  l_child_no text;
  l_app_id   integer;
  l_list     jsonb;
BEGIN
  SELECT * INTO l_center FROM hbh.centers c
  WHERE c.code = p_center_code AND c.active_flg;
  IF NOT FOUND THEN
    -- Deliberately vague. A caller with no identity learns nothing
    -- about which centre codes exist.
    RETURN QUERY SELECT false, 'REJECTED', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;

  l_per_mob := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_MOBILE_DAY', '3')::integer;
  l_per_ip  := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_IP_HOUR',   '10')::integer;

  -- =================================================================
  -- NO PROOF: v1, unchanged, unless the centre requires the proof.
  -- =================================================================
  IF p_verification_id IS NULL THEN
    IF hbh.param(l_center.center_id, 'ENROLMENT_REQUIRE_VERIFICATION', 'false')::boolean THEN
      RETURN QUERY SELECT false, 'VERIFICATION_REQUIRED', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;

    IF (SELECT count(*) FROM hbh.enrolment_applications a
        WHERE a.parent_mobile = hbh.canonical_mobile(p_parent_mobile, l_center.country_code)
          AND a.submitted_at > now() - interval '1 day') >= l_per_mob THEN
      RETURN QUERY SELECT false, 'TOO_MANY_FOR_MOBILE', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;

    IF p_client_ip IS NOT NULL
       AND (SELECT count(*) FROM hbh.enrolment_applications a
            WHERE a.client_ip = p_client_ip
              AND a.submitted_at > now() - interval '1 hour') >= l_per_ip THEN
      RETURN QUERY SELECT false, 'TOO_MANY_FOR_IP', NULL::text, NULL::text, NULL::jsonb; RETURN;
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

    RETURN QUERY SELECT true, 'OK', l_no, 'CREATED'::text, NULL::jsonb; RETURN;
  END IF;

  -- =================================================================
  -- A PROOF WAS SENT. From here nothing falls back to v1.
  -- =================================================================

  -- 0122: compare the canonical form, never the raw input.
  BEGIN
    l_mobile := hbh.canonical_mobile(p_parent_mobile, l_center.country_code);
  EXCEPTION WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
    l_mobile := NULL;
  END;

  -- One submission per (centre, number) at a time: see RACE in the header.
  PERFORM pg_advisory_xact_lock(hashtext('enrolment:' || l_center.center_id || ':' || coalesce(l_mobile, '')));

  SELECT * INTO l_v FROM hbh.mobile_verifications v
  WHERE  v.verification_id = p_verification_id
    AND  v.center_id = l_center.center_id
    AND  v.purpose = 'ENROLMENT'
    AND  v.mobile_e164 IS NOT DISTINCT FROM l_mobile
    AND  l_mobile IS NOT NULL
    AND  v.verified_at IS NOT NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'VERIFICATION_REQUIRED', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;

  -- A proof already spent: a retry of the submission it paid for gets
  -- that submission back. Anything else is a spent proof.
  IF l_v.consumed_at IS NOT NULL THEN
    SELECT * INTO l_app FROM hbh.enrolment_applications a
    WHERE a.verification_id = l_v.verification_id AND a.active_flg;
    IF FOUND AND l_app.status IN ('NEW', 'CONTACTED', 'ASSESSMENT_BOOKED') THEN
      RETURN QUERY SELECT true, 'ALREADY_OPEN', l_app.application_no, 'ALREADY_OPEN'::text, NULL::jsonb; RETURN;
    ELSIF FOUND AND l_app.status IN ('REJECTED', 'DUPLICATE') THEN
      RETURN QUERY SELECT false, 'CONTACT_CENTER', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;
    RETURN QUERY SELECT false, 'VERIFICATION_REQUIRED', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;

  IF l_v.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'VERIFICATION_REQUIRED', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;

  -- The same limits as v1, on the canonical number.
  IF (SELECT count(*) FROM hbh.enrolment_applications a
      WHERE a.parent_mobile = l_mobile
        AND a.submitted_at > now() - interval '1 day') >= l_per_mob THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_MOBILE', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;
  IF p_client_ip IS NOT NULL
     AND (SELECT count(*) FROM hbh.enrolment_applications a
          WHERE a.client_ip = p_client_ip
            AND a.submitted_at > now() - interval '1 hour') >= l_per_ip THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_IP', NULL::text, NULL::text, NULL::jsonb; RETURN;
  END IF;

  -- ---------------------------------------------------------------
  -- The guardian. The caller proved the number, so every guardian on
  -- it is theirs to be shown - nothing beyond what belongs to them.
  -- ---------------------------------------------------------------
  IF p_guardian_id IS NOT NULL THEN
    SELECT g.guardian_id INTO l_g FROM hbh.guardians g
    WHERE g.guardian_id = p_guardian_id AND g.center_id = l_center.center_id
      AND g.mobile = l_mobile AND g.active_flg;
    IF NOT FOUND THEN
      RETURN QUERY SELECT false, 'NO_SUCH_CHOICE', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;
  ELSE
    SELECT m.result INTO l_gmatch FROM hbh.find_guardian_matches(l_center.center_id, l_mobile) m LIMIT 1;
    IF l_gmatch = 'EXACT' THEN
      SELECT m.guardian_id INTO l_g FROM hbh.find_guardian_matches(l_center.center_id, l_mobile) m LIMIT 1;
    ELSIF l_gmatch = 'AMBIGUOUS' THEN
      SELECT jsonb_agg(jsonb_build_object('guardian_id', m.guardian_id, 'full_name_ar', m.full_name_ar)
                       ORDER BY m.guardian_id)
        INTO l_list
      FROM hbh.find_guardian_matches(l_center.center_id, l_mobile) m;
      RETURN QUERY SELECT false, 'AMBIGUOUS', NULL::text, 'AMBIGUOUS_GUARDIAN'::text, l_list; RETURN;
    END IF;                                   -- NONE: created below
  END IF;

  IF l_g IS NOT NULL THEN
    PERFORM 1 FROM hbh.guardians g WHERE g.guardian_id = l_g FOR UPDATE;
  END IF;

  -- ---------------------------------------------------------------
  -- The child - only ever among THIS guardian's own (OD-07).
  -- ---------------------------------------------------------------
  IF p_child_id IS NOT NULL THEN
    SELECT c.child_id INTO l_c FROM hbh.children c
    JOIN hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
    WHERE c.child_id = p_child_id AND gc.guardian_id = l_g AND c.active_flg;
    IF l_g IS NULL OR NOT FOUND THEN
      RETURN QUERY SELECT false, 'NO_SUCH_CHOICE', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;
  ELSIF l_g IS NOT NULL AND NOT p_child_is_new THEN
    SELECT m.result INTO l_cmatch
    FROM hbh.find_beneficiary_matches(l_g, p_child_name_ar, p_child_birth_date) m LIMIT 1;
    IF l_cmatch = 'EXACT' THEN
      SELECT m.child_id INTO l_c
      FROM hbh.find_beneficiary_matches(l_g, p_child_name_ar, p_child_birth_date) m LIMIT 1;
    ELSIF l_cmatch = 'AMBIGUOUS' THEN
      SELECT jsonb_agg(jsonb_build_object('child_id', m.child_id, 'full_name_ar', m.full_name_ar,
                                          'birth_date', m.birth_date) ORDER BY m.child_id)
        INTO l_list
      FROM hbh.find_beneficiary_matches(l_g, p_child_name_ar, p_child_birth_date) m;
      RETURN QUERY SELECT false, 'AMBIGUOUS', NULL::text, 'AMBIGUOUS_CHILD'::text, l_list; RETURN;
    END IF;                                   -- NONE: created below
  END IF;

  -- ---------------------------------------------------------------
  -- OD-32: an open request for this child is returned, not repeated.
  -- ---------------------------------------------------------------
  IF l_c IS NOT NULL THEN
    SELECT * INTO l_app FROM hbh.enrolment_applications a
    WHERE a.guardian_id = l_g AND a.child_id = l_c AND a.active_flg
    ORDER BY a.submitted_at DESC
    LIMIT 1;
    IF FOUND AND l_app.status IN ('NEW', 'CONTACTED', 'ASSESSMENT_BOOKED') THEN
      RETURN QUERY SELECT true, 'ALREADY_OPEN', l_app.application_no, 'ALREADY_OPEN'::text, NULL::jsonb; RETURN;
    ELSIF FOUND AND l_app.status IN ('REJECTED', 'DUPLICATE') THEN
      RETURN QUERY SELECT false, 'CONTACT_CENTER', NULL::text, NULL::text, NULL::jsonb; RETURN;
    END IF;
  END IF;

  -- =================================================================
  -- WRITE. Every refusal is above this line (D-1).
  -- =================================================================
  IF l_g IS NULL THEN
    INSERT INTO hbh.guardians (center_id, full_name_ar, mobile, email, registration_source)
    VALUES (l_center.center_id, p_parent_name_ar, l_mobile, p_parent_email, 'ENROLMENT_REQUEST')
    RETURNING hbh.guardians.guardian_id INTO l_g;
    l_new_g := true;
  END IF;

  IF l_c IS NULL THEN
    l_child_no := hbh.next_number(l_center.center_id, 'CHILD');
    INSERT INTO hbh.children (center_id, child_no, full_name_ar, birth_date, gender, origin_source)
    VALUES (l_center.center_id, l_child_no, p_child_name_ar, p_child_birth_date, p_child_gender,
            'ENROLMENT_REQUEST')
    RETURNING hbh.children.child_id INTO l_c;
    l_new_c := true;

    -- can_view_live_flg is NOT set: an enrolment form is not a consent
    -- to watch a child in therapy (D-24), exactly as convert_enrolment.
    INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
    VALUES (l_g, l_c, coalesce(p_relationship_code, 'FATHER'), true);
  END IF;

  l_no := hbh.next_number(l_center.center_id, 'ENROL');

  INSERT INTO hbh.enrolment_applications (
    center_id, application_no, parent_name_ar, parent_mobile, parent_email,
    relationship_code, address_ar, preferred_contact_time,
    child_name_ar, child_birth_date, child_gender, main_concern_ar,
    previous_therapy_ar, preferred_service_id, source_code, client_ip,
    guardian_id, child_id, verification_id)
  VALUES (
    l_center.center_id, l_no, p_parent_name_ar, l_mobile, p_parent_email,
    coalesce(p_relationship_code, 'FATHER'), p_address_ar, p_preferred_contact_time,
    p_child_name_ar, p_child_birth_date, p_child_gender, p_main_concern_ar,
    p_previous_therapy_ar, p_preferred_service_id, p_source_code, p_client_ip,
    l_g, l_c, l_v.verification_id)
  RETURNING hbh.enrolment_applications.application_id INTO l_app_id;

  -- Recorded once, where there was nothing; trg_origin_immutable then
  -- freezes it. A child who already existed keeps the origin they had.
  IF l_new_c THEN
    UPDATE hbh.children SET origin_reference_id = l_app_id WHERE child_id = l_c;
  END IF;

  UPDATE hbh.mobile_verifications SET consumed_at = now()
  WHERE verification_id = l_v.verification_id;

  PERFORM hbh.audit_attempt('READ', l_center.center_id, 'mobile:' || right(l_mobile, 4),
                            'enrolment application ' || l_no || ' submitted (verified; guardian '
                            || CASE WHEN l_new_g THEN 'created' ELSE 'matched' END || ', child '
                            || CASE WHEN l_new_c THEN 'created' ELSE 'matched' END || ')',
                            p_client_ip);

  RETURN QUERY SELECT true, 'OK', l_no, 'CREATED'::text, NULL::jsonb;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.submit_enrolment(text, text, text, text, date, character, text, text, text,
                                               integer, text, text, text, text, inet,
                                               bigint, integer, integer, boolean) TO hbh_app;

-- =====================================================================
-- EN-05 · convert_enrolment v3
--
-- Rebuilt from pg_get_functiondef, not from 0018: assert_same_center
-- (0101), the atomic grant (0125) and - through grant_portal_access -
-- HB204 (0126) and HB261 (0140) all stay exactly where they are.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.convert_enrolment(p_application_id integer, p_note_ar text DEFAULT NULL::text)
 RETURNS TABLE(guardian_id integer, child_id integer, child_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
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

  IF l_app.guardian_id IS NOT NULL THEN
    -- ---------------------------------------------------------------
    -- 0144 · A LINKED REQUEST. The family was created when the verified
    -- request arrived; converting it confirms, and creates nothing.
    -- ---------------------------------------------------------------
    l_g := l_app.guardian_id;
    l_c := l_app.child_id;
    SELECT c.child_no INTO l_no FROM hbh.children c WHERE c.child_id = l_c;
  ELSE
    -- ---------------------------------------------------------------
    -- 0144 · THE HISTORIC PATH - a request from before 0144, or one sent
    -- without a verification while ENROLMENT_REQUIRE_VERIFICATION is
    -- false. Unchanged; marked in the attempt log below so a count of
    -- families still born this way is one query.
    -- ---------------------------------------------------------------
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

    PERFORM hbh.audit_attempt('READ', l_app.center_id, hbh.current_portal_user(),
                              'convert_enrolment: historic path (unlinked request) for application '
                              || l_app.application_no, NULL);
  END IF;

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

  -- converted_* are filled on both paths: ck_enr_converted ties ENROLLED
  -- to them, and on a linked request they are simply true.
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
$function$;

-- =====================================================================
-- THE PROOF - structural. Behaviour is proved in a rolled-back
-- transaction before this file is placed.
-- =====================================================================
DO $verify$
BEGIN
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'submit_enrolment' AND pronamespace = 'hbh'::regnamespace) <> 1 THEN
    RAISE EXCEPTION 'submit_enrolment must exist exactly once';
  END IF;
  IF NOT has_function_privilege('hbh_app',
       'hbh.submit_enrolment(text,text,text,text,date,character,text,text,text,integer,text,text,text,text,inet,bigint,integer,integer,boolean)',
       'EXECUTE') THEN
    RAISE EXCEPTION 'hbh_app lost EXECUTE on submit_enrolment';
  END IF;
  -- The internal matchers stay internal (0132): granting them would build
  -- the registration oracle the verified path exists to avoid.
  IF EXISTS (SELECT 1 FROM information_schema.routine_privileges
             WHERE grantee = 'hbh_app'
               AND routine_name IN ('find_guardian_matches', 'find_beneficiary_matches')) THEN
    RAISE EXCEPTION 'find_*_matches must carry no grant to hbh_app';
  END IF;
  IF (SELECT prosrc FROM pg_proc WHERE oid = 'hbh.convert_enrolment(integer,text)'::regprocedure)
     !~ 'assert_same_center.*has_permission.*grant_portal_access' THEN
    RAISE EXCEPTION 'convert_enrolment lost assert_same_center, its permission, or the atomic grant - or their order';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0144');
