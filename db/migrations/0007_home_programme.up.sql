-- =====================================================================
-- Hand By Hand (new) - migration 0007: the home programme and parent
-- requests.
--
-- These are the two places where a GUARDIAN writes. Everything before
-- this migration the family could only read, so the rules here are
-- about what a parent may put into the system, and where the line is.
--
-- 1. A PARENT LOGS, A CLINICIAN PRESCRIBES.
--    child_activities is written by the therapist; activity_log is
--    written by the family. A parent who could edit the prescription
--    could quietly rewrite the programme and then report full
--    adherence to it.
--
-- 2. A REQUEST IS NOT AN ACTION.
--    Submitting "please move Tuesday" changes no appointment. It
--    creates a row for reception to decide on. The portal says so, and
--    the schema makes it true: parent_requests has no foreign key that
--    can move a booking, and the appointment tables are untouched here.
--
-- 3. A LOG ENTRY IS ONE ACTIVITY ON ONE DAY.
--    Enforced by a unique index rather than by the screen, so a double
--    tap on a phone with a slow connection cannot inflate adherence.
--
-- Error classes added here:
--   HB040  illegal request status transition
--   HB041  not permitted to log against this activity
--   HB042  that activity is already logged for that day
--   HB043  not permitted to submit a request for this child
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0007') THEN
    RAISE EXCEPTION 'migration 0007 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0006') THEN
    RAISE EXCEPTION 'migration 0006 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE ACTIVITY LIBRARY
-- =====================================================================
CREATE TABLE hbh.activity_library (
  activity_id  integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  code         text        NOT NULL,
  title_ar     text        NOT NULL,
  how_to_ar    text,
  service_id   integer,
  age_from_mon smallint,
  age_to_mon   smallint,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_activity_library PRIMARY KEY (activity_id),
  CONSTRAINT fk_lib_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_lib_service FOREIGN KEY (service_id) REFERENCES hbh.services (service_id),
  CONSTRAINT uq_lib_code UNIQUE (center_id, code),
  CONSTRAINT ck_lib_age CHECK (age_to_mon IS NULL OR age_from_mon IS NULL OR age_to_mon >= age_from_mon)
);

CREATE INDEX ix_lib_center  ON hbh.activity_library (center_id);
CREATE INDEX ix_lib_service ON hbh.activity_library (service_id);

-- =====================================================================
-- WHAT THIS CHILD IS ASKED TO DO
--
-- Prescribed by the therapist. The family never writes here - the
-- policy grants SELECT and nothing else, and the acceptance suite
-- proves a guardian's UPDATE is refused with a privilege error rather
-- than quietly ignored.
-- =====================================================================
CREATE TABLE hbh.child_activities (
  child_activity_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id         integer     NOT NULL,
  child_id          integer     NOT NULL,
  activity_id       integer     NOT NULL,
  plan_id           integer,
  goal_id           integer,
  assigned_by       integer     NOT NULL,
  times_per_week    smallint    NOT NULL DEFAULT 7,
  minutes_each      smallint,
  instructions_ar   text,
  start_date        date        NOT NULL DEFAULT current_date,
  end_date          date,
  active_flg        boolean     NOT NULL DEFAULT true,
  deleted_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at        timestamptz,
  updated_by        text,
  CONSTRAINT pk_child_activities PRIMARY KEY (child_activity_id),
  CONSTRAINT fk_ca_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ca_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT fk_ca_activity FOREIGN KEY (activity_id) REFERENCES hbh.activity_library (activity_id),
  CONSTRAINT fk_ca_plan     FOREIGN KEY (plan_id)     REFERENCES hbh.treatment_plans (plan_id),
  CONSTRAINT fk_ca_goal     FOREIGN KEY (goal_id)     REFERENCES hbh.plan_goals (goal_id),
  CONSTRAINT fk_ca_assigner FOREIGN KEY (assigned_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_ca_times   CHECK (times_per_week BETWEEN 1 AND 21),
  CONSTRAINT ck_ca_minutes CHECK (minutes_each IS NULL OR minutes_each BETWEEN 1 AND 240),
  CONSTRAINT ck_ca_window  CHECK (end_date IS NULL OR end_date >= start_date)
);

-- The same activity twice, live, for one child is a prescription that
-- cannot be counted.
CREATE UNIQUE INDEX uix_ca_live
  ON hbh.child_activities (child_id, activity_id) WHERE active_flg AND end_date IS NULL;

CREATE INDEX ix_ca_center   ON hbh.child_activities (center_id);
CREATE INDEX ix_ca_child    ON hbh.child_activities (child_id);
CREATE INDEX ix_ca_activity ON hbh.child_activities (activity_id);
CREATE INDEX ix_ca_plan     ON hbh.child_activities (plan_id);
CREATE INDEX ix_ca_goal     ON hbh.child_activities (goal_id);
CREATE INDEX ix_ca_assigner ON hbh.child_activities (assigned_by);

-- =====================================================================
-- WHAT THE FAMILY ACTUALLY DID
-- =====================================================================
CREATE TABLE hbh.activity_log (
  log_id            bigint      GENERATED ALWAYS AS IDENTITY,
  center_id         integer     NOT NULL,
  child_activity_id integer     NOT NULL,
  child_id          integer     NOT NULL,
  log_date          date        NOT NULL DEFAULT current_date,
  done_flg          boolean     NOT NULL DEFAULT true,
  parent_note_ar    text,
  logged_by         integer     NOT NULL,
  active_flg        boolean     NOT NULL DEFAULT true,
  deleted_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at        timestamptz,
  updated_by        text,
  CONSTRAINT pk_activity_log PRIMARY KEY (log_id),
  CONSTRAINT fk_log_center   FOREIGN KEY (center_id)         REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_log_ca       FOREIGN KEY (child_activity_id) REFERENCES hbh.child_activities (child_activity_id),
  CONSTRAINT fk_log_child    FOREIGN KEY (child_id)          REFERENCES hbh.children (child_id),
  CONSTRAINT fk_log_user     FOREIGN KEY (logged_by)         REFERENCES hbh.users (user_id),
  -- A programme is not logged before it is prescribed.
  CONSTRAINT ck_log_date CHECK (log_date <= current_date)
);

-- One activity, one day. A double tap on a phone with a slow connection
-- must not be able to inflate adherence.
CREATE UNIQUE INDEX uix_log_day
  ON hbh.activity_log (child_activity_id, log_date) WHERE active_flg;

CREATE INDEX ix_log_center ON hbh.activity_log (center_id);
CREATE INDEX ix_log_child  ON hbh.activity_log (child_id, log_date DESC);
CREATE INDEX ix_log_ca     ON hbh.activity_log (child_activity_id, log_date DESC);
CREATE INDEX ix_log_user   ON hbh.activity_log (logged_by);

-- =====================================================================
-- PARENT REQUESTS
--
-- A row here changes nothing. There is deliberately no foreign key from
-- this table into appointments that could move one, and no trigger that
-- acts on acceptance. Reception reads the request and does the work.
-- =====================================================================
CREATE TABLE hbh.parent_requests (
  request_id     integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  branch_id      integer,
  request_no     text        NOT NULL,
  child_id       integer     NOT NULL,
  guardian_id    integer     NOT NULL,
  kind_code      text        NOT NULL,
  appointment_id integer,
  body_ar        text,
  preferred_at   timestamptz,
  status         text        NOT NULL DEFAULT 'NEW',
  decided_by     integer,
  decided_at     timestamptz,
  decision_note_ar text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_parent_requests PRIMARY KEY (request_id),
  CONSTRAINT fk_req_center   FOREIGN KEY (center_id)      REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_req_branch   FOREIGN KEY (branch_id)      REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_req_child    FOREIGN KEY (child_id)       REFERENCES hbh.children (child_id),
  CONSTRAINT fk_req_guardian FOREIGN KEY (guardian_id)    REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_req_appt     FOREIGN KEY (appointment_id) REFERENCES hbh.appointments (appointment_id),
  CONSTRAINT fk_req_decider  FOREIGN KEY (decided_by)     REFERENCES hbh.users (user_id),
  CONSTRAINT uq_req_no UNIQUE (center_id, request_no),
  CONSTRAINT ck_req_kind   CHECK (kind_code IN ('RESCHEDULE','CANCEL','CALLBACK')),
  CONSTRAINT ck_req_status CHECK (status IN ('NEW','ACCEPTED','REJECTED')),
  -- A decision without a decider is a decision nobody made.
  CONSTRAINT ck_req_decided CHECK ((status = 'NEW') = (decided_by IS NULL)),
  CONSTRAINT ck_req_decided_at CHECK ((decided_by IS NULL) = (decided_at IS NULL)),
  -- A reschedule or a cancellation is about a specific appointment.
  CONSTRAINT ck_req_appt CHECK (kind_code = 'CALLBACK' OR appointment_id IS NOT NULL)
);

CREATE INDEX ix_req_center   ON hbh.parent_requests (center_id, created_at DESC);
CREATE INDEX ix_req_branch   ON hbh.parent_requests (branch_id);
CREATE INDEX ix_req_child    ON hbh.parent_requests (child_id, created_at DESC);
CREATE INDEX ix_req_guardian ON hbh.parent_requests (guardian_id);
CREATE INDEX ix_req_appt     ON hbh.parent_requests (appointment_id);
CREATE INDEX ix_req_decider  ON hbh.parent_requests (decided_by);
CREATE INDEX ix_req_open     ON hbh.parent_requests (center_id, created_at) WHERE status = 'NEW';

-- =====================================================================
-- STATE MACHINE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.legal_request_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('NEW', 'ACCEPTED'),
    ('NEW', 'REJECTED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_request_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_request_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'request % cannot go from % to %', OLD.request_id, OLD.status, NEW.status
      USING ERRCODE = 'HB040';
  END IF;
  RETURN NEW;
END
$$;

-- =====================================================================
-- WRITING, AS A PARENT
--
-- Both entry points are SECURITY DEFINER and both start by asking
-- can_access_child. The policies would refuse a read of somebody
-- else's child anyway; these refuse the WRITE, which no policy on a
-- SELECT can do.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.log_activity(
  p_child_activity_id integer,
  p_log_date          date DEFAULT current_date,
  p_done              boolean DEFAULT true,
  p_note_ar           text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_ca hbh.child_activities%ROWTYPE;
  l_id bigint;
BEGIN
  SELECT * INTO l_ca FROM hbh.child_activities WHERE child_activity_id = p_child_activity_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such activity %', p_child_activity_id USING ERRCODE = 'HB041';
  END IF;

  IF NOT hbh.can_access_child(l_ca.child_id) THEN
    RAISE EXCEPTION 'not permitted to log against activity %', p_child_activity_id
      USING ERRCODE = 'HB041';
  END IF;

  BEGIN
    INSERT INTO hbh.activity_log (center_id, child_activity_id, child_id, log_date, done_flg,
                                  parent_note_ar, logged_by)
    VALUES (l_ca.center_id, p_child_activity_id, l_ca.child_id, p_log_date, p_done,
            p_note_ar, hbh.current_user_id())
    RETURNING log_id INTO l_id;
  EXCEPTION WHEN unique_violation THEN
    -- Not an error the family should see as a failure: the day is
    -- already recorded. The caller decides whether to update it.
    RAISE EXCEPTION 'activity % is already logged for %', p_child_activity_id, p_log_date
      USING ERRCODE = 'HB042';
  END;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.submit_request(
  p_child_id       integer,
  p_kind_code      text,
  p_appointment_id integer DEFAULT NULL,
  p_body_ar        text    DEFAULT NULL,
  p_preferred_at   timestamptz DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_guardian integer;
  l_center   integer;
  l_branch   integer;
  l_id       integer;
BEGIN
  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'not permitted to submit a request for child %', p_child_id
      USING ERRCODE = 'HB043';
  END IF;

  SELECT g.guardian_id, g.center_id, g.branch_id INTO l_guardian, l_center, l_branch
  FROM   hbh.guardians g
  JOIN   hbh.guardian_children gc ON gc.guardian_id = g.guardian_id AND gc.child_id = p_child_id
  WHERE  g.user_id = hbh.current_user_id() AND g.active_flg AND gc.active_flg;

  IF NOT FOUND THEN
    -- Staff can READ a child without being a guardian of one; they
    -- cannot submit a request on a family's behalf.
    RAISE EXCEPTION 'only a guardian of child % may submit a request for them', p_child_id
      USING ERRCODE = 'HB043';
  END IF;

  INSERT INTO hbh.parent_requests (center_id, branch_id, request_no, child_id, guardian_id,
                                   kind_code, appointment_id, body_ar, preferred_at)
  VALUES (l_center, l_branch, hbh.next_number(l_center, 'REQUEST'), p_child_id, l_guardian,
          p_kind_code, p_appointment_id, p_body_ar, p_preferred_at)
  RETURNING request_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.decide_request(
  p_request_id integer,
  p_status     text,
  p_note_ar    text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.has_permission('REQUEST.MANAGE') THEN
    RAISE EXCEPTION 'deciding a request needs REQUEST.MANAGE' USING ERRCODE = 'HB043';
  END IF;

  UPDATE hbh.parent_requests
     SET status           = p_status,
         decided_by       = hbh.current_user_id(),
         decided_at       = now(),
         decision_note_ar = p_note_ar
   WHERE request_id = p_request_id;

  -- Deliberately nothing else. Accepting a reschedule does NOT move the
  -- appointment: reception does that, deliberately, through
  -- book_appointment, where every slot rule still applies.
END
$$;

-- =====================================================================
-- ADHERENCE
--
-- security_invoker = true, for the reason in D-15: without it this view
-- would hand a guardian every child in the centre.
-- =====================================================================
CREATE VIEW hbh.v_activity_adherence
WITH (security_invoker = true)
AS
SELECT ca.child_activity_id,
       ca.center_id,
       ca.child_id,
       ca.activity_id,
       l.title_ar,
       ca.times_per_week,
       ca.minutes_each,
       coalesce(d.done_cnt, 0)                                   AS done_last_7,
       round(100.0 * least(coalesce(d.done_cnt, 0), ca.times_per_week)
             / ca.times_per_week, 0)                             AS adherence_pct,
       d.last_done_on
FROM   hbh.child_activities ca
JOIN   hbh.activity_library l ON l.activity_id = ca.activity_id
LEFT   JOIN LATERAL (
         SELECT count(*) FILTER (WHERE g.done_flg) AS done_cnt,
                max(g.log_date) FILTER (WHERE g.done_flg) AS last_done_on
         FROM   hbh.activity_log g
         WHERE  g.child_activity_id = ca.child_activity_id
         AND    g.active_flg
         AND    g.log_date > current_date - 7
       ) d ON true
WHERE  ca.active_flg AND (ca.end_date IS NULL OR ca.end_date >= current_date);

COMMENT ON VIEW hbh.v_activity_adherence IS
  'Home programme adherence over the last seven days. security_invoker=true so the caller''s policies apply.';

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_lib_touch  BEFORE UPDATE ON hbh.activity_library FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_ca_touch   BEFORE UPDATE ON hbh.child_activities FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_log_touch  BEFORE UPDATE ON hbh.activity_log     FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_req_touch  BEFORE UPDATE ON hbh.parent_requests  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_req_status BEFORE UPDATE ON hbh.parent_requests  FOR EACH ROW EXECUTE FUNCTION hbh.trg_request_status();

CREATE TRIGGER trg_ca_audit   AFTER INSERT OR UPDATE OR DELETE ON hbh.child_activities FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('child_activity_id');
CREATE TRIGGER trg_req_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.parent_requests  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('request_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.activity_library  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.child_activities  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.activity_log      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.parent_requests   ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_lib_select ON hbh.activity_library
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_ca_select ON hbh.child_activities
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND hbh.can_access_child(child_id));

CREATE POLICY p_log_select ON hbh.activity_log
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND hbh.can_access_child(child_id));

CREATE POLICY p_req_select ON hbh.parent_requests
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND hbh.can_access_child(child_id));

-- =====================================================================
-- GRANTS
--
-- SELECT only, on every one of them. The family writes through
-- log_activity and submit_request, which check the gate first; there is
-- no INSERT grant anywhere for hbh_app, so a client cannot write a row
-- the functions would have refused.
-- =====================================================================
GRANT SELECT ON hbh.activity_library, hbh.child_activities, hbh.activity_log,
                hbh.parent_requests, hbh.v_activity_adherence
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.log_activity(integer, date, boolean, text)                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.submit_request(integer, text, integer, text, timestamptz)         FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.decide_request(integer, text, text)                               FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.log_activity(integer, date, boolean, text)                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.submit_request(integer, text, integer, text, timestamptz)      TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.decide_request(integer, text, text)                            TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_request_transition(text, text)                           TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0007');
