-- =====================================================================
-- Hand By Hand (new) - migration 0093: the last two unblocked gaps
-- (LC-02 · LC-15)
--
-- LC-02 · THE FAMILY'S WINDOW, ASKED ON THE FORM
--
--   enrolment_applications carries preferred_contact_time - free text.
--   Reception reads "mornings after nine" and matches it by hand
--   against therapist_working_hours, every time, for every family.
--
--   The schema already knows how to say this properly: hbh.waiting_list
--   holds weekdays, a time range and a date range, and
--   waiting_candidates matches them in the centre's local zone. The
--   enrolment form was simply never given the same vocabulary. This
--   gives it the same three columns, with the same meaning, so the
--   window a family states at the door is the window the waiting list
--   can already match.
--
--   preferred_contact_time STAYS. It answers a different question -
--   when to phone them - and deleting a column people are filling in
--   because a better one arrived is how you lose a year of answers.
--
-- LC-15 · THE TIMELINE, WHICH IS ASSEMBLY NOT COLLECTION
--
--   Application -> Assigned -> Appointment -> Assessment -> Approved
--   Plan -> Package -> Payment -> Sessions -> Report. Every one of
--   those facts is already recorded, well, in a table built for it.
--   Twelve views in this schema and not one of them puts them in a row.
--
--   AND THE SECURITY POINT IS THE WHOLE POINT. This view reads NINE
--   tables guarded by nine different policies. A view runs as its OWNER
--   unless told otherwise, and the owner here bypasses RLS on every one
--   of them - so this view without security_invoker hands a guardian
--   the entire case history of every child in the centre. It is the
--   single most dangerous view in the schema to get wrong, and the
--   p00 conventions suite fails if any view is created without the
--   setting.
--
--   NO CLINICAL TEXT TRAVELS. The timeline says WHAT happened and WHEN
--   and points at the row. A note's body, a report's summary, an
--   assessment's recommendation - each has its own gate and its own
--   publication ladder, and a timeline that inlined them would hand
--   round the contents of a draft note as an event label.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0093') THEN
    RAISE EXCEPTION 'migration 0093 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0091') THEN
    RAISE EXCEPTION 'migration 0091 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- LC-02
-- =====================================================================
ALTER TABLE hbh.enrolment_applications
  ADD COLUMN preferred_weekdays  smallint[],
  ADD COLUMN preferred_time_from time,
  ADD COLUMN preferred_time_to   time;

-- Same vocabulary as hbh.waiting_list: 1 = Monday ... 7 = Sunday.
ALTER TABLE hbh.enrolment_applications
  ADD CONSTRAINT ck_enrol_weekdays
  CHECK (preferred_weekdays IS NULL
         OR (array_length(preferred_weekdays, 1) BETWEEN 1 AND 7
             AND preferred_weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[])),
  ADD CONSTRAINT ck_enrol_time_window
  CHECK ((preferred_time_from IS NULL) = (preferred_time_to IS NULL)),
  -- An inverted window silently matches nothing, which reads as "no
  -- slots available" rather than as the bad input it is.
  ADD CONSTRAINT ck_enrol_time_order
  CHECK (preferred_time_from IS NULL OR preferred_time_from < preferred_time_to);

COMMENT ON COLUMN hbh.enrolment_applications.preferred_weekdays IS
  'Days the family can attend, 1=Monday..7=Sunday - the same vocabulary as hbh.waiting_list so the two can be matched without translation. Distinct from preferred_contact_time, which is when to phone them.';

-- =====================================================================
-- LC-15
--
-- UNION ALL of nine sources, each contributing (when, what, detail,
-- where to look). Ordering is left to the caller: a timeline read
-- newest-first on one screen and oldest-first on another is the same
-- view, and baking ORDER BY into it only makes the planner sort twice.
-- =====================================================================
CREATE VIEW hbh.v_case_timeline
WITH (security_invoker = true)
AS
-- 1. the family knocked
SELECT a.center_id, a.converted_child_id AS child_id, a.submitted_at AS at,
       'ENROLMENT_SUBMITTED'::text AS event, a.application_no AS ref,
       NULL::text AS detail, 'ENROLMENT'::text AS link_kind, a.application_id AS link_id
FROM   hbh.enrolment_applications a
WHERE  a.converted_child_id IS NOT NULL AND a.active_flg

UNION ALL
-- 2. a clinician took them on
SELECT cl.center_id, cl.child_id, cl.assigned_date::timestamptz,
       'ASSIGNED', t.full_name_ar, s.name_ar, 'CASELOAD', cl.caseload_id
FROM   hbh.caseload cl
JOIN   hbh.therapists t ON t.therapist_id = cl.therapist_id
LEFT   JOIN hbh.services s ON s.service_id = cl.service_id
WHERE  cl.active_flg

UNION ALL
-- 3. every move an appointment made, from the history table that
--    already records them - not from the appointment's current status,
--    which remembers only where it ended up
SELECT h.center_id, ap.child_id, h.changed_at,
       'APPOINTMENT_' || h.to_status, to_char(ap.starts_at, 'YYYY-MM-DD HH24:MI'),
       h.reason, 'APPOINTMENT', h.appointment_id
FROM   hbh.appointment_status_history h
JOIN   hbh.appointments ap ON ap.appointment_id = h.appointment_id

UNION ALL
-- 4. and a move is ONE event, which is what 0088's link buys
SELECT ap.center_id, ap.child_id, ap.created_at,
       'APPOINTMENT_MOVED_FROM', to_char(prev.starts_at, 'YYYY-MM-DD HH24:MI'),
       to_char(ap.starts_at, 'YYYY-MM-DD HH24:MI'), 'APPOINTMENT', ap.appointment_id
FROM   hbh.appointments ap
JOIN   hbh.appointments prev ON prev.appointment_id = ap.rescheduled_from_appointment_id

UNION ALL
SELECT h.center_id, s.child_id, h.changed_at,
       'SESSION_' || h.to_status, NULL, h.reason, 'SESSION', h.session_id
FROM   hbh.session_status_history h
JOIN   hbh.therapy_sessions s ON s.session_id = h.session_id

UNION ALL
-- 6. an assessment, only once PUBLISHED. A draft on a timeline is a
--    clinician's working paper shown to a family.
SELECT asm.center_id, asm.child_id, asm.published_at,
       'ASSESSMENT_PUBLISHED', i.name_ar, NULL, 'ASSESSMENT', asm.assessment_id
FROM   hbh.assessments asm
JOIN   hbh.assessment_instruments i ON i.instrument_id = asm.instrument_id
WHERE  asm.status = 'PUBLISHED' AND asm.published_at IS NOT NULL AND asm.active_flg

UNION ALL
-- 7. who approved the plan - the column 0088 added, and the reason it
--    was added at all
SELECT p.center_id, p.child_id, p.approved_at,
       'PLAN_APPROVED', p.title_ar, u.full_name_ar, 'PLAN', p.plan_id
FROM   hbh.treatment_plans p
LEFT   JOIN hbh.users u ON u.user_id = p.approved_by
WHERE  p.approved_at IS NOT NULL AND p.active_flg

UNION ALL
SELECT cp.center_id, cp.child_id, cp.purchased_on::timestamptz,
       'PACKAGE_PURCHASED', pk.name_ar, cp.sessions_total::text, 'PACKAGE', cp.child_package_id
FROM   hbh.child_packages cp
JOIN   hbh.service_packages pk ON pk.package_id = cp.package_id
WHERE  cp.active_flg

UNION ALL
-- 9. money. The amount travels because an invoice is the family's own
--    document, unlike a clinical note.
SELECT pay.center_id, inv.child_id, pay.paid_at,
       'PAYMENT_RECEIVED', inv.invoice_no, pay.amount::text, 'INVOICE', inv.invoice_id
FROM   hbh.payments pay
JOIN   hbh.invoices inv ON inv.invoice_id = pay.invoice_id
WHERE  pay.active_flg AND inv.active_flg

UNION ALL
SELECT r.center_id, r.child_id, r.published_at,
       'REPORT_PUBLISHED', r.title_ar, NULL, 'REPORT', r.report_id
FROM   hbh.progress_reports r
WHERE  r.status = 'PUBLISHED' AND r.published_at IS NOT NULL AND r.active_flg;

COMMENT ON VIEW hbh.v_case_timeline IS
  'One child, one thread: enrolment, assignment, appointments, sessions, assessments, plan approval, packages, payments, reports. security_invoker - it reads nine policy-guarded tables and without it would hand any caller every child in the centre. Carries no clinical text: what happened and where to look, never what was written.';

GRANT SELECT ON hbh.v_case_timeline TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0093');
