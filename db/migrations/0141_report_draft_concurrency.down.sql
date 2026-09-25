-- 0141 down. The API that sends a version calls this function, so roll
-- that API back FIRST - dropping it under a live caller turns every draft
-- save into 42883. And 0143 must be down before this one, or there is no
-- update_report left at all.
--
-- Going down reintroduces #14: two editors of one draft, and the second
-- save silently replaces the first.
DROP FUNCTION IF EXISTS hbh.update_report(integer, timestamptz, text, text, date, date, integer);
DELETE FROM hbh.schema_migrations WHERE version = '0141';
