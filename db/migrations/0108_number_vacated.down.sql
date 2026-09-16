-- =====================================================================
-- 0108 down - the number is given up again.
--
-- There is nothing to undo, because nothing was done. Removing the row
-- restores the gap the up file exists to fill, which is the correct
-- reversal: a ledger that no longer claims 0108 is a ledger that is
-- telling the truth about a database where 0108 was never applied.
--
-- The conventions suite will fail on the gap again, and that is the
-- point of it rather than a side effect.
-- =====================================================================

DELETE FROM hbh.schema_migrations WHERE version = '0108';
