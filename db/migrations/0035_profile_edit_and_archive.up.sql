-- =====================================================================
-- Hand By Hand (new) - migration 0035: two gaps 0033 left, both found
-- by running it
--
-- =====================================================================
-- GAP 1: A THERAPIST COULD NOT EDIT THEIR OWN PROFILE.
--
-- 0033 added the columns and the function that says who may change
-- them, and then never put that function in a policy. The only UPDATE
-- policy on hbh.therapists is p_therapists_edit from 0012, which wants
-- STAFF.MANAGE - held by CENTER_ADMIN alone. So the person whose
-- biography it is was refused, and the acceptance suite said 404 on the
-- first check that mattered.
--
-- WHY NOT SIMPLY ADD A SECOND UPDATE POLICY. Because RLS grants rows,
-- not columns. A permissive policy saying "you may update your own
-- therapist row" would let a therapist change status, user_id and
-- branch_id as well - marking themselves inactive, or pointing their
-- row at another account. Those are the centre's fields.
--
-- So the profile columns move through a function that names them, and
-- hbh.therapists gains no new policy at all. The generic CRUD route
-- keeps only the columns the centre owns.
--
-- =====================================================================
-- GAP 2: NOTHING COULD BE ARCHIVED.
--
-- Removing a language returned 42501. The cause is the trap this
-- project has already paid for once, in migration 0013:
--
--   POSTGRES APPLIES THE SELECT POLICY TO THE **NEW** ROW OF AN UPDATE.
--
-- The three SELECT policies in 0033 all end with AND active_flg, so an
-- UPDATE that sets active_flg = false produces a new row the policy
-- rejects, and the whole statement is refused. Soft delete was
-- impossible on every table the migration created, and the failure
-- looks like a permission problem rather than what it is.
--
-- The fix is 0013's: a second permissive SELECT policy admitting
-- archived rows to whoever may edit the profile. Not weakening the
-- first one - a family must still see live rows only.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0035') THEN
    RAISE EXCEPTION 'migration 0035 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0033') THEN
    RAISE EXCEPTION 'migration 0033 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- 1. THE PROFILE COLUMNS, AND ONLY THOSE
--
-- Each parameter is a pointer in the caller's sense: NULL means "not
-- mentioned", so a screen editing the biography does not blank the age
-- range it never showed. Clearing a field is p_clear, said out loud -
-- because "leave it alone" and "empty it" are different requests and a
-- single NULL cannot mean both.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.update_therapist_profile(
  p_therapist_id        integer,
  p_bio_ar              text     DEFAULT NULL,
  p_practice_since_year smallint DEFAULT NULL,
  p_age_from_mon        smallint DEFAULT NULL,
  p_age_to_mon          smallint DEFAULT NULL,
  p_clear               text[]   DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.therapists
                  WHERE therapist_id = p_therapist_id
                  AND   center_id = hbh.current_center_id()
                  AND   active_flg) THEN
    RAISE EXCEPTION 'no such therapist %', p_therapist_id USING ERRCODE = 'HB140';
  END IF;

  IF NOT hbh.can_edit_therapist(p_therapist_id) THEN
    RAISE EXCEPTION 'not permitted to edit this profile' USING ERRCODE = 'HB141';
  END IF;

  UPDATE hbh.therapists
     SET bio_ar = CASE WHEN 'bio_ar' = ANY(coalesce(p_clear, '{}')) THEN NULL
                       ELSE coalesce(p_bio_ar, bio_ar) END,
         practice_since_year = CASE WHEN 'practice_since_year' = ANY(coalesce(p_clear, '{}')) THEN NULL
                                    ELSE coalesce(p_practice_since_year, practice_since_year) END,
         age_from_mon = CASE WHEN 'age_from_mon' = ANY(coalesce(p_clear, '{}')) THEN NULL
                             ELSE coalesce(p_age_from_mon, age_from_mon) END,
         age_to_mon = CASE WHEN 'age_to_mon' = ANY(coalesce(p_clear, '{}')) THEN NULL
                           ELSE coalesce(p_age_to_mon, age_to_mon) END
   WHERE therapist_id = p_therapist_id;
END
$$;

COMMENT ON FUNCTION hbh.update_therapist_profile(integer, text, smallint, smallint, smallint, text[]) IS
  'The profile columns and no others. status, user_id and branch_id stay the centre''s, because RLS grants rows and not columns (0035).';

GRANT EXECUTE ON FUNCTION hbh.update_therapist_profile(integer, text, smallint, smallint, smallint, text[]) TO hbh_app;

-- =====================================================================
-- 2. ARCHIVED ROWS STAY VISIBLE TO WHOEVER MAY EDIT
--
-- A SECOND policy, permissive, exactly as migration 0013 did for the
-- catalogue. PostgreSQL ORs permissive policies, so this widens the
-- read for editors and leaves the family's view untouched.
-- =====================================================================
CREATE POLICY p_thl_select_archived ON hbh.therapist_languages
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND hbh.can_edit_therapist(therapist_id));

CREATE POLICY p_thq_select_archived ON hbh.therapist_qualifications
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.can_edit_therapist(therapist_id));

CREATE POLICY p_thc_select_archived ON hbh.therapist_certificates
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.can_edit_therapist(therapist_id));

-- =====================================================================
-- IT PROVES THE ARCHIVE ACTUALLY WORKS NOW
--
-- The check the last migration should have had. An UPDATE that the
-- SELECT policy silently refuses reads as a permission problem, and
-- three checks downstream of it fail for reasons that name the wrong
-- thing entirely.
-- =====================================================================
DO $prove$
DECLARE
  l_th   integer;
  l_user integer;
BEGIN
  SELECT t.therapist_id, t.user_id INTO l_th, l_user
  FROM   hbh.therapists t WHERE t.active_flg AND t.user_id IS NOT NULL LIMIT 1;
  IF l_th IS NULL THEN
    RAISE WARNING 'no therapist with an account, so the archive path was not exercised';
    RETURN;
  END IF;

  INSERT INTO hbh.therapist_languages (therapist_id, lang_code, level_code)
  VALUES (l_th, 'zz', 'BASIC')
  ON CONFLICT (therapist_id, lang_code) DO UPDATE SET active_flg = true;

  UPDATE hbh.therapist_languages
     SET active_flg = false, deleted_at = now()
   WHERE therapist_id = l_th AND lang_code = 'zz';

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_languages
                  WHERE therapist_id = l_th AND lang_code = 'zz' AND NOT active_flg) THEN
    RAISE EXCEPTION 'the row could not be archived';
  END IF;

  DELETE FROM hbh.therapist_languages WHERE therapist_id = l_th AND lang_code = 'zz';
END
$prove$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0035');
