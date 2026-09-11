-- =====================================================================
-- Hand By Hand (new) - migration 0027 rollback
--
-- Removes the audit trigger from hbh.assessment_item_scores and leaves
-- the rows it already wrote in place: an audit record describes
-- something that happened, and dropping the recorder is not a reason to
-- deny it happened.
--
-- Rolling this back puts the schema back in the state the phase-4
-- invariant refuses, so the suite will go red again. That is the point
-- of the check.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_ascore_audit ON hbh.assessment_item_scores;

DELETE FROM hbh.schema_migrations WHERE version = '0027';
