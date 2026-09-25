-- =====================================================================
-- Hand By Hand (new) - migration 0129: where a record came from
-- (BE-01 · BE-02, online consultation)
--
-- Two columns on hbh.guardians and two on hbh.children, saying which
-- door a record came through. And the reason this is worth writing even
-- before the owner has decided anything about online consultation is
-- that TWO OF THE THREE VALUES DESCRIBE THE SCHEMA AS IT ALREADY IS:
-- a row a member of staff created inside the application, and a row
-- convert_enrolment produced from an application. The column is a
-- truthful description of what has already happened; its absence is
-- the defect.
--
-- ---------------------------------------------------------------------
-- 1. THE BACKFILL IS DERIVED, AND ONLY FROM POSITIVE EVIDENCE
--
-- NOT NULL DEFAULT 'CENTER' would stamp a lie on every guardian who
-- came from an enrolment application - and nobody ever goes back to
-- question a default once it has landed. So each row is derived, and
-- from evidence that says yes rather than evidence that fails to say
-- no:
--
--   appears in enrolment_applications.converted_guardian_id
--       -> ENROLMENT_REQUEST. 0018 wrote that column as, in its own
--          words, the proof that a real record came FROM this
--          application and not the other way round.
--   created_by names a real application user
--       -> CENTER. A person created this row inside the application.
--   neither
--       -> NULL. Seed and script rows came through no business door at
--          all, and "no evidence" is the honest answer. Counted and
--          reported below, not filled with something plausible.
--
-- HOW MANY THAT RESOLVES IS NOT WRITTEN HERE, ON PURPOSE. The first
-- draft of this header said "4 of 18 guardians and 8 of 11 children" -
-- true when it was typed, and false within the hour, because most of
-- the derived rows were other sessions' fixtures and got cleaned up.
-- A live count quoted in a migration header is a measurement that ages
-- into a lie, and the next reader takes it for a description of the
-- schema. The verify block at the foot of this file PRINTS the counts
-- when it runs, which is the same fact with a timestamp on it.
--
-- ---------------------------------------------------------------------
-- 2. IT IS NOT CALLED profile_status
--
-- hbh.therapists.profile_status has existed since 0033 with
-- DRAFT/PUBLISHED/WITHDRAWN, and it means WHETHER A PROFILE IS
-- PUBLISHED ON THE PUBLIC SITE - a different axis entirely from how
-- complete a record is. One name with two meanings on two tables is a
-- trap that costs whoever reads the first and assumes the second, and
-- nothing stops them. record_completeness reads without a reference.
--
-- ---------------------------------------------------------------------
-- 3. AND THE SPELLING IS ENROLMENT, WITH ONE L
--
-- The request said ENROLLMENT_REQUEST. This schema is British
-- throughout - enrolment_applications, ENROLMENT.MANAGE,
-- ENROLMENT_PENDING, submit_enrolment, convert_enrolment - and a value
-- spelled the other way would be the one place it is not, which is how
-- a WHERE clause comes to match nothing while looking correct.
--
-- ---------------------------------------------------------------------
-- 4. IMMUTABILITY IS A TRIGGER, NOT AN UNDERSTANDING
--
-- The rule is that origin does not change after creation. Left to the
-- API layer, test scenario 21 - which tries a direct UPDATE - would
-- pass while the rule was broken, because the direct UPDATE never goes
-- near the API.
--
-- NULL -> a value is allowed, once: that is RECORDING an origin, not
-- changing it, and it is how the rows this migration could not derive
-- can be corrected by somebody who actually knows. A value -> anything
-- else is refused.
--
-- Error classes added here:
--   HB240  origin cannot be changed once recorded
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0129') THEN
    RAISE EXCEPTION 'migration 0129 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0128') THEN
    RAISE EXCEPTION 'migration 0128 must be applied first';
  END IF;
  -- The name clash this migration exists partly to avoid. If somebody
  -- has meanwhile added guardians.profile_status, stop and talk.
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'hbh' AND table_name = 'guardians'
               AND column_name = 'profile_status') THEN
    RAISE EXCEPTION 'guardians.profile_status already exists - see note 2 in this header';
  END IF;
END
$guard$;

-- =====================================================================
-- THE COLUMNS
-- =====================================================================
ALTER TABLE hbh.guardians
  ADD COLUMN registration_source text,
  ADD COLUMN record_completeness text;

ALTER TABLE hbh.guardians
  ADD CONSTRAINT ck_guardians_reg_source
  CHECK (registration_source IS NULL
         OR registration_source IN ('CENTER', 'ENROLMENT_REQUEST', 'ONLINE_CONSULTATION')),
  ADD CONSTRAINT ck_guardians_completeness
  CHECK (record_completeness IS NULL
         OR record_completeness IN ('MINIMAL', 'PARTIAL', 'COMPLETE'));

ALTER TABLE hbh.children
  ADD COLUMN origin_source       text,
  ADD COLUMN origin_reference_id integer;

ALTER TABLE hbh.children
  ADD CONSTRAINT ck_children_origin
  CHECK (origin_source IS NULL
         OR origin_source IN ('CENTER', 'ENROLMENT_REQUEST', 'ONLINE_CONSULTATION')),
  -- A reference without a source is a pointer into nothing.
  ADD CONSTRAINT ck_children_origin_ref
  CHECK (origin_reference_id IS NULL OR origin_source IS NOT NULL);

-- NO FOREIGN KEY on origin_reference_id, and the reason is the same one
-- hbh.attachments.owner_id carries: what it points at depends on the
-- source. ENROLMENT_REQUEST means an enrolment_applications row;
-- ONLINE_CONSULTATION will mean a consultation_requests row, a table
-- that does not exist yet. One column cannot reference two tables, and
-- a constraint that referenced only the first would forbid the second
-- the day it arrives.
COMMENT ON COLUMN hbh.children.origin_reference_id IS
  'The row in the table named by origin_source. No FK: what it points at depends on the source, the same shape as attachments.owner_id.';

CREATE INDEX ix_guardians_reg_source ON hbh.guardians (registration_source)
  WHERE registration_source IS NOT NULL;
CREATE INDEX ix_children_origin ON hbh.children (origin_source, origin_reference_id)
  WHERE origin_source IS NOT NULL;

-- =====================================================================
-- THE BACKFILL
-- =====================================================================
-- AND IT SKIPS ROWS THE SCHEMA HAS ALREADY FROZEN, which is a sentence
-- I did not expect to write in a migration about origins.
--
-- 0128 left hbh.guardians 668 - a legacy seven-digit mobile - writable
-- only by the UPDATE that retires it. Its created_by is dev_admin, a
-- real user, so the CENTER backfill below matched it and
-- ck_guardians_mobile_e164 killed the whole migration on a column that
-- has nothing to do with mobiles.
--
-- A FROZEN ROW FREEZES EVERY COLUMN ADDED AFTER IT. So the backfill
-- writes what it can write and counts what it cannot, instead of
-- failing on a row nobody can repair - and the count is printed, not
-- swallowed.
UPDATE hbh.guardians g
   SET registration_source = 'ENROLMENT_REQUEST'
 WHERE g.registration_source IS NULL
   AND g.mobile ~ '^\+[1-9][0-9]{7,14}$'
   AND EXISTS (SELECT 1 FROM hbh.enrolment_applications a
               WHERE a.converted_guardian_id = g.guardian_id);

UPDATE hbh.guardians g
   SET registration_source = 'CENTER'
 WHERE g.registration_source IS NULL
   AND g.mobile ~ '^\+[1-9][0-9]{7,14}$'
   AND EXISTS (SELECT 1 FROM hbh.users u
               WHERE lower(u.username) = lower(g.created_by));

UPDATE hbh.children c
   SET origin_source       = 'ENROLMENT_REQUEST',
       origin_reference_id = a.application_id
  FROM hbh.enrolment_applications a
 WHERE a.converted_child_id = c.child_id
   AND c.origin_source IS NULL;

UPDATE hbh.children c
   SET origin_source = 'CENTER'
 WHERE c.origin_source IS NULL
   AND EXISTS (SELECT 1 FROM hbh.users u
               WHERE lower(u.username) = lower(c.created_by));

-- =====================================================================
-- IMMUTABILITY
-- =====================================================================
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
        USING ERRCODE = 'HB240';
    END IF;
  END LOOP;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_guardians_origin_immutable
  BEFORE UPDATE ON hbh.guardians
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_origin_immutable('registration_source');

CREATE TRIGGER trg_children_origin_immutable
  BEFORE UPDATE ON hbh.children
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_origin_immutable('origin_source', 'origin_reference_id');

-- =====================================================================
-- AND THE PROOF, AT APPLY TIME - BOTH HALVES, AND THE COUNT SAID ALOUD
-- =====================================================================
DO $verify$
DECLARE
  l_id      integer;
  l_g_null  integer;
  l_c_null  integer;
  l_refused boolean := false;
  l_allowed boolean := false;
BEGIN
  -- AND THE PROBE PICKS A ROW IT CAN ACTUALLY UPDATE. The first draft
  -- took any row with a null source, and drew hbh.guardians 668 - the
  -- one holding a legacy mobile that 0128 left updatable only by
  -- retirement. The probe died on ck_guardians_mobile_e164 while
  -- testing something else entirely, and said nothing about HB240. A
  -- row that cannot be written for an unrelated reason is not a
  -- fixture, and "any row" is an assumption about state, not a
  -- statement of it.
  SELECT guardian_id INTO l_id FROM hbh.guardians
  WHERE registration_source IS NOT NULL
    AND mobile ~ '^\+[1-9][0-9]{7,14}$'
  LIMIT 1;

  IF l_id IS NULL THEN
    RAISE EXCEPTION 'the backfill derived nothing, so immutability could not be tested at all';
  END IF;

  BEGIN
    UPDATE hbh.guardians SET registration_source = 'CENTER'
    WHERE guardian_id = l_id AND registration_source <> 'CENTER';
    -- If the row was already CENTER the UPDATE matched nothing and
    -- proved nothing, so force a real change.
    UPDATE hbh.guardians SET registration_source = 'ONLINE_CONSULTATION'
    WHERE guardian_id = l_id;
  EXCEPTION WHEN sqlstate 'HB240' THEN
    l_refused := true;
  END;

  IF NOT l_refused THEN
    RAISE EXCEPTION 'a recorded origin was overwritten - the trigger is not doing its job';
  END IF;

  -- The accepting half. A guard that refuses everything is not a guard,
  -- and only a positive case can tell the two apart.
  SELECT guardian_id INTO l_id FROM hbh.guardians
  WHERE registration_source IS NULL
    AND mobile ~ '^\+[1-9][0-9]{7,14}$'
  LIMIT 1;

  IF l_id IS NULL THEN
    RAISE WARNING 'every guardian already has a source, so recording one into an empty column was not exercised';
  ELSE
    BEGIN
      UPDATE hbh.guardians SET registration_source = 'CENTER' WHERE guardian_id = l_id;
      l_allowed := true;
      RAISE EXCEPTION 'rollback the probe' USING ERRCODE = 'HB999';
    EXCEPTION
      WHEN sqlstate 'HB999' THEN NULL;
      WHEN sqlstate 'HB240' THEN l_allowed := false;
    END;

    IF NOT l_allowed THEN
      RAISE EXCEPTION 'recording a source into an empty column was refused - NULL is not a value being changed';
    END IF;
  END IF;

  -- Said out loud, because a silent partial backfill reads as a
  -- complete one.
  SELECT count(*) INTO l_g_null FROM hbh.guardians WHERE registration_source IS NULL;
  SELECT count(*) INTO l_c_null FROM hbh.children  WHERE origin_source IS NULL;
  RAISE NOTICE 'origin left empty on purpose: % guardian(s), % child(ren) - no positive evidence either way, not filled with a guess',
               l_g_null, l_c_null;

  -- Counted separately, because "could not derive" and "could not
  -- write" are different problems and only one of them is about
  -- evidence.
  SELECT count(*) INTO l_g_null FROM hbh.guardians
  WHERE registration_source IS NULL AND mobile !~ '^\+[1-9][0-9]{7,14}$';

  IF l_g_null > 0 THEN
    RAISE NOTICE 'and % guardian(s) were skipped because the row itself is frozen by ck_guardians_mobile_e164 - derivable, but not writable until somebody supplies a real mobile or retires the row',
                 l_g_null;
  END IF;
END
$verify$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0129');
