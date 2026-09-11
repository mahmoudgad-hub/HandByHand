-- Hand By Hand (new) - migration 0088 DOWN. Development only.
--
-- Restores hbh.publish_report to its 0006 body, which is worth stating
-- plainly: rolling this back removes the child-access check, so the
-- function goes back to publishing any report in any centre for anyone
-- holding REPORT.PUBLISH.
--
-- REPORT.WRITE is removed from the roles and then from the permission
-- table, in that order - role_permissions references it.
--
-- The authoring functions are dropped last. Nothing else calls them.

\set ON_ERROR_STOP on

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

DELETE FROM hbh.role_permissions rp
USING  hbh.permissions p
WHERE  p.permission_id = rp.permission_id AND p.code = 'REPORT.WRITE';

DELETE FROM hbh.permissions WHERE code = 'REPORT.WRITE';

DROP FUNCTION IF EXISTS hbh.update_report(integer, text, text, date, date, integer);
DROP FUNCTION IF EXISTS hbh.create_report(integer, text, date, date, integer, text);

DELETE FROM hbh.schema_migrations WHERE version = '0091';
