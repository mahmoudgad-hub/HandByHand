-- =====================================================================
-- Hand By Hand (new) - migration 0006: plans, goals, measurements,
-- session notes and progress reports.
--
-- Four rules, and the first is the one the whole migration is built to
-- protect.
--
-- 1. EVERY NOTE IS BORN INTERNAL.
--    The trigger forces it on INSERT no matter what the caller asked
--    for. Publishing to a parent is a SEPARATE act, with its own
--    permission, that stamps who approved it. And the portal shows a
--    note only when THREE conditions hold together: visibility is
--    PARENT, it is not a draft, and an approver is named. Any one of
--    them alone would be a clinical note reaching a family before the
--    clinician meant it to.
--
-- 2. AUTHORING AND CLOSING ARE DIFFERENT RIGHTS.
--    can_close_session already exists and admits an administrator.
--    can_edit_session does NOT. A clinical note is written by the
--    clinician who was in the room, and by nobody else - which is why
--    the seed withholds SESSION.NOTES.EDIT from CENTER_ADMIN, and why
--    one gate serving both would silently redefine that.
--
-- 3. A PUBLISHED REPORT IS A SNAPSHOT.
--    Goals move. A report a family received in August must still say in
--    December what it said in August, so publishing copies the numbers
--    into the row and the report stops reading live data.
--
-- 4. A VIEW BYPASSES RLS UNLESS TOLD NOT TO.
--    In Postgres a view runs with its OWNER's rights by default, so a
--    view over a policy-protected table hands out everything the owner
--    can see. Every view here is created WITH (security_invoker = true)
--    and the acceptance suite proves a guardian reading through it
--    still sees only their own child.
--
-- Error classes added here:
--   HB030  illegal treatment plan status transition
--   HB031  not permitted to author notes on this session
--   HB032  not permitted to publish
--   HB033  a published report cannot be edited
--   HB034  illegal report status transition
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0006') THEN
    RAISE EXCEPTION 'migration 0006 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0005') THEN
    RAISE EXCEPTION 'migration 0005 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- TREATMENT PLANS
-- =====================================================================
CREATE TABLE hbh.treatment_plans (
  plan_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  child_id     integer     NOT NULL,
  service_id   integer     NOT NULL,
  therapist_id integer     NOT NULL,
  title_ar     text        NOT NULL,
  start_date   date        NOT NULL DEFAULT current_date,
  end_date     date,
  status       text        NOT NULL DEFAULT 'DRAFT',
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_treatment_plans PRIMARY KEY (plan_id),
  CONSTRAINT fk_plans_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_plans_branch    FOREIGN KEY (branch_id)    REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_plans_child     FOREIGN KEY (child_id)     REFERENCES hbh.children (child_id),
  CONSTRAINT fk_plans_service   FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id),
  CONSTRAINT fk_plans_therapist FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT ck_plans_status CHECK (status IN ('DRAFT','ACTIVE','COMPLETED','CANCELLED')),
  CONSTRAINT ck_plans_window CHECK (end_date IS NULL OR end_date >= start_date)
);

-- One live plan per child per service. Two would mean two answers to
-- "what are we working on", and a report that cannot say which it used.
CREATE UNIQUE INDEX uix_plans_active
  ON hbh.treatment_plans (child_id, service_id) WHERE status = 'ACTIVE';

CREATE INDEX ix_plans_center    ON hbh.treatment_plans (center_id);
CREATE INDEX ix_plans_branch    ON hbh.treatment_plans (branch_id);
CREATE INDEX ix_plans_child     ON hbh.treatment_plans (child_id);
CREATE INDEX ix_plans_service   ON hbh.treatment_plans (service_id);
CREATE INDEX ix_plans_therapist ON hbh.treatment_plans (therapist_id);

CREATE TABLE hbh.plan_goals (
  goal_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  plan_id       integer     NOT NULL,
  title_ar      text        NOT NULL,
  description_ar text,
  baseline_pct  numeric(5,2),
  target_pct    numeric(5,2) NOT NULL DEFAULT 80,
  sort_order    integer     NOT NULL DEFAULT 100,
  status        text        NOT NULL DEFAULT 'OPEN',
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_plan_goals PRIMARY KEY (goal_id),
  CONSTRAINT fk_goals_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_goals_plan   FOREIGN KEY (plan_id)   REFERENCES hbh.treatment_plans (plan_id),
  CONSTRAINT ck_goals_status   CHECK (status IN ('OPEN','MET','DROPPED')),
  CONSTRAINT ck_goals_target   CHECK (target_pct   BETWEEN 0 AND 100),
  CONSTRAINT ck_goals_baseline CHECK (baseline_pct IS NULL OR baseline_pct BETWEEN 0 AND 100)
);

CREATE INDEX ix_goals_center ON hbh.plan_goals (center_id);
CREATE INDEX ix_goals_plan   ON hbh.plan_goals (plan_id, sort_order);

CREATE TABLE hbh.goal_measurements (
  measurement_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  goal_id        integer     NOT NULL,
  session_id     integer,
  measured_on    date        NOT NULL DEFAULT current_date,
  value_pct      numeric(5,2) NOT NULL,
  trials_cnt     smallint,
  note_ar        text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_goal_measurements PRIMARY KEY (measurement_id),
  CONSTRAINT fk_meas_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_meas_goal    FOREIGN KEY (goal_id)    REFERENCES hbh.plan_goals (goal_id),
  CONSTRAINT fk_meas_session FOREIGN KEY (session_id) REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT ck_meas_value  CHECK (value_pct BETWEEN 0 AND 100),
  CONSTRAINT ck_meas_trials CHECK (trials_cnt IS NULL OR trials_cnt > 0)
);

CREATE INDEX ix_meas_center  ON hbh.goal_measurements (center_id);
CREATE INDEX ix_meas_goal    ON hbh.goal_measurements (goal_id, measured_on DESC);
CREATE INDEX ix_meas_session ON hbh.goal_measurements (session_id);

-- =====================================================================
-- SESSION NOTES
--
-- visibility, is_draft_flg and approved_by are three separate facts and
-- the constraint below ties them together, so a row can never claim to
-- be visible to a parent while still being a draft or while naming
-- nobody as its approver.
-- =====================================================================
CREATE TABLE hbh.session_notes (
  note_id        integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  session_id     integer     NOT NULL,
  child_id       integer     NOT NULL,
  author_user_id integer     NOT NULL,
  body_ar        text        NOT NULL,
  visibility     text        NOT NULL DEFAULT 'INTERNAL',
  is_draft_flg   boolean     NOT NULL DEFAULT true,
  approved_by    integer,
  approved_at    timestamptz,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_session_notes PRIMARY KEY (note_id),
  CONSTRAINT fk_notes_center   FOREIGN KEY (center_id)      REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_notes_session  FOREIGN KEY (session_id)     REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT fk_notes_child    FOREIGN KEY (child_id)       REFERENCES hbh.children (child_id),
  CONSTRAINT fk_notes_author   FOREIGN KEY (author_user_id) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_notes_approver FOREIGN KEY (approved_by)    REFERENCES hbh.users (user_id),
  CONSTRAINT ck_notes_visibility CHECK (visibility IN ('INTERNAL','PARENT')),
  -- The three facts, tied together in one place.
  CONSTRAINT ck_notes_published CHECK (
    visibility = 'INTERNAL'
    OR (is_draft_flg = false AND approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT ck_notes_approval CHECK ((approved_by IS NULL) = (approved_at IS NULL))
);

CREATE INDEX ix_notes_center  ON hbh.session_notes (center_id);
CREATE INDEX ix_notes_session ON hbh.session_notes (session_id);
CREATE INDEX ix_notes_child   ON hbh.session_notes (child_id, created_at DESC);
CREATE INDEX ix_notes_author  ON hbh.session_notes (author_user_id);
CREATE INDEX ix_notes_approver ON hbh.session_notes (approved_by);
-- The portal's own query: published notes for a child, newest first.
CREATE INDEX ix_notes_published ON hbh.session_notes (child_id, created_at DESC)
  WHERE visibility = 'PARENT' AND NOT is_draft_flg;

-- =====================================================================
-- PROGRESS REPORTS
--
-- goals_snapshot is the point of the table. A report published in
-- August must still say in December what it said in August; reading
-- live goals would silently rewrite history every time a therapist
-- recorded a new measurement.
-- =====================================================================
CREATE TABLE hbh.progress_reports (
  report_id     integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  branch_id     integer,
  child_id      integer     NOT NULL,
  plan_id       integer,
  report_no     text        NOT NULL,
  title_ar      text        NOT NULL,
  period_start  date        NOT NULL,
  period_end    date        NOT NULL,
  summary_ar    text,
  status        text        NOT NULL DEFAULT 'DRAFT',
  goals_snapshot jsonb,
  published_by  integer,
  published_at  timestamptz,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_progress_reports PRIMARY KEY (report_id),
  CONSTRAINT fk_reports_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_reports_branch    FOREIGN KEY (branch_id)    REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_reports_child     FOREIGN KEY (child_id)     REFERENCES hbh.children (child_id),
  CONSTRAINT fk_reports_plan      FOREIGN KEY (plan_id)      REFERENCES hbh.treatment_plans (plan_id),
  CONSTRAINT fk_reports_publisher FOREIGN KEY (published_by) REFERENCES hbh.users (user_id),
  CONSTRAINT uq_reports_no UNIQUE (center_id, report_no),
  CONSTRAINT ck_reports_status CHECK (status IN ('DRAFT','PUBLISHED')),
  CONSTRAINT ck_reports_window CHECK (period_end >= period_start),
  -- A published report without a snapshot is a report that will change
  -- under the family's feet.
  CONSTRAINT ck_reports_published CHECK (
    status = 'DRAFT'
    OR (goals_snapshot IS NOT NULL AND published_by IS NOT NULL AND published_at IS NOT NULL))
);

CREATE INDEX ix_reports_center    ON hbh.progress_reports (center_id);
CREATE INDEX ix_reports_branch    ON hbh.progress_reports (branch_id);
CREATE INDEX ix_reports_child     ON hbh.progress_reports (child_id, period_end DESC);
CREATE INDEX ix_reports_plan      ON hbh.progress_reports (plan_id);
CREATE INDEX ix_reports_publisher ON hbh.progress_reports (published_by);

-- =====================================================================
-- THE AUTHORSHIP GATE
--
-- Deliberately narrower than can_close_session. That one admits an
-- administrator, because closing a session is an administrative act.
-- This one does not, because writing a clinical note is not.
--
-- The Oracle system asked ONE gate for both and demanded CHILD.VIEW_ALL
-- together with SESSION.NOTES.EDIT - a permission the seed withholds
-- from administrators on purpose. The result was that reception could
-- start a session nobody but the assigned therapist could end, and the
-- screen refused a user holding the very permission the action was
-- named after.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.can_edit_session(p_session_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   hbh.therapy_sessions s
    JOIN   hbh.therapists t ON t.therapist_id = s.therapist_id
    WHERE  s.session_id = p_session_id
    AND    t.user_id = hbh.current_user_id()
    AND    hbh.has_permission('SESSION.NOTES.EDIT')
  )
$$;

COMMENT ON FUNCTION hbh.can_edit_session(integer) IS
  'Authorship gate. The clinician who ran the session, holding SESSION.NOTES.EDIT. Never an administrator - closing is can_close_session.';

-- =====================================================================
-- NOTES ARE BORN INTERNAL
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_note_born_internal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Forced, not defaulted. A DEFAULT is a suggestion the caller may
  -- override; this is the rule. Whatever arrived on the row, a note
  -- starts its life invisible to the family.
  NEW.visibility   := 'INTERNAL';
  NEW.is_draft_flg := true;
  NEW.approved_by  := NULL;
  NEW.approved_at  := NULL;
  RETURN NEW;
END
$$;

-- Publishing is gated in the TRIGGER, not only in the function, so a
-- direct UPDATE cannot put a note in front of a parent either.
CREATE OR REPLACE FUNCTION hbh.trg_note_publish_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.visibility = 'PARENT' AND OLD.visibility <> 'PARENT' THEN
    IF NOT hbh.has_permission('NOTE.PUBLISH') THEN
      RAISE EXCEPTION 'publishing a note to a guardian needs NOTE.PUBLISH'
        USING ERRCODE = 'HB032';
    END IF;
    IF NEW.approved_by IS NULL THEN
      RAISE EXCEPTION 'a published note must name its approver'
        USING ERRCODE = 'HB032';
    END IF;
  END IF;

  -- Unpublishing is not a silent edit either: it is allowed, but the
  -- approval stamp goes with it so the row cannot keep a signature for
  -- something it no longer says.
  IF NEW.visibility = 'INTERNAL' AND OLD.visibility = 'PARENT' THEN
    NEW.approved_by := NULL;
    NEW.approved_at := NULL;
    NEW.is_draft_flg := true;
  END IF;

  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.write_session_note(
  p_session_id integer,
  p_body_ar    text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_sess hbh.therapy_sessions%ROWTYPE;
  l_id   integer;
BEGIN
  IF NOT hbh.can_edit_session(p_session_id) THEN
    RAISE EXCEPTION 'not permitted to write notes on session %', p_session_id
      USING ERRCODE = 'HB031';
  END IF;

  SELECT * INTO l_sess FROM hbh.therapy_sessions WHERE session_id = p_session_id;

  INSERT INTO hbh.session_notes (center_id, session_id, child_id, author_user_id, body_ar)
  VALUES (l_sess.center_id, p_session_id, l_sess.child_id, hbh.current_user_id(), p_body_ar)
  RETURNING note_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.publish_session_note(p_note_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_note hbh.session_notes%ROWTYPE;
BEGIN
  SELECT * INTO l_note FROM hbh.session_notes WHERE note_id = p_note_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such note %', p_note_id USING ERRCODE = 'HB032';
  END IF;

  IF NOT hbh.has_permission('NOTE.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a note to a guardian needs NOTE.PUBLISH'
      USING ERRCODE = 'HB032';
  END IF;

  UPDATE hbh.session_notes
     SET visibility   = 'PARENT',
         is_draft_flg = false,
         approved_by  = hbh.current_user_id(),
         approved_at  = now()
   WHERE note_id = p_note_id;

  -- Logged as an attempt-class record so it survives a rollback: a
  -- clinical note reaching a family is not something the log may lose.
  PERFORM hbh.audit_attempt('READ', l_note.center_id, hbh.current_app_user(),
                            'note ' || p_note_id || ' published to guardian');
END
$$;

-- =====================================================================
-- PLAN AND REPORT STATE MACHINES
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.legal_plan_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('DRAFT',  'ACTIVE'),
    ('DRAFT',  'CANCELLED'),
    ('ACTIVE', 'COMPLETED'),
    ('ACTIVE', 'CANCELLED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_plan_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_plan_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'plan % cannot go from % to %', OLD.plan_id, OLD.status, NEW.status
      USING ERRCODE = 'HB030';
  END IF;
  RETURN NEW;
END
$$;

-- A published report is finished. Everything except a withdrawal is
-- refused, and the refusal names the rule rather than a constraint.
CREATE OR REPLACE FUNCTION hbh.trg_report_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'PUBLISHED' THEN
    IF NEW.status = 'PUBLISHED' THEN
      IF NEW.title_ar       IS DISTINCT FROM OLD.title_ar
         OR NEW.summary_ar    IS DISTINCT FROM OLD.summary_ar
         OR NEW.goals_snapshot IS DISTINCT FROM OLD.goals_snapshot
         OR NEW.period_start IS DISTINCT FROM OLD.period_start
         OR NEW.period_end   IS DISTINCT FROM OLD.period_end THEN
        RAISE EXCEPTION 'report % is published and cannot be edited', OLD.report_id
          USING ERRCODE = 'HB033';
      END IF;
    ELSIF NEW.status <> 'DRAFT' THEN
      RAISE EXCEPTION 'report % cannot go from PUBLISHED to %', OLD.report_id, NEW.status
        USING ERRCODE = 'HB034';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.publish_report(p_report_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_rep  hbh.progress_reports%ROWTYPE;
  l_snap jsonb;
BEGIN
  SELECT * INTO l_rep FROM hbh.progress_reports WHERE report_id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such report %', p_report_id USING ERRCODE = 'HB032';
  END IF;

  IF NOT hbh.has_permission('REPORT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a report needs REPORT.PUBLISH' USING ERRCODE = 'HB032';
  END IF;

  IF l_rep.status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'report % is already published', p_report_id USING ERRCODE = 'HB033';
  END IF;

  -- The snapshot. Taken once, here, and never read live again.
  SELECT jsonb_agg(jsonb_build_object(
           'goal_id',      g.goal_id,
           'title_ar',     g.title_ar,
           'target_pct',   g.target_pct,
           'baseline_pct', g.baseline_pct,
           'latest_pct',   (SELECT m.value_pct FROM hbh.goal_measurements m
                            WHERE m.goal_id = g.goal_id AND m.active_flg
                              AND m.measured_on <= l_rep.period_end
                            ORDER BY m.measured_on DESC, m.measurement_id DESC
                            LIMIT 1),
           'status',       g.status)
         ORDER BY g.sort_order, g.goal_id)
    INTO l_snap
  FROM hbh.plan_goals g
  WHERE g.plan_id = l_rep.plan_id AND g.active_flg;

  UPDATE hbh.progress_reports
     SET status         = 'PUBLISHED',
         goals_snapshot = coalesce(l_snap, '[]'::jsonb),
         published_by   = hbh.current_user_id(),
         published_at   = now()
   WHERE report_id = p_report_id;

  PERFORM hbh.audit_attempt('READ', l_rep.center_id, hbh.current_app_user(),
                            'report ' || p_report_id || ' published to guardian');
END
$$;

-- =====================================================================
-- A VIEW, AND THE ONE OPTION THAT MAKES IT SAFE
--
-- security_invoker = true is not a nicety. Without it a view runs with
-- its OWNER's rights, and since the owner is hbh_owner - who bypasses
-- row level security on every table here - a guardian reading this view
-- would receive every child in the centre.
--
-- The acceptance suite reads through this view AS a guardian and counts
-- the rows, because that is the only way to tell the difference.
-- =====================================================================
CREATE VIEW hbh.v_goal_progress
WITH (security_invoker = true)
AS
SELECT g.goal_id,
       g.center_id,
       g.plan_id,
       p.child_id,
       g.title_ar,
       g.target_pct,
       g.baseline_pct,
       g.status,
       g.sort_order,
       m.value_pct   AS latest_pct,
       m.measured_on AS latest_measured_on,
       (SELECT count(*) FROM hbh.goal_measurements x
        WHERE x.goal_id = g.goal_id AND x.active_flg) AS measurement_cnt
FROM   hbh.plan_goals g
JOIN   hbh.treatment_plans p ON p.plan_id = g.plan_id
LEFT   JOIN LATERAL (
         SELECT mm.value_pct, mm.measured_on
         FROM   hbh.goal_measurements mm
         WHERE  mm.goal_id = g.goal_id AND mm.active_flg
         ORDER  BY mm.measured_on DESC, mm.measurement_id DESC
         LIMIT  1
       ) m ON true
WHERE  g.active_flg AND p.active_flg;

COMMENT ON VIEW hbh.v_goal_progress IS
  'Goal with its latest measurement. security_invoker=true so the caller''s policies apply - without it the view would hand a guardian every child in the centre.';

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_plans_touch    BEFORE UPDATE ON hbh.treatment_plans   FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_goals_touch    BEFORE UPDATE ON hbh.plan_goals        FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_meas_touch     BEFORE UPDATE ON hbh.goal_measurements FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_notes_touch    BEFORE UPDATE ON hbh.session_notes     FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_reports_touch  BEFORE UPDATE ON hbh.progress_reports  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_plans_status   BEFORE UPDATE ON hbh.treatment_plans   FOR EACH ROW EXECUTE FUNCTION hbh.trg_plan_status();

CREATE TRIGGER trg_notes_born     BEFORE INSERT ON hbh.session_notes     FOR EACH ROW EXECUTE FUNCTION hbh.trg_note_born_internal();
CREATE TRIGGER trg_notes_publish  BEFORE UPDATE ON hbh.session_notes     FOR EACH ROW EXECUTE FUNCTION hbh.trg_note_publish_guard();

CREATE TRIGGER trg_reports_guard  BEFORE UPDATE ON hbh.progress_reports  FOR EACH ROW EXECUTE FUNCTION hbh.trg_report_guard();

CREATE TRIGGER trg_plans_audit    AFTER INSERT OR UPDATE OR DELETE ON hbh.treatment_plans  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('plan_id');
CREATE TRIGGER trg_goals_audit    AFTER INSERT OR UPDATE OR DELETE ON hbh.plan_goals       FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('goal_id');
CREATE TRIGGER trg_notes_audit    AFTER INSERT OR UPDATE OR DELETE ON hbh.session_notes    FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('note_id');
CREATE TRIGGER trg_reports_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.progress_reports FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('report_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.treatment_plans   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.plan_goals        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.goal_measurements ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.session_notes     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.progress_reports  ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_plans_select ON hbh.treatment_plans
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND hbh.can_access_child(child_id));

CREATE POLICY p_goals_select ON hbh.plan_goals
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND EXISTS (
    SELECT 1 FROM hbh.treatment_plans p
    WHERE p.plan_id = hbh.plan_goals.plan_id AND hbh.can_access_child(p.child_id)));

CREATE POLICY p_meas_select ON hbh.goal_measurements
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg AND EXISTS (
    SELECT 1 FROM hbh.plan_goals g
    JOIN   hbh.treatment_plans p ON p.plan_id = g.plan_id
    WHERE  g.goal_id = hbh.goal_measurements.goal_id AND hbh.can_access_child(p.child_id)));

-- ---------------------------------------------------------------------
-- The visibility ladder, as a policy.
--
-- A guardian sees a note only when all three hold. Staff who can see
-- every child see the internal ones too - that is what the permission
-- is for.
-- ---------------------------------------------------------------------
CREATE POLICY p_notes_select ON hbh.session_notes
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND active_flg
    AND hbh.can_access_child(child_id)
    AND (
      hbh.has_permission('CHILD.VIEW_ALL')
      OR (visibility = 'PARENT' AND is_draft_flg = false AND approved_by IS NOT NULL)
    )
  );

CREATE POLICY p_reports_select ON hbh.progress_reports
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND active_flg
    AND hbh.can_access_child(child_id)
    AND (hbh.has_permission('CHILD.VIEW_ALL') OR status = 'PUBLISHED')
  );

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.treatment_plans, hbh.plan_goals, hbh.goal_measurements,
                hbh.session_notes, hbh.progress_reports, hbh.v_goal_progress
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.can_edit_session(integer)               FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.write_session_note(integer, text)       FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.publish_session_note(integer)           FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.publish_report(integer)                 FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.can_edit_session(integer)            TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.write_session_note(integer, text)    TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.publish_session_note(integer)        TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.publish_report(integer)              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_plan_transition(text, text)    TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

-- =====================================================================
-- =====================================================================
-- NOTE ON SEEDING
--
-- The permissions this migration needs, the roles they attach to and
-- the report number series are NOT inserted here. They are reference
-- data and they live in db/seed/0002_rbac.sql.
--
-- The reason is an ordering one, and it cost a full acceptance run:
-- scripts/db.sh applies EVERY migration first and the seed files
-- afterwards. So at the moment this file runs, hbh.roles and
-- hbh.centers are empty on a rebuilt database - and an INSERT that
-- reads either of them matches nothing, inserts nothing, and reports
-- success. The grants simply never happened, and thirteen checks in
-- the phase-4 suite failed with no hint of why.
--
-- The rule: a migration creates STRUCTURE. Anything that reads a table
-- the seed populates belongs in the seed.
-- =====================================================================

INSERT INTO hbh.schema_migrations (version) VALUES ('0006');
