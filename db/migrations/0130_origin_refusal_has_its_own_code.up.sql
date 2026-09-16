-- =====================================================================
-- Hand By Hand (new) - migration 0130: HB240 meant two things, and I
-- made it mean the second
--
-- 0129 raised HB240 for "an origin cannot be changed once recorded".
-- HB240 was already taken. 0100 and 0127 raise it from available_slots
-- for "you may not read the booking ledger", and the API translates it
-- accordingly, in ops_handlers.go:
--
--     case "HB240":
--         return http.StatusForbidden, CodeForbidden, true
--
-- So a receptionist trying to change a recorded origin would have been
-- told they lack a permission - a 403 for what is a business rule, and
-- the one message that sends them to ask an administrator for access
-- they already have. The discovery report caught it the same day
-- (C-04). I picked the code without grepping for it.
--
-- THE LESSON IS ALREADY IN CLAUDE.md, from HB052: "a third meaning for
-- one code is not a shortcut, it is a loss". This was a second meaning,
-- written by the person who wrote that sentence down.
--
-- WHY NOW, AND WHY IT COSTS NOTHING TODAY
--
-- No API path writes origin_source or registration_source yet - a grep
-- over api/ and web/ finds nothing. So no screen can reach the refusal,
-- and renumbering it before any code learns HB240 is the cheapest this
-- change will ever be. The day an endpoint writes an origin, the old
-- meaning would already be load-bearing.
--
-- And `bash scripts/api.sh code-drift` compares pg_proc against the
-- API's code table, so HB241 appears as unknown to Go the moment this
-- lands - which is the point: the API adds its case deliberately rather
-- than inheriting a wrong one by accident.
--
-- Error classes:
--   HB240  unchanged - available_slots: may not read the booking ledger
--   HB241  NEW       - an origin cannot be changed once recorded
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0130') THEN
    RAISE EXCEPTION 'migration 0130 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0129') THEN
    RAISE EXCEPTION 'migration 0129 must be applied first';
  END IF;
  -- The new code must be as free as the old one was not.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%HB241%') THEN
    RAISE EXCEPTION 'HB241 is already raised by some function - pick another, and grep first';
  END IF;
END
$guard$;

CREATE OR REPLACE FUNCTION hbh.trg_origin_immutable()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  l_cols text[] := TG_ARGV;
  l_col  text;
  l_old  text;
  l_new  text;
BEGIN
  FOREACH l_col IN ARRAY l_cols LOOP
    l_old := to_jsonb(OLD) ->> l_col;
    l_new := to_jsonb(NEW) ->> l_col;

    -- Recording an origin that was never recorded is allowed, once.
    -- Changing one that was is not.
    IF l_old IS NOT NULL AND l_new IS DISTINCT FROM l_old THEN
      RAISE EXCEPTION '% cannot be changed once recorded (% -> %)', l_col, l_old,
                      coalesce(l_new, 'null')
        USING ERRCODE = 'HB241';
    END IF;
  END LOOP;
  RETURN NEW;
END
$$;

-- =====================================================================
-- THE PROOF: the right code now, and the other meaning left alone
-- =====================================================================
DO $verify$
DECLARE
  l_id    integer;
  l_state text;
BEGIN
  -- The origin refusal raises HB241, measured - not assumed.
  SELECT guardian_id INTO l_id FROM hbh.guardians
  WHERE registration_source IS NOT NULL AND mobile ~ '^\+[1-9][0-9]{7,14}$'
  LIMIT 1;

  IF l_id IS NULL THEN
    RAISE WARNING 'no guardian with a recorded origin and a writable row, so the new code was not exercised';
  ELSE
    BEGIN
      UPDATE hbh.guardians
         SET registration_source = CASE WHEN registration_source = 'CENTER'
                                         THEN 'ONLINE_CONSULTATION' ELSE 'CENTER' END
       WHERE guardian_id = l_id;
      l_state := 'NOTHING RAISED';
    EXCEPTION WHEN OTHERS THEN
      l_state := SQLSTATE;
    END;

    IF l_state IS DISTINCT FROM 'HB241' THEN
      RAISE EXCEPTION 'changing a recorded origin raised % - expected HB241', l_state;
    END IF;
  END IF;

  -- And no function still raises HB240 for the origin meaning.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.proname = 'trg_origin_immutable'
               AND p.prosrc LIKE '%HB240%') THEN
    RAISE EXCEPTION 'trg_origin_immutable still raises HB240';
  END IF;

  -- The other meaning untouched: available_slots keeps its code.
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                 WHERE n.nspname = 'hbh' AND p.proname = 'available_slots'
                   AND p.prosrc LIKE '%HB240%') THEN
    RAISE EXCEPTION 'available_slots no longer raises HB240 - this migration was not supposed to touch it';
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0130');
