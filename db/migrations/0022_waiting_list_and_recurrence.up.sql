-- =====================================================================
-- Hand By Hand (new) - migration 0022: the waiting list, and booking a
-- course of sessions rather than one.
--
-- Both are things reception asks for on the first day, and both have an
-- obvious design that is wrong.
--
-- 1. A WAITING LIST IS NOT A QUEUE OF NAMES.
--    A family waiting for speech therapy is waiting for a slot that
--    suits them - Sunday mornings, not any Sunday, and not before the
--    school run. Storing a name and a date produces a list nobody can
--    act on, because matching it against a slot that just freed up
--    means ringing everybody. So the row carries the WINDOW the family
--    can attend, and waiting_candidates answers the only question that
--    matters: this slot just opened, who actually fits it?
--
-- 2. TWELVE WEEKLY SESSIONS ARE NOT ONE BOOKING.
--    Book a course across a public holiday and the honest outcome is
--    eleven appointments and one refusal with a reason. The obvious
--    designs are both wrong: failing all twelve because one clashed
--    wastes the eleven that were free, and skipping the clash silently
--    hands reception a course with a hole they find out about in six
--    weeks. book_recurring returns a row per occurrence saying which
--    happened and why the rest did not.
--
-- Error classes added here:
--   HB100  illegal waiting list status transition
--   HB101  not permitted
--   HB102  the offer is not in a state that can be accepted
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0022') THEN
    RAISE EXCEPTION 'migration 0022 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0021') THEN
    RAISE EXCEPTION 'migration 0021 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- RECURRENCE
--
-- A course of sessions is a set of ordinary appointments that know they
-- belong together. Not a separate table: every rule about a slot -
-- the exclusion constraints, the closures, the working hours - has to
-- apply to each of them exactly as it applies to a single booking, and
-- the surest way to guarantee that is for them to BE single bookings.
-- =====================================================================
CREATE SEQUENCE hbh.seq_recurrence_group;

ALTER TABLE hbh.appointments
  ADD COLUMN recurrence_group_id bigint,
  ADD COLUMN recurrence_index    smallint;

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ck_appointments_recurrence CHECK (
    (recurrence_group_id IS NULL) = (recurrence_index IS NULL));

CREATE INDEX ix_appointments_recurrence
  ON hbh.appointments (recurrence_group_id, recurrence_index)
  WHERE recurrence_group_id IS NOT NULL;

-- ---------------------------------------------------------------------
-- Booking a course
--
-- Returns one row per occurrence. ok says whether it was booked and
-- reason says why not - the same vocabulary validate_slot uses, so the
-- screen that explains a single refusal already explains these.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.book_recurring(
  p_center_id    integer,
  p_branch_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_first_start  timestamptz,
  p_first_end    timestamptz,
  p_occurrences  smallint,
  p_every_days   smallint DEFAULT 7,
  p_note_ar      text     DEFAULT NULL)
RETURNS TABLE (occurrence smallint, starts_at timestamptz, ok boolean,
               reason text, appointment_id integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_group bigint;
  l_i     smallint;
  l_from  timestamptz;
  l_to    timestamptz;
  l_check record;
  l_id    integer;
  l_no    text;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'booking a course needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  IF p_occurrences < 1 OR p_occurrences > 52 THEN
    RAISE EXCEPTION 'a course is between 1 and 52 sessions, not %', p_occurrences
      USING ERRCODE = 'HB021';
  END IF;

  l_group := nextval('hbh.seq_recurrence_group');

  FOR l_i IN 1 .. p_occurrences LOOP
    l_from := p_first_start + make_interval(days => (l_i - 1) * p_every_days);
    l_to   := p_first_end   + make_interval(days => (l_i - 1) * p_every_days);

    SELECT * INTO l_check
    FROM hbh.validate_slot(p_center_id, p_child_id, p_therapist_id, p_room_id,
                           p_service_id, l_from, l_to);

    IF NOT l_check.ok THEN
      -- Reported, not skipped. Reception has to KNOW which weeks are
      -- missing, or they find out in six weeks when a family arrives.
      occurrence := l_i; starts_at := l_from; ok := false;
      reason := l_check.reason; appointment_id := NULL;
      RETURN NEXT;
      CONTINUE;
    END IF;

    l_no := hbh.next_number(p_center_id, 'APPT');

    BEGIN
      INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                    therapist_id, room_id, service_id, starts_at, ends_at,
                                    note_ar, recurrence_group_id, recurrence_index)
      VALUES (p_center_id, p_branch_id, l_no, p_child_id, p_therapist_id, p_room_id,
              p_service_id, l_from, l_to, p_note_ar, l_group, l_i)
      RETURNING hbh.appointments.appointment_id INTO l_id;

      occurrence := l_i; starts_at := l_from; ok := true;
      reason := 'OK'; appointment_id := l_id;
    EXCEPTION WHEN exclusion_violation THEN
      -- Another booking landed between the check and the insert. The
      -- index caught it, and this occurrence is reported like any other
      -- refusal instead of taking the whole course down.
      occurrence := l_i; starts_at := l_from; ok := false;
      reason := 'SLOT_TAKEN'; appointment_id := NULL;
    END;

    RETURN NEXT;
  END LOOP;
END
$$;

-- Cancelling the rest of a course from a date onwards. The ones already
-- attended keep their history; only what has not happened is withdrawn.
CREATE OR REPLACE FUNCTION hbh.cancel_recurrence(
  p_group_id bigint,
  p_from     timestamptz,
  p_reason   text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.CANCEL') THEN
    RAISE EXCEPTION 'cancelling a course needs APPOINTMENT.CANCEL' USING ERRCODE = 'HB101';
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'a cancellation needs a stated reason' USING ERRCODE = 'HB101';
  END IF;

  UPDATE hbh.appointments
     SET status = 'CANCELLED', cancel_reason = p_reason
   WHERE recurrence_group_id = p_group_id
     AND starts_at >= p_from
     AND status IN ('BOOKED','CONFIRMED');

  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

-- =====================================================================
-- THE WAITING LIST
--
-- The window the family can attend is the whole point. A row with a
-- name and a date produces a list nobody can act on.
-- =====================================================================
CREATE TABLE hbh.waiting_list (
  wait_id        integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  branch_id      integer,
  child_id       integer     NOT NULL,
  service_id     integer     NOT NULL,
  therapist_id   integer,
  priority       smallint    NOT NULL DEFAULT 5,

  -- when they can actually come
  earliest_date  date        NOT NULL DEFAULT current_date,
  latest_date    date,
  weekdays       smallint[]  NOT NULL DEFAULT '{1,2,3,4,7}',
  time_from      time        NOT NULL DEFAULT '09:00',
  time_to        time        NOT NULL DEFAULT '17:00',

  status         text        NOT NULL DEFAULT 'WAITING',
  offered_appointment_id integer,
  offered_at     timestamptz,
  offer_expires_at timestamptz,
  requested_by   integer,
  note_ar        text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_waiting_list PRIMARY KEY (wait_id),
  CONSTRAINT fk_wait_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_wait_branch    FOREIGN KEY (branch_id)    REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_wait_child     FOREIGN KEY (child_id)     REFERENCES hbh.children (child_id),
  CONSTRAINT fk_wait_service   FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id),
  CONSTRAINT fk_wait_therapist FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_wait_appt      FOREIGN KEY (offered_appointment_id) REFERENCES hbh.appointments (appointment_id),
  CONSTRAINT fk_wait_requester FOREIGN KEY (requested_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_wait_status CHECK (status IN ('WAITING','OFFERED','BOOKED','EXPIRED','CANCELLED')),
  CONSTRAINT ck_wait_priority CHECK (priority BETWEEN 1 AND 9),
  CONSTRAINT ck_wait_window   CHECK (latest_date IS NULL OR latest_date >= earliest_date),
  CONSTRAINT ck_wait_time     CHECK (time_to > time_from),
  CONSTRAINT ck_wait_weekdays CHECK (weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]
                                     AND array_length(weekdays, 1) >= 1),
  -- An offer names the appointment it is an offer OF, and expires.
  CONSTRAINT ck_wait_offer CHECK (
    (status = 'OFFERED') = (offered_appointment_id IS NOT NULL AND offer_expires_at IS NOT NULL)
    OR status = 'BOOKED')
);

-- One live entry per child per service. Two would produce two offers
-- for one family and a race between them.
CREATE UNIQUE INDEX uix_wait_live
  ON hbh.waiting_list (child_id, service_id) WHERE status IN ('WAITING','OFFERED');

CREATE INDEX ix_wait_center    ON hbh.waiting_list (center_id, priority, created_at);
CREATE INDEX ix_wait_branch    ON hbh.waiting_list (branch_id);
CREATE INDEX ix_wait_child     ON hbh.waiting_list (child_id);
CREATE INDEX ix_wait_service   ON hbh.waiting_list (service_id);
CREATE INDEX ix_wait_therapist ON hbh.waiting_list (therapist_id);
CREATE INDEX ix_wait_appt      ON hbh.waiting_list (offered_appointment_id);
CREATE INDEX ix_wait_requester ON hbh.waiting_list (requested_by);
-- The queue reception actually reads.
CREATE INDEX ix_wait_open ON hbh.waiting_list (center_id, service_id, priority, created_at)
  WHERE status = 'WAITING';

CREATE OR REPLACE FUNCTION hbh.legal_wait_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('WAITING', 'OFFERED'),
    ('WAITING', 'CANCELLED'),
    ('WAITING', 'EXPIRED'),
    ('OFFERED', 'BOOKED'),
    -- An offer that lapses goes back to WAITING, keeping its place.
    ('OFFERED', 'WAITING'),
    ('OFFERED', 'CANCELLED'),
    ('OFFERED', 'EXPIRED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_wait_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_wait_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'waiting entry % cannot go from % to %', OLD.wait_id, OLD.status, NEW.status
      USING ERRCODE = 'HB100';
  END IF;
  RETURN NEW;
END
$$;

-- ---------------------------------------------------------------------
-- THIS SLOT JUST OPENED - WHO ACTUALLY FITS IT?
--
-- The one question a waiting list exists to answer. A family whose
-- window does not cover the slot is not a candidate, however long they
-- have waited, so the ordering is over people who can actually come.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.waiting_candidates(
  p_center_id    integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_therapist_id integer DEFAULT NULL,
  p_limit        integer DEFAULT 20)
RETURNS TABLE (wait_id integer, child_id integer, priority smallint,
               waiting_since timestamptz, therapist_id integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_tz      text;
  l_local   timestamp;
  l_weekday smallint;
BEGIN
  SELECT c.time_zone INTO l_tz FROM hbh.centers c WHERE c.center_id = p_center_id;
  IF NOT FOUND THEN RETURN; END IF;

  -- The family's window is written in the centre's local clock, so the
  -- instant is rendered there before it is compared. Asking in UTC puts
  -- a Cairo evening slot on the wrong day for three hours of every day.
  l_local   := p_starts_at AT TIME ZONE l_tz;
  l_weekday := extract(isodow FROM l_local)::smallint;

  RETURN QUERY
  SELECT w.wait_id, w.child_id, w.priority, w.created_at, w.therapist_id
  FROM   hbh.waiting_list w
  WHERE  w.status = 'WAITING'
  AND    w.active_flg
  AND    w.center_id  = p_center_id
  AND    w.service_id = p_service_id
  AND    l_weekday = ANY (w.weekdays)
  AND    l_local::date >= w.earliest_date
  AND    (w.latest_date IS NULL OR l_local::date <= w.latest_date)
  AND    w.time_from <= l_local::time
  AND    w.time_to   >= (p_ends_at AT TIME ZONE l_tz)::time
  -- A family that asked for a particular therapist is not a candidate
  -- for somebody else's slot.
  AND    (w.therapist_id IS NULL OR p_therapist_id IS NULL OR w.therapist_id = p_therapist_id)
  ORDER  BY w.priority, w.created_at
  LIMIT  p_limit;
END
$$;

CREATE OR REPLACE FUNCTION hbh.add_to_waiting_list(
  p_child_id      integer,
  p_service_id    integer,
  p_therapist_id  integer    DEFAULT NULL,
  p_priority      smallint   DEFAULT 5,
  p_earliest_date date       DEFAULT current_date,
  p_latest_date   date       DEFAULT NULL,
  p_weekdays      smallint[] DEFAULT '{1,2,3,4,7}',
  p_time_from     time       DEFAULT '09:00',
  p_time_to       time       DEFAULT '17:00',
  p_note_ar       text       DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'adding to the waiting list needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB101';
  END IF;

  INSERT INTO hbh.waiting_list (center_id, branch_id, child_id, service_id, therapist_id,
                                priority, earliest_date, latest_date, weekdays,
                                time_from, time_to, requested_by, note_ar)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_service_id, p_therapist_id,
          p_priority, p_earliest_date, p_latest_date, p_weekdays,
          p_time_from, p_time_to, hbh.current_user_id(), p_note_ar)
  RETURNING wait_id INTO l_id;

  RETURN l_id;
END
$$;

-- Offering a slot holds it for the family for a while. The hold has an
-- expiry because an offer nobody answers must not block the slot for
-- everyone else for ever.
CREATE OR REPLACE FUNCTION hbh.offer_slot(
  p_wait_id        integer,
  p_appointment_id integer,
  p_hold_hours     integer DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_w     hbh.waiting_list%ROWTYPE;
  l_hours integer;
  l_exp   timestamptz;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'offering a slot needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND OR l_w.status <> 'WAITING' THEN
    RAISE EXCEPTION 'waiting entry % is not waiting', p_wait_id USING ERRCODE = 'HB102';
  END IF;

  l_hours := coalesce(p_hold_hours,
                      hbh.param(l_w.center_id, 'WAITLIST_OFFER_HOURS', '48')::integer);
  l_exp   := now() + make_interval(hours => l_hours);

  UPDATE hbh.waiting_list
     SET status = 'OFFERED', offered_appointment_id = p_appointment_id,
         offered_at = now(), offer_expires_at = l_exp
   WHERE wait_id = p_wait_id;

  RETURN l_exp;
END
$$;

CREATE OR REPLACE FUNCTION hbh.accept_offer(p_wait_id integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_w hbh.waiting_list%ROWTYPE;
BEGIN
  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND OR l_w.status <> 'OFFERED' THEN
    RAISE EXCEPTION 'waiting entry % has no live offer', p_wait_id USING ERRCODE = 'HB102';
  END IF;
  IF l_w.offer_expires_at <= now() THEN
    RAISE EXCEPTION 'the offer on waiting entry % expired at %', p_wait_id, l_w.offer_expires_at
      USING ERRCODE = 'HB102';
  END IF;

  UPDATE hbh.waiting_list SET status = 'BOOKED' WHERE wait_id = p_wait_id;
  RETURN true;
END
$$;

-- Lapsed offers go back to WAITING keeping their place in the queue.
-- Called by run_maintenance; changes state and raises nothing.
CREATE OR REPLACE FUNCTION hbh.release_expired_offers()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  UPDATE hbh.waiting_list
     SET status = 'WAITING', offered_appointment_id = NULL,
         offered_at = NULL, offer_expires_at = NULL
   WHERE status = 'OFFERED' AND offer_expires_at <= now();
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_wait_touch  BEFORE UPDATE ON hbh.waiting_list
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_wait_status BEFORE UPDATE ON hbh.waiting_list
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_wait_status();
CREATE TRIGGER trg_wait_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.waiting_list
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('wait_id');

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- A family sees their own place in the queue - "you are on the list" is
-- exactly what they ring to ask. They do NOT see anybody else's, and
-- they do not see the priority ordering of other children.
-- =====================================================================
ALTER TABLE hbh.waiting_list ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_wait_select ON hbh.waiting_list
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.can_access_child(child_id));

CREATE POLICY p_wait_update ON hbh.waiting_list
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('APPOINTMENT.BOOK'))
  WITH CHECK (center_id = hbh.current_center_id()
         AND hbh.has_permission('APPOINTMENT.BOOK'));

GRANT SELECT, UPDATE ON hbh.waiting_list TO hbh_app;

REVOKE ALL ON FUNCTION hbh.book_recurring(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, smallint, smallint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.cancel_recurrence(bigint, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.waiting_candidates(integer, integer, timestamptz, timestamptz, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.add_to_waiting_list(integer, integer, integer, smallint, date, date, smallint[], time, time, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.offer_slot(integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.accept_offer(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.release_expired_offers() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.book_recurring(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, smallint, smallint, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.cancel_recurrence(bigint, timestamptz, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.waiting_candidates(integer, integer, timestamptz, timestamptz, integer, integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.add_to_waiting_list(integer, integer, integer, smallint, date, date, smallint[], time, time, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.offer_slot(integer, integer, integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.accept_offer(integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.release_expired_offers() TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_wait_transition(text, text) TO hbh_app;

GRANT USAGE, SELECT ON SEQUENCE hbh.seq_recurrence_group TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'WAITLIST_OFFER_HOURS', '48', 'NUMBER',
   'كم ساعة تُحجَز الفتحة لأسرة عُرضت عليها قبل أن تعود للطابور')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.schema_migrations (version) VALUES ('0022');
