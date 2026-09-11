-- =====================================================================
-- 0099 down - the centre checks come back off.
--
-- READ THIS BEFORE RUNNING IT. This restores two PROVEN cross-tenant
-- write defects:
--
--   issue_invoice   an administrator of one centre can issue another
--                   centre's invoice
--   decide_request  a receptionist of one centre can decide another
--                   centre's family's request, sign it with their own
--                   user id, and have the notification trigger deliver
--                   their text to that family
--
-- It exists because every migration in this project has a down, and
-- because a down that quietly differs from its up is worse than one that
-- is dangerous and says so. It should not be run.
--
-- THE API MAY GO SECOND HERE. ops_handlers.go still maps HB232, and an
-- error class nothing raises costs nothing. Leave it in place.
-- =====================================================================

CREATE OR REPLACE FUNCTION hbh.issue_invoice(p_invoice_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.has_permission('BILLING.MANAGE') THEN
    RAISE EXCEPTION 'issuing an invoice needs BILLING.MANAGE' USING ERRCODE = 'HB052';
  END IF;
  UPDATE hbh.invoices SET status = 'ISSUED' WHERE invoice_id = p_invoice_id;
  PERFORM hbh.recalc_invoice(p_invoice_id);
END
$$;

CREATE OR REPLACE FUNCTION hbh.decide_request(
  p_request_id integer, p_status text, p_note_ar text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.has_permission('REQUEST.MANAGE') THEN
    RAISE EXCEPTION 'deciding a request needs REQUEST.MANAGE' USING ERRCODE = 'HB043';
  END IF;

  UPDATE hbh.parent_requests
     SET status           = p_status,
         decided_by       = hbh.current_user_id(),
         decided_at       = now(),
         decision_note_ar = p_note_ar
   WHERE request_id = p_request_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.cancel_recurrence(
  p_group_id bigint, p_from timestamptz, p_reason text)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  IF NOT hbh.has_permission('APPOINTMENT.CANCEL') THEN
    RAISE EXCEPTION 'cancelling a course needs APPOINTMENT.CANCEL' USING ERRCODE = 'HB101';
  END IF;
  IF coalesce(btrim(p_reason), '') = '' THEN
    RAISE EXCEPTION 'a cancellation needs a stated reason' USING ERRCODE = 'HB101';
  END IF;

  UPDATE hbh.appointments
     SET status = 'CANCELLED', cancel_reason = p_reason
   WHERE recurrence_group_id = p_group_id
     AND starts_at >= p_from
     AND status IN ('BOOKED','CONFIRMED');

  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n;
END
$$;

CREATE OR REPLACE FUNCTION hbh.accept_offer(p_wait_id integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_w hbh.waiting_list%ROWTYPE;
BEGIN
  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND OR l_w.status <> 'OFFERED' THEN
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

CREATE OR REPLACE FUNCTION hbh.offer_slot(
  p_wait_id integer, p_appointment_id integer, p_hold_hours integer DEFAULT NULL)
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
  IF NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'offering a slot needs APPOINTMENT.BOOK' USING ERRCODE = 'HB101';
  END IF;

  SELECT * INTO l_w FROM hbh.waiting_list WHERE wait_id = p_wait_id FOR UPDATE;
  IF NOT FOUND OR l_w.status <> 'WAITING' THEN
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

CREATE OR REPLACE FUNCTION hbh.add_to_waiting_list(
  p_child_id integer, p_service_id integer, p_therapist_id integer DEFAULT NULL,
  p_priority smallint DEFAULT 5, p_earliest_date date DEFAULT CURRENT_DATE,
  p_latest_date date DEFAULT NULL,
  p_weekdays smallint[] DEFAULT '{1,2,3,4,7}'::smallint[],
  p_time_from time DEFAULT '09:00:00', p_time_to time DEFAULT '17:00:00',
  p_note_ar text DEFAULT NULL)
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

DROP FUNCTION IF EXISTS hbh.assert_same_center(text, bigint, integer);

DELETE FROM hbh.schema_migrations WHERE version = '0099';
