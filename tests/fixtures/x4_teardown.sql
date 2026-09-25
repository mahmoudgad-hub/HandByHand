-- =====================================================================
-- Hand By Hand (new) - X4 teardown. Runs BEFORE the fixture as well as
-- after the walk.
--
-- THE IDENTITY PROBLEM THIS FILE HAD TO SOLVE FIRST.
--
-- Every other teardown here scopes the child by `child_no LIKE 'A5-%'`,
-- because its fixture chose that number. X4 cannot: the child is created
-- by hbh.convert_enrolment, which numbers it from the CHILD series like
-- any real child. There is no X4 in it, and inventing one would mean
-- writing the row by hand - which is the one thing this suite exists not
-- to do.
--
-- So the family is scoped by THE MOBILE IT APPLIED WITH, exactly:
-- '+201500000440', canonical form, `=` and never LIKE. A prefix is not a
-- namespace - '015000000%' once matched a neighbouring suite's row and
-- took its whole teardown down with it - and the child is reached
-- through the guardian link rather than by any name of its own.
--
-- The staff room is scoped the ordinary way: x4_ accounts, X4- service
-- and room.
-- =====================================================================

\set ON_ERROR_STOP on

-- ONE TRANSACTION. DISABLE TRIGGER is transactional, so a failure half
-- way takes the disables back with it: a broken teardown leaves rows
-- behind, never a switched-off append-only guarantee.
BEGIN;

CREATE TEMP TABLE IF NOT EXISTS x4_scope (child_id integer PRIMARY KEY);
DELETE FROM x4_scope;
INSERT INTO x4_scope (child_id)
SELECT DISTINCT gc.child_id
FROM   hbh.guardian_children gc
JOIN   hbh.guardians g ON g.guardian_id = gc.guardian_id
WHERE  g.mobile = '+201500000440';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id
   AND (u.username LIKE 'x4\_%' OR u.mobile = '+201500000440');

ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND g.mobile = '+201500000440';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g
 WHERE g.guardian_id = cn.guardian_id AND g.mobile = '+201500000440';

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;

DELETE FROM hbh.session_notes  WHERE child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.progress_reports WHERE child_id IN (SELECT child_id FROM x4_scope);

DELETE FROM hbh.goal_measurements m
 USING hbh.plan_goals g, hbh.treatment_plans p
 WHERE g.goal_id = m.goal_id AND p.plan_id = g.plan_id
   AND p.child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.plan_goals g
 USING hbh.treatment_plans p
 WHERE p.plan_id = g.plan_id AND p.child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.treatment_plans WHERE child_id IN (SELECT child_id FROM x4_scope);

DELETE FROM hbh.parent_requests WHERE child_id IN (SELECT child_id FROM x4_scope);

DELETE FROM hbh.session_status_history h
 USING hbh.therapy_sessions s
 WHERE s.session_id = h.session_id AND s.child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.therapy_sessions WHERE child_id IN (SELECT child_id FROM x4_scope);

DELETE FROM hbh.appointment_status_history h
 USING hbh.appointments a
 WHERE a.appointment_id = h.appointment_id
   AND a.child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.appointments WHERE child_id IN (SELECT child_id FROM x4_scope);

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;

DELETE FROM hbh.caseload           WHERE child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.guardian_children  WHERE child_id IN (SELECT child_id FROM x4_scope);

-- THE APPLICATION GOES BEFORE THE CHILD, and it is the conversion that
-- makes that true: hbh.convert_enrolment writes the new child_id back
-- onto the application row (fk_enr_child), so the child is still
-- referenced when it looks unreferenced. The first run of this file
-- deleted the child first and died on the constraint - which rolled the
-- whole teardown back and left every row of the walk in place.
DELETE FROM hbh.enrolment_applications WHERE parent_mobile = '+201500000440';
DELETE FROM hbh.enrolment_applications WHERE child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.children               WHERE child_id IN (SELECT child_id FROM x4_scope);
DELETE FROM hbh.guardians              WHERE mobile        = '+201500000440';

DELETE FROM hbh.auth_sessions s USING hbh.users u
 WHERE u.user_id = s.user_id AND (u.username LIKE 'x4\_%' OR u.mobile = '+201500000440');
DELETE FROM hbh.otp_codes o USING hbh.users u
 WHERE u.user_id = o.user_id AND (u.username LIKE 'x4\_%' OR u.mobile = '+201500000440');
DELETE FROM hbh.user_roles ur USING hbh.users u
 WHERE u.user_id = ur.user_id AND (u.username LIKE 'x4\_%' OR u.mobile = '+201500000440');

-- The staff room.
DELETE FROM hbh.therapist_working_hours w
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = w.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'x4\_%';
DELETE FROM hbh.therapist_services ts
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = ts.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'x4\_%';
DELETE FROM hbh.therapists t
 USING hbh.users u WHERE u.user_id = t.user_id AND u.username LIKE 'x4\_%';

DELETE FROM hbh.rooms WHERE code LIKE 'X4-%';
DELETE FROM hbh.service_prices sp
 USING hbh.services s WHERE s.service_id = sp.service_id AND s.code LIKE 'X4-%';
DELETE FROM hbh.services WHERE code LIKE 'X4-%';

DELETE FROM hbh.users
 WHERE username LIKE 'x4\_%' OR mobile = '+201500000440';

DROP TABLE IF EXISTS x4_scope;

-- The guards go back, and it is asserted INSIDE the transaction: if this
-- raises, nothing here commits and they are exactly as they were.
DO $restored$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n FROM pg_trigger
   WHERE tgname IN ('trg_ash_append_only','trg_ssh_append_only') AND tgenabled = 'O';
  IF n <> 2 THEN
    RAISE EXCEPTION 'teardown left an append-only trigger disabled (% of 2 enabled)', n;
  END IF;
END
$restored$;

COMMIT;

\echo 'teardown x4: done'
