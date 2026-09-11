-- =====================================================================
-- Hand By Hand (new) - PHASE 15 acceptance suite: international mobiles
--
-- Must print:  PHASE 15 ACCEPTED
--
-- Migrations 0112, 0113 and 0114. Four claims:
--
--   1. A FAMILY OUTSIDE EGYPT CAN BE REGISTERED AND REACHED. That is the
--      feature; everything else here is what stops it costing something.
--   2. EVERY SPELLING OF ONE NUMBER BECOMES ONE VALUE. This is the claim
--      that protects 0098. Sign-in resolves an account by mobile alone,
--      globally, before there is an identity, and a number that can be
--      written two ways makes uix_users_mobile_active blind to a
--      duplicate - which is how a code issued for a guardian once signed
--      in as a therapist at another centre.
--   3. AND WHAT CANNOT BE READ IS REFUSED, NOT GUESSED. Bare digits are
--      either an international number missing its plus or a national one
--      in a country with no trunk prefix. The cost of choosing wrong is
--      a login code delivered to a stranger.
--   4. AND THE GATE OPENS. A photograph consent in this project asked
--      for a type the schema never had: it refused every upload for a
--      fortnight while its "without consent it is refused" check stayed
--      green. Every refusal here is followed by the acceptance that
--      proves the refusal was conditional.
--
-- EVERY NEGATIVE CHECK NAMES ITS SQLSTATE. "Did it fail" is not the
-- question - HB010 for a missing number series and HB170 for a bad
-- number look identical to a harness that only asks whether something
-- was raised, and this project has already reported six open functions
-- as closed that way.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp text NOT NULL, name text NOT NULL, ok boolean NOT NULL, detail text);
CREATE TABLE hbh_test.fx (k text PRIMARY KEY, v integer);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL' ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', THE CALL SUCCEEDED');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || left(SQLERRM, 60));
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE
--
-- The numbers are +2015999 9xxxx and +9665999 9xxxx: a block no other
-- suite in this tree uses. Cleanup at the bottom deletes BY THE KEYS
-- RECORDED HERE and not by resemblance - a LIKE '015000000%' in phase 5
-- once matched a neighbouring session's fixture, died on a foreign key,
-- rolled back its own cleanup with it, and cost the next round
-- twenty-one failures that had nothing to do with anything.
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

-- THE STATE IS MADE, NOT ASSUMED, AND IT IS MADE HERE.
--
-- The first draft of this suite signed in with an account belonging to
-- the phase 1 fixture and asserted it was there. Phase 1 tears its own
-- accounts down, so the assertion failed - and because a suite runs with
-- ON_ERROR_STOP off, so that every probe records its own failure and the
-- verdict always prints, the raise printed and the run CARRIED ON. Five
-- sign-in checks then tested an account that did not exist and reported
-- it as a broken feature.
--
-- A suite that needs a row creates that row. Borrowing one makes it fail
-- on the order the phases happen to run in, which is a fact about the
-- glob in db.sh and not about anything being tested.
--
-- The children go before the parents. otp_codes references users, and a
-- single statement deleting both would be undefined in its ordering -
-- it works until the plan changes.
DELETE FROM hbh.otp_codes WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p15.%');
DELETE FROM hbh.users     WHERE username LIKE 'p15.%';
DELETE FROM hbh.guardians WHERE full_name_ar LIKE 'p15 %';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile, status)
SELECT f.v, b.v, v.username, v.name, 'GUARDIAN', v.mobile, 'ACTIVE'
FROM hbh_test.fx f, hbh_test.fx b,
     (VALUES ('p15.riyadh', 'p15 ولي أمر الرياض', '+966599912345'),
             ('p15.cairo',  'p15 ولي أمر القاهرة', '+201599991001')
     ) AS v(username, name, mobile)
WHERE f.k = 'center' AND b.k = 'branch';

INSERT INTO hbh_test.fx (k, v)
SELECT 'user_riyadh', user_id FROM hbh.users WHERE username = 'p15.riyadh';
INSERT INTO hbh_test.fx (k, v)
SELECT 'user_cairo', user_id FROM hbh.users WHERE username = 'p15.cairo';

-- Asserted BY NAME, before anything is tested. A missing piece found
-- fifty checks later reads as a puzzling refusal from sound code.
DO $fixture$
DECLARE n integer;
BEGIN
  IF (SELECT count(*) FROM hbh_test.fx
       WHERE k IN ('center','branch','user_riyadh','user_cairo')) <> 4 THEN
    RAISE EXCEPTION 'fixture: a key is missing from hbh_test.fx';
  END IF;

  SELECT count(*) INTO n FROM hbh.country_dial_codes
   WHERE country_code IN ('EG','SA') AND active_flg;
  IF n <> 2 THEN
    RAISE EXCEPTION 'fixture: the EG and SA dial codes are not both loaded - every check below would fail as HB173';
  END IF;

  -- The two accounts had to survive the canonicaliser to be what the
  -- sign-in checks think they are.
  SELECT count(*) INTO n FROM hbh.users
   WHERE username LIKE 'p15.%' AND active_flg AND status = 'ACTIVE'
     AND mobile IN ('+966599912345', '+201599991001');
  IF n <> 2 THEN
    RAISE EXCEPTION 'fixture: the two p15 accounts are not stored in E.164';
  END IF;
END
$fixture$;

-- =====================================================================
-- 1. ONE NUMBER, ONE VALUE
-- =====================================================================
CALL hbh_test.chk('canon', 'the national form becomes E.164',
  $q$ SELECT hbh.canonical_mobile('01500000093', 'EG') = '+201500000093' $q$);

CALL hbh_test.chk('canon', '00 is the other way of writing +',
  $q$ SELECT hbh.canonical_mobile('00201500000093', 'EG') = '+201500000093' $q$);

CALL hbh_test.chk('canon', 'the international form is already itself',
  $q$ SELECT hbh.canonical_mobile('+201500000093', 'EG') = '+201500000093' $q$);

-- THE CLAIM 0098 DEPENDS ON. Six spellings, one value - so a second
-- account cannot be created on a number that already has one by typing
-- it differently.
CALL hbh_test.chk('canon', 'six spellings of one number collapse to one value',
  $q$ SELECT count(DISTINCT hbh.canonical_mobile(v, 'EG')) = 1
      FROM (VALUES ('01500000093'), ('+201500000093'), ('00201500000093'),
                   ('0150 000 0093'), ('(0150) 000-0093'), ('٠١٥٠٠٠٠٠٠٩٣')
           ) t(v) $q$);

CALL hbh_test.chk('canon', 'a Saudi number survives being typed the way it is written',
  $q$ SELECT hbh.canonical_mobile('+966 50 123 4567', 'EG') = '+966501234567' $q$);

CALL hbh_test.chk('canon', 'the country of a national number is the centre''s, not a constant',
  $q$ SELECT hbh.canonical_mobile('0501234567', 'SA') = '+966501234567' $q$);

-- =====================================================================
-- 2. WHAT CANNOT BE READ IS REFUSED
-- =====================================================================
CALL hbh_test.chk_raises('refuse', 'bare digits are ambiguous and are not guessed at',
  $q$ SELECT hbh.canonical_mobile('201500000093', 'EG') $q$, 'HB173');

CALL hbh_test.chk_raises('refuse', 'a country with no dial code row is refused, not assumed',
  $q$ SELECT hbh.canonical_mobile('+99912345678', 'EG') $q$, 'HB173');

CALL hbh_test.chk_raises('refuse', 'a national number with no country to read it against',
  $q$ SELECT hbh.canonical_mobile('0501234567', 'ZZ') $q$, 'HB173');

-- An SMS to a landline disappears at the provider without an error worth
-- the name, so the difference is worth keeping.
CALL hbh_test.chk_raises('refuse', 'an Egyptian landline is not a mobile',
  $q$ SELECT hbh.canonical_mobile('0223456789', 'EG') $q$, 'HB170');

CALL hbh_test.chk_raises('refuse', 'a Saudi landline is not a mobile',
  $q$ SELECT hbh.canonical_mobile('+966112345678', 'EG') $q$, 'HB170');

CALL hbh_test.chk_raises('refuse', 'too short for the country it names',
  $q$ SELECT hbh.canonical_mobile('+9665012345', 'EG') $q$, 'HB170');

-- =====================================================================
-- 3. THE GATE OPENS - a family outside Egypt is registered and stored
--    in the one form the rest of the system reads
-- =====================================================================
CALL hbh_test.chk('gulf', 'a Saudi guardian is accepted, typed the way it is written',
  $q$ WITH ins AS (
        INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
        SELECT v, 'p15 والدة من جدة', '+966 59 991 2346' FROM hbh_test.fx WHERE k = 'center'
        RETURNING mobile)
      SELECT mobile = '+966599912346' FROM ins $q$);

CALL hbh_test.chk('gulf', 'an Emirati guardian too',
  $q$ WITH ins AS (
        INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
        SELECT v, 'p15 والد من دبي', '+971-50-999-1234' FROM hbh_test.fx WHERE k = 'center'
        RETURNING mobile)
      SELECT mobile = '+971509991234' FROM ins $q$);

CALL hbh_test.chk('gulf', 'and an Egyptian one is stored in the same form',
  $q$ WITH ins AS (
        INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
        SELECT v, 'p15 والد من القاهرة', '0159 999 1234' FROM hbh_test.fx WHERE k = 'center'
        RETURNING mobile)
      SELECT mobile = '+201599991234' FROM ins $q$);

CALL hbh_test.chk_raises('gulf', 'a word is refused by the typing sieve, by name',
  $q$ INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
      SELECT v, 'p15 ليس رقمًا', 'ابن خالتي' FROM hbh_test.fx WHERE k = 'center' $q$,
  'HB170');

-- =====================================================================
-- 4. THE DUPLICATE 0098 EXISTS TO CATCH IS CAUGHT
--
-- Before this, two spellings of one number were two rows that the unique
-- index could not see, and request_otp chose between them by user_id:
-- the older account received every code and the newer could never sign
-- in, with nothing raised and both rows looking correct.
-- =====================================================================
CALL hbh_test.chk_raises('dup', 'a second account on the same number, typed differently, is refused',
  $q$ INSERT INTO hbh.users (center_id, username, full_name_ar, user_type, mobile, status)
      SELECT v, 'p15.riyadh2', 'p15 نفس الرقم بصيغة أخرى', 'GUARDIAN',
             '00966 59 991 2345', 'ACTIVE'
      FROM hbh_test.fx WHERE k = 'center' $q$,
  '23505');

CALL hbh_test.chk('dup', 'and the account that was already there is untouched',
  $q$ SELECT count(*) = 1 FROM hbh.users
       WHERE user_id = (SELECT v FROM hbh_test.fx WHERE k = 'user_riyadh')
         AND mobile = '+966599912345' $q$);

-- =====================================================================
-- 5. SIGN-IN READS EITHER SPELLING AND FINDS THE SAME ACCOUNT
--
-- This is what lets the API lag behind the schema: a build that still
-- sends the national form keeps working, unchanged.
-- =====================================================================
-- ONE CHECK, TWO ASSERTIONS, AND THAT IS DELIBERATE. Only the FIRST
-- request inside OTP_RESEND_SECONDS comes back OK, and mobile_e164 is
-- NULL on every outcome that did not issue a code. Splitting these would
-- make the second one assert NULL = a number and fail for a reason that
-- has nothing to do with canonicalisation.
CALL hbh_test.chk('signin', 'the national form signs in and names the number to deliver to',
  $q$ SELECT ok AND mobile_e164 = '+201599991001'
      FROM hbh.request_otp('01599991001') $q$);

-- RESEND_TOO_SOON is the useful answer here: it means the lookup found
-- the SAME account the previous line issued a code for. NOT_REGISTERED
-- would mean these two spellings reached different rows, which is the
-- whole defect.
CALL hbh_test.chk('signin', 'the international form reaches the same account',
  $q$ SELECT reason = 'RESEND_TOO_SOON'
      FROM hbh.request_otp('+201599991001') $q$);

CALL hbh_test.chk('signin', 'and so does the same number typed with spaces',
  $q$ SELECT reason = 'RESEND_TOO_SOON'
      FROM hbh.request_otp('0159 999 1001') $q$);

CALL hbh_test.chk('signin', 'and so does a Saudi number, which is the point of all this',
  $q$ SELECT ok AND mobile_e164 = '+966599912345'
      FROM hbh.request_otp('+966 59 991 2345') $q$);

-- FAILS CLOSED. An unreadable number is certainly not registered, and
-- saying so tells the caller nothing it did not already know.
CALL hbh_test.chk('signin', 'an ambiguous number is not registered, and is not guessed at',
  $q$ SELECT NOT ok AND reason = 'NOT_REGISTERED'
      FROM hbh.request_otp('201599991001') $q$);

-- WRONG_CODE rather than NO_PENDING_CODE: the national spelling found
-- the account AND the code the international spelling issued for it.
CALL hbh_test.chk('signin', 'verify_otp reads either spelling too',
  $q$ SELECT reason = 'WRONG_CODE'
      FROM hbh.verify_otp('01599991001', '000000') $q$);

-- =====================================================================
-- 6. THE OUTBOX HOLDS ONE REPRESENTATION, WHICHEVER FUNCTION WROTE IT
--
-- 0112 missed this and the login handler put the typed national form
-- back into the column within three minutes: it passes what the parent
-- typed to record_otp_delivery, which INSERTs directly rather than
-- through enqueue_sms. 0114 put the rule on the table.
-- =====================================================================
-- THE WRITE AND THE ASSERTION ARE TWO STATEMENTS, and the first draft of
-- this file proved why they have to be. Written as
--
--   WITH ins AS (SELECT hbh.record_otp_delivery(...) AS id)
--   SELECT s.destination FROM hbh.sms_outbox s JOIN ins ON s.sms_id = ins.id
--
-- both halves read the snapshot taken when the statement began, so the
-- row the function had just inserted was invisible to the join and the
-- check returned NULL. It is the CTE rule written up in CLAUDE.md,
-- arriving through a function call rather than a literal INSERT, which
-- is what made it look like the migration was at fault.
INSERT INTO hbh_test.fx (k, v)
SELECT 'outbox_ok',
       hbh.record_otp_delivery((SELECT v FROM hbh_test.fx WHERE k = 'center'),
                               '01599991299', 'p15', 'p15-msg')::integer;

CALL hbh_test.chk('outbox', 'a national destination is canonicalised on the way in',
  $q$ SELECT destination = '+201599991299' FROM hbh.sms_outbox
       WHERE sms_id = (SELECT v FROM hbh_test.fx WHERE k = 'outbox_ok') $q$);

CALL hbh_test.chk('outbox', 'and the dedupe key carries the same value as the column',
  $q$ SELECT dedupe_key LIKE '%+201599991299' FROM hbh.sms_outbox
       WHERE sms_id = (SELECT v FROM hbh_test.fx WHERE k = 'outbox_ok') $q$);

-- LENIENT ON PURPOSE. An outbox row is written inside somebody else's
-- transaction - an appointment confirmation, a report published - and
-- raising here would fail THAT because a number recorded years ago is
-- seven digits long. It travels on and the sender refuses it, which is
-- what happened before 0114 as well.
INSERT INTO hbh_test.fx (k, v)
SELECT 'outbox_bad',
       hbh.record_otp_delivery((SELECT v FROM hbh_test.fx WHERE k = 'center'),
                               '0100000', 'p15', NULL, 'PERMANENT', 'p15 short')::integer;

CALL hbh_test.chk('outbox', 'an unconvertible destination is kept, not raised on',
  $q$ SELECT destination = '0100000' FROM hbh.sms_outbox
       WHERE sms_id = (SELECT v FROM hbh_test.fx WHERE k = 'outbox_bad') $q$);

-- =====================================================================
-- CLEANUP - BY IDENTITY, and it is a recorded check like any other.
-- A cleanup that swallows its failure is worse than no cleanup: the rows
-- it left behind become the next round's mysterious failures.
-- =====================================================================
CALL hbh_test.chk('cleanup', 'the outbox rows this suite wrote are gone',
  $q$ WITH d AS (DELETE FROM hbh.sms_outbox WHERE provider_code = 'p15' RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the guardians are gone',
  $q$ WITH d AS (DELETE FROM hbh.guardians WHERE full_name_ar LIKE 'p15 %' RETURNING 1)
      SELECT count(*) >= 3 FROM d $q$);

-- The codes before the accounts that own them. otp_codes references
-- users, and several CTEs modifying data in one statement have no
-- ordering between them - it succeeds for days and then the plan changes.
CALL hbh_test.chk('cleanup', 'the login codes this suite issued are gone',
  $q$ WITH d AS (DELETE FROM hbh.otp_codes
                  WHERE user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p15.%')
                  RETURNING 1)
      SELECT count(*) >= 1 FROM d $q$);

CALL hbh_test.chk('cleanup', 'the accounts are gone',
  $q$ WITH d AS (DELETE FROM hbh.users WHERE username LIKE 'p15.%' RETURNING 1)
      SELECT count(*) >= 2 FROM d $q$);

-- "At least one, then none left" - the property is that nothing of this
-- suite remains, not that a particular run's arithmetic came out.
CALL hbh_test.chk('cleanup', 'and nothing of this suite is left behind',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.users     WHERE username     LIKE 'p15.%')
         AND NOT EXISTS (SELECT 1 FROM hbh.guardians WHERE full_name_ar LIKE 'p15 %')
         AND NOT EXISTS (SELECT 1 FROM hbh.sms_outbox WHERE provider_code = 'p15') $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة", count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM hbh_test.results GROUP BY grp ORDER BY min(seq);

\echo ''
SELECT seq, grp, name, detail FROM hbh_test.results WHERE NOT ok ORDER BY seq;

DO $verdict$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 15 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 15 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
