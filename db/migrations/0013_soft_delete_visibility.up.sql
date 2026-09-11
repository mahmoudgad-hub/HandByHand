-- =====================================================================
-- Hand By Hand (new) - migration 0013: seeing what you archived
--
-- WHY THIS EXISTS. Migration 0012 opened writing and granted UPDATE so
-- that a "delete" could be a soft delete - active_flg = false plus a
-- timestamp. It did not work, and the reason is a real Postgres
-- behaviour that is easy to be surprised by:
--
--   PostgreSQL applies the SELECT policy to the NEW row of an UPDATE.
--
-- You cannot update a row into a state where you would no longer be
-- able to see it. And every SELECT policy in this schema filters
-- active_flg - so setting active_flg = false makes the new row
-- invisible to its own author, and the whole UPDATE is refused with
-- "new row violates row-level security policy".
--
-- Seventeen of the eighteen write-enabled tables were affected. Only
-- hbh.children was not, because its policy gates on can_access_child
-- and never mentioned active_flg. That difference is what identified
-- the cause: the same statement succeeded on one table and failed on
-- the other.
--
-- THE FIX, AND THE TWO REJECTED ONES.
--
--   Rejected: drop active_flg from the SELECT policies and filter it in
--   the API queries instead. That moves an access rule out of the
--   policy and into the query, where a forgotten WHERE clause exposes
--   archived rows - which is the exact failure mode the policies exist
--   to make impossible.
--
--   Rejected: a SECURITY DEFINER soft_delete(table_name, id) helper.
--   Dynamic SQL over a table name, to avoid writing a policy.
--
--   Taken: a SECOND, permissive SELECT policy per table admitting the
--   row to whoever holds the right to manage it - without the
--   active_flg filter. Policies are OR'd, so an ordinary reader still
--   sees only active rows; the manager sees the archived ones too.
--
-- And that is not a workaround, it is the correct product behaviour.
-- Whoever can archive a row must be able to see what they archived, or
-- "delete" is irreversible from the screen and the soft delete bought
-- nothing.
--
-- The distinction it rests on is worth stating: a POLICY answers "may
-- this person see this row at all"; a QUERY answers "which of the rows
-- I may see do I want right now". Active-versus-archived is the second
-- kind, so the list endpoints filter it and the policy does not.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0013') THEN
    RAISE EXCEPTION 'migration 0013 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0012') THEN
    RAISE EXCEPTION 'migration 0012 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE CATALOGUE
-- =====================================================================
CREATE POLICY p_services_select_archived ON hbh.services
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_rooms_select_archived ON hbh.rooms
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_activity_library_select_archived ON hbh.activity_library
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

CREATE POLICY p_service_packages_select_archived ON hbh.service_packages
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('CATALOG.MANAGE'));

-- Cameras keep both permissions, exactly as the write policy does. An
-- archived camera row still holds a gateway_path.
CREATE POLICY p_cameras_select_archived ON hbh.cameras
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id()
         AND hbh.has_permission('CATALOG.MANAGE')
         AND hbh.has_permission('LIVE.VIEW'));

-- =====================================================================
-- STAFF
-- =====================================================================
CREATE POLICY p_therapists_select_archived ON hbh.therapists
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_therapist_hours_select_archived ON hbh.therapist_working_hours
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

CREATE POLICY p_therapist_services_select_archived ON hbh.therapist_services
  FOR SELECT TO hbh_app
  USING (hbh.has_permission('STAFF.MANAGE')
         AND EXISTS (SELECT 1 FROM hbh.therapists t
                     WHERE t.therapist_id = therapist_services.therapist_id
                     AND   t.center_id = hbh.current_center_id()));

CREATE POLICY p_caseload_select_archived ON hbh.caseload
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('STAFF.MANAGE'));

-- =====================================================================
-- PEOPLE
-- =====================================================================
CREATE POLICY p_guardians_select_archived ON hbh.guardians
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('GUARDIAN.MANAGE'));

CREATE POLICY p_guardian_children_select_archived ON hbh.guardian_children
  FOR SELECT TO hbh_app
  USING (hbh.has_permission('GUARDIAN.MANAGE')
         AND EXISTS (SELECT 1 FROM hbh.children c
                     WHERE c.child_id = guardian_children.child_id
                     AND   c.center_id = hbh.current_center_id()));

-- =====================================================================
-- CLINICAL AUTHORSHIP
-- =====================================================================
CREATE POLICY p_plans_select_archived ON hbh.treatment_plans
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_goals_select_archived ON hbh.plan_goals
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_child_activities_select_archived ON hbh.child_activities
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('PLAN.MANAGE'));

CREATE POLICY p_measurements_select_archived ON hbh.goal_measurements
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('GOAL.MEASURE'));

-- =====================================================================
-- THE FAMILY'S OWN ROWS
--
-- No permission here: the gate is authorship. A parent may see the day
-- they reported and the request they opened even after withdrawing it,
-- because otherwise they could not withdraw it at all - and because a
-- family that cannot see what it wrote cannot tell whether the
-- withdrawal worked.
--
-- Note this admits ONLY their own rows, which is narrower than the
-- policy it sits beside: that one admits any row for a child they may
-- access. Nothing new is exposed.
-- =====================================================================
CREATE POLICY p_activity_log_select_own ON hbh.activity_log
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND logged_by = hbh.current_user_id());

CREATE POLICY p_parent_requests_select_own ON hbh.parent_requests
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id()
         AND EXISTS (SELECT 1 FROM hbh.guardians g
                     WHERE g.guardian_id = parent_requests.guardian_id
                     AND   g.user_id = hbh.current_user_id()));

INSERT INTO hbh.schema_migrations (version) VALUES ('0013');
