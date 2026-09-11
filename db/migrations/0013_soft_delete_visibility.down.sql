-- =====================================================================
-- Hand By Hand (new) - migration 0013 DOWN
--
-- Development convenience only. Dropping these makes soft delete
-- impossible again for hbh_app - see the note in the up migration.
-- =====================================================================

DROP POLICY IF EXISTS p_services_select_archived          ON hbh.services;
DROP POLICY IF EXISTS p_rooms_select_archived             ON hbh.rooms;
DROP POLICY IF EXISTS p_activity_library_select_archived  ON hbh.activity_library;
DROP POLICY IF EXISTS p_service_packages_select_archived  ON hbh.service_packages;
DROP POLICY IF EXISTS p_cameras_select_archived           ON hbh.cameras;
DROP POLICY IF EXISTS p_therapists_select_archived        ON hbh.therapists;
DROP POLICY IF EXISTS p_therapist_hours_select_archived   ON hbh.therapist_working_hours;
DROP POLICY IF EXISTS p_therapist_services_select_archived ON hbh.therapist_services;
DROP POLICY IF EXISTS p_caseload_select_archived          ON hbh.caseload;
DROP POLICY IF EXISTS p_guardians_select_archived         ON hbh.guardians;
DROP POLICY IF EXISTS p_guardian_children_select_archived ON hbh.guardian_children;
DROP POLICY IF EXISTS p_plans_select_archived             ON hbh.treatment_plans;
DROP POLICY IF EXISTS p_goals_select_archived             ON hbh.plan_goals;
DROP POLICY IF EXISTS p_child_activities_select_archived  ON hbh.child_activities;
DROP POLICY IF EXISTS p_measurements_select_archived      ON hbh.goal_measurements;
DROP POLICY IF EXISTS p_activity_log_select_own           ON hbh.activity_log;
DROP POLICY IF EXISTS p_parent_requests_select_own        ON hbh.parent_requests;

DELETE FROM hbh.schema_migrations WHERE version = '0013';
