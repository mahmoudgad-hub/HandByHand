-- =====================================================================
-- 0121 down - no room opens itself, and there is no door
--
-- The trigger goes before the function it calls, and both go before
-- 0120 takes the tables away. The file is one transaction, so a step
-- that fails on a dependency drops nothing at all and the rebuild
-- quietly keeps the new definitions while appearing to have reverted.
--
-- THE ROOMS ALREADY OPENED ARE LEFT ALONE. They are 0120's rows and
-- 0120's down is what removes them; deleting them here would mean this
-- file half-undoes its neighbour, and a consultation's room is not this
-- migration's to throw away.
--
-- The sequence grant stays. It corrected a defect in 0120 rather than
-- introducing anything, and taking it back would restore the defect.
-- =====================================================================

\set ON_ERROR_STOP on

DROP TRIGGER IF EXISTS trg_appointments_meeting ON hbh.appointments;

DROP FUNCTION IF EXISTS hbh.record_meeting_token(bigint, bytea, boolean, timestamptz, inet);
DROP FUNCTION IF EXISTS hbh.authorize_meeting_entry(integer);
DROP FUNCTION IF EXISTS hbh.trg_appointment_meeting();

DELETE FROM hbh.schema_migrations WHERE version = '0121';
