-- =====================================================================
-- 0098 - one mobile, one account that can sign in with it
--
-- WHAT WAS POSSIBLE BEFORE THIS. hbh.users had no unique index on
-- mobile at all, and hbh.request_otp resolves a login with:
--
--   WHERE u.mobile = p_mobile AND u.active_flg
--   ORDER BY u.user_id
--   LIMIT 1
--
-- The LIMIT is there because duplicates were possible, and ORDER BY
-- user_id decides them: the OLDEST account wins. So two accounts on one
-- number meant the older one received every login code and the newer one
-- could never sign in - with nothing raised, nothing logged, and both
-- rows looking perfectly correct.
--
-- IT HAPPENED, in this database, to me. An acceptance fixture wrote four
-- accounts on numbers the dev seed already held. Every insert was
-- accepted. Then the code issued for a1's guardian signed in as
-- dev_therapist - staff, a different centre role, a different person -
-- and the isolation checks underneath were comparing the wrong two
-- callers while passing. Reception typing a number that already exists
-- produces exactly the same thing, quietly, on a real family.
--
-- WHY PARTIAL, AND WHY ON THESE TWO CONDITIONS:
--
--   mobile IS NOT NULL
--     NULL here means ABSENCE - "no number recorded yet" - not a value.
--     Two unknowns are not a duplicate, and a plain UNIQUE would refuse
--     the SECOND account without a mobile. That is the Oracle defect
--     this project already paid for once, on children.national_id, in a
--     centre where many small children have no national ID.
--
--   active_flg
--     Deletion is soft (rule 3), so an archived account keeps its row
--     and its number for ever. A full unique index would mean a family
--     who leaves the centre takes their phone number with them - nobody
--     could ever be registered on it again. And it is not needed: the
--     lookup above filters on active_flg too, so an archived row is
--     already unreachable for sign-in. The index matches the query it
--     exists to protect, exactly.
--
-- WHY GLOBAL AND NOT PER CENTRE. Sign-in happens BEFORE there is an
-- identity, so the lookup cannot know a centre and does not filter by
-- one. Making the index per-centre would let two centres hold the same
-- number and leave request_otp choosing between them by user_id again -
-- the same defect wearing a scope. If this system ever serves a family
-- attending two centres, the sign-in path is what has to change first,
-- and this index is the thing that will say so out loud.
--
-- THE DUPLICATES ARE ALREADY GONE. Verified before writing this: zero
-- mobiles held by more than one row, active or not. So this migration
-- creates the index directly rather than cleaning up first - and if a
-- duplicate appears between this line and the apply, it FAILS here,
-- loudly, which is the right place for it to be noticed.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE UNIQUE INDEX IF NOT EXISTS uix_users_mobile_active
  ON hbh.users (mobile)
  WHERE mobile IS NOT NULL AND active_flg;

COMMENT ON INDEX hbh.uix_users_mobile_active IS
  'One active account per mobile. hbh.request_otp resolves a login by mobile alone, so a duplicate makes the oldest account receive the code and the newest unable to sign in - silently.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0098');
