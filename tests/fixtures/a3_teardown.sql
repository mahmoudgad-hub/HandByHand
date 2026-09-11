-- =====================================================================
-- Hand By Hand (new) - API phase 3 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- FIVE append-only guards across four tables have to be opened to
-- remove this fixture: the two status histories, the package ledger,
-- and stream_views, which carries TWO of them. stream_views is the one
-- to be careful about - it exists so that a person who watched a child
-- in therapy cannot do so without leaving a trace, and a teardown that
-- left a trigger off would quietly remove that guarantee for every
-- later run. The final block asserts all five came back. (D-14)
--
-- The media gateway parameters are restored to their safe defaults here
-- too. The suite has to configure a gateway to test the happy path, and
-- leaving it configured would mean the next fresh run no longer starts
-- from "refuses to stream".
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.package_ledger             DISABLE TRIGGER trg_led_append_only;
ALTER TABLE hbh.stream_views               DISABLE TRIGGER trg_view_append_only;
-- stream_views carries TWO guards, not one: trg_view_append_only and
-- trg_view_no_delete. Disabling only the first is how this teardown
-- failed the first time it ran - the table stayed undeletable and the
-- other three triggers were left switched off behind it.
ALTER TABLE hbh.stream_views               DISABLE TRIGGER trg_view_no_delete;

-- Live stream
DELETE FROM hbh.stream_tokens t
 USING hbh.therapy_sessions s, hbh.children c
 WHERE s.session_id = t.session_id AND c.child_id = s.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.stream_views v
 USING hbh.children c
 WHERE c.child_id = v.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.cameras WHERE code LIKE 'A3-%';

-- Consents (migration 0015). The events table is append-only, so its
-- trigger comes off by name and goes back at the end with the others.
ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g, hbh.users u
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a3_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = cn.guardian_id AND u.user_id = g.user_id
   AND u.username LIKE 'a3_%';

-- Billing - payments, lines and invoices in ONE statement
--
-- Not three, and this is the second thing that broke this teardown.
-- Deleting a payment on its own fires trg_pay_recalc, which recomputes
-- the invoice and tries to move it from PARTIALLY_PAID back to ISSUED -
-- and the status machine refuses that transition, correctly. Removing
-- all three in a single statement is how the phase-6 suite does it, and
-- it is the right answer here for the same reason: the invoice is going
-- anyway, so there is no state for the recalculation to land on.
WITH p AS (
  DELETE FROM hbh.payments
   WHERE invoice_id IN (SELECT i.invoice_id FROM hbh.invoices i
                        JOIN hbh.children c ON c.child_id = i.child_id
                        WHERE c.child_no LIKE 'A3-%')
  RETURNING 1),
l AS (
  DELETE FROM hbh.invoice_lines
   WHERE invoice_id IN (SELECT i.invoice_id FROM hbh.invoices i
                        JOIN hbh.children c ON c.child_id = i.child_id
                        WHERE c.child_no LIKE 'A3-%')
  RETURNING 1)
DELETE FROM hbh.invoices
 WHERE child_id IN (SELECT child_id FROM hbh.children WHERE child_no LIKE 'A3-%');

DELETE FROM hbh.package_ledger pl
 USING hbh.child_packages cp, hbh.children c
 WHERE cp.child_package_id = pl.child_package_id AND c.child_id = cp.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.child_packages cp
 USING hbh.children c
 WHERE c.child_id = cp.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.service_packages WHERE code LIKE 'A3-%';

-- Home programme
DELETE FROM hbh.activity_log al
 USING hbh.children c
 WHERE c.child_id = al.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.child_activities ca
 USING hbh.children c
 WHERE c.child_id = ca.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.activity_library WHERE code LIKE 'A3-%';

DELETE FROM hbh.parent_requests pr
 USING hbh.children c
 WHERE c.child_id = pr.child_id AND c.child_no LIKE 'A3-%';

-- Sessions and appointments
DELETE FROM hbh.session_status_history h
 USING hbh.therapy_sessions s, hbh.children c
 WHERE s.session_id = h.session_id AND c.child_id = s.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.therapy_sessions s
 USING hbh.children c
 WHERE c.child_id = s.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.appointment_status_history h
 USING hbh.appointments a, hbh.children c
 WHERE a.appointment_id = h.appointment_id AND c.child_id = a.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.appointments a
 USING hbh.children c
 WHERE c.child_id = a.child_id AND c.child_no LIKE 'A3-%';

ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.package_ledger             ENABLE TRIGGER trg_led_append_only;
ALTER TABLE hbh.stream_views               ENABLE TRIGGER trg_view_append_only;
ALTER TABLE hbh.stream_views               ENABLE TRIGGER trg_view_no_delete;

-- People and places
DELETE FROM hbh.caseload cl
 USING hbh.children c WHERE c.child_id = cl.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A3-%';

DELETE FROM hbh.children WHERE child_no LIKE 'A3-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a3\_%';

DELETE FROM hbh.therapist_working_hours w
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = w.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a3\_%';

DELETE FROM hbh.therapist_services ts
 USING hbh.therapists t, hbh.users u
 WHERE t.therapist_id = ts.therapist_id AND u.user_id = t.user_id AND u.username LIKE 'a3\_%';

DELETE FROM hbh.therapists t
 USING hbh.users u WHERE u.user_id = t.user_id AND u.username LIKE 'a3\_%';

DELETE FROM hbh.rooms    WHERE code LIKE 'A3-%';
DELETE FROM hbh.services WHERE code LIKE 'A3-%';

-- Notifications (migration 0015). Triggers raise one whenever a report
-- is published, a note reaches a family, a request is decided or an
-- invoice is issued - so this fixture creates them as a side effect and
-- they hold a foreign key to the user.
DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a3\_%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a3\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a3\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a3\_%';
DELETE FROM hbh.users WHERE username LIKE 'a3\_%';

-- The gateway goes back to refusing. A fresh run must start from the
-- state a fresh install is in.
UPDATE hbh.sys_params SET param_value = ''     WHERE center_id IS NULL AND param_code = 'MEDIA_GATEWAY_BASE_URL';
UPDATE hbh.sys_params SET param_value = 'true' WHERE center_id IS NULL AND param_code = 'MEDIA_GATEWAY_IS_TEMPORARY';

DO $restored$
DECLARE n integer;
BEGIN
  SELECT count(*) INTO n
  FROM   pg_trigger
  WHERE  tgname IN ('trg_ash_append_only','trg_ssh_append_only','trg_led_append_only','trg_view_append_only','trg_view_no_delete')
  AND    tgenabled = 'O';
  IF n <> 5 THEN
    RAISE EXCEPTION 'teardown left an append-only trigger disabled (% of 5 enabled)', n;
  END IF;

  SELECT count(*) INTO n
  FROM   hbh.sys_params
  WHERE  center_id IS NULL
  AND   (   (param_code = 'MEDIA_GATEWAY_BASE_URL'     AND param_value = '')
         OR (param_code = 'MEDIA_GATEWAY_IS_TEMPORARY' AND param_value = 'true'));
  IF n <> 2 THEN
    RAISE EXCEPTION 'teardown left the media gateway configured (% of 2 reset)', n;
  END IF;
END
$restored$;
