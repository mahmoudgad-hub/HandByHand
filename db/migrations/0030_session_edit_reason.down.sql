-- Hand By Hand (new) - migration 0030 DOWN. Development only.
-- Restores the single-answer gate from 0006.
CREATE OR REPLACE FUNCTION hbh.can_edit_session(p_session_id integer)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $f$
  SELECT EXISTS (
    SELECT 1 FROM hbh.therapy_sessions s
    JOIN hbh.therapists t ON t.therapist_id = s.therapist_id
    WHERE s.session_id = p_session_id
      AND t.user_id = hbh.current_user_id()
      AND hbh.has_permission('SESSION.NOTES.EDIT'))
$f$;
DROP FUNCTION IF EXISTS hbh.check_session_edit(integer);
DELETE FROM hbh.schema_migrations WHERE version = '0030';
