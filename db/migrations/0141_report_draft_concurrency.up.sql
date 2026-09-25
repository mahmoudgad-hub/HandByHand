-- 0141 - a draft report is saved only over the version its editor opened.
--
-- Backlog #14. hbh.update_report took the row lock and wrote whatever it
-- was sent, so two clinicians with the same draft open both "saved" and
-- the second one silently replaced the first one's prose. The lock made
-- the writes serial; it did nothing about the second writer never having
-- seen the first one's text. Nothing on screen or in any log said so.
--
-- The version is coalesce(updated_at, created_at) - no new column.
-- trg_reports_touch stamps updated_at on every UPDATE, and ONLY on update:
-- a draft nobody has edited yet has updated_at NULL (report 310 on the
-- shared database, measured). Comparing updated_at alone would make every
-- fresh draft unsaveable, since the NULL check below refuses a NULL
-- expected version. The API reads the version with the same expression.
-- (A create and an edit inside ONE transaction share now(), so the two
-- versions coincide there; no client does that - each call is a request.)
--
-- It is compared AFTER the
-- status check: a report someone published meanwhile is better told as
-- HB033 (published, cannot be edited) than as "somebody changed it".
--
-- CODES (measured in pg_proc AND the code base on 2026-09-13). pg_proc
-- alone said HB265 was free; the API already names HB265-HB273 for 0142
-- (payment plans), not yet applied. HB290 leaves that family room to grow.
--
-- NUMBER: written as 0150 and renumbered 0141 on 2026-09-13 - p00 fails on
-- any gap in the ledger, and application order is 0141 -> image -> 0142
-- (payment plans) -> 0143 (drop of the six-argument function).
--   HB290  the draft changed since this editor opened it          -> 409
--   HB029  no expected version sent at all - the caller can fix that
--          by reading the report first, so it is a validation refusal
--          rather than a conflict. Refusing it is the point: a NULL that
--          meant "skip the check" would be the old behaviour with a new
--          signature.
--
-- SIGNATURE. The expected version is a REQUIRED second parameter and the
-- function now returns the new version, so a client can save twice in a
-- row without re-reading. The old six-argument function stays in this
-- migration, untouched, because the API running today calls it: dropping
-- it here would turn every draft save into 42883 between this migration
-- and the API deploy. It is dropped in 0143, once the API that sends a
-- version is live. The new parameter carries no default on purpose - with
-- one, a six-argument call would be ambiguous between the two.
--
-- ORDER: this migration first, then the API, then 0143.
-- Built from pg_get_functiondef of the live function, not from 0088.

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0141') THEN
    RAISE EXCEPTION 'migration 0141 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0140') THEN
    RAISE EXCEPTION 'migration 0140 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc ~ 'HB290') THEN
    RAISE EXCEPTION 'a live function already raises HB290 - renumber before applying';
  END IF;
END
$guard$;

CREATE FUNCTION hbh.update_report(
  p_report_id           integer,
  p_expected_version    timestamptz,
  p_title_ar            text,
  p_summary_ar          text,
  p_period_start        date,
  p_period_end          date,
  p_plan_id             integer)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $function$
DECLARE
  l_rep     hbh.progress_reports%ROWTYPE;
  l_start   date;
  l_end     date;
  l_version timestamptz;
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

  IF p_expected_version IS NULL THEN
    RAISE EXCEPTION 'saving report % needs the version it was opened at', p_report_id
      USING ERRCODE = 'HB029';
  END IF;

  -- IS DISTINCT FROM, not <>: this comparison decides whether a write is
  -- allowed, and a three-valued answer must not fall through to the UPDATE.
  IF coalesce(l_rep.updated_at, l_rep.created_at) IS DISTINCT FROM p_expected_version THEN
    RAISE EXCEPTION 'report % changed since it was opened', p_report_id
      USING ERRCODE = 'HB290',
            HINT = 'reload the draft; the text on screen is not saved';
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
   WHERE report_id = p_report_id
  RETURNING updated_at INTO l_version;

  RETURN l_version;
END
$function$;

COMMENT ON FUNCTION hbh.update_report(integer, timestamptz, text, text, date, date, integer) IS
  'Edits a DRAFT report only if it is still at the version the caller opened (coalesce(updated_at, created_at)); returns the new version. HB290 when someone saved in between. Backlog #14, migration 0141.';

REVOKE ALL ON FUNCTION hbh.update_report(integer, timestamptz, text, text, date, date, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.update_report(integer, timestamptz, text, text, date, date, integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0141');
