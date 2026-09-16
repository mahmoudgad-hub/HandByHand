-- =====================================================================
-- Hand By Hand (new) - API phase 5 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- Order is by foreign key, and the two things that must go FIRST are
-- notifications and consents: notifications hold a key to the USER and
-- consents one to the CHILD, so removing either after the rows they
-- point at fails on the constraint. Both are created as side effects -
-- publishing a report and issuing an invoice each raise a notification.
--
-- The status histories are append-only by trigger, so those come off by
-- name and go back at the end. The last block asserts they did: a
-- teardown that left the append-only guarantee switched off is a worse
-- outcome than one that failed. (D-14)
-- =====================================================================

\set ON_ERROR_STOP on

-- ONE TRANSACTION - see a3_teardown.sql for the night this was learned.
-- The invoice DELETE failed on 0142's instalment foreign key after the
-- guards had been disabled in their own statements, and three stayed off.
-- DISABLE TRIGGER is transactional: inside BEGIN/COMMIT a failure takes
-- the disable back with it, so a broken teardown leaves rows, not a
-- switched-off guarantee.
BEGIN;

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a5\_%';

ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g, hbh.users u
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a5\_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = cn.guardian_id AND u.user_id = g.user_id
   AND u.username LIKE 'a5\_%';

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.package_ledger             DISABLE TRIGGER trg_led_append_only;

-- FROM 0142: instalments and their append-only history go first, in FK
-- order, as separate statements. See a3_teardown.sql.
ALTER TABLE hbh.invoice_installment_status_history DISABLE TRIGGER trg_iish_append_only;
DELETE FROM hbh.invoice_installment_status_history h
 USING hbh.invoice_installments ii, hbh.invoices i, hbh.children c
 WHERE ii.installment_id = h.installment_id AND i.invoice_id = ii.invoice_id
   AND c.child_id = i.child_id AND c.child_no LIKE 'A5-%';
DELETE FROM hbh.invoice_installments ii
 USING hbh.invoices i, hbh.children c
 WHERE i.invoice_id = ii.invoice_id AND c.child_id = i.child_id AND c.child_no LIKE 'A5-%';
ALTER TABLE hbh.invoice_installment_status_history ENABLE TRIGGER trg_iish_append_only;

-- Billing: payments, lines and invoices in ONE statement. Deleting a
-- payment alone fires trg_pay_recalc, which tries to move the invoice
-- back to ISSUED - a transition the status machine correctly refuses.
WITH p AS (
  DELETE FROM hbh.payments
   WHERE invoice_id IN (SELECT i.invoice_id FROM hbh.invoices i
                        JOIN hbh.children c ON c.child_id = i.child_id
                        WHERE c.child_no LIKE 'A5-%')
  RETURNING 1),
l AS (
  DELETE FROM hbh.invoice_lines
   WHERE invoice_id IN (SELECT i.invoice_id FROM hbh.invoices i
                        JOIN hbh.children c ON c.child_id = i.child_id
                        WHERE c.child_no LIKE 'A5-%')
  RETURNING 1)
DELETE FROM hbh.invoices
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'A5-%');

DELETE FROM hbh.package_ledger pl
 USING hbh.child_packages cp, hbh.children c
 WHERE cp.child_package_id = pl.child_package_id AND c.child_id = cp.child_id
   AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.child_packages cp
 USING hbh.children c WHERE c.child_id = cp.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.service_packages WHERE code LIKE 'A5-%';

DELETE FROM hbh.progress_reports r
 USING hbh.children c WHERE c.child_id = r.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.session_notes n
 USING hbh.children c WHERE c.child_id = n.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.goal_measurements m
 USING hbh.plan_goals g, hbh.treatment_plans p, hbh.children c
 WHERE g.goal_id = m.goal_id AND p.plan_id = g.plan_id
   AND c.child_id = p.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.plan_goals g
 USING hbh.treatment_plans p, hbh.children c
 WHERE p.plan_id = g.plan_id AND c.child_id = p.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.treatment_plans p
 USING hbh.children c WHERE c.child_id = p.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.parent_requests pr
 USING hbh.children c WHERE c.child_id = pr.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.session_status_history h
 USING hbh.therapy_sessions s, hbh.children c
 WHERE s.session_id = h.session_id AND c.child_id = s.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.therapy_sessions s
 USING hbh.children c WHERE c.child_id = s.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.appointment_status_history h
 USING hbh.appointments a, hbh.children c
 WHERE a.appointment_id = h.appointment_id AND c.child_id = a.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.appointments a
 USING hbh.children c WHERE c.child_id = a.child_id AND c.child_no LIKE 'A5-%';

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.package_ledger             ENABLE TRIGGER trg_led_append_only;

DELETE FROM hbh.caseload cl
 USING hbh.children c WHERE c.child_id = cl.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A5-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A5-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a5\_%';

DELETE FROM hbh.therapist_working_hours w
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = w.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a5\_%';

DELETE FROM hbh.therapist_services ts
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = ts.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a5\_%';

DELETE FROM hbh.therapists t
 USING hbh.users u WHERE u.user_id = t.user_id AND u.username LIKE 'a5\_%';

DELETE FROM hbh.rooms    WHERE code LIKE 'A5-%';
DELETE FROM hbh.services WHERE code LIKE 'A5-%';

-- If the delete below fails on fk_req_decider, an a5 account decided a
-- request that belongs to another fixture. That is not a teardown bug
-- to be worked around: it means the suite acted on a row it did not
-- create, and the fix is upstream - the request identifier is read from
-- the database by child, never out of the centre-wide list, because
-- that list contains other people's rows by design.
--
-- Deliberately NOT patched here. ck_req_decided forbids clearing
-- decided_by while the status is ACCEPTED, and deleting somebody else's
-- row to unblock this one would trade a visible failure for a silent
-- change to their data.
DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a5\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a5\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a5\_%';
DELETE FROM hbh.users WHERE username LIKE 'a5\_%';

DO $restored$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   pg_trigger
  WHERE  tgname IN ('trg_ash_append_only','trg_ssh_append_only','trg_led_append_only','trg_iish_append_only')
  AND    tgenabled = 'O';
  IF n <> 4 THEN
    RAISE EXCEPTION 'teardown left an append-only trigger disabled (% of 4 enabled)', n;
  END IF;
END
$restored$;

-- The assertion above ran INSIDE the transaction: if it raised, nothing
-- here committed, and the guards are exactly as they were before.
COMMIT;
