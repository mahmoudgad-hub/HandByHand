-- =====================================================================
-- Hand By Hand (new) - migration 0104 rollback
--
-- Restores the per-row form from migration 0020. The MEANING is
-- identical either way; what changes is that the two identity functions
-- are called once per row again, which at 34,000 rows was 5,260ms and
-- grows linearly from there.
--
-- There is no correctness reason to run this.
-- =====================================================================

DROP POLICY IF EXISTS p_rlog_select ON hbh.request_log;

CREATE POLICY p_rlog_select ON hbh.request_log
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND hbh.has_permission('OPS.VIEW'));

COMMENT ON TABLE hbh.request_log IS NULL;

DELETE FROM hbh.schema_migrations WHERE version = '0104';
