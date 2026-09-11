-- =====================================================================
-- Hand By Hand (new) - migration 0031: is the caller staff?
--
-- WHY THIS EXISTS. Row level security filters ROWS. It cannot filter
-- COLUMNS, and there are columns on rows a family is entitled to see
-- that a family is not entitled to read:
--
--   hbh.therapists.mobile   a therapist's personal number
--   hbh.rooms.notes_ar      the centre's internal note about a room
--
-- p_therapists_select admits ANY authenticated user of the centre - and
-- correctly so, because a parent choosing an appointment needs to see
-- who the therapists are. It was the API that then returned the whole
-- row. Verified against a running build before this was written: a
-- guardian's GET /api/v1/therapists came back carrying mobile numbers.
--
-- WHY A FUNCTION AND NOT A PERMISSION. The obvious mask is
-- has_permission('STAFF.MANAGE'), and it is wrong twice over: only
-- CENTER_ADMIN holds it, so reception could no longer telephone a
-- therapist - and a permission granted for one purpose would silently
-- become the gate for another. That is precisely the can_close_session
-- defect: CHILD.VIEW_ALL and SESSION.COMPLETE both live in THERAPIST
-- for good reasons, and together they let any therapist close any
-- colleague's session.
--
-- The question here is not "what may you do", it is "which side of the
-- desk are you on" - and that is user_type, exactly as the admin
-- override in hbh.can_close_session is pinned to it.
--
-- FAILS CLOSED. No identity is not staff. An unauthenticated connection
-- gets false, never NULL and never true.
--
-- SECURITY DEFINER because it reads hbh.users, which has a policy that
-- calls hbh.current_center_id(), which reads hbh.users. That is the same
-- recursion current_center_id itself breaks the same way.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0031') THEN
    RAISE EXCEPTION 'migration 0031 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0002') THEN
    RAISE EXCEPTION 'migration 0002 must be applied first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.current_user_is_staff()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT coalesce(
           (SELECT u.user_type IN ('STAFF', 'THERAPIST')
              FROM hbh.users u
             WHERE u.user_id = hbh.current_user_id()
               AND u.active_flg),
           false);
$$;

COMMENT ON FUNCTION hbh.current_user_is_staff() IS
  'True when the caller works at the centre rather than being a family. For column masking, and for admin overrides that must not rest on a permission alone (0031).';

GRANT EXECUTE ON FUNCTION hbh.current_user_is_staff() TO hbh_app;

DO $verify$
DECLARE l_answer boolean;
BEGIN
  -- No identity is set here, so the only correct answer is false. A
  -- function that returned NULL would make "NOT is_staff" unknown, and a
  -- mask written on it would leak on the one connection that matters.
  SELECT hbh.current_user_is_staff() INTO l_answer;
  IF l_answer IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'current_user_is_staff must be false with no identity, got %', coalesce(l_answer::text, 'NULL');
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0031');
