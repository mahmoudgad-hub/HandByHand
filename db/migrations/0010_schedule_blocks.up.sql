-- =====================================================================
-- Hand By Hand (new) - migration 0010: closures, leave and blocked rooms
--
-- The gap this closes, stated plainly: until now validate_slot knew a
-- therapist's WEEKLY hours and nothing else. A therapist travelling
-- next week, a public holiday, a room being painted - none of them
-- existed, so reception could book into all three and the system would
-- agree. It is the first thing that would have gone wrong on day one.
--
-- therapists.status = 'ON_LEAVE' does exist, but it means "not working
-- at the moment, at all" - a property of the person's file, not of a
-- date range. Marking somebody ON_LEAVE for a fortnight and back to
-- ACTIVE afterwards loses the fact that they were away, and blocks
-- every future booking rather than the ones in that fortnight.
--
-- One table, four scopes. A block is a range of time in which something
-- cannot be booked:
--
--   CENTER     the centre is closed        - a public holiday
--   BRANCH     one branch is closed
--   THERAPIST  one person is away          - leave, training, illness
--   ROOM       one room is unusable        - maintenance
--
-- Error classes added here:
--   HB070  a schedule block is malformed for its scope
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0010') THEN
    RAISE EXCEPTION 'migration 0010 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0009') THEN
    RAISE EXCEPTION 'migration 0009 must be applied first';
  END IF;
END
$guard$;

CREATE TABLE hbh.schedule_blocks (
  block_id     integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  scope        text        NOT NULL,
  therapist_id integer,
  room_id      integer,
  starts_at    timestamptz NOT NULL,
  ends_at      timestamptz NOT NULL,
  reason_code  text        NOT NULL,
  note_ar      text,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_schedule_blocks PRIMARY KEY (block_id),
  CONSTRAINT fk_blk_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_blk_branch    FOREIGN KEY (branch_id)    REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_blk_therapist FOREIGN KEY (therapist_id) REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_blk_room      FOREIGN KEY (room_id)      REFERENCES hbh.rooms (room_id),
  CONSTRAINT ck_blk_scope  CHECK (scope IN ('CENTER','BRANCH','THERAPIST','ROOM')),
  CONSTRAINT ck_blk_reason CHECK (reason_code IN ('HOLIDAY','LEAVE','SICK','TRAINING','MAINTENANCE','OTHER')),
  CONSTRAINT ck_blk_window CHECK (ends_at > starts_at),
  -- The scope decides which key must be present, and which must not be.
  -- A block scoped to a therapist that names no therapist would silently
  -- match nothing; one that names a therapist AND a room is two rules
  -- pretending to be one.
  CONSTRAINT ck_blk_shape CHECK (
    (scope = 'CENTER'    AND therapist_id IS NULL AND room_id IS NULL AND branch_id IS NULL)
    OR (scope = 'BRANCH'    AND therapist_id IS NULL AND room_id IS NULL AND branch_id IS NOT NULL)
    OR (scope = 'THERAPIST' AND therapist_id IS NOT NULL AND room_id IS NULL)
    OR (scope = 'ROOM'      AND room_id IS NOT NULL AND therapist_id IS NULL)
  )
);

CREATE INDEX ix_blk_center    ON hbh.schedule_blocks (center_id, starts_at);
CREATE INDEX ix_blk_branch    ON hbh.schedule_blocks (branch_id);
CREATE INDEX ix_blk_therapist ON hbh.schedule_blocks (therapist_id, starts_at);
CREATE INDEX ix_blk_room      ON hbh.schedule_blocks (room_id, starts_at);
-- The lookup validate_slot does on every booking attempt.
CREATE INDEX ix_blk_live      ON hbh.schedule_blocks (center_id, starts_at, ends_at)
  WHERE active_flg;

CREATE TRIGGER trg_blk_touch BEFORE UPDATE ON hbh.schedule_blocks
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_blk_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.schedule_blocks
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('block_id');

ALTER TABLE hbh.schedule_blocks ENABLE ROW LEVEL SECURITY;

-- Rota information. A family has no business with who is on leave.
CREATE POLICY p_blk_select ON hbh.schedule_blocks
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('CHILD.VIEW_ALL'));

GRANT SELECT ON hbh.schedule_blocks TO hbh_app;

-- =====================================================================
-- validate_slot, now aware of closures
--
-- Three new reasons rather than one, because a booking screen that can
-- only say "unavailable" sends the receptionist to ring somebody. The
-- distinction between "the centre is shut", "she is away" and "the room
-- is being painted" is the difference between rebooking the day, the
-- therapist, or the room.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.validate_slot(
  p_center_id    integer,
  p_child_id     integer,
  p_therapist_id integer,
  p_room_id      integer,
  p_service_id   integer,
  p_starts_at    timestamptz,
  p_ends_at      timestamptz,
  p_exclude_id   integer DEFAULT NULL)
RETURNS TABLE (ok boolean, reason text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_tz        text;
  l_weekend   smallint[];
  l_local     timestamp;
  l_weekday   smallint;
  l_backdays  integer;
  l_branch    integer;
  -- Declared, NOT initialised here.
  --
  -- A DECLARE initialiser runs before the first line of the body, so
  -- building the range up there happened BEFORE the check below - and a
  -- reversed window raised 22000 "range lower bound must be less than
  -- or equal to range upper bound" instead of returning BAD_WINDOW.
  -- The guard has to come first, which means the range comes after it.
  l_span      tstzrange;
BEGIN
  IF p_ends_at <= p_starts_at THEN
    RETURN QUERY SELECT false, 'BAD_WINDOW'; RETURN;
  END IF;

  l_span := tstzrange(p_starts_at, p_ends_at, '[)');

  SELECT c.time_zone, c.weekend_days INTO l_tz, l_weekend
  FROM hbh.centers c WHERE c.center_id = p_center_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_SUCH_CENTRE'; RETURN;
  END IF;

  -- The weekend and the working day are questions about the centre's
  -- LOCAL calendar, so the instant is rendered in the centre's zone
  -- before either is asked.
  l_local   := p_starts_at AT TIME ZONE l_tz;
  l_weekday := extract(isodow FROM l_local)::smallint;

  l_backdays := hbh.param(p_center_id, 'ALLOW_BACKDATED_BOOKING_DAYS', '0')::integer;
  IF l_local::date < (now() AT TIME ZONE l_tz)::date - l_backdays THEN
    RETURN QUERY SELECT false, 'IN_THE_PAST'; RETURN;
  END IF;

  IF l_weekday = ANY (l_weekend) THEN
    RETURN QUERY SELECT false, 'WEEKEND'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                 WHERE t.therapist_id = p_therapist_id AND t.center_id = p_center_id
                   AND t.active_flg AND t.status = 'ACTIVE') THEN
    RETURN QUERY SELECT false, 'THERAPIST_UNAVAILABLE'; RETURN;
  END IF;

  SELECT r.branch_id INTO l_branch FROM hbh.rooms r
  WHERE r.room_id = p_room_id AND r.center_id = p_center_id AND r.active_flg;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'ROOM_UNAVAILABLE'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_services ts
                 WHERE ts.therapist_id = p_therapist_id AND ts.service_id = p_service_id
                   AND ts.active_flg) THEN
    RETURN QUERY SELECT false, 'THERAPIST_SERVICE_MISMATCH'; RETURN;
  END IF;

  -- ---------------------------------------------------------------
  -- Closures. Checked BEFORE working hours, because "the centre is
  -- shut on Eid" is a better answer than "outside working hours".
  -- ---------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.center_id = p_center_id
               AND b.scope = 'CENTER'
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'CENTER_CLOSED'; RETURN;
  END IF;

  IF l_branch IS NOT NULL AND EXISTS (
       SELECT 1 FROM hbh.schedule_blocks b
       WHERE b.active_flg AND b.center_id = p_center_id
         AND b.scope = 'BRANCH' AND b.branch_id = l_branch
         AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'BRANCH_CLOSED'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.scope = 'THERAPIST'
               AND b.therapist_id = p_therapist_id
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'THERAPIST_ON_LEAVE'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.schedule_blocks b
             WHERE b.active_flg AND b.scope = 'ROOM'
               AND b.room_id = p_room_id
               AND tstzrange(b.starts_at, b.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'ROOM_BLOCKED'; RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapist_working_hours w
                 WHERE w.therapist_id = p_therapist_id AND w.active_flg
                   AND w.weekday = l_weekday
                   AND w.start_time <= l_local::time
                   AND w.end_time   >= (p_ends_at AT TIME ZONE l_tz)::time) THEN
    RETURN QUERY SELECT false, 'OUTSIDE_WORKING_HOURS'; RETURN;
  END IF;

  -- These three duplicate the exclusion constraints on purpose: the
  -- constraint is the guarantee, this is the explanation.
  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.therapist_id = p_therapist_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'THERAPIST_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.room_id = p_room_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'ROOM_BUSY'; RETURN;
  END IF;

  IF EXISTS (SELECT 1 FROM hbh.appointments a
             WHERE a.child_id = p_child_id
               AND a.status IN ('BOOKED','CONFIRMED','CHECKED_IN','COMPLETED')
               AND a.appointment_id IS DISTINCT FROM p_exclude_id
               AND tstzrange(a.starts_at, a.ends_at, '[)') && l_span) THEN
    RETURN QUERY SELECT false, 'CHILD_BUSY'; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK';
END
$$;

-- =====================================================================
-- WHAT A NEW BLOCK WOULD STRAND
--
-- Declaring leave must not silently orphan bookings, and it must not be
-- refused either - the leave is a fact, and the bookings have to move.
-- So creating a block is allowed, and this says what reception now has
-- to deal with.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.block_conflicts(p_block_id integer)
RETURNS TABLE (appointment_id integer, appointment_no text, child_id integer,
               therapist_id integer, room_id integer, starts_at timestamptz, status text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT a.appointment_id, a.appointment_no, a.child_id, a.therapist_id, a.room_id,
         a.starts_at, a.status
  FROM   hbh.schedule_blocks b
  JOIN   hbh.appointments a
    ON   a.center_id = b.center_id
   AND   a.status IN ('BOOKED','CONFIRMED','CHECKED_IN')
   AND   tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(b.starts_at, b.ends_at, '[)')
   AND   ( b.scope = 'CENTER'
        OR (b.scope = 'BRANCH'    AND a.branch_id    = b.branch_id)
        OR (b.scope = 'THERAPIST' AND a.therapist_id = b.therapist_id)
        OR (b.scope = 'ROOM'      AND a.room_id      = b.room_id))
  WHERE  b.block_id = p_block_id AND b.active_flg
  ORDER  BY a.starts_at
$$;

COMMENT ON FUNCTION hbh.block_conflicts(integer) IS
  'Appointments a block would strand. Declaring leave is allowed; this is what reception must then move.';

REVOKE ALL ON FUNCTION hbh.block_conflicts(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.block_conflicts(integer) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0010');
