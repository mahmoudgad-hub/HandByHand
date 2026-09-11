-- =====================================================================
-- Hand By Hand (new) - migration 0017 DOWN
--
-- Development convenience only, and it is a NO-OP on purpose.
--
-- Reverting would mean putting the history triggers back to running as
-- the caller, which breaks every direct UPDATE that 0016 enabled and
-- puts nothing right. If the intent is to close those writes, run the
-- 0016 down migration - that removes the grants and leaves the triggers
-- harmlessly definer.
-- =====================================================================

DELETE FROM hbh.schema_migrations WHERE version = '0017';
