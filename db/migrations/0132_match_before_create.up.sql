-- =====================================================================
-- Hand By Hand (new) - migration 0132: match before you create
-- (EN-03, OD-01 · OD-07)
--
-- OD-01 says the site creates ONLY WHAT IS MISSING, and that means
-- asking first whether the guardian and the beneficiary already exist.
-- These are the questions, asked one way for every door: the public
-- path in phase 2, and reception's POST /guardians and POST /children -
-- which today create duplicates freely, because nothing asks (C-07,
-- C-09).
--
-- Three answers, never two: EXACT · AMBIGUOUS · NONE. AMBIGUOUS is the
-- one that matters. OD-07: an uncertain match is NEVER merged
-- automatically - the candidates are shown and a person chooses, or
-- creates. A function that collapsed "probably the same child" into
-- EXACT would merge two siblings with the same first name the day one
-- of them mistyped a birth date.
--
-- ---------------------------------------------------------------------
-- AND THE SPEC, AS WRITTEN, WOULD HAVE BUILT A REGISTRATION ORACLE
--
-- match_guardian(center, mobile) granted to hbh_app answers one
-- question to anyone holding a token: IS THIS NUMBER REGISTERED HERE?
-- That is precisely what the login door was built not to disclose
-- (09-05): request_otp collapses "unknown number" and "locked account"
-- into the same silence so that nobody can walk a list of phone
-- numbers and learn which ones are families at this centre. A guardian
-- logged in to the portal would have been able to do exactly that.
--
-- So the matching lives in two layers:
--
--   find_guardian_matches · find_beneficiary_matches
--     The logic. SECURITY DEFINER, NO grant to hbh_app - the same
--     standing as notify_guardians and recalc_invoice. Only other
--     definer functions reach them; submit_enrolment v2 will, after the
--     caller has PROVED they hold the number (0131), which is the one
--     case where answering is not a disclosure.
--
--   match_guardian · match_beneficiary
--     The door reception uses. Gated on GUARDIAN.MANAGE, and the centre
--     is the CALLER'S, never a parameter - "a permission says what, it
--     never says which row", and eight functions in this schema once
--     wrote into whatever centre they were handed.
--
-- Reception can already look guardians up by mobile in the console, so
-- the gated door discloses nothing reception could not already see. The
-- only thing withheld is from people who were never meant to ask.
--
-- Error classes added here (grepped free):
--   HB255  not permitted to match, or not this centre's guardian
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0132') THEN
    RAISE EXCEPTION 'migration 0132 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0131') THEN
    RAISE EXCEPTION 'migration 0131 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%HB255%') THEN
    RAISE EXCEPTION 'HB255 is already raised by some function - grep and pick another';
  END IF;
END
$guard$;

-- =====================================================================
-- THE LOGIC - internal, ungranted
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.find_guardian_matches(p_center_id integer, p_mobile text)
RETURNS TABLE (result text, guardian_id integer, full_name_ar text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_mobile text;
  l_cc     text;
  l_n      integer;
BEGIN
  SELECT c.country_code INTO l_cc FROM hbh.centers c WHERE c.center_id = p_center_id;

  -- canonical_mobile both raises (HB170/HB173, unreadable) and returns
  -- NULL (empty) - measured, not assumed. Either way there is no number
  -- to match on, which is NONE, not an error the caller must handle.
  BEGIN
    l_mobile := hbh.canonical_mobile(p_mobile, l_cc);
  EXCEPTION WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
    l_mobile := NULL;
  END;

  IF l_mobile IS NULL THEN
    RETURN QUERY SELECT 'NONE'::text, NULL::integer, NULL::text;
    RETURN;
  END IF;

  SELECT count(*) INTO l_n FROM hbh.guardians g
  WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg;

  IF l_n = 0 THEN
    RETURN QUERY SELECT 'NONE'::text, NULL::integer, NULL::text;
  ELSIF l_n = 1 THEN
    RETURN QUERY
      SELECT 'EXACT'::text, g.guardian_id, g.full_name_ar FROM hbh.guardians g
      WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg;
  ELSE
    -- Two live guardians on one number. BL-51 (a phone shared by two
    -- guardians) is still open, and this is exactly its case - so the
    -- function does not decide it. It lists them.
    RETURN QUERY
      SELECT 'AMBIGUOUS'::text, g.guardian_id, g.full_name_ar FROM hbh.guardians g
      WHERE g.center_id = p_center_id AND g.mobile = l_mobile AND g.active_flg
      ORDER BY g.guardian_id;
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hbh.find_beneficiary_matches(
  p_guardian_id integer,
  p_name_ar     text,
  p_birth_date  date)
RETURNS TABLE (result text, child_id integer, full_name_ar text, birth_date date)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_name  text := hbh.normalize_arabic(coalesce(p_name_ar, ''));
  l_exact integer;
  l_half  integer;
BEGIN
  -- OD-07: only within THIS guardian's own beneficiaries. Matching a
  -- name and a birth date across the whole centre would find a stranger
  -- who happens to share both, and offer to merge them.
  --
  -- No temp table. The first draft built one, inside a function
  -- declared STABLE - and a STABLE function may not create anything, so
  -- it would have died on its first call. A temp table in a SECURITY
  -- DEFINER function is a search_path hazard besides. The candidates are
  -- one subquery, counted twice.
  SELECT count(*) FILTER (WHERE m.name_hit AND m.dob_hit),
         count(*) FILTER (WHERE m.name_hit OR  m.dob_hit)
    INTO l_exact, l_half
  FROM (SELECT l_name <> '' AND hbh.normalize_arabic(c.full_name_ar) = l_name AS name_hit,
               p_birth_date IS NOT NULL AND c.birth_date = p_birth_date    AS dob_hit
        FROM   hbh.children c
        JOIN   hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
        WHERE  gc.guardian_id = p_guardian_id AND c.active_flg) m;

  IF l_exact = 1 THEN
    RETURN QUERY
      SELECT 'EXACT'::text, c.child_id, c.full_name_ar, c.birth_date
      FROM   hbh.children c
      JOIN   hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
      WHERE  gc.guardian_id = p_guardian_id AND c.active_flg
        AND  l_name <> '' AND hbh.normalize_arabic(c.full_name_ar) = l_name
        AND  c.birth_date = p_birth_date;
    RETURN;
  END IF;

  -- Anything that half-matches - the name without the date, the date
  -- without the name, or two children matching both - is a question for
  -- a person, never an answer from a function.
  IF l_half > 0 THEN
    RETURN QUERY
      SELECT 'AMBIGUOUS'::text, c.child_id, c.full_name_ar, c.birth_date
      FROM   hbh.children c
      JOIN   hbh.guardian_children gc ON gc.child_id = c.child_id AND gc.active_flg
      WHERE  gc.guardian_id = p_guardian_id AND c.active_flg
        AND  ((l_name <> '' AND hbh.normalize_arabic(c.full_name_ar) = l_name)
              OR (p_birth_date IS NOT NULL AND c.birth_date = p_birth_date))
      ORDER  BY c.child_id;
    RETURN;
  END IF;

  RETURN QUERY SELECT 'NONE'::text, NULL::integer, NULL::text, NULL::date;
END
$$;

-- =====================================================================
-- THE DOOR RECEPTION USES - gated, centre from the caller
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.match_guardian(p_mobile text)
RETURNS TABLE (result text, guardian_id integer, full_name_ar text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'matching a guardian needs GUARDIAN.MANAGE' USING ERRCODE = 'HB255';
  END IF;

  RETURN QUERY SELECT * FROM hbh.find_guardian_matches(l_center, p_mobile);
END
$$;

CREATE OR REPLACE FUNCTION hbh.match_beneficiary(
  p_guardian_id integer,
  p_name_ar     text,
  p_birth_date  date)
RETURNS TABLE (result text, child_id integer, full_name_ar text, birth_date date)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'matching a beneficiary needs GUARDIAN.MANAGE' USING ERRCODE = 'HB255';
  END IF;

  -- Read the row, is it mine, then act - the order every write in this
  -- schema now follows. A guardian of another centre is answered with
  -- the same refusal as a missing permission, so the function cannot be
  -- walked to learn which guardian_ids exist elsewhere.
  IF NOT EXISTS (SELECT 1 FROM hbh.guardians g
                 WHERE g.guardian_id = p_guardian_id AND g.center_id = l_center
                   AND g.active_flg) THEN
    RAISE EXCEPTION 'guardian % is not this centre''s', p_guardian_id USING ERRCODE = 'HB255';
  END IF;

  RETURN QUERY SELECT * FROM hbh.find_beneficiary_matches(p_guardian_id, p_name_ar, p_birth_date);
END
$$;

-- The internal pair stays ungranted - that is the whole design.
REVOKE ALL ON FUNCTION hbh.find_guardian_matches(integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.find_beneficiary_matches(integer, text, date) FROM PUBLIC;

REVOKE ALL ON FUNCTION hbh.match_guardian(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.match_beneficiary(integer, text, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.match_guardian(text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.match_beneficiary(integer, text, date) TO hbh_app;

-- =====================================================================
-- THE PROOF: the oracle is closed, and the door still opens
-- =====================================================================
DO $verify$
BEGIN
  IF has_function_privilege('hbh_app', 'hbh.find_guardian_matches(integer, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'find_guardian_matches is executable by hbh_app - that is a registration oracle';
  END IF;
  IF has_function_privilege('hbh_app', 'hbh.find_beneficiary_matches(integer, text, date)', 'EXECUTE') THEN
    RAISE EXCEPTION 'find_beneficiary_matches is executable by hbh_app';
  END IF;
  IF NOT has_function_privilege('hbh_app', 'hbh.match_guardian(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'match_guardian is not executable by hbh_app - reception has no door';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0132');
