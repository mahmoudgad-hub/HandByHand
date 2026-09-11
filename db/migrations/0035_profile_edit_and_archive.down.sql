-- =====================================================================
-- Hand By Hand (new) - migration 0035 rollback
--
-- Rolling this back leaves 0033 in the state it was found in: a
-- therapist cannot edit their own profile, and nothing on the three
-- profile tables can be archived. Both failures present as permission
-- errors rather than as what they are.
-- =====================================================================

DROP POLICY IF EXISTS p_thc_select_archived ON hbh.therapist_certificates;
DROP POLICY IF EXISTS p_thq_select_archived ON hbh.therapist_qualifications;
DROP POLICY IF EXISTS p_thl_select_archived ON hbh.therapist_languages;

DROP FUNCTION IF EXISTS hbh.update_therapist_profile(integer, text, smallint, smallint, smallint, text[]);

DELETE FROM hbh.schema_migrations WHERE version = '0035';
