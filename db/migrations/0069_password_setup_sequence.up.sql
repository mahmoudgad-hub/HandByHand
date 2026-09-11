-- =====================================================================
-- 0069 - the grant 0068 forgot, and the check that caught it
--
-- Every migration in this project that adds a table ends with
--
--   GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;
--
-- 0061 forgot it, 0062 fixed that and added a conventions check so the
-- next one would not be found by a person. 0068 forgot it too - and the
-- check found it, on the first run after the migration, by name.
--
-- hbh.password_setups is written only through a SECURITY DEFINER
-- function, so hbh_app would never have reached the sequence and
-- nothing was actually broken. That is the argument for exempting it,
-- and it is the wrong argument: the check is worth more as a rule with
-- no exceptions than as one that has to be reasoned about each time,
-- and a grant on a sequence for a table hbh_app cannot write to gives
-- away nothing. The consistent answer is cheaper than the clever one.
-- =====================================================================

\set ON_ERROR_STOP on

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0069');
