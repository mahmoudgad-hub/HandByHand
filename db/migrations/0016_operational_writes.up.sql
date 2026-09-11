-- =====================================================================
-- Hand By Hand (new) - migration 0016: the operational writes
--
-- Three gaps, all found by running the phase-5 API suite against a real
-- build. Two are missing grants and one is an authorisation hole.
--
-- 1. APPOINTMENTS COULD NOT CHANGE STATE.
--    Migration 0012 opened the catalogue, the people and the clinical
--    authorship tables, and left hbh.appointments read-only. Booking
--    worked because hbh.book_appointment is SECURITY DEFINER, but
--    moving an appointment to CONFIRMED or CHECKED_IN is a plain UPDATE
--    and was refused. Reception could create a day and then not run it.
--
-- 2. PAYMENTS COULD NOT BE RECORDED, for the same reason.
--
-- 3. A GUARDIAN COULD BOOK AN APPOINTMENT.
--    hbh.book_appointment checked the SLOT and never the CALLER, so any
--    authenticated guardian could book into the diary for their own
--    child. Verified against a running build: 201 Created.
--
--    That is not what this domain says. A family asks and the centre
--    decides - which is why hbh.parent_requests exists at all, with
--    RESCHEDULE and CANCEL among its kinds. A parent who can book
--    directly makes that whole table decorative.
--
-- WHY INSERT ON appointments STAYS CLOSED. Booking keeps going through
-- hbh.book_appointment, which validates the slot first. An INSERT grant
-- would be a second way in that skips validate_slot, and the exclusion
-- constraints would catch the overlap but nothing would catch a booking
-- on a Friday, outside working hours, or for a service the therapist
-- does not offer.
--
-- Same reasoning for therapy_sessions: start_session and close_session
-- own that lifecycle, so the table needs no grant.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0016') THEN
    RAISE EXCEPTION 'migration 0016 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0015') THEN
    RAISE EXCEPTION 'migration 0015 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- 1. MOVING AN APPOINTMENT ALONG ITS STATE MACHINE
--
-- Cancelling and confirming are different rights, and the schema
-- already had different codes for them - so they get different gates.
-- The distinction is on the NEW row, which is what WITH CHECK sees.
--
-- The transition itself is still policed by hbh.trg_appointment_status,
-- which refuses an illegal one with HB020. This policy answers "may you
-- touch this row at all"; the trigger answers "is that a legal move".
-- =====================================================================
CREATE POLICY p_appointments_edit ON hbh.appointments
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id()
         AND hbh.can_access_child(child_id)
         AND (hbh.has_permission('APPOINTMENT.BOOK')
              OR hbh.has_permission('APPOINTMENT.CANCEL')))
  WITH CHECK (center_id = hbh.current_center_id()
              AND hbh.can_access_child(child_id)
              AND CASE
                    WHEN status = 'CANCELLED' THEN hbh.has_permission('APPOINTMENT.CANCEL')
                    ELSE hbh.has_permission('APPOINTMENT.BOOK')
                  END);

GRANT UPDATE ON hbh.appointments TO hbh_app;

-- =====================================================================
-- 2. RECORDING A PAYMENT
--
-- The triggers on hbh.payments already refuse a payment against a draft
-- or cancelled invoice, and refuse one larger than what is outstanding.
-- This policy only decides who may add a row at all.
-- =====================================================================
CREATE POLICY p_payments_write ON hbh.payments
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('BILLING.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.invoices i
                          WHERE i.invoice_id = payments.invoice_id
                          AND   i.center_id = hbh.current_center_id()));

GRANT INSERT ON hbh.payments TO hbh_app;

-- Reversing a payment is not an UPDATE and not a DELETE: it is a
-- refund, and this schema has no refund yet. No grant, deliberately -
-- an editable payment row is a cash drawer with an eraser.

-- =====================================================================
-- 3. BOOKING NEEDS THE RIGHT TO BOOK
--
-- The body is unchanged apart from the block marked below. The slot
-- check, the numbering and the exclusion-violation handling are exactly
-- as migration 0005 wrote them.
--
-- The guard is conditional on there BEING a caller. hbh.current_user_id()
-- is NULL only when no request identity is set - which never happens on
-- an authenticated API route, and always happens when the owner runs a
-- fixture or a maintenance script. So an acting user must hold the
-- right; a migration is not an acting user.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.book_appointment(
  p_center_id    integer,
  p_branch_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_note_ar      text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_check  record;
  l_no     text;
  l_id     integer;
BEGIN
  -- ADDED IN 0016. A family asks; the centre decides. Without this a
  -- guardian could book straight into the diary, which makes
  -- hbh.parent_requests - and its RESCHEDULE and CANCEL kinds -
  -- decorative.
  IF hbh.current_user_id() IS NOT NULL
     AND NOT hbh.has_permission('APPOINTMENT.BOOK') THEN
    RAISE EXCEPTION 'not permitted to book an appointment'
      USING ERRCODE = 'HB027';
  END IF;

  SELECT * INTO l_check
  FROM hbh.validate_slot(p_center_id, p_child_id, p_therapist_id, p_room_id,
                         p_service_id, p_starts_at, p_ends_at);
  IF NOT l_check.ok THEN
    RAISE EXCEPTION 'slot rejected: %', l_check.reason USING ERRCODE = 'HB021';
  END IF;

  l_no := hbh.next_number(p_center_id, 'APPT');

  BEGIN
    INSERT INTO hbh.appointments (center_id, branch_id, appointment_no, child_id,
                                  therapist_id, room_id, service_id, starts_at, ends_at, note_ar)
    VALUES (p_center_id, p_branch_id, l_no, p_child_id, p_therapist_id, p_room_id,
            p_service_id, p_starts_at, p_ends_at, p_note_ar)
    RETURNING appointment_id INTO l_id;
  EXCEPTION WHEN exclusion_violation THEN
    -- Another transaction committed the same slot between the check and
    -- this insert. The index caught it - which is the whole point - and
    -- the caller gets the same reason it would have got a moment
    -- earlier, instead of a raw 23P01.
    RAISE EXCEPTION 'slot rejected: SLOT_TAKEN' USING ERRCODE = 'HB021';
  END;

  RETURN l_id;
END
$$;

COMMENT ON FUNCTION hbh.book_appointment(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, text) IS
  'Books a validated slot. Requires APPOINTMENT.BOOK of an acting user (0016). A guardian asks through parent_requests instead.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0016');
