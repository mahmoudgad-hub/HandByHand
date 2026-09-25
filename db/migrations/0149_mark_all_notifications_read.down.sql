-- =====================================================================
-- 0149 down - no "mark all read". Rows already marked stay read: the
-- person did read them, and withdrawing the button does not undo that.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.mark_all_notifications_read();

DELETE FROM hbh.schema_migrations WHERE version = '0149';
