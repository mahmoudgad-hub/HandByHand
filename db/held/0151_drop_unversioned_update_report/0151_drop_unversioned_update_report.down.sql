-- 0151 down. Restores the six-argument update_report exactly as it was live
-- before 0141 (from pg_get_functiondef, 2026-09-13). WARNING: while it
-- exists the version check in 0141 is optional - any caller that picks
-- this signature overwrites a colleague's draft unseen (#14).
CREATE FUNCTION hbh.update_report(p_report_id integer, p_title_ar text DEFAULT NULL::text, p_summary_ar text DEFAULT NULL::text, p_period_start date DEFAULT NULL::date, p_period_end date DEFAULT NULL::date, p_plan_id integer DEFAULT NULL::integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'hbh', 'pg_catalog'
AS $function$
DECLARE
  l_rep   hbh.progress_reports%ROWTYPE;
  l_start date;
  l_end   date;
BEGIN
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB032';
  END IF;

  IF NOT hbh.has_permission('REPORT.WRITE') THEN
    RAISE EXCEPTION 'editing a report needs REPORT.WRITE' USING ERRCODE = 'HB032';
  END IF;

  SELECT * INTO l_rep FROM hbh.progress_reports
  WHERE report_id = p_report_id AND active_flg FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such report %', p_report_id USING ERRCODE = 'HB032';
  END IF;

  IF NOT hbh.can_access_child(l_rep.child_id) THEN
    RAISE EXCEPTION 'report % is not yours to edit', p_report_id USING ERRCODE = 'HB032';
  END IF;

  IF l_rep.status <> 'DRAFT' THEN
    RAISE EXCEPTION 'report % is published and cannot be edited', p_report_id
      USING ERRCODE = 'HB033';
  END IF;

  l_start := coalesce(p_period_start, l_rep.period_start);
  l_end   := coalesce(p_period_end,   l_rep.period_end);
  IF l_end < l_start THEN
    RAISE EXCEPTION 'the report period is not a period' USING ERRCODE = 'HB029';
  END IF;

  IF p_title_ar IS NOT NULL AND btrim(p_title_ar) = '' THEN
    RAISE EXCEPTION 'a report needs a title' USING ERRCODE = 'HB029';
  END IF;

  IF p_plan_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM hbh.treatment_plans t
       WHERE t.plan_id = p_plan_id AND t.child_id = l_rep.child_id AND t.active_flg) THEN
    RAISE EXCEPTION 'plan % is not this child''s', p_plan_id USING ERRCODE = 'HB029';
  END IF;

  UPDATE hbh.progress_reports
     SET title_ar     = coalesce(btrim(p_title_ar), title_ar),
         summary_ar   = CASE WHEN p_summary_ar IS NULL THEN summary_ar
                             ELSE nullif(btrim(p_summary_ar), '') END,
         period_start = l_start,
         period_end   = l_end,
         plan_id      = coalesce(p_plan_id, plan_id)
   WHERE report_id = p_report_id;
END
$function$;

REVOKE ALL ON FUNCTION hbh.update_report(integer, text, text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.update_report(integer, text, text, date, date, integer) TO hbh_app;

DELETE FROM hbh.schema_migrations WHERE version = '0151';
