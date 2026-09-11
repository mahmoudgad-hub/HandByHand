-- =====================================================================
-- Hand By Hand (new) - migration 0099: a permission is not an address.
--
-- THE API GOES FIRST. This migration raises SQLSTATE HB232, which the
-- transport layer has never seen, and an unrecognised code there becomes
-- a 500 - the trap 0053, 0058, 0059, 0083 and 0094 each carry the same
-- warning about. ops_handlers.go maps HB232 to 403 and was deployed
-- before this file was applied.
--
-- WHAT WAS WRONG, AND IT WAS WRONG IN THE SAME WAY TWICE
--
-- hbh.issue_invoice asked one question:
--
--     IF NOT hbh.has_permission('BILLING.MANAGE') THEN ... refuse
--     UPDATE hbh.invoices SET status='ISSUED' WHERE invoice_id = $1;
--
-- A permission says WHAT a person may do. It says nothing about WHICH
-- ROW. Row level security is what normally supplies the second half -
-- and a SECURITY DEFINER function is precisely the place where it does
-- not apply. So the function held the permission, skipped the policy,
-- and took the identifier on trust.
--
-- Demonstrated on this database, in a rolled-back transaction:
--
--   dev_admin       my_center = 1, BILLING.MANAGE = t
--   invoice         center_id = 86
--   invoice_visible_to_me = 0      <- RLS hid it correctly
--   SELECT hbh.issue_invoice(...)  <- succeeded
--   status_after = ISSUED          <- a write into another centre
--
-- hbh.decide_request was worse, because it does not stop at the row:
--
--   dev_reception   my_center = 1, REQUEST.MANAGE = t
--   request         center_id = 90
--   request_visible_to_me = 0
--   SELECT hbh.decide_request(...,'REJECTED','قرار كتبه موظّف مركز آخر')
--   -> status REJECTED, decided_by = 6, and the note stored verbatim
--   -> notifications_sent_to_other_centre = 1
--
-- A member of one centre's staff rejected another centre's family's
-- request, signed it with their own user id, and the notification
-- trigger DELIVERED THEIR TEXT to that family. Not a read leak - a
-- write, an attribution, and a message.
--
-- WHY IT SURVIVED. Both functions are correct on a single-centre
-- database, which is every database this project has ever run on. The
-- defect is invisible from the only direction anybody looks, exactly
-- like 0097's NULL comparison.
--
-- THE RULE THIS ESTABLISHES, and tests/db/p00_verify.sql now enforces it
-- mechanically:
--
--     A SECURITY DEFINER function that takes a raw entity id and
--     mutates that entity must ask BOTH questions:
--         may this caller do this KIND of thing   (has_permission)
--         AND does this ROW belong to them        (centre / ownership)
--
-- WHAT IS FIXED HERE. The two proven ones, and the five the audit found
-- with the same shape but no HTTP route - because "not reachable today"
-- is a property of the router, not of the function, and the router
-- changes more often than the schema.
--
--   issue_invoice          proven, reachable
--   decide_request         proven, reachable
--   cancel_recurrence      same shape, no route
--   accept_offer           NO permission check at all, no route
--   offer_slot             same shape, no route
--   add_to_waiting_list    could add any centre's child; fixed
--   book_recurring         NOT fixed here - see the note at the end
--
-- WHAT IS DELIBERATELY NOT CHANGED. Every function gated on
-- hbh.can_access_child is already safe: that helper joins the child to
-- the caller's own centre (c.center_id = u.center_id) for staff and to
-- the guardian link for families. The audit checked all eighty
-- mutation-capable definers; the safe ones are safe BECAUSE of it.
--
-- Error class added here:
--   HB232  the row belongs to another centre
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0099') THEN
    RAISE EXCEPTION 'migration 0099 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0098') THEN
    RAISE EXCEPTION 'migration 0098 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE HELPER
--
-- One function, so the rule has one definition and the next reviewer has
-- one thing to look for rather than seven copies to compare.
--
-- IT FAILS CLOSED THREE WAYS. A NULL centre on the row, a NULL centre on
-- the caller (no identity), or a mismatch - all refuse. The middle one
-- matters most: an unauthenticated connection has no centre, and the
-- whole of this schema is built so that means zero rows rather than all
-- of them.
--
-- IT DOES NOT SAY WHICH CENTRE. The message names the entity kind and
-- the id the caller already supplied, and nothing else. Telling somebody
-- "that belongs to centre 86" would hand them the map.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.assert_same_center(
  p_entity     text,
  p_entity_id  bigint,
  p_center_id  integer)
RETURNS void
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_mine integer;
BEGIN
  l_mine := hbh.current_center_id();

  IF l_mine IS NULL OR p_center_id IS NULL OR p_center_id <> l_mine THEN
    RAISE EXCEPTION '% % does not belong to this centre', p_entity, p_entity_id
      USING ERRCODE = 'HB232';
  END IF;
END
$$;

-- =====================================================================
-- 1. issue_invoice  - PROVEN, REACHABLE
--
-- The centre check goes BEFORE the permission check, and the order is
-- deliberate: a caller who supplies an identifier from another centre
-- should be refused for that reason in the audit log, not for a
-- permission they may well hold. Reverse the order and every cross-
-- tenant attempt by a legitimate administrator is logged as "needs
-- BILLING.MANAGE", which is both false and unsearchable.
--
-- The row is read FOR UPDATE so the centre cannot change underneath the
-- check - and the NOT FOUND branch answers HB051, which is what a
-- genuinely absent invoice has always answered.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.issue_invoice(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_inv hbh.invoices%ROWTYPE;
BEGIN
  SELECT * INTO l_inv FROM hbh.invoices WHERE invoice_id = p_invoice_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such invoice %', p_invoice_id USING ERRCODE = 'HB051';
  END IF;

  PERFORM hbh.assert_same_center('invoice', p_invoice_id, l_inv.center_id);

  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'issuing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;

  UPDATE hbh.invoices SET status = 'ISSUED' WHERE invoice_id = p_invoice_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);
END
$$;

-- =====================================================================
-- 2. decide_request  - PROVEN, REACHABLE, AND IT SENDS A MESSAGE
--
-- The notification is written by trg_notify_request on the UPDATE, so
-- there is nothing to suppress separately: refusing before the UPDATE is
-- what stops the message. That is the whole reason the guard is placed
-- where it is rather than after - an exception after the UPDATE would
-- roll the row back, but this project has already learned twice
-- (verify_otp, consume_package_session) that "update then raise" is a
-- shape to avoid rather than to reason about.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.decide_request(
  p_request_id integer,
  p_status     text,
  p_note_ar    text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_req hbh.parent_requests%ROWTYPE;
BEGIN
  SELECT * INTO l_req FROM hbh.parent_requests WHERE request_id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such request %', p_request_id USING ERRCODE = 'HB043';
  END IF;

  PERFORM hbh.assert_same_center('request', p_request_id, l_req.center_id);

  IF NOT hbh.has_permission('REQUEST.MANAGE') THEN
    RAISE EXCEPTION 'deciding a request needs REQUEST.MANAGE' USING ERRCODE = 'HB043';
  END IF;

  UPDATE hbh.parent_requests
     SET status           = p_status,
         decided_by       = hbh.current_user_id(),
         decided_at       = now(),
         decision_note_ar = p_note_ar
   WHERE request_id = p_request_id;

  -- Deliberately nothing else. Accepting a reschedule does NOT move the
  -- appointment: reception does that, deliberately, through
  -- book_appointment, where every slot rule still applies.
END
$$;

-- =====================================================================
-- 3. cancel_recurrence  - SAME SHAPE, NO ROUTE TODAY
--
-- A recurrence group is not a row, it is a SET of rows, and they could
-- in principle span centres. So the check is expressed as a set
-- property: every appointment this call would touch must belong to the
-- caller's centre, or nothing is cancelled. A partial cancellation
-- across a tenant boundary is the worst of both answers.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.cancel_recurrence(
  p_group_id bigint,
  p_from     timestamptz,
  p_reason   text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_n       integer;
  l_foreign integer;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.CANCEL') THEN
    RAISE EXCEPTION 'cancelling a course needs APPOINTMENT.CANCEL' USING ERRCODE = 'HB101';
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'a cancellation needs a stated reason' USING ERRCODE = 'HB101';
  END IF;

  SELECT count(*) INTO l_foreign
  FROM   hbh.appointments a
  WHERE  a.recurrence_group_id = p_group_id
  AND    a.center_id IS DISTINCT FROM hbh.current_center_id();

  IF l_foreign > 0 OR hbh.current_center_id() IS NULL THEN
    RAISE EXCEPTION 'recurrence group % does not belong to this centre', p_group_id
      USING ERRCODE = 'HB232';
  END IF;

  UPDATE hbh.appointments
     SET status = 'CANCELLED', cancel_reason = p_reason
   WHERE recurrence_group_id = p_group_id
     AND starts_at >= p_from
     AND status IN ('BOOKED','CONFIRMED')
     AND center_id = hbh.current_center_id();

  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

-- =====================================================================
-- 4. accept_offer  - NO PERMISSION CHECK AT ALL
--
-- This one had neither half of the rule. It took a wait_id, checked
-- that the offer was live and unexpired, and booked it. Anything that
-- could call it could accept any centre's offer for any family.
--
-- WHO SHOULD BE ABLE TO. An offer is accepted on a family's behalf by
-- the desk, so APPOINTMENT.BOOK is the right permission - the same one
-- that would be needed to make the booking the offer becomes.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.accept_offer(p_wait_id integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_w hbh.waiting_list%ROWTYPE;
BEGIN
  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'waiting entry % has no live offer', p_wait_id USING ERRCODE = 'HB102';
  END IF;

  PERFORM hbh.assert_same_center('waiting entry', p_wait_id, l_w.center_id);

  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'accepting an offer needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  IF l_w.status <> 'OFFERED' THEN
    RAISE EXCEPTION 'waiting entry % has no live offer', p_wait_id USING ERRCODE = 'HB102';
  END IF;
  IF l_w.offer_expires_at <= now() THEN
    RAISE EXCEPTION 'the offer on waiting entry % expired at %', p_wait_id, l_w.offer_expires_at
      USING ERRCODE = 'HB102';
  END IF;

  UPDATE hbh.waiting_list SET status = 'BOOKED' WHERE wait_id = p_wait_id;
  RETURN true;
END
$$;


-- =====================================================================
-- 5. offer_slot  - SAME SHAPE, NO ROUTE TODAY
--
-- THE SIGNATURE IS THE REAL ONE. A first draft of this migration
-- redefined it as (p_wait_id, p_hours) - which does not replace the
-- existing (p_wait_id, p_appointment_id, p_hold_hours), it ADDS A
-- SECOND OVERLOAD beside it and silently drops offered_appointment_id
-- from every offer made through the new one. CREATE OR REPLACE matches
-- on the argument list, so a wrong signature is not an error; it is a
-- fork. Caught by reading the deployed definition before writing.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.offer_slot(
  p_wait_id        integer,
  p_appointment_id integer,
  p_hold_hours     integer DEFAULT NULL)
RETURNS timestamptz
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_w     hbh.waiting_list%ROWTYPE;
  l_hours integer;
  l_exp   timestamptz;
BEGIN
  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'waiting entry % is not waiting', p_wait_id USING ERRCODE = 'HB102';
  END IF;

  PERFORM hbh.assert_same_center('waiting entry', p_wait_id, l_w.center_id);

  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'offering a slot needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  IF l_w.status <> 'WAITING' THEN
    RAISE EXCEPTION 'waiting entry % is not waiting', p_wait_id USING ERRCODE = 'HB102';
  END IF;

  l_hours := coalesce(p_hold_hours,
                      hbh.param(l_w.center_id, 'WAITLIST_OFFER_HOURS', '48')::integer);
  l_exp   := now() + make_interval(hours => l_hours);

  UPDATE hbh.waiting_list
     SET status = 'OFFERED', offered_appointment_id = p_appointment_id,
         offered_at = now(), offer_expires_at = l_exp
   WHERE wait_id = p_wait_id;

  RETURN l_exp;
END
$$;

-- =====================================================================
-- 6. add_to_waiting_list  - THE CHILD, NOT THE ENTRY
--
-- This one reads the child and copies its centre onto the new row, so it
-- could not write into another centre by accident. What it could not do
-- was refuse: a caller holding APPOINTMENT.BOOK could add ANY child in
-- the database to a waiting list, and the entry would be filed correctly
-- under that child's centre - where the caller cannot see it and cannot
-- remove it.
--
-- can_access_child rather than assert_same_center, because the question
-- here is about a CHILD and that helper is the one this schema already
-- uses for it. It is centre-bound for staff and link-bound for families,
-- which is exactly the pair of answers needed.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.add_to_waiting_list(
  p_child_id      integer,
  p_service_id    integer,
  p_therapist_id  integer  DEFAULT NULL,
  p_priority      smallint DEFAULT 5,
  p_earliest_date date     DEFAULT CURRENT_DATE,
  p_latest_date   date     DEFAULT NULL,
  p_weekdays      smallint[] DEFAULT '{1,2,3,4,7}'::smallint[],
  p_time_from     time     DEFAULT '09:00:00',
  p_time_to       time     DEFAULT '17:00:00',
  p_note_ar       text     DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'adding to the waiting list needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB101';
  END IF;

  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'child % does not belong to this centre', p_child_id
      USING ERRCODE = 'HB232';
  END IF;

  INSERT INTO hbh.waiting_list (center_id, branch_id, child_id, service_id, therapist_id,
                                priority, earliest_date, latest_date, weekdays,
                                time_from, time_to, requested_by, note_ar)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_service_id, p_therapist_id,
          p_priority, p_earliest_date, p_latest_date, p_weekdays,
          p_time_from, p_time_to, hbh.current_user_id(), p_note_ar)
  RETURNING wait_id INTO l_id;

  RETURN l_id;
END
$$;

-- =====================================================================
-- WHAT IS *NOT* FIXED HERE, AND WHY IT IS WRITTEN DOWN INSTEAD
--
-- hbh.book_appointment and hbh.book_recurring take p_center_id from the
-- CALLER and insert with it. Nothing in either function checks that the
-- centre they are handed is the caller's own.
--
-- It is not reachable today: store.BookAppointment passes
-- hbh.current_center_id(), never anything from a request body. The Go
-- layer got this right.
--
-- It is left alone because closing it means redefining the two busiest
-- functions in the scheduling module during a security fix, and because
-- it is a DIFFERENT defect from the one this migration is about - this
-- one is "the function trusts an id", that one is "the function trusts a
-- tenant". Folding an unproven, unreachable change into a migration that
-- fixes two proven, reachable ones is how a rollback stops being
-- possible.
--
-- The new check in tests/db/p00_verify.sql does NOT catch it either, and
-- deliberately: a centre arriving as a parameter is a different shape
-- from an entity id arriving as a parameter. Reported separately.
-- =====================================================================

REVOKE ALL ON FUNCTION hbh.assert_same_center(text, bigint, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.assert_same_center(text, bigint, integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0099');
