-- =====================================================================
-- Hand By Hand (new) - migration 0012 DOWN
--
-- Development convenience only. Closes writing again and leaves every
-- SELECT policy standing.
--
-- Revoke BEFORE dropping the policies, not after. A window in which the
-- grant exists and the policy does not is a window in which hbh_app can
-- write with nothing filtering the rows - and on a database with real
-- data in it, that window is the whole point of this ordering.
-- =====================================================================

REVOKE INSERT, UPDATE ON
  hbh.services, hbh.rooms, hbh.activity_library, hbh.service_packages, hbh.cameras,
  hbh.therapists, hbh.therapist_services, hbh.therapist_working_hours, hbh.caseload,
  hbh.children, hbh.guardians, hbh.guardian_children,
  hbh.treatment_plans, hbh.plan_goals, hbh.child_activities, hbh.goal_measurements
  FROM hbh_app;

REVOKE UPDATE ON hbh.activity_log, hbh.parent_requests FROM hbh_app;

DROP POLICY IF EXISTS p_services_write            ON hbh.services;
DROP POLICY IF EXISTS p_services_edit             ON hbh.services;
DROP POLICY IF EXISTS p_rooms_write               ON hbh.rooms;
DROP POLICY IF EXISTS p_rooms_edit                ON hbh.rooms;
DROP POLICY IF EXISTS p_activity_library_write    ON hbh.activity_library;
DROP POLICY IF EXISTS p_activity_library_edit     ON hbh.activity_library;
DROP POLICY IF EXISTS p_service_packages_write    ON hbh.service_packages;
DROP POLICY IF EXISTS p_service_packages_edit     ON hbh.service_packages;
DROP POLICY IF EXISTS p_cameras_write             ON hbh.cameras;
DROP POLICY IF EXISTS p_cameras_edit              ON hbh.cameras;
DROP POLICY IF EXISTS p_therapists_write          ON hbh.therapists;
DROP POLICY IF EXISTS p_therapists_edit           ON hbh.therapists;
DROP POLICY IF EXISTS p_therapist_hours_write     ON hbh.therapist_working_hours;
DROP POLICY IF EXISTS p_therapist_hours_edit      ON hbh.therapist_working_hours;
DROP POLICY IF EXISTS p_therapist_services_write  ON hbh.therapist_services;
DROP POLICY IF EXISTS p_therapist_services_edit   ON hbh.therapist_services;
DROP POLICY IF EXISTS p_caseload_write            ON hbh.caseload;
DROP POLICY IF EXISTS p_caseload_edit             ON hbh.caseload;
DROP POLICY IF EXISTS p_children_write            ON hbh.children;
DROP POLICY IF EXISTS p_children_edit             ON hbh.children;
DROP POLICY IF EXISTS p_guardians_write           ON hbh.guardians;
DROP POLICY IF EXISTS p_guardians_edit            ON hbh.guardians;
DROP POLICY IF EXISTS p_guardian_children_write   ON hbh.guardian_children;
DROP POLICY IF EXISTS p_guardian_children_edit    ON hbh.guardian_children;
DROP POLICY IF EXISTS p_plans_write               ON hbh.treatment_plans;
DROP POLICY IF EXISTS p_plans_edit                ON hbh.treatment_plans;
DROP POLICY IF EXISTS p_goals_write               ON hbh.plan_goals;
DROP POLICY IF EXISTS p_goals_edit                ON hbh.plan_goals;
DROP POLICY IF EXISTS p_child_activities_write    ON hbh.child_activities;
DROP POLICY IF EXISTS p_child_activities_edit     ON hbh.child_activities;
DROP POLICY IF EXISTS p_measurements_write        ON hbh.goal_measurements;
DROP POLICY IF EXISTS p_measurements_edit         ON hbh.goal_measurements;
DROP POLICY IF EXISTS p_activity_log_edit         ON hbh.activity_log;
DROP POLICY IF EXISTS p_parent_requests_edit      ON hbh.parent_requests;

DELETE FROM hbh.schema_migrations WHERE version = '0012';
