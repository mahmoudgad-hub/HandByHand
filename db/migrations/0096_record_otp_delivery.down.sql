-- =====================================================================
-- 0096 down - the login handler loses its way to record a delivery.
--
-- Nothing else calls this function. The rows it wrote stay: they are a
-- record that a code was sent to a number, and that does not become
-- untrue because the function was withdrawn.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.record_otp_delivery(integer, text, text, text, text, text);

DELETE FROM hbh.schema_migrations WHERE version = '0096';
