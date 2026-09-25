-- =====================================================================
-- Hand By Hand (new) - migration 0128
-- a row that cannot be repaired must at least be retirable
--
-- WHAT WAS REPORTED TO ME, AND WHAT IS ACTUALLY TRUE
--
-- The API session flagged one hbh.guardians row still holding a raw
-- mobile, and said any UPDATE on it "wakes the trigger and is refused
-- with HB173". Both halves of that are wrong, and worth writing down,
-- because the trigger is innocent and the real cause is quieter.
--
-- trg_canonical_mobile already carries the right guard:
--
--     IF TG_OP = 'UPDATE' AND raw IS NOT DISTINCT FROM (OLD->>col)
--     THEN RETURN NEW;
--
-- So an UPDATE that does not touch the mobile skips canonicalisation
-- entirely - and that is exactly the problem. The stale value survives
-- untouched, and then ck_guardians_mobile_e164 rejects the row. The
-- refusal is 23514 from a CHECK, not HB173 from the trigger.
--
-- AND THIS IS WHAT `NOT VALID` DOES AND DOES NOT BUY
--
-- All four constraints were added NOT VALID, which skips the scan of
-- existing rows. It does NOT exempt those rows from the NEXT UPDATE.
-- So a pre-existing bad row becomes immortal AND unusable: it cannot be
-- renamed, cannot be linked to an account, and - the part that matters -
-- CANNOT BE DEACTIVATED. Retiring it is an UPDATE, and the UPDATE is
-- refused by the value it is trying to retire.
--
-- Proven before touching anything, inside a rolled-back transaction:
--   rename          -> 23514 ck_guardians_mobile_e164
--   soft delete     -> 23514 ck_guardians_mobile_e164
--   set a valid one -> accepted
--
-- THE FIX: THE INVARIANT IS ABOUT LIVE DATA
--
-- Every ACTIVE row must carry an E.164 mobile - that rule is untouched
-- and is what the application depends on. A deactivated row is history,
-- and freezing history was never the point. So each CHECK gains
-- "NOT active_flg OR ...", which is the smallest change that restores
-- the one operation you actually need on data you cannot repair.
--
-- WHAT THIS MIGRATION DELIBERATELY DOES NOT DO: invent a phone number.
-- hbh.guardians 668 holds '0100000' - seven digits, not a number any
-- country has - and nothing in this schema knows what it was meant to
-- be. Writing a plausible one would put a fabricated contact detail for
-- a family into the clinical record, which is worse than a row somebody
-- has to look at. Retiring it is an operational decision and is left to
-- one; this migration only makes it possible.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0128') THEN
    RAISE EXCEPTION 'migration 0128 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0127') THEN
    RAISE EXCEPTION 'migration 0127 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- The four constraints, each keeping its exact shape for live rows
-- =====================================================================
ALTER TABLE hbh.guardians DROP CONSTRAINT ck_guardians_mobile_e164;
ALTER TABLE hbh.guardians
  ADD CONSTRAINT ck_guardians_mobile_e164
  CHECK (NOT active_flg OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.users DROP CONSTRAINT ck_users_mobile_e164;
ALTER TABLE hbh.users
  ADD CONSTRAINT ck_users_mobile_e164
  CHECK (NOT active_flg OR mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.therapists DROP CONSTRAINT ck_therapists_mobile_e164;
ALTER TABLE hbh.therapists
  ADD CONSTRAINT ck_therapists_mobile_e164
  CHECK (NOT active_flg OR mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.enrolment_applications DROP CONSTRAINT ck_enr_mobile_e164;
ALTER TABLE hbh.enrolment_applications
  ADD CONSTRAINT ck_enr_mobile_e164
  CHECK (NOT active_flg OR parent_mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

-- =====================================================================
-- AND THE PROOF, AT APPLY TIME
--
-- Both halves, because a constraint that accepts everything is fast and
-- useless, and a timing or a row count would not tell them apart. The
-- accepting half is checked FIRST on a row we then roll back, and the
-- refusing half on a row that must still be refused.
-- =====================================================================
DO $verify$
DECLARE
  l_id      integer;
  l_refused boolean := false;
  l_retired boolean := false;
BEGIN
  SELECT guardian_id INTO l_id FROM hbh.guardians
  WHERE mobile IS NOT NULL AND mobile !~ '^\+[1-9][0-9]{7,14}$' AND active_flg
  LIMIT 1;

  IF l_id IS NULL THEN
    -- Said out loud. Silence here would read as "verified".
    RAISE WARNING 'no active row with a legacy mobile exists, so the retirement path was not exercised';
  ELSE
    -- A SAVEPOINT, and the first draft of this block got it wrong in a
    -- way worth keeping: it retired the row and then set active_flg
    -- back to true to leave things as they were. That UPDATE is REFUSED
    -- - correctly, because reactivating a row with a raw mobile is
    -- exactly what this constraint must prevent. The probe was undone
    -- by the very rule it was proving. A savepoint undoes it instead.
    BEGIN
      UPDATE hbh.guardians SET active_flg = false WHERE guardian_id = l_id;
      l_retired := true;
      -- Deliberately not kept. Whether to retire this row is an
      -- operational decision, not a side effect of a migration.
      RAISE EXCEPTION 'rollback the probe' USING ERRCODE = 'HB999';
    EXCEPTION
      WHEN sqlstate 'HB999' THEN NULL;
      WHEN check_violation THEN l_retired := false;
    END;

    IF NOT l_retired THEN
      RAISE EXCEPTION 'the constraint still blocks retiring guardian % - the whole point of this migration', l_id;
    END IF;
  END IF;

  -- The refusing half, on a row that has no business existing: an
  -- ACTIVE guardian with a raw mobile must still be rejected.
  --
  -- AND THE REFUSAL IS NAMED, not merely counted. The first draft
  -- caught "check_violation OR raise_exception" and the migration died
  -- anyway, because the refusal arrives EARLIER than expected and from
  -- somewhere else: trg_canonical_mobile raises HB173 on a number no
  -- country has, before the CHECK is ever consulted. Two legitimate
  -- refusals, two SQLSTATEs, and naming both is what makes this check
  -- mean something - a bare WHEN OTHERS here would have passed on a
  -- refusal for any reason at all, including a typo in the INSERT.
  BEGIN
    INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile, active_flg)
    SELECT c.center_id, NULL, '0128 فحص القيد', '0100000', true
    FROM   hbh.centers c ORDER BY c.center_id LIMIT 1;
  EXCEPTION
    WHEN check_violation  THEN l_refused := true;   -- 23514, the CHECK
    WHEN sqlstate 'HB170' THEN l_refused := true;   -- the trigger: unreadable number
    WHEN sqlstate 'HB173' THEN l_refused := true;   -- the trigger: wrong country shape
  END;

  IF NOT l_refused THEN
    RAISE EXCEPTION 'an ACTIVE guardian with a raw mobile was accepted - the invariant is gone';
  END IF;
END
$verify$;

COMMENT ON CONSTRAINT ck_guardians_mobile_e164 ON hbh.guardians IS
  'Every LIVE guardian carries an E.164 mobile. A deactivated row keeps whatever was recorded - because a row nobody can repair still has to be retirable, and retiring it is an UPDATE.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0128');
