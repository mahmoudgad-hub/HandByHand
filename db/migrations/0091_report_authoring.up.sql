-- =====================================================================
-- Report authoring: the write half of a domain that only ever had a read
-- half, and the authorization publish_report was missing.
--
-- WHY THERE WAS NO "CREATE REPORT". Not an oversight in the console - a
-- gap in the schema. hbh_app holds SELECT on hbh.progress_reports and
-- nothing else, and the table's only policy is p_reports_select. There
-- is no INSERT grant, no INSERT policy, and no function that writes one.
-- Every report in this database was inserted by the OWNER, from a
-- fixture or a seed. The console could not have created one whatever
-- button it drew, and adding a POST that inserts directly would have
-- been refused by the engine - correctly.
--
-- So the write path arrives the way every other clinical write in this
-- schema does: a SECURITY DEFINER function that asks the permission
-- question itself, because the table grants nothing.
--
-- WHAT THIS DOES NOT CHANGE. The report model. A progress report belongs
-- to a CHILD and covers a PERIOD, optionally against a treatment plan.
-- It has no session_id and no therapist_id, and this migration does not
-- give it either: authorship is hbh.current_app_user() in created_by,
-- the same as everywhere else. A report is not a session note.
--
-- Statuses stay the two the CHECK already allows - DRAFT and PUBLISHED -
-- and published reports stay immutable: trg_reports_immutable raises
-- HB033 on any UPDATE of a published row, and nothing here weakens it.
--
-- =====================================================================
-- THE SECOND THING THIS FIXES, and it is a real hole.
--
-- hbh.publish_report asks for REPORT.PUBLISH and stops there. It is
-- SECURITY DEFINER, so its SELECT sees EVERY report in every centre,
-- and it never asks whether the caller may reach the report's child.
--
-- Proven, not inferred: signed in as dev_therapist - who has no caseload
-- row, no appointment and no session for child 122 - publishing that
-- child's draft succeeded. Reception and a guardian were refused, so the
-- permission gate works; the ROW gate was simply absent.
--
-- Inside one centre that result is the documented model rather than a
-- bug: THERAPIST holds CHILD.VIEW_ALL so a clinician can cover for a
-- colleague, and hbh.can_access_child says so. ACROSS centres it is not
-- a model, it is a missing predicate - the function would have published
-- another centre's report for another centre's family.
--
-- can_access_child is the fix because it is the rule the table's own
-- SELECT policy already uses. Adding it changes nothing for a clinician
-- covering a colleague and closes the tenant boundary. It is not a new
-- rule; it is the existing one, asked in the one place that forgot to.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- REPORT.WRITE
--
-- A new permission, and the smallest one that works. The alternatives
-- were both wrong:
--
--   REPORT.PUBLISH means "a family may now read this" - the terminal,
--   irreversible act. Drafting is the opposite: private, revisable, the
--   step review exists to protect. Reusing PUBLISH for drafting would
--   mean anyone who may write a draft may also publish it, which
--   collapses the two-step workflow into one.
--
--   PLAN.MANAGE and ASSESSMENT.RECORD name different artefacts. Widening
--   either to cover reports would make both mean "clinical writing",
--   and the day the centre wants a therapist who drafts but does not
--   publish, there would be nothing left to take away.
--
-- It goes to the same two roles that already hold REPORT.PUBLISH, so no
-- account gains a capability it did not effectively have. What it buys
-- is the ability to separate them later without a migration.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('REPORT.WRITE', 'كتابة تقرير وتعديل مسودته', 'Author a report and edit its draft')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('CENTER_ADMIN', 'REPORT.WRITE'),
        ('THERAPIST',    'REPORT.WRITE')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- CREATE
--
-- Every trusted field is derived here and none is accepted from the
-- caller: the centre and branch come from the CHILD's row, the number
-- from the series, created_by from the session identity, and the status
-- is DRAFT because a report that could be born published would skip the
-- only review this workflow has.
--
-- period_start/period_end and title are required because the table
-- requires them. summary_ar is NOT required - a draft exists to be
-- finished later, and demanding the prose up front would mean a
-- therapist cannot save what they have written so far.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.create_report(
  p_child_id     integer,
  p_title_ar     text,
  p_period_start date,
  p_period_end   date,
  p_plan_id      integer DEFAULT NULL,
  p_summary_ar   text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF hbh.current_user_id() IS NULL THEN
    RAISE EXCEPTION 'no identity' USING ERRCODE = 'HB032';
  END IF;

  -- Permission before the row is read, so a caller with no right to
  -- write reports cannot use "no such child" to probe for children.
  IF NOT hbh.has_permission('REPORT.WRITE') THEN
    RAISE EXCEPTION 'writing a report needs REPORT.WRITE' USING ERRCODE = 'HB032';
  END IF;

  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB032';
  END IF;

  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'child % is not yours to report on', p_child_id USING ERRCODE = 'HB032';
  END IF;

  IF coalesce(btrim(p_title_ar), '') = '' THEN
    RAISE EXCEPTION 'a report needs a title' USING ERRCODE = 'HB029';
  END IF;

  IF p_period_start IS NULL OR p_period_end IS NULL OR p_period_end < p_period_start THEN
    RAISE EXCEPTION 'the report period is not a period' USING ERRCODE = 'HB029';
  END IF;

  -- A plan, when named, must belong to the same child. Without this a
  -- report could snapshot another child's goals at publish time.
  IF p_plan_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM hbh.treatment_plans t
       WHERE t.plan_id = p_plan_id AND t.child_id = p_child_id AND t.active_flg) THEN
    RAISE EXCEPTION 'plan % is not this child''s', p_plan_id USING ERRCODE = 'HB029';
  END IF;

  INSERT INTO hbh.progress_reports (center_id, branch_id, child_id, plan_id, report_no,
                                    title_ar, period_start, period_end, summary_ar, status)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_plan_id,
          hbh.next_number(l_child.center_id, 'REPORT'),
          btrim(p_title_ar), p_period_start, p_period_end,
          nullif(btrim(coalesce(p_summary_ar, '')), ''), 'DRAFT')
  RETURNING report_id INTO l_id;

  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.create_report(integer, text, date, date, integer, text) IS
  'Opens a progress report as a DRAFT. Needs REPORT.WRITE and access to the child. Centre, branch, number, author and status are derived here and never accepted from the caller.';

-- ---------------------------------------------------------------------
-- EDIT THE DRAFT
--
-- Only a draft. A published report is clinical history a family has
-- already read, and trg_reports_immutable refuses to change one - this
-- function says so with its own message first rather than letting the
-- trigger answer, so the screen can explain instead of apologising.
--
-- NULL means "leave alone" on every field, so the editor can save one
-- box without resending the whole report.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.update_report(
  p_report_id    integer,
  p_title_ar     text DEFAULT NULL,
  p_summary_ar   text DEFAULT NULL,
  p_period_start date DEFAULT NULL,
  p_period_end   date DEFAULT NULL,
  p_plan_id      integer DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
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
$$;

COMMENT ON FUNCTION hbh.update_report(integer, text, text, date, date, integer) IS
  'Edits a DRAFT report. Needs REPORT.WRITE and access to the child. A published report is refused with HB033 - it is history a family has read.';

-- ---------------------------------------------------------------------
-- PUBLISH, with the row gate it never had
--
-- The body is 0006's, unchanged except for the two blocks marked NEW.
-- ---------------------------------------------------------------------
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

  -- NEW: whose report it is. See the header - without this the function
  -- would publish another centre's report for another centre's family.
  IF NOT hbh.can_access_child(l_rep.child_id) THEN
    RAISE EXCEPTION 'report % is not yours to publish', p_report_id USING ERRCODE = 'HB032';
  END IF;

  IF l_rep.status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'report % is already published', p_report_id USING ERRCODE = 'HB033';
  END IF;

  -- NEW: publishing is the moment a family reads this, and a report with
  -- no summary is a notification pretending to be a report. Required
  -- HERE and not on the draft, which exists precisely to be incomplete.
  IF coalesce(btrim(l_rep.summary_ar), '') = '' THEN
    RAISE EXCEPTION 'report % has no summary to publish', p_report_id
      USING ERRCODE = 'HB029';
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

REVOKE ALL ON FUNCTION hbh.create_report(integer, text, date, date, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.update_report(integer, text, text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.create_report(integer, text, date, date, integer, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.update_report(integer, text, text, date, date, integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0091');
