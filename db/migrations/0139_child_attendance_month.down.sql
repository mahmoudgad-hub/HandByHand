-- 0139 down. The API reads this function for GET /api/v1/children, so
-- the API that selects it must be rolled back FIRST - dropping the
-- function under a live SELECT turns every children read, portal and
-- console alike, into 42883. Same lesson as children.photo_url.
DROP FUNCTION IF EXISTS hbh.child_attendance_month(integer);
DELETE FROM hbh.schema_migrations WHERE version = '0139';
