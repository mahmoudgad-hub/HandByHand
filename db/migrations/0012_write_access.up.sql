-- =====================================================================
-- Hand By Hand (new) - migration 0012: write access
--
-- Until now this schema was READ-ONLY to the API by construction: 41
-- SELECT policies, one INSERT policy (the audit log), and not a single
-- write grant. That was correct while Oracle was production - the rule
-- was "one source of truth, no dual writes".
--
-- On 2026-09-03 the owner decided Oracle stops and PostgreSQL becomes
-- the source of truth (D-26). This migration is the first technical
-- consequence: it opens writing.
--
-- FOUR RULES SHAPE EVERY POLICY BELOW. They are not style.
--
--   1. NO DELETE GRANT. Anywhere. Not one.
--      Deletion is soft - active_flg = false plus a timestamp - because
--      a child's clinical record may not be destroyed without a
--      documented compliance action. A DELETE grant is the difference
--      between "we can undo that" and "it is gone".
--
--   2. THE PERMISSION IS CHECKED INSIDE THE POLICY, never in Go.
--      A check in a handler is a second copy of a rule, and the day the
--      two copies disagree the weaker one decides. Here the engine
--      decides, underneath the query, where a forgotten condition in
--      application code cannot reach.
--
--   3. center_id IS PINNED ON BOTH SIDES of every UPDATE.
--      USING alone says which rows you may change. Without the same
--      condition in WITH CHECK, an UPDATE could MOVE a row into another
--      centre - writing a child out of the tenant that owns them. The
--      pair is what closes that, and it is easy to write only half.
--
--   4. hbh.current_center_id() IS NOT NULL comes first, always.
--      An unauthenticated connection has no centre, and a condition
--      like "center_id = NULL" is NULL, not true - so it denies. But a
--      policy that ever compares something else first can leak. The
--      identity check is the door; the centre check is the room.
--
-- Two link tables - guardian_children and therapist_services - carry no
-- center_id of their own, so they are scoped through their parent.
--
-- New permissions (CATALOG.MANAGE, STAFF.MANAGE) are NOT inserted here.
-- They are reference data and they live in db/seed/0002_rbac.sql: this
-- file runs before the seed on a rebuilt database, so an INSERT here
-- that reads hbh.roles would match nothing, insert nothing, and report
-- success. That lesson cost the phase-4 suite thirteen checks.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0012') THEN
    RAISE EXCEPTION 'migration 0012 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0011') THEN
    RAISE EXCEPTION 'migration 0011 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE CATALOGUE - services, rooms, activities, packages
--
-- What the centre offers and where. Reference data a centre
-- administrator maintains; no clinical content.
-- =====================================================================
CREATE POLICY p_services_write ON hbh.services
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_services_edit ON hbh.services
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_rooms_write ON hbh.rooms
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_rooms_edit ON hbh.rooms
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_activity_library_write ON hbh.activity_library
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_activity_library_edit ON hbh.activity_library
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_service_packages_write ON hbh.service_packages
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_service_packages_edit ON hbh.service_packages
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

-- ---------------------------------------------------------------------
-- Cameras need TWO permissions, not one
--
-- The row holds gateway_path, and the SELECT policy already demands
-- LIVE.VIEW and CHILD.VIEW_ALL together to read it. Writing one is
-- strictly more dangerous than reading one - a bad path points the
-- portal at a different room - so it asks for the catalogue right AND
-- the live right. Whoever maintains the price list does not thereby get
-- to repoint a camera.
-- ---------------------------------------------------------------------
CREATE POLICY p_cameras_write ON hbh.cameras
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE')
              AND hbh.has_permission('LIVE.VIEW'));

CREATE POLICY p_cameras_edit ON hbh.cameras
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE') AND hbh.has_permission('LIVE.VIEW'))
  WITH CHECK (center_id = hbh.current_center_id()
              AND hbh.has_permission('CATALOG.MANAGE') AND hbh.has_permission('LIVE.VIEW'));

-- =====================================================================
-- STAFF - therapists, what they offer, when they work, who they carry
-- =====================================================================
CREATE POLICY p_therapists_write ON hbh.therapists
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_therapists_edit ON hbh.therapists
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_therapist_hours_write ON hbh.therapist_working_hours
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_therapist_hours_edit ON hbh.therapist_working_hours
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

-- therapist_services has no center_id. It is scoped through the
-- therapist, so a row cannot be attached to a therapist in another
-- centre - which is the only way a link table can leak.
CREATE POLICY p_therapist_services_write ON hbh.therapist_services
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.has_permission('STAFF.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.therapists t
                          WHERE t.therapist_id = therapist_services.therapist_id
                          AND   t.center_id = hbh.current_center_id()));

CREATE POLICY p_therapist_services_edit ON hbh.therapist_services
  FOR UPDATE TO hbh_app
  USING      (hbh.has_permission('STAFF.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.therapists t
                          WHERE t.therapist_id = therapist_services.therapist_id
                          AND   t.center_id = hbh.current_center_id()))
  WITH CHECK (hbh.has_permission('STAFF.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.therapists t
                          WHERE t.therapist_id = therapist_services.therapist_id
                          AND   t.center_id = hbh.current_center_id()));

CREATE POLICY p_caseload_write ON hbh.caseload
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_caseload_edit ON hbh.caseload
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

-- =====================================================================
-- PEOPLE
--
-- Registering a child and editing one are SEPARATE rights, and the
-- schema already had separate codes for them. Two rights with two codes
-- get two gates: the Oracle system once demanded two permissions for a
-- single action and refused a user holding the very right the action
-- was named after.
-- =====================================================================
CREATE POLICY p_children_write ON hbh.children
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('CHILD.CREATE'));

CREATE POLICY p_children_edit ON hbh.children
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('CHILD.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('CHILD.EDIT'));

CREATE POLICY p_guardians_write ON hbh.guardians
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('GUARDIAN.MANAGE'));

CREATE POLICY p_guardians_edit ON hbh.guardians
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('GUARDIAN.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('GUARDIAN.MANAGE'));

-- The link that the whole portal hangs on, and the one that carries
-- can_view_live_flg. No center_id of its own: scoped through the child.
CREATE POLICY p_guardian_children_write ON hbh.guardian_children
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.has_permission('GUARDIAN.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.children c
                          WHERE c.child_id = guardian_children.child_id
                          AND   c.center_id = hbh.current_center_id()));

CREATE POLICY p_guardian_children_edit ON hbh.guardian_children
  FOR UPDATE TO hbh_app
  USING      (hbh.has_permission('GUARDIAN.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.children c
                          WHERE c.child_id = guardian_children.child_id
                          AND   c.center_id = hbh.current_center_id()))
  WITH CHECK (hbh.has_permission('GUARDIAN.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.children c
                          WHERE c.child_id = guardian_children.child_id
                          AND   c.center_id = hbh.current_center_id()));

-- =====================================================================
-- CLINICAL AUTHORSHIP
--
-- A plan, its goals and the home programme are authored under
-- PLAN.MANAGE. Recording a measurement is GOAL.MEASURE - a separate
-- code, because taking a reading during a session and rewriting the
-- plan are different acts by different people.
--
-- Note what is NOT opened here: session_notes and progress_reports.
-- Those keep their existing publication path - write_session_note,
-- publish_session_note, publish_report - because the visibility ladder
-- lives in those functions, and a plain UPDATE grant would let a row be
-- flipped to visibility='PARENT' without passing the approval the
-- ladder exists to require.
-- =====================================================================
CREATE POLICY p_plans_write ON hbh.treatment_plans
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_plans_edit ON hbh.treatment_plans
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_goals_write ON hbh.plan_goals
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_goals_edit ON hbh.plan_goals
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_child_activities_write ON hbh.child_activities
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_child_activities_edit ON hbh.child_activities
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_measurements_write ON hbh.goal_measurements
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('GOAL.MEASURE'));

CREATE POLICY p_measurements_edit ON hbh.goal_measurements
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id() AND hbh.has_permission('GOAL.MEASURE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('GOAL.MEASURE'));

-- =====================================================================
-- THE FAMILY'S OWN CORRECTIONS
--
-- Two things a parent may change, and they are narrow on purpose.
--
-- A family that ticked the wrong day can fix it, and a family that
-- opened a request by mistake can withdraw it - but only while nobody
-- has acted on it. Once staff have decided a request, it is a record of
-- a conversation and not a draft.
--
-- INSERT is NOT granted on either table. Creating stays with
-- hbh.log_activity and hbh.submit_request, which derive the guardian
-- from the request identity: a client that could name the guardian
-- could file for another family.
-- =====================================================================
CREATE POLICY p_activity_log_edit ON hbh.activity_log
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id()
              AND logged_by = hbh.current_user_id())
  WITH CHECK (center_id = hbh.current_center_id()
              AND logged_by = hbh.current_user_id());

CREATE POLICY p_parent_requests_edit ON hbh.parent_requests
  FOR UPDATE TO hbh_app
  USING      (center_id = hbh.current_center_id()
              AND status = 'NEW'
              AND EXISTS (SELECT 1 FROM hbh.guardians g
                          WHERE g.guardian_id = parent_requests.guardian_id
                          AND   g.user_id = hbh.current_user_id()))
  WITH CHECK (center_id = hbh.current_center_id()
              AND status = 'NEW'
              AND EXISTS (SELECT 1 FROM hbh.guardians g
                          WHERE g.guardian_id = parent_requests.guardian_id
                          AND   g.user_id = hbh.current_user_id()));

-- =====================================================================
-- GRANTS
--
-- INSERT and UPDATE. There is no DELETE on this list and there must
-- never be one: deletion in this system is active_flg = false plus a
-- timestamp, so that a record can be restored and an auditor can see
-- that it once existed. The acceptance suite asserts the absence.
-- =====================================================================
GRANT INSERT, UPDATE ON
  hbh.services, hbh.rooms, hbh.activity_library, hbh.service_packages, hbh.cameras,
  hbh.therapists, hbh.therapist_services, hbh.therapist_working_hours, hbh.caseload,
  hbh.children, hbh.guardians, hbh.guardian_children,
  hbh.treatment_plans, hbh.plan_goals, hbh.child_activities, hbh.goal_measurements
  TO hbh_app;

-- UPDATE only: these two are created through their functions.
GRANT UPDATE ON hbh.activity_log, hbh.parent_requests TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0012');
