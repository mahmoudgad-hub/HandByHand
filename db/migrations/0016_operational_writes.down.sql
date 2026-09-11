-- =====================================================================
-- Hand By Hand (new) - migration 0016 DOWN
--
-- Development convenience only.
--
-- Note what this does NOT restore: the version of book_appointment
-- without the permission guard. Dropping back to a function that let a
-- guardian book is not something a down migration should do quietly, so
-- the guard stays and only the grants come off.
-- =====================================================================

REVOKE UPDATE ON hbh.appointments FROM hbh_app;
REVOKE INSERT ON hbh.payments     FROM hbh_app;

DROP POLICY IF EXISTS p_appointments_edit ON hbh.appointments;
DROP POLICY IF EXISTS p_payments_write    ON hbh.payments;

DELETE FROM hbh.schema_migrations WHERE version = '0016';
