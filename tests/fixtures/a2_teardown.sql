-- =====================================================================
-- Hand By Hand (new) - API phase 2 fixture teardown
--
-- Runs BEFORE the fixture as well as after it, so a run that died half
-- way does not make the next run report a broken fixture instead of the
-- broken run that caused it.
--
-- Two history tables are append-only by trigger, and a fixture cannot
-- be removed while they are. The triggers are disabled BY NAME, the
-- rows go, and the triggers go back - and the last statement in this
-- file asserts that they really did. A teardown that left the
-- append-only guarantee switched off would be a far worse outcome than
-- a teardown that failed. (D-14)
-- =====================================================================

\set ON_ERROR_STOP on

-- Consents and notifications (migration 0015) come FIRST.
--
-- hbh.consents holds a foreign key to the CHILD and hbh.notifications
-- one to the USER, so removing either later than the rows they point at
-- fails on the constraint. This block ran last at first and did exactly
-- that.
ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g, hbh.users u
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a2\_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = cn.guardian_id AND u.user_id = g.user_id
   AND u.username LIKE 'a2\_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a2\_%';

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;

DELETE FROM hbh.session_notes n
 USING hbh.children c
 WHERE c.child_id = n.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.goal_measurements m
 USING hbh.plan_goals g, hbh.treatment_plans p, hbh.children c
 WHERE g.goal_id = m.goal_id AND p.plan_id = g.plan_id
   AND c.child_id = p.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.progress_reports r
 USING hbh.children c
 WHERE c.child_id = r.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.plan_goals g
 USING hbh.treatment_plans p, hbh.children c
 WHERE p.plan_id = g.plan_id AND c.child_id = p.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.treatment_plans p
 USING hbh.children c
 WHERE c.child_id = p.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.session_status_history h
 USING hbh.therapy_sessions s, hbh.children c
 WHERE s.session_id = h.session_id AND c.child_id = s.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.therapy_sessions s
 USING hbh.children c
 WHERE c.child_id = s.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.appointment_status_history h
 USING hbh.appointments a, hbh.children c
 WHERE a.appointment_id = h.appointment_id AND c.child_id = a.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.appointments a
 USING hbh.children c
 WHERE c.child_id = a.child_id AND c.child_no LIKE 'A2-%';

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;

DELETE FROM hbh.caseload cl
 USING hbh.children c
 WHERE c.child_id = cl.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c
 WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A2-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A2-%';

DELETE FROM hbh.guardians g
 USING hbh.users u
 WHERE u.user_id = g.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.therapist_working_hours w
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = w.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.therapist_services ts
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = ts.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.therapists t
 USING hbh.users u
 WHERE u.user_id = t.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.rooms    WHERE code LIKE 'A2-%';
DELETE FROM hbh.services WHERE code LIKE 'A2-%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a2\_%';

DELETE FROM hbh.users WHERE username LIKE 'a2\_%';

-- The append-only guarantee is back, or this file fails loudly.
DO $restored$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   pg_trigger
  WHERE  tgname IN ('trg_ash_append_only', 'trg_ssh_append_only')
  AND    tgenabled = 'O';
  IF n <> 2 THEN
    RAISE EXCEPTION 'teardown left an append-only trigger disabled (% of 2 enabled)', n;
  END IF;
END
$restored$;
