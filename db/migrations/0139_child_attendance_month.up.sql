-- =====================================================================
-- Hand By Hand (new) - migration 0139: a child's attendance this month
--
-- WHAT THE FAMILY SEES TODAY
--
-- Every child card on the portal's welcome screen carries a ring titled
-- "نسبة الحضور هذا الشهر" with a dash in it and the words "غير متاحة
-- حاليًا" underneath - for every child, every month, forever. The dash is
-- written into the template; nothing was ever computed. A permanent
-- "unavailable" is not an empty state, it is a feature that does not
-- exist wearing the costume of one that is briefly down.
--
-- WHY IT CAN BE COMPUTED HONESTLY
--
-- The appointment state machine already records both halves:
--   attended   CHECKED_IN, COMPLETED   the child came
--   missed     NO_SHOW                 the child did not, and reception
--                                      marked it
-- so attendance is attended / (attended + missed), over appointments that
-- have already started this month.
--
-- WHAT IS DELIBERATELY NOT COUNTED, AND WHY
--
--   CANCELLED - a cancellation is not an absence. A session the centre
--     called off because a therapist was ill would otherwise count
--     against the child, and one the family cancelled a week ahead is
--     exactly the behaviour a centre wants to encourage.
--   BOOKED / CONFIRMED that have already started - nobody has recorded
--     what happened yet. Counting them as missed would accuse a family
--     of an absence reception simply has not entered; counting them as
--     attended would invent a visit. They wait until someone knows.
--   Future appointments - nothing has happened.
--
-- WHY A FUNCTION, AND WHY SECURITY INVOKER
--
-- Rule 2: which statuses count is a business rule, and a percentage
-- computed in the portal would be a second copy of it - the one that
-- quietly disagrees the day a status is added. So the portal receives
-- two counts and does arithmetic on them, and the counting lives here.
--
-- It is NOT security definer. It reads hbh.appointments under the
-- caller's own identity, so p_appointments_select decides which rows are
-- counted: a guardian counts their own child and gets zero rows for any
-- other - and with no identity at all, zero rows, which is how identity
-- fails closed here. A definer function that took a raw child_id would be
-- a way to ask about any child in the schema.
--
-- The centre's own time zone draws the month, never UTC and never the
-- browser: "this month" for a family in Cairo starts at local midnight
-- on the 1st, two hours away from the UTC boundary. p_centers_select lets
-- a caller read their own centre row, which is the only one this joins.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0139') THEN
    RAISE EXCEPTION 'migration 0139 is already applied - migrations are forward-only';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.child_attendance_month(p_child_id integer)
RETURNS TABLE (attended integer, missed integer)
LANGUAGE sql
STABLE
SET search_path = hbh, pg_catalog
AS $fn$
  SELECT count(*) FILTER (WHERE a.status IN ('CHECKED_IN', 'COMPLETED'))::integer,
         count(*) FILTER (WHERE a.status = 'NO_SHOW')::integer
  FROM   hbh.appointments a
  JOIN   hbh.centers c ON c.center_id = a.center_id
  WHERE  a.child_id = p_child_id
    AND  a.active_flg
    AND  a.starts_at >= (date_trunc('month', now() AT TIME ZONE c.time_zone)
                         AT TIME ZONE c.time_zone)
    AND  a.starts_at <  now()
$fn$;

COMMENT ON FUNCTION hbh.child_attendance_month(integer) IS
  'Sessions this child attended (CHECKED_IN, COMPLETED) and missed (NO_SHOW) since the 1st of the month in the centre''s time zone. Cancelled and unrecorded appointments are not counted. Runs as the caller, so RLS decides which child may be asked about. Backlog #11.';

REVOKE ALL ON FUNCTION hbh.child_attendance_month(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.child_attendance_month(integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0139');
