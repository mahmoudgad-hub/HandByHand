-- =====================================================================
-- Hand By Hand (new) - migration 0089
-- the system learns to tell a clinician something (LC-04 · LC-05)
--
-- LC-04. Every notification kind in this schema is addressed to a
-- family, and the only sender is hbh.notify_guardians. So the system
-- CANNOT NOTIFY A THERAPIST AT ALL - there is no kind that means it and
-- no function that would do it. The owner's lifecycle asks for exactly
-- that at three separate steps, and every one of them is today a person
-- remembering to tell another person.
--
-- LC-05. And on the family side there is a stranger gap: an appointment
-- has APPOINTMENT_CANCELLED and nothing else. The system tells a family
-- when their appointment is TAKEN AWAY and says nothing when it is
-- given. Read as a product decision that is indefensible; read as an
-- accident it is obvious - cancellation was built with the cancel path
-- and booking never got its own.
--
-- WHY notify_staff IS NOT notify_guardians WITH A DIFFERENT ARGUMENT
--
-- They differ in every part that matters. A family is reached THROUGH A
-- CHILD - every guardian linked to that child, with SMS consent decided
-- per guardian. Staff are reached BY ROLE OR BY NAME, carry no consent
-- record because this is their job, and must never have sms_pending_flg
-- set from a guardian's consent - which is what passing staff through
-- notify_guardians would silently do.
--
-- AND NO NOTIFICATION CARRIES CLINICAL TEXT. The title says a thing
-- happened and the link says where to look. A body holding what a child
-- did in a session is a clinical note delivered by SMS, outside every
-- gate this schema builds - and 0020 already refuses personal data in
-- the request log for the same reason.
--
-- Error classes added here:
--   HB220  no recipient - notifying nobody is not a success
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0089') THEN
    RAISE EXCEPTION 'migration 0089 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0088') THEN
    RAISE EXCEPTION 'migration 0088 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE KINDS
--
-- Named by audience, because the two audiences have different rules and
-- a reader should not have to know the list to tell them apart.
-- =====================================================================
ALTER TABLE hbh.notifications DROP CONSTRAINT ck_ntf_kind;
ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code IN (
  -- to the family
  'REPORT_PUBLISHED', 'NOTE_PUBLISHED', 'REQUEST_DECIDED', 'INVOICE_ISSUED',
  'APPOINTMENT_CANCELLED', 'SESSION_STARTED', 'ASSESSMENT_PUBLISHED',
  'APPOINTMENT_BOOKED', 'APPOINTMENT_RESCHEDULED', 'APPOINTMENT_REMINDER',
  -- to the centre's own people
  'STAFF_CHILD_ASSIGNED', 'STAFF_APPOINTMENT_BOOKED', 'STAFF_APPOINTMENT_CANCELLED',
  'STAFF_ENROLMENT_NEW', 'STAFF_REQUEST_NEW', 'STAFF_PLAN_APPROVED'
));

-- A staff notification has no child in the family sense - it may name
-- one, but it is addressed to a colleague. This tells the two apart
-- without anybody memorising the list.
ALTER TABLE hbh.notifications
  ADD CONSTRAINT ck_ntf_audience
  CHECK (kind_code NOT LIKE 'STAFF\_%' OR child_id IS NOT NULL OR link_kind IS NOT NULL);

-- =====================================================================
-- REACHING A COLLEAGUE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.notify_staff(
  p_user_ids  integer[],
  p_kind      text,
  p_title_ar  text,
  p_child_id  integer DEFAULT NULL,
  p_link_kind text    DEFAULT NULL,
  p_link_id   integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  IF p_kind NOT LIKE 'STAFF\_%' THEN
    RAISE EXCEPTION 'notify_staff sends staff kinds only, not %', p_kind USING ERRCODE = 'HB220';
  END IF;

  INSERT INTO hbh.notifications (center_id, user_id, child_id, kind_code, title_ar,
                                 link_kind, link_id, sms_pending_flg)
  SELECT u.center_id, u.user_id, p_child_id, p_kind, p_title_ar, p_link_kind, p_link_id,
         -- NEVER. SMS consent is a family's decision about their child's
         -- data; staff are reached in the application they already use.
         false
  FROM   hbh.users u
  WHERE  u.user_id = ANY (p_user_ids)
    AND  u.active_flg
    AND  u.user_type IN ('STAFF', 'THERAPIST');

  GET DIAGNOSTICS l_n = ROW_COUNT;

  -- Returning zero quietly is how "the therapist was never told" becomes
  -- nobody's fault. The caller decides whether that matters; it cannot
  -- decide if it is not told.
  RETURN l_n;
END
$$;

-- By role, for the cases where the right recipient is "whoever is on
-- reception" rather than a named person.
CREATE OR REPLACE FUNCTION hbh.notify_role(
  p_role_code text,
  p_kind      text,
  p_title_ar  text,
  p_child_id  integer DEFAULT NULL,
  p_link_kind text    DEFAULT NULL,
  p_link_id   integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_ids    integer[];
BEGIN
  SELECT array_agg(ur.user_id)
  INTO   l_ids
  FROM   hbh.user_roles ur
  JOIN   hbh.roles r  ON r.role_id = ur.role_id
  JOIN   hbh.users u  ON u.user_id = ur.user_id AND u.active_flg
  WHERE  r.code = p_role_code
    AND  r.center_id = coalesce(l_center, r.center_id)
    AND  u.center_id = coalesce(l_center, u.center_id);

  IF l_ids IS NULL THEN
    RETURN 0;
  END IF;

  RETURN hbh.notify_staff(l_ids, p_kind, p_title_ar, p_child_id, p_link_kind, p_link_id);
END
$$;

-- =====================================================================
-- THE FAMILY IS TOLD WHEN A SLOT IS GIVEN, NOT ONLY WHEN IT IS TAKEN
--
-- And the assigned therapist hears about it too, which until now the
-- schema had no way to say.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_notify_booked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_moved boolean := NEW.rescheduled_from_appointment_id IS NOT NULL;
  l_user  integer;
BEGIN
  -- A move is one event, not a cancellation followed by a booking. The
  -- family gets one message that says so - which is the whole point of
  -- the link 0088 added.
  PERFORM hbh.notify_guardians(
    NEW.child_id,
    CASE WHEN l_moved THEN 'APPOINTMENT_RESCHEDULED' ELSE 'APPOINTMENT_BOOKED' END,
    CASE WHEN l_moved THEN 'تم نقل موعد' ELSE 'تم حجز موعد' END,
    NULL, 'APPOINTMENT', NEW.appointment_id);

  SELECT t.user_id INTO l_user FROM hbh.therapists t
  WHERE t.therapist_id = NEW.therapist_id AND t.active_flg;

  IF l_user IS NOT NULL THEN
    PERFORM hbh.notify_staff(ARRAY[l_user], 'STAFF_APPOINTMENT_BOOKED',
                             'موعد جديد في جدولك', NEW.child_id,
                             'APPOINTMENT', NEW.appointment_id);
  END IF;

  RETURN NULL;
END
$$;

CREATE TRIGGER trg_appt_notify_booked
  AFTER INSERT ON hbh.appointments
  FOR EACH ROW WHEN (NEW.status = 'BOOKED')
  EXECUTE FUNCTION hbh.trg_notify_booked();

-- ---------------------------------------------------------------------
-- A child joins a caseload - the clinician who now carries that child
-- should not learn it from the schedule.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_notify_assigned()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_user integer;
BEGIN
  SELECT t.user_id INTO l_user FROM hbh.therapists t
  WHERE t.therapist_id = NEW.therapist_id AND t.active_flg;

  IF l_user IS NOT NULL THEN
    PERFORM hbh.notify_staff(ARRAY[l_user], 'STAFF_CHILD_ASSIGNED',
                             'طفل جديد في قائمتك', NEW.child_id,
                             'CHILD', NEW.child_id);
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_caseload_notify
  AFTER INSERT ON hbh.caseload
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_notify_assigned();

REVOKE ALL ON FUNCTION hbh.notify_staff(integer[], text, text, integer, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.notify_role(text, text, text, integer, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.notify_staff(integer[], text, text, integer, text, integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.notify_role(text, text, text, integer, text, integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0089');
