-- =====================================================================
-- 0120 down - the rooms and the passes go
--
-- THIS DESTROYS EVIDENCE, and it should say so out loud rather than in a
-- commit message. hbh.meeting_tokens is the record of who entered which
-- consultation and when - the answer to a question a family or a
-- regulator can ask a year later. Going down past this migration throws
-- that away, and there is no other copy.
--
-- So it REFUSES while any pass exists. Somebody who genuinely means to
-- discard them can empty the table first, deliberately, and that is a
-- different act from running a migration.
--
-- CHILDREN BEFORE PARENTS, each in its own statement: meeting_tokens
-- references meetings, and several data-modifying CTEs in one statement
-- have no ordering between them - it works until the plan changes.
--
-- The trigger and the functions belong to 0121 and its down removes
-- them. They are dropped here too, defensively: PL/pgSQL bodies are not
-- dependency-checked, so dropping these tables underneath a live trigger
-- succeeds and leaves a function that fails on the next booking - with
-- nothing at drop time to say so.
-- =====================================================================

\set ON_ERROR_STOP on

DO $evidence$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM hbh.meeting_tokens;
  IF n > 0 THEN
    RAISE EXCEPTION '0120 down: % pass record(s) would be destroyed', n
      USING HINT = 'meeting_tokens is the record of who entered which consultation. Empty it deliberately first if that is really what you mean.';
  END IF;
END
$evidence$;

DROP TRIGGER IF EXISTS trg_appointments_meeting ON hbh.appointments;
DROP FUNCTION IF EXISTS hbh.record_meeting_token(bigint, bytea, boolean, timestamptz, inet);
DROP FUNCTION IF EXISTS hbh.authorize_meeting_entry(integer);
DROP FUNCTION IF EXISTS hbh.trg_appointment_meeting();

DROP TABLE IF EXISTS hbh.meeting_tokens;
DROP TABLE IF EXISTS hbh.meetings;

DELETE FROM hbh.convention_exemptions WHERE table_name = 'meeting_tokens';

DELETE FROM hbh.sys_params
 WHERE center_id IS NULL
   AND param_code IN ('MEETING_TOKEN_TTL_MIN', 'CONSULT_DOOR_OPENS_MIN',
                      'CONSULT_DOOR_GRACE_MIN', 'MEETING_PROVIDER');

DELETE FROM hbh.schema_migrations WHERE version = '0120';
