-- =====================================================================
-- 0062 - the grant 0061 forgot
--
-- Creating a table with GENERATED ALWAYS AS IDENTITY creates a sequence
-- that hbh_app cannot use until it is granted. Every migration in this
-- project that adds a table ends with the same line for exactly this
-- reason; 0061 did not, so both new tables accepted reads and refused
-- every insert with
--
--   permission denied for sequence site_team_media_media_id_seq
--
-- which the service correctly reports as 403. A permission error naming
-- a sequence reads as a policy problem, and the policies were fine.
--
-- The conventions suite did not catch it, which is the more interesting
-- half: it checks tables, columns, indexes and policies, and had
-- nothing to say about the sequences underneath the identity columns.
-- p00 gains that check with this migration - a rule that grows with the
-- schema rather than a fix for one table.
-- =====================================================================

\set ON_ERROR_STOP on

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0062');
