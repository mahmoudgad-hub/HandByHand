-- =====================================================================
-- Hand By Hand (new) - migration 0005: scheduling and sessions
--
-- Three decisions carried over from the Oracle system, and one that
-- replaces an Oracle workaround with something Postgres does properly.
--
-- 1. TWO STATUSES, TWO QUESTIONS.
--    appointments.status answers "did the visit happen?"
--    therapy_sessions.status answers "did the clinical work finish?"
--    A child who arrives and tires after five minutes leaves an
--    appointment that is COMPLETED - the slot and the therapist were
--    consumed - and a session that is ABORTED. Whether the family is
--    charged is a THIRD question, is_billable_flg, and it lives on
--    both rows. Collapsing the three into one status is precisely what
--    makes attendance reports and invoices contradict each other.
--
-- 2. ONE CHILD PER SESSION. child_id sits directly on the appointment
--    and on the session. There is no participant table and there will
--    not be one.
--
-- 3. A STATUS IS A STATE MACHINE WITH A HISTORY, NEVER A FREE UPDATE.
--    Legality is enforced by a trigger, not only by the API, so a
--    direct UPDATE cannot walk around it. The history row is written by
--    a second trigger for the same reason.
--
-- 4. DOUBLE BOOKING IS PREVENTED BY THE INDEX, NOT BY A LOCK.
--    The Oracle version took row locks on therapist, room and child in
--    a fixed order before the decisive check, because Oracle has no way
--    to say "these ranges may not overlap". Postgres does: an EXCLUDE
--    constraint over a GiST index. Two receptionists pressing save at
--    the same instant are serialised by the index itself, and the
--    second one is refused - no lock ordering to get wrong, and no
--    window between the check and the insert. Carrying the Oracle lock
--    across as well would be cargo cult.
--
-- Error classes added here:
--   HB020  illegal appointment status transition
--   HB021  the requested slot is not valid (reason in the message)
--   HB022  the appointment already has a session
--   HB023  the therapist is not on this child's caseload
--   HB024  the child has not been checked in
--   HB025  illegal session status transition
--   HB026  not permitted to close this session
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0005') THEN
    RAISE EXCEPTION 'migration 0005 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0004') THEN
    RAISE EXCEPTION 'migration 0004 must be applied first';
  END IF;
END
$guard$;

-- btree_gist is what lets an exclusion constraint mix plain equality on
-- an integer with range overlap in the same index.
CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;

-- =====================================================================
-- MASTER DATA
-- =====================================================================
CREATE TABLE hbh.services (
  service_id           integer     GENERATED ALWAYS AS IDENTITY,
  center_id            integer     NOT NULL,
  branch_id            integer,
  code                 text        NOT NULL,
  name_ar              text        NOT NULL,
  name_en              text,
  kind_code            text        NOT NULL,
  default_duration_min smallint    NOT NULL DEFAULT 45,
  color_hex            text,
  sort_order           integer     NOT NULL DEFAULT 100,
  active_flg           boolean     NOT NULL DEFAULT true,
  deleted_at           timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at           timestamptz,
  updated_by           text,
  CONSTRAINT pk_services PRIMARY KEY (service_id),
  CONSTRAINT fk_services_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_services_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT uq_services_code UNIQUE (center_id, code),
  CONSTRAINT ck_services_duration CHECK (default_duration_min BETWEEN 5 AND 480),
  -- A regex PREDICATE is legal in a check constraint; a regex function
  -- that returns a value is not. This is the legal shape.
  CONSTRAINT ck_services_color CHECK (color_hex IS NULL OR color_hex ~ '^#[0-9A-Fa-f]{6}$')
);

CREATE INDEX ix_services_center ON hbh.services (center_id);
CREATE INDEX ix_services_branch ON hbh.services (branch_id);

CREATE TABLE hbh.rooms (
  room_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id  integer     NOT NULL,
  branch_id  integer,
  code       text        NOT NULL,
  name_ar    text        NOT NULL,
  name_en    text,
  notes_ar   text,
  active_flg boolean     NOT NULL DEFAULT true,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at timestamptz,
  updated_by text,
  CONSTRAINT pk_rooms PRIMARY KEY (room_id),
  CONSTRAINT fk_rooms_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_rooms_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT uq_rooms_code UNIQUE (center_id, code)
);

CREATE INDEX ix_rooms_center ON hbh.rooms (center_id);
CREATE INDEX ix_rooms_branch ON hbh.rooms (branch_id);

-- ON_LEAVE and RESIGNED, and no INACTIVE.
--
-- A Phase 4 test in the Oracle system set a therapist to 'INACTIVE',
-- got a refusal, and believed it had proven the rule under test. It had
-- proven a CHECK constraint. The states are named here so a test cannot
-- make that mistake quietly.
CREATE TABLE hbh.therapists (
  therapist_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  user_id      integer,
  full_name_ar text        NOT NULL,
  mobile       text,
  title_ar     text,
  status       text        NOT NULL DEFAULT 'ACTIVE',
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_therapists PRIMARY KEY (therapist_id),
  CONSTRAINT fk_therapists_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_therapists_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_therapists_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT ck_therapists_status CHECK (status IN ('ACTIVE','ON_LEAVE','RESIGNED')),
  CONSTRAINT ck_therapists_mobile CHECK (mobile IS NULL OR mobile ~ '^[0-9+]{6,20}$')
);

CREATE INDEX ix_therapists_center    ON hbh.therapists (center_id);
CREATE INDEX ix_therapists_branch    ON hbh.therapists (branch_id);
CREATE INDEX ix_therapists_name_srch ON hbh.therapists (hbh.normalize_arabic(full_name_ar));
CREATE UNIQUE INDEX uix_therapists_user ON hbh.therapists (user_id) WHERE user_id IS NOT NULL;

CREATE TABLE hbh.therapist_services (
  therapist_id integer     NOT NULL,
  service_id   integer     NOT NULL,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_therapist_services PRIMARY KEY (therapist_id, service_id),
  CONSTRAINT fk_therapist_services_t FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_therapist_services_s FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id)
);

CREATE INDEX ix_therapist_services_s ON hbh.therapist_services (service_id);

-- Working hours. The Oracle project lost a round trip in Phase 6 to a
-- forgotten row here: correct code refused a correct booking, dozens of
-- tests away from the cause. The acceptance suite asserts these by name.
CREATE TABLE hbh.therapist_working_hours (
  working_hour_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  therapist_id    integer     NOT NULL,
  -- ISO day of week: 1 = Monday .. 7 = Sunday.
  weekday         smallint    NOT NULL,
  start_time      time        NOT NULL,
  end_time        time        NOT NULL,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_therapist_working_hours PRIMARY KEY (working_hour_id),
  CONSTRAINT fk_twh_center     FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_twh_therapist  FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT ck_twh_weekday    CHECK (weekday BETWEEN 1 AND 7),
  CONSTRAINT ck_twh_window     CHECK (end_time > start_time)
);

CREATE INDEX ix_twh_therapist ON hbh.therapist_working_hours (therapist_id, weekday);
CREATE INDEX ix_twh_center    ON hbh.therapist_working_hours (center_id);

-- Caseload: which therapist is responsible for which child, per service.
--
-- Booking does NOT require it - reception books before assignment is
-- settled. STARTING A SESSION does. That is the same boundary the
-- Oracle system drew, and the reason a Phase 5 test there was refused
-- with the wrong error code for twenty minutes.
CREATE TABLE hbh.caseload (
  caseload_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  therapist_id   integer     NOT NULL,
  child_id       integer     NOT NULL,
  service_id     integer     NOT NULL,
  is_primary_flg boolean     NOT NULL DEFAULT false,
  assigned_date  date        NOT NULL DEFAULT current_date,
  ended_date     date,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_caseload PRIMARY KEY (caseload_id),
  CONSTRAINT fk_caseload_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_caseload_therapist FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_caseload_child     FOREIGN KEY (child_id)     REFERENCES hbh.children (child_id),
  CONSTRAINT fk_caseload_service   FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id),
  CONSTRAINT ck_caseload_window    CHECK (ended_date IS NULL OR ended_date >= assigned_date)
);

CREATE UNIQUE INDEX uix_caseload_live
  ON hbh.caseload (therapist_id, child_id, service_id) WHERE active_flg;
CREATE INDEX ix_caseload_center  ON hbh.caseload (center_id);
CREATE INDEX ix_caseload_child   ON hbh.caseload (child_id);
CREATE INDEX ix_caseload_service ON hbh.caseload (service_id);

-- =====================================================================
-- APPOINTMENTS
-- =====================================================================
CREATE TABLE hbh.appointments (
  appointment_id  integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  branch_id       integer,
  appointment_no  text        NOT NULL,
  child_id        integer     NOT NULL,
  therapist_id    integer     NOT NULL,
  room_id         integer     NOT NULL,
  service_id      integer     NOT NULL,
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  status          text        NOT NULL DEFAULT 'BOOKED',
  cancel_reason   text,
  note_ar         text,
  -- The third question, and it is neither of the two statuses.
  is_billable_flg boolean     NOT NULL DEFAULT true,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_appointments PRIMARY KEY (appointment_id),
  CONSTRAINT fk_appointments_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_appointments_branch    FOREIGN KEY (branch_id)    REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_appointments_child     FOREIGN KEY (child_id)     REFERENCES hbh.children (child_id),
  CONSTRAINT fk_appointments_therapist FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_appointments_room      FOREIGN KEY (room_id)      REFERENCES hbh.rooms (room_id),
  CONSTRAINT fk_appointments_service   FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id),
  CONSTRAINT uq_appointments_no UNIQUE (center_id, appointment_no),
  CONSTRAINT ck_appointments_window CHECK (ends_at > starts_at),
  CONSTRAINT ck_appointments_status CHECK (status IN
    ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED','CANCELLED','NO_SHOW')),
  -- A cancellation without a stated reason is a row nobody can explain
  -- to a parent six weeks later.
  CONSTRAINT ck_appointments_cancel CHECK (
    (status = 'CANCELLED') = (cancel_reason IS NOT NULL))
);

CREATE INDEX ix_appointments_center    ON hbh.appointments (center_id);
CREATE INDEX ix_appointments_branch    ON hbh.appointments (branch_id);
CREATE INDEX ix_appointments_child     ON hbh.appointments (child_id, starts_at DESC);
CREATE INDEX ix_appointments_therapist ON hbh.appointments (therapist_id, starts_at DESC);
CREATE INDEX ix_appointments_room      ON hbh.appointments (room_id, starts_at DESC);
CREATE INDEX ix_appointments_service   ON hbh.appointments (service_id);
CREATE INDEX ix_appointments_day       ON hbh.appointments (center_id, starts_at)
  WHERE status IN ('BOOKED','CONFIRMED','CHECKED_IN');

-- ---------------------------------------------------------------------
-- The three constraints that make double booking impossible
--
-- Not "unlikely" - impossible. The index serialises the two inserts, so
-- there is no window between checking and writing for a second
-- receptionist to slip through. CANCELLED and NO_SHOW rows are excluded
-- because a cancelled slot is free.
--
-- A violation raises 23P01, which book_appointment turns into a
-- readable reason. Anything writing to this table directly still gets
-- the refusal - that is the point of putting it here rather than in a
-- function.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_therapist
  EXCLUDE USING gist (
    therapist_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED'));

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_room
  EXCLUDE USING gist (
    room_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED'));

ALTER TABLE hbh.appointments
  ADD CONSTRAINT ex_appointments_child
  EXCLUDE USING gist (
    child_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  ) WHERE (status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED'));

CREATE TABLE hbh.appointment_status_history (
  history_id     bigint      GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  appointment_id integer     NOT NULL,
  from_status    text,
  to_status      text        NOT NULL,
  reason         text,
  note_ar        text,
  changed_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_appointment_status_history PRIMARY KEY (history_id),
  CONSTRAINT fk_ash_center      FOREIGN KEY (center_id)      REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ash_appointment FOREIGN KEY (appointment_id) REFERENCES hbh.appointments (appointment_id)
);

CREATE INDEX ix_ash_appointment ON hbh.appointment_status_history (appointment_id, changed_at DESC);
CREATE INDEX ix_ash_center      ON hbh.appointment_status_history (center_id);

CREATE TRIGGER trg_ash_append_only
  BEFORE UPDATE OR DELETE ON hbh.appointment_status_history
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- SESSIONS
-- =====================================================================
CREATE TABLE hbh.therapy_sessions (
  session_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  branch_id       integer,
  appointment_id  integer     NOT NULL,
  child_id        integer     NOT NULL,
  therapist_id    integer     NOT NULL,
  room_id         integer     NOT NULL,
  service_id      integer     NOT NULL,
  started_at      timestamptz NOT NULL DEFAULT now(),
  ended_at        timestamptz,
  status          text        NOT NULL DEFAULT 'IN_PROGRESS',
  abort_reason    text,
  is_billable_flg boolean     NOT NULL DEFAULT true,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_therapy_sessions PRIMARY KEY (session_id),
  CONSTRAINT fk_ts_center      FOREIGN KEY (center_id)      REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ts_branch      FOREIGN KEY (branch_id)      REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_ts_appointment FOREIGN KEY (appointment_id) REFERENCES hbh.appointments (appointment_id),
  CONSTRAINT fk_ts_child       FOREIGN KEY (child_id)       REFERENCES hbh.children (child_id),
  CONSTRAINT fk_ts_therapist   FOREIGN KEY (therapist_id)   REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_ts_room        FOREIGN KEY (room_id)        REFERENCES hbh.rooms (room_id),
  CONSTRAINT fk_ts_service     FOREIGN KEY (service_id)     REFERENCES hbh.services (service_id),
  -- One session per appointment. A second one would be a second answer
  -- to "did the clinical work finish", for a visit that happened once.
  CONSTRAINT uq_ts_appointment UNIQUE (appointment_id),
  CONSTRAINT ck_ts_status CHECK (status IN ('IN_PROGRESS','COMPLETED','ABORTED')),
  CONSTRAINT ck_ts_window CHECK (ended_at IS NULL OR ended_at >= started_at),
  CONSTRAINT ck_ts_closed CHECK ((status = 'IN_PROGRESS') = (ended_at IS NULL)),
  CONSTRAINT ck_ts_abort  CHECK ((status = 'ABORTED') = (abort_reason IS NOT NULL))
);

CREATE INDEX ix_ts_center    ON hbh.therapy_sessions (center_id);
CREATE INDEX ix_ts_branch    ON hbh.therapy_sessions (branch_id);
CREATE INDEX ix_ts_child     ON hbh.therapy_sessions (child_id, started_at DESC);
CREATE INDEX ix_ts_therapist ON hbh.therapy_sessions (therapist_id, started_at DESC);
CREATE INDEX ix_ts_room      ON hbh.therapy_sessions (room_id);
CREATE INDEX ix_ts_service   ON hbh.therapy_sessions (service_id);
CREATE INDEX ix_ts_live      ON hbh.therapy_sessions (center_id) WHERE status = 'IN_PROGRESS';

CREATE TABLE hbh.session_status_history (
  history_id  bigint      GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  session_id  integer     NOT NULL,
  from_status text,
  to_status   text        NOT NULL,
  reason      text,
  changed_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_session_status_history PRIMARY KEY (history_id),
  CONSTRAINT fk_ssh_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ssh_session FOREIGN KEY (session_id) REFERENCES hbh.therapy_sessions (session_id)
);

CREATE INDEX ix_ssh_session ON hbh.session_status_history (session_id, changed_at DESC);
CREATE INDEX ix_ssh_center  ON hbh.session_status_history (center_id);

CREATE TRIGGER trg_ssh_append_only
  BEFORE UPDATE OR DELETE ON hbh.session_status_history
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- THE STATE MACHINES
-- =====================================================================

-- Returns FALSE for a status to itself.
--
-- The Oracle version returned TRUE for that case - harmless inside the
-- API, a lie on a menu. It offered "confirm this appointment" for an
-- already-confirmed appointment, and pressing it looked like it worked
-- while changing nothing. Every list built on that function then had to
-- remember to add "AND target <> current". Returning FALSE removes the
-- trap at the source; a caller that wants a no-op can say so.
CREATE OR REPLACE FUNCTION hbh.legal_appointment_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('BOOKED',     'CONFIRMED'),
    ('BOOKED',     'CANCELLED'),
    ('BOOKED',     'NO_SHOW'),
    ('CONFIRMED',  'CHECKED_IN'),
    ('CONFIRMED',  'CANCELLED'),
    ('CONFIRMED',  'NO_SHOW'),
    ('CHECKED_IN', 'COMPLETED'),
    ('CHECKED_IN', 'CANCELLED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.legal_session_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('IN_PROGRESS', 'COMPLETED'),
    ('IN_PROGRESS', 'ABORTED')
  )
$$;

-- Enforced in a trigger, so a direct UPDATE cannot skip the machine.
CREATE OR REPLACE FUNCTION hbh.trg_appointment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_appointment_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'appointment % cannot go from % to %',
                    OLD.appointment_id, OLD.status, NEW.status
      USING ERRCODE = 'HB020';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_appointment_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO hbh.appointment_status_history (center_id, appointment_id, from_status, to_status, note_ar)
    VALUES (NEW.center_id, NEW.appointment_id, NULL, NEW.status, NEW.note_ar);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO hbh.appointment_status_history (center_id, appointment_id, from_status, to_status, reason)
    VALUES (NEW.center_id, NEW.appointment_id, OLD.status, NEW.status,
            CASE WHEN NEW.status = 'CANCELLED' THEN NEW.cancel_reason END);
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_session_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_session_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'session % cannot go from % to %', OLD.session_id, OLD.status, NEW.status
      USING ERRCODE = 'HB025';
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_session_history()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO hbh.session_status_history (center_id, session_id, from_status, to_status)
    VALUES (NEW.center_id, NEW.session_id, NULL, NEW.status);
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO hbh.session_status_history (center_id, session_id, from_status, to_status, reason)
    VALUES (NEW.center_id, NEW.session_id, OLD.status, NEW.status, NEW.abort_reason);
  END IF;
  RETURN NEW;
END
$$;

-- =====================================================================
-- SLOT VALIDATION
--
-- Returns a reason rather than raising, so a booking screen can say
-- what is wrong without a round trip through an exception.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.validate_slot(
  p_center_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_exclude_id   integer DEFAULT NULL)
RETURNS TABLE (ok boolean, reason text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_tz        text;
  l_weekend   smallint[];
  l_local     timestamp;
  l_weekday   smallint;
  l_backdays  integer;
BEGIN
  IF p_ends_at <= p_starts_at THEN
    RETURN QUERY SELECT false, 'BAD_WINDOW'; RETURN;
  END IF;

  SELECT c.time_zone, c.weekend_days INTO l_tz, l_weekend
  FROM hbh.centers c WHERE c.center_id = p_center_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_SUCH_CENTRE'; RETURN;
  END IF;

  -- The weekend and the working day are questions about the centre's
  -- LOCAL calendar, so the instant is rendered in the centre's zone
  -- before either is asked. Asking them in UTC puts a Cairo evening
  -- appointment on the wrong day for three hours of every day.
  l_local   := p_starts_at AT TIME ZONE l_tz;
  l_weekday := extract(isodow FROM l_local)::smallint;

  l_backdays := hbh.param(p_center_id, 'ALLOW_BACKDATED_BOOKING_DAYS', '0')::integer;
  IF l_local::date < (now() AT TIME ZONE l_tz)::date - l_backdays THEN
    RETURN QUERY SELECT false, 'IN_THE_PAST'; RETURN;
  END IF;

  IF l_weekday = ANY (l_weekend) THEN
    RETURN QUERY SELECT false, 'WEEKEND'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                 WHERE t.therapist_id = p_therapist_id AND t.center_id = p_center_id
                   AND t.active_flg AND t.status = 'ACTIVE') THEN
    RETURN QUERY SELECT false, 'THERAPIST_UNAVAILABLE'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.rooms r
                 WHERE r.room_id = p_room_id AND r.center_id = p_center_id AND r.active_flg) THEN
    RETURN QUERY SELECT false, 'ROOM_UNAVAILABLE'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_services ts
                 WHERE ts.therapist_id = p_therapist_id AND ts.service_id = p_service_id
                   AND ts.active_flg) THEN
    RETURN QUERY SELECT false, 'THERAPIST_SERVICE_MISMATCH'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_working_hours w
                 WHERE w.therapist_id = p_therapist_id AND w.active_flg
                   AND w.weekday = l_weekday
                   AND w.start_time <= l_local::time
                   AND w.end_time   >= (p_ends_at AT TIME ZONE l_tz)::time) THEN
    RETURN QUERY SELECT false, 'OUTSIDE_WORKING_HOURS'; RETURN;
  END IF;

  -- These three duplicate the exclusion constraints on purpose: the
  -- constraint is the guarantee, this is the explanation. Without it a
  -- booking screen could only say "23P01".
  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.therapist_id = p_therapist_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')) THEN
    RETURN QUERY SELECT false, 'THERAPIST_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.room_id = p_room_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')) THEN
    RETURN QUERY SELECT false, 'ROOM_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.child_id = p_child_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(p_starts_at, p_ends_at, '[)')) THEN
    RETURN QUERY SELECT false, 'CHILD_BUSY'; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK';
END
$$;

-- =====================================================================
-- BOOKING
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.book_appointment(
  p_center_id    integer,
  p_branch_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_note_ar      text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_check  record;
  l_no     text;
  l_id     integer;
BEGIN
  SELECT * INTO l_check
  FROM hbh.validate_slot(p_center_id, p_child_id, p_therapist_id, p_room_id,
                         p_service_id, p_starts_at, p_ends_at);
  IF NOT l_check.ok THEN
    RAISE EXCEPTION 'slot rejected: %', l_check.reason USING ERRCODE = 'HB021';
  END IF;

  l_no := hbh.next_number(p_center_id, 'APPT');

  BEGIN
    INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                  therapist_id, room_id, service_id, starts_at, ends_at, note_ar)
    VALUES (p_center_id, p_branch_id, l_no, p_child_id, p_therapist_id, p_room_id,
            p_service_id, p_starts_at, p_ends_at, p_note_ar)
    RETURNING appointment_id INTO l_id;
  EXCEPTION WHEN exclusion_violation THEN
    -- Another transaction committed the same slot between the check and
    -- this insert. The index caught it - which is the whole point - and
    -- the caller gets the same reason it would have got a moment
    -- earlier, instead of a raw 23P01.
    RAISE EXCEPTION 'slot rejected: SLOT_TAKEN' USING ERRCODE = 'HB021';
  END;

  RETURN l_id;
END
$$;

-- =====================================================================
-- SESSIONS
-- =====================================================================

-- Closing a session and authoring its notes are DIFFERENT rights.
--
-- The Oracle system asked one gate for both, and it demanded
-- CHILD.VIEW_ALL together with SESSION.NOTES.EDIT. The seed withholds
-- NOTES.EDIT from administrators on purpose - a clinical note is
-- written by the clinician who was in the room - so reception could
-- start a session that nobody but the assigned therapist could end, and
-- the screen refused a user holding the very permission the action was
-- named after.
--
-- When notes arrive they get their OWN gate, can_edit_session, and it
-- must not be this one.
CREATE OR REPLACE FUNCTION hbh.can_close_session(p_session_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    -- the therapist who ran it
    SELECT 1 FROM hbh.therapy_sessions s
    JOIN   hbh.therapists t ON t.therapist_id = s.therapist_id
    WHERE  s.session_id = p_session_id
    AND    t.user_id = hbh.current_user_id()

    UNION ALL

    -- or an administrator: STAFF holding both rights.
    --
    -- user_type = 'STAFF' is load-bearing, and the acceptance suite is
    -- what found it. Without it, the THERAPIST role - which holds
    -- CHILD.VIEW_ALL so a clinician can cover for a colleague, and
    -- SESSION.COMPLETE so they can close their own work - let ANY
    -- therapist close ANY other therapist's session. That is not an
    -- administrative override, it is no rule at all.
    --
    -- The line the system draws: a clinician closes their own work; an
    -- administrator may close anyone's. Two different justifications,
    -- so two different branches.
    SELECT 1 FROM hbh.therapy_sessions s
    JOIN   hbh.users u ON u.user_id = hbh.current_user_id()
    WHERE  s.session_id = p_session_id
    AND    u.user_type = 'STAFF'
    AND    hbh.has_permission('CHILD.VIEW_ALL')
    AND    hbh.has_permission('SESSION.COMPLETE')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.start_session(p_appointment_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_appt hbh.appointments%ROWTYPE;
  l_id   integer;
BEGIN
  SELECT * INTO l_appt FROM hbh.appointments a
  WHERE a.appointment_id = p_appointment_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such appointment %', p_appointment_id USING ERRCODE = 'HB021';
  END IF;

  -- The child must be in the building. This is the check, and a test
  -- that expects it must assert HB024 and nothing else - a refusal for
  -- some other reason has proven nothing.
  IF l_appt.status <> 'CHECKED_IN' THEN
    RAISE EXCEPTION 'appointment % is % - a session starts only from CHECKED_IN',
                    p_appointment_id, l_appt.status
      USING ERRCODE = 'HB024';
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.therapy_sessions s WHERE s.appointment_id = p_appointment_id) THEN
    RAISE EXCEPTION 'appointment % already has a session', p_appointment_id
      USING ERRCODE = 'HB022';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.caseload c
                 WHERE c.therapist_id = l_appt.therapist_id
                   AND c.child_id = l_appt.child_id
                   AND c.service_id = l_appt.service_id
                   AND c.active_flg) THEN
    RAISE EXCEPTION 'therapist % is not on child %''s caseload for this service',
                    l_appt.therapist_id, l_appt.child_id
      USING ERRCODE = 'HB023';
  END IF;

  INSERT INTO hbh.therapy_sessions (center_id, branch_id, appointment_id, child_id,
                                    therapist_id, room_id, service_id)
  VALUES (l_appt.center_id, l_appt.branch_id, p_appointment_id, l_appt.child_id,
          l_appt.therapist_id, l_appt.room_id, l_appt.service_id)
  RETURNING session_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.close_session(
  p_session_id integer,
  p_status     text,
  p_reason     text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.can_close_session(p_session_id) THEN
    RAISE EXCEPTION 'not permitted to close session %', p_session_id USING ERRCODE = 'HB026';
  END IF;

  UPDATE hbh.therapy_sessions
     SET status       = p_status,
         ended_at     = now(),
         abort_reason = CASE WHEN p_status = 'ABORTED' THEN p_reason END
   WHERE session_id = p_session_id;

  -- The appointment is a separate question and gets its own answer: the
  -- visit happened either way, so it completes even when the clinical
  -- work did not.
  UPDATE hbh.appointments a
     SET status = 'COMPLETED'
   WHERE a.appointment_id = (SELECT s.appointment_id FROM hbh.therapy_sessions s
                             WHERE s.session_id = p_session_id)
     AND a.status = 'CHECKED_IN';
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_services_touch      BEFORE UPDATE ON hbh.services      FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_rooms_touch         BEFORE UPDATE ON hbh.rooms         FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_therapists_touch    BEFORE UPDATE ON hbh.therapists    FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_tsvc_touch          BEFORE UPDATE ON hbh.therapist_services FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_twh_touch           BEFORE UPDATE ON hbh.therapist_working_hours FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_caseload_touch      BEFORE UPDATE ON hbh.caseload      FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_appointments_touch  BEFORE UPDATE ON hbh.appointments  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_ts_touch            BEFORE UPDATE ON hbh.therapy_sessions FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- The state machine runs BEFORE the history is written, so an illegal
-- move leaves no trace of having been attempted on the row itself.
CREATE TRIGGER trg_appointments_status BEFORE UPDATE ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_appointment_status();
CREATE TRIGGER trg_appointments_history AFTER INSERT OR UPDATE ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_appointment_history();

CREATE TRIGGER trg_ts_status BEFORE UPDATE ON hbh.therapy_sessions
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_session_status();
CREATE TRIGGER trg_ts_history AFTER INSERT OR UPDATE ON hbh.therapy_sessions
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_session_history();

CREATE TRIGGER trg_appointments_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.appointments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('appointment_id');
CREATE TRIGGER trg_ts_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.therapy_sessions
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('session_id');
CREATE TRIGGER trg_caseload_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.caseload
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('caseload_id');

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- The gate composes: an appointment is reachable exactly when its child
-- is. Nothing here restates who may see which child.
-- =====================================================================
ALTER TABLE hbh.services                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.rooms                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapists               ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapist_services       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapist_working_hours  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.caseload                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.appointments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.appointment_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapy_sessions         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.session_status_history   ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_services_select ON hbh.services
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_rooms_select ON hbh.rooms
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_therapists_select ON hbh.therapists
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_therapist_services_select ON hbh.therapist_services
  FOR SELECT TO hbh_app
  USING (active_flg AND EXISTS (
    SELECT 1 FROM hbh.therapists t
    WHERE t.therapist_id = hbh.therapist_services.therapist_id
      AND t.center_id = hbh.current_center_id()));

-- Working hours are rota information. A parent has no business with it.
CREATE POLICY p_twh_select ON hbh.therapist_working_hours
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('CHILD.VIEW_ALL'));

CREATE POLICY p_caseload_select ON hbh.caseload
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.can_access_child(child_id));

CREATE POLICY p_appointments_select ON hbh.appointments
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_access_child(child_id));

CREATE POLICY p_ash_select ON hbh.appointment_status_history
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND EXISTS (
    SELECT 1 FROM hbh.appointments a
    WHERE a.appointment_id = hbh.appointment_status_history.appointment_id
      AND hbh.can_access_child(a.child_id)));

CREATE POLICY p_ts_select ON hbh.therapy_sessions
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_access_child(child_id));

CREATE POLICY p_ssh_select ON hbh.session_status_history
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND EXISTS (
    SELECT 1 FROM hbh.therapy_sessions s
    WHERE s.session_id = hbh.session_status_history.session_id
      AND hbh.can_access_child(s.child_id)));

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.services, hbh.rooms, hbh.therapists, hbh.therapist_services,
                hbh.therapist_working_hours, hbh.caseload, hbh.appointments,
                hbh.appointment_status_history, hbh.therapy_sessions,
                hbh.session_status_history
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer, timestamptz, timestamptz, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.start_session(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.close_session(integer, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.can_close_session(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.validate_slot(integer, integer, integer, integer, integer, timestamptz, timestamptz, integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.start_session(integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.close_session(integer, text, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.can_close_session(integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_appointment_transition(text, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_session_transition(text, text) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

-- =====================================================================
-- EXEMPTIONS
--
-- The two history tables are append-only records, like audit_log, and
-- for the same reasons.
-- =====================================================================
INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('appointment_status_history', 'AUDIT_COLUMNS',
   'An append-only record of one transition. changed_by and changed_at are its attribution; a row here is never edited, so an update trail would always be empty.'),
  ('appointment_status_history', 'SOFT_DELETE',
   'Append-only by trigger. A flag that hid a transition would be a way to rewrite what happened to an appointment.'),
  ('session_status_history', 'AUDIT_COLUMNS',
   'An append-only record of one transition. changed_by and changed_at are its attribution; a row here is never edited.'),
  ('session_status_history', 'SOFT_DELETE',
   'Append-only by trigger. A flag that hid a transition would be a way to rewrite what happened in a clinical session.');

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar)
VALUES (NULL, 'ALLOW_BACKDATED_BOOKING_DAYS', '0', 'NUMBER', 'كم يومًا للخلف يُسمح بالحجز فيه')
ON CONFLICT (center_id, param_code) DO NOTHING;


INSERT INTO hbh.schema_migrations (version) VALUES ('0005');
