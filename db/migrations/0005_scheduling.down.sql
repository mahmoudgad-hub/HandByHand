-- =====================================================================
-- Hand By Hand (new) - migration 0005 DOWN
--
-- Development convenience only.
-- Tables before functions: a policy depends on the function it calls,
-- and the whole file runs in one transaction - so a function dropped
-- while its policy still exists takes the entire teardown down with it,
-- silently leaving the old definitions in place.
-- =====================================================================

DROP TABLE IF EXISTS hbh.session_status_history;
DROP TABLE IF EXISTS hbh.therapy_sessions;
DROP TABLE IF EXISTS hbh.appointment_status_history;
DROP TABLE IF EXISTS hbh.appointments;
DROP TABLE IF EXISTS hbh.caseload;
DROP TABLE IF EXISTS hbh.therapist_working_hours;
DROP TABLE IF EXISTS hbh.therapist_services;
DROP TABLE IF EXISTS hbh.therapists;
DROP TABLE IF EXISTS hbh.rooms;
DROP TABLE IF EXISTS hbh.services;

DROP FUNCTION IF EXISTS hbh.close_session(integer, text, text);
DROP FUNCTION IF EXISTS hbh.start_session(integer);
DROP FUNCTION IF EXISTS hbh.can_close_session(integer);
DROP FUNCTION IF EXISTS hbh.book_appointment(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, text);
DROP FUNCTION IF EXISTS hbh.validate_slot(integer, integer, integer, integer, integer, timestamptz, timestamptz, integer);
DROP FUNCTION IF EXISTS hbh.trg_session_history();
DROP FUNCTION IF EXISTS hbh.trg_session_status();
DROP FUNCTION IF EXISTS hbh.trg_appointment_history();
DROP FUNCTION IF EXISTS hbh.trg_appointment_status();
DROP FUNCTION IF EXISTS hbh.legal_session_transition(text, text);
DROP FUNCTION IF EXISTS hbh.legal_appointment_transition(text, text);

DELETE FROM hbh.convention_exemptions
 WHERE table_name IN ('appointment_status_history', 'session_status_history');

DELETE FROM hbh.sys_params    WHERE param_code = 'ALLOW_BACKDATED_BOOKING_DAYS';

DELETE FROM hbh.schema_migrations WHERE version = '0005';
