-- =====================================================================
-- Hand By Hand (new) - API phase 1 fixture teardown
--
-- Runs BEFORE the fixture as well as after it. A previous run that died
-- half way leaves rows behind, and a fixture that fails on those rows
-- reports a broken fixture rather than the broken run that caused it.
--
-- Order is by foreign key, deepest first. audit_log rows are not
-- removed: the table is append-only by design, and the suite scopes its
-- own counts by time rather than expecting an empty log.
-- =====================================================================

-- Consents and notifications (migration 0015) come FIRST.
--
-- hbh.consents holds a foreign key to the CHILD and hbh.notifications
-- one to the USER, so removing either after the rows they point at fails
-- on the constraint. This block was appended near the end at first and
-- did exactly that.
ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g, hbh.users u
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a1\_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = cn.guardian_id AND u.user_id = g.user_id
   AND u.username LIKE 'a1\_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a1\_%';

-- BILLING THIS FIXTURE NEVER CREATED.
--
-- The phase-1 fixture makes a family and a gate to test it with, and no
-- invoice at all - yet a teardown that only removes what it created is
-- incomplete on a database other people work on. These children appear
-- in the operations console like any others, and somebody testing the
-- new invoice endpoint billed one of them. The delete then failed on
-- fk_inv_child, and phase 1 went red for something that was not wrong
-- with phase 1.
--
-- A teardown OWNS ITS CHILDREN: whatever points at them goes, whoever
-- made it. The rows below belong to this fixture's children by
-- definition - nothing else can reach them.
--
-- One statement per level, children first. Several data-modifying CTEs
-- in one statement have no ordering between them: it works for days and
-- then fails when the plan changes, and the failure looks intermittent
-- when it is actually undefined.
DELETE FROM hbh.payments p
 USING hbh.invoices i, hbh.children c
 WHERE i.invoice_id = p.invoice_id AND c.child_id = i.child_id
   AND c.child_no LIKE 'A1-%';

DELETE FROM hbh.invoice_lines l
 USING hbh.invoices i, hbh.children c
 WHERE i.invoice_id = l.invoice_id AND c.child_id = i.child_id
   AND c.child_no LIKE 'A1-%';

DELETE FROM hbh.invoices i
 USING hbh.children c WHERE c.child_id = i.child_id AND c.child_no LIKE 'A1-%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c
 WHERE c.child_id = gc.child_id
   AND c.child_no LIKE 'A1-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A1-%';

DELETE FROM hbh.guardians g
 USING hbh.users u
 WHERE u.user_id = g.user_id
   AND u.username LIKE 'a1\_%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u
 WHERE u.user_id = ur.user_id
   AND u.username LIKE 'a1\_%';

DELETE FROM hbh.auth_sessions s
 USING hbh.users u
 WHERE u.user_id = s.user_id
   AND u.username LIKE 'a1\_%';

DELETE FROM hbh.otp_codes o
 USING hbh.users u
 WHERE u.user_id = o.user_id
   AND u.username LIKE 'a1\_%';

DELETE FROM hbh.users WHERE username LIKE 'a1\_%';

-- The enrolment applications the ENROLMENT_PENDING checks need. Removed
-- by the reference numbers this fixture writes, not by mobile and not by
-- a prefix: an application carries a family's own number, and a LIKE over
-- those reaches other people's rows - which is how a cleanup once took
-- twenty-one checks down with it.
DELETE FROM hbh.enrolment_applications
 WHERE application_no IN ('A1-ENR-PENDING', 'A1-ENR-REJECTED');
