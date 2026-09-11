-- =====================================================================
-- Hand By Hand (new) - migration 0032: one primary guardian per child
--
-- WHY. "The primary guardian" is a phrase several places in this system
-- already use as though it named exactly one person, and nothing made
-- it true:
--
--   hbh.create_invoice picks
--       ORDER BY is_primary_flg DESC, guardian_id LIMIT 1
--   which quietly means "a primary one, or whichever came first". With
--   two primaries it bills whichever guardian_id is smaller - stable,
--   arbitrary, and wrong half the time.
--
--   The printed child card names an emergency contact. "Whichever of
--   the two" is the wrong number on the wrong day.
--
-- The design session asked for this while building that card, and it is
-- worth having regardless of the card: a flag that says "the" and
-- permits several is a flag that reads as a decision and behaves as a
-- coin toss.
--
-- WHY active_flg IS IN THE PREDICATE, and this is the part that would
-- have bitten. Deletion here is soft: archiving a guardian's link
-- leaves the row with is_primary_flg still true. An index over
-- is_primary_flg alone would then refuse to make anybody else primary -
-- a family whose primary parent left could never name another, and the
-- error would arrive at the worst possible moment with no explanation.
-- Only LIVE links compete.
--
-- Verified against the data before writing this: zero children carry
-- more than one primary link, archived rows included. If that were not
-- true the right answer would be a data fix first, never a weaker
-- index.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0032') THEN
    RAISE EXCEPTION 'migration 0032 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0002') THEN
    RAISE EXCEPTION 'migration 0002 must be applied first';
  END IF;

  -- Named before it is enforced. A unique index that fails to build
  -- reports a duplicate key and leaves the reader to work out which
  -- rule they broke; this says it.
  IF EXISTS (SELECT 1 FROM hbh.guardian_children
              WHERE is_primary_flg AND active_flg
              GROUP BY child_id HAVING count(*) > 1) THEN
    RAISE EXCEPTION 'some children already have more than one primary guardian - fix the data first, do not weaken the index';
  END IF;
END
$guard$;

CREATE UNIQUE INDEX uix_gc_one_primary
  ON hbh.guardian_children (child_id)
  WHERE is_primary_flg AND active_flg;

COMMENT ON INDEX hbh.uix_gc_one_primary IS
  'One primary guardian per child, among LIVE links. Archived links keep their flag and do not compete (0032).';

-- It has to actually refuse. An index that exists and does not bite is
-- the same as no index, and the difference is invisible until somebody
-- relies on it.
DO $prove$
DECLARE
  l_child integer;
  l_g     integer;
  l_ok    boolean := false;
BEGIN
  SELECT child_id INTO l_child FROM hbh.guardian_children
   WHERE is_primary_flg AND active_flg LIMIT 1;
  IF l_child IS NULL THEN
    -- Nothing to test against. Silence would be wrong here: the check
    -- did not pass, it did not run.
    RAISE WARNING 'no primary link exists yet, so the new index was not exercised';
    RETURN;
  END IF;

  SELECT guardian_id INTO l_g FROM hbh.guardians
   WHERE active_flg AND guardian_id NOT IN (
     SELECT guardian_id FROM hbh.guardian_children WHERE child_id = l_child)
   LIMIT 1;
  IF l_g IS NULL THEN
    RAISE WARNING 'no spare guardian to test with, so the new index was not exercised';
    RETURN;
  END IF;

  BEGIN
    INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
    VALUES (l_g, l_child, 'GUARDIAN', true);
  EXCEPTION WHEN unique_violation THEN
    l_ok := true;
  END;

  IF NOT l_ok THEN
    RAISE EXCEPTION 'a second primary guardian was accepted - the index is not doing its job';
  END IF;
END
$prove$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0032');
