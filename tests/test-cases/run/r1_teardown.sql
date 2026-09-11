-- Teardown for the R1 role-journey scenario. Runs before the scenario so
-- a half-applied previous run cannot make the next one fail on a
-- duplicate and read as a broken fixture.
\set ON_ERROR_STOP on
SELECT set_config('hbh.user_id', 'admin', false);

-- The history tables are append-only by trigger, so the trigger is
-- disabled BY NAME and put back at the end.
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;

DELETE FROM hbh.session_notes
 WHERE session_id IN (SELECT session_id FROM hbh.therapy_sessions
                       WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%'));
DELETE FROM hbh.session_status_history
 WHERE session_id IN (SELECT session_id FROM hbh.therapy_sessions
                       WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%'));
DELETE FROM hbh.therapy_sessions
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%');
DELETE FROM hbh.appointment_status_history
 WHERE appointment_id IN (SELECT appointment_id FROM hbh.appointments WHERE appointment_no LIKE 'R1-%');
DELETE FROM hbh.appointments      WHERE appointment_no LIKE 'R1-%';
DELETE FROM hbh.parent_requests
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%');
DELETE FROM hbh.caseload
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%');
DELETE FROM hbh.consent_events
 WHERE consent_id IN (SELECT consent_id FROM hbh.consents
                       WHERE guardian_id IN (SELECT guardian_id FROM hbh.guardians WHERE mobile LIKE '+2017%'));
DELETE FROM hbh.consents
 WHERE guardian_id IN (SELECT guardian_id FROM hbh.guardians WHERE mobile LIKE '+2017%');
DELETE FROM hbh.guardian_children
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'R1-%');
DELETE FROM hbh.children          WHERE child_no LIKE 'R1-%';
DELETE FROM hbh.guardians         WHERE mobile LIKE '+2017%';
DELETE FROM hbh.therapist_services
 WHERE therapist_id IN (SELECT therapist_id FROM hbh.therapists
                         WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'r1\_%'));
DELETE FROM hbh.therapists
 WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'r1\_%');
DELETE FROM hbh.rooms             WHERE code = 'R1ROOM';
DELETE FROM hbh.services          WHERE code = 'R1SVC';
DELETE FROM hbh.auth_sessions
 WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'r1\_%');
DELETE FROM hbh.otp_codes
 WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'r1\_%');
DELETE FROM hbh.user_roles
 WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'r1\_%');
DELETE FROM hbh.users             WHERE username LIKE 'r1\_%';

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;

SELECT 'teardown r1: clean' AS done;
