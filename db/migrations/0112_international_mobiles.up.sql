-- =====================================================================
-- 0112 - a mobile number is stored in E.164, and only in E.164
--
-- ORDER OF DEPLOYMENT: THE API GOES FIRST.
-- This migration raises HB173, and api/internal/store/pgerr.go has to
-- know it or the handlers fall through to their `default` and answer 500
-- with the cause in the log. The lesson is written in 0053 and was paid
-- for there: a business rule refusing on purpose must not reach the desk
-- as "an unexpected error occurred".
--
-- ---------------------------------------------------------------------
-- WHY
--
-- The centre is taking online consultations from families outside Egypt.
-- Two things stopped that, and neither announced itself:
--
--   sys_params.MOBILE_PATTERN = '^01[0-9]{9}$'
--     A Gulf number is refused with HB170 the moment reception tries to
--     create the guardian. That one at least says something.
--
--   api/internal/sms/sms.go, func E164
--     Hard-codes "+20" and refuses anything else as ClassPermanent - no
--     retry, no queue, nothing to notice. The login code is marked
--     failed and the family sits waiting for a message that was never
--     going to be sent. And "+20" living in Go is itself against the
--     rule in CLAUDE.md: Egypt's specifics are parameters, never code.
--
-- ---------------------------------------------------------------------
-- WHY E.164 EVERYWHERE, AND NOT "LOCAL FOR EGYPT, INTERNATIONAL FOR THE
-- REST", WHICH WOULD HAVE NEEDED NO BACKFILL AT ALL
--
-- Because of 0098. Sign-in resolves an account by mobile ALONE, before
-- there is an identity and therefore before there is a centre:
--
--     WHERE u.mobile = p_mobile AND u.active_flg
--
-- and uix_users_mobile_active is what keeps that lookup honest. Allow a
-- number to be written two ways and the index stops seeing duplicates:
-- 01500000093 and +201500000093 are one person and two rows, both valid,
-- and request_otp goes back to choosing between them by user_id. That is
-- the defect 0098 exists to prevent, and it is not hypothetical there
-- either - it is written up in that file because it happened, and a code
-- issued for a guardian signed in as a therapist at another centre.
--
-- A key compared globally has to be unambiguous globally. A national
-- format is not: the same digits are a different person in a different
-- country.
--
-- ---------------------------------------------------------------------
-- WHY THE DATABASE CANONICALISES ITS OWN INPUT INSTEAD OF TRUSTING THE
-- CALLER TO SEND THE RIGHT SHAPE
--
-- Two reasons, and the second is what made this safe to ship.
--
-- Rule 4: the check belongs inside, not in a handler. A condition in Go
-- saying "convert before you write" is a second copy of a rule, and the
-- weaker copy is the one that decides.
--
-- And it removes the deployment gap entirely. If the API had to convert
-- first there would be a window where it sends +201500000093 while the
-- column still holds 01500000093 - and every sign-in in the country
-- fails for the length of a deploy. request_otp and verify_otp
-- canonicalise their own argument, so an API build that still sends the
-- national form keeps working, unchanged, for as long as it takes.
--
-- ---------------------------------------------------------------------
-- WHAT IS DELIBERATELY NOT TOUCHED
--
--   branches.phone, site_contact.phone
--     A centre's landline on a public page. Nothing signs in with it and
--     nothing is sent to it. MOBILE_PATTERN never governed them and this
--     does not start.
--
--   Two rows that do not match '^01[0-9]{9}$' and predate the 0053
--     trigger: guardians.guardian_id = 668 (seven digits) and
--     enrolment_applications.application_id = 331 (ten digits, inactive).
--     They are NOT converted, because there is no correct conversion of
--     a number that is not a number - "+20" on seven digits would invent
--     a subscriber and could hand somebody a stranger's login code. They
--     are left exactly as they are and NAMED by the report at the end of
--     this file. The canonicalising trigger fires only when the value
--     CHANGES, so they sit unbothered until a person who knows the
--     family fixes them.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0112') THEN
    RAISE EXCEPTION 'migration 0112 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0053') THEN
    RAISE EXCEPTION 'migration 0053 must be applied first';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0098') THEN
    RAISE EXCEPTION 'migration 0098 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- 1. WHICH COUNTRIES THIS CENTRE CAN REACH
--
-- THE ROWS ARE HERE AND NOT IN db/seed/, WHICH IS AGAINST THE USUAL RULE
-- AND IS THE RIGHT WAY ROUND THIS ONE TIME. db.sh applies every
-- migration first and the seeds afterwards, and the backfill in section
-- 5 of this file READS this table. Put the rows in db/seed/ and the
-- backfill matches nothing, converts nothing, and reports success -
-- which is the exact failure CLAUDE.md describes for INSERT ... SELECT
-- against a seeded table, arriving from the other direction.
--
-- The usual rule exists because seed data depends on other seed data.
-- These rows depend on nothing: they are facts about the world, and a
-- new country is a new migration, reviewed like any other change.
--
-- country_code is the primary key on purpose - no identity column, so no
-- sequence, so no sequence grant to forget. 0061 forgot one and the
-- table refused every insert with "permission denied for sequence",
-- which reads as a policy fault when the policies are fine.
--
-- e164_pattern is the shape of a MOBILE in that country, not of any
-- number in it. A Riyadh landline is a perfectly valid +966 number and
-- an SMS to it disappears without an error worth the name.
-- =====================================================================
CREATE TABLE IF NOT EXISTS hbh.country_dial_codes (
  country_code text        NOT NULL,
  dial_code    text        NOT NULL,
  e164_pattern text        NOT NULL,
  name_ar      text        NOT NULL,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_country_dial_codes PRIMARY KEY (country_code),
  CONSTRAINT ck_cdc_country CHECK (country_code ~ '^[A-Z]{2}$'),
  CONSTRAINT ck_cdc_dial    CHECK (dial_code ~ '^[1-9][0-9]{0,3}$'),
  -- The pattern must be anchored and must be about the international
  -- form, so it starts with the three characters ^ \ + literally. Said
  -- with left() rather than with a regex, because the regex that matches
  -- a regex starting with a backslash needs four of them and is read
  -- wrong by everyone including the person writing it - this file was
  -- refused by its own constraint once, exactly there.
  CONSTRAINT ck_cdc_pattern CHECK (left(e164_pattern, 3) = '^\+')
);

COMMENT ON TABLE hbh.country_dial_codes IS
  'Dial code and mobile shape per country. A country absent from here cannot be reached - which is the intended answer rather than a guess at what the digits meant.';

CREATE TRIGGER trg_country_dial_codes_touch BEFORE UPDATE ON hbh.country_dial_codes
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- No policy, and that IS the access decision rather than an omission.
-- Nothing outside this schema reads this table: hbh.canonical_mobile is
-- SECURITY DEFINER and reaches it that way. RLS on with no policy means
-- hbh_app sees zero rows if a query is ever pointed at it directly,
-- which is the right answer until there is a screen that needs one.
ALTER TABLE hbh.country_dial_codes ENABLE ROW LEVEL SECURITY;

INSERT INTO hbh.country_dial_codes (country_code, dial_code, e164_pattern, name_ar) VALUES
  ('EG', '20',  '^\+201[0-9]{9}$',      'مصر'),
  ('SA', '966', '^\+9665[0-9]{8}$',     'السعودية'),
  ('AE', '971', '^\+9715[0-9]{8}$',     'الإمارات'),
  ('KW', '965', '^\+965[569][0-9]{7}$', 'الكويت'),
  ('QA', '974', '^\+974[3567][0-9]{7}$','قطر'),
  ('BH', '973', '^\+973[36][0-9]{7}$',  'البحرين'),
  ('OM', '968', '^\+9689[0-9]{7}$',     'عُمان'),
  ('JO', '962', '^\+9627[0-9]{8}$',     'الأردن')
ON CONFLICT (country_code) DO NOTHING;

-- =====================================================================
-- 2. THE ONE PLACE A TYPED NUMBER BECOMES THE STORED ONE
--
-- SECURITY DEFINER is not decoration here. request_otp calls this BEFORE
-- a session exists, so the connection has no identity, and an RLS-
-- covered read from that path returns zero rows silently - exactly what
-- 0095 was written to fix on hbh.users. A dial code that came back empty
-- because nobody was logged in would turn every foreign login into
-- "number not recognised", with nothing raised anywhere.
--
-- WHAT IT REFUSES, AND WHY IT REFUSES RATHER THAN GUESSES:
--
--   "201500000093" - bare digits, no + and no leading 0.
--     This is either the Egyptian number written internationally without
--     its plus, or a national number in a country with no trunk prefix.
--     There is no way to tell from the digits, and the cost of telling
--     wrong is a login code delivered to a stranger. A number arrives
--     international (+ or 00) or national (leading 0). Anything else is
--     refused by name.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.canonical_mobile(p_raw text, p_country text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  d    text;
  cc   text;
  row_ hbh.country_dial_codes%ROWTYPE;
BEGIN
  IF p_raw IS NULL THEN
    RETURN NULL;
  END IF;

  -- Everything a person types as a separator goes, and so does the
  -- Arabic-Indic digit an Arabic phone keyboard produces.
  d := translate(p_raw, '٠١٢٣٤٥٦٧٨٩', '0123456789');
  d := regexp_replace(d, '[^0-9+]', '', 'g');

  IF d = '' THEN
    RETURN NULL;
  END IF;

  -- 00 is the other way of writing +, and reception types it.
  IF left(d, 2) = '00' THEN
    d := '+' || substr(d, 3);
  END IF;

  IF left(d, 1) = '0' THEN
    -- National form. It means nothing without a country.
    cc := upper(coalesce(p_country, hbh.param(NULL, 'DEFAULT_COUNTRY', NULL)));
    IF cc IS NULL OR cc = '' THEN
      RAISE EXCEPTION 'no country to read a national mobile number against'
        USING ERRCODE = 'HB173',
              HINT = 'sys_params.DEFAULT_COUNTRY, or the centre country_code';
    END IF;

    SELECT * INTO row_ FROM hbh.country_dial_codes
     WHERE country_code = cc AND active_flg;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'country % is not in hbh.country_dial_codes', cc
        USING ERRCODE = 'HB173',
              HINT = 'a new country is a new migration';
    END IF;

    d := '+' || row_.dial_code || substr(d, 2);

  ELSIF left(d, 1) <> '+' THEN
    -- The value is not in the message. This text reaches a log an
    -- operator reads, and a mobile number is personal data.
    RAISE EXCEPTION 'a mobile number must start with +, 00 or 0'
      USING ERRCODE = 'HB173',
            HINT = 'bare digits are ambiguous between an international and a national number';
  END IF;

  IF d !~ '^\+[1-9][0-9]{7,14}$' THEN
    RAISE EXCEPTION 'mobile does not match the centre''s accepted format'
      USING ERRCODE = 'HB170',
            HINT = 'E.164: a plus, a country code, then the subscriber number';
  END IF;

  -- The country code is on the front now, so the country is knowable and
  -- the mobile shape can be held to it. LONGEST dial code wins: a number
  -- can begin with two different valid dial codes and only one is right.
  SELECT * INTO row_ FROM hbh.country_dial_codes
   WHERE active_flg AND d LIKE '+' || dial_code || '%'
   ORDER BY length(dial_code) DESC
   LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no country in hbh.country_dial_codes matches this number'
      USING ERRCODE = 'HB173',
            HINT = 'a new country is a new migration';
  END IF;

  IF d !~ row_.e164_pattern THEN
    RAISE EXCEPTION 'mobile does not match the centre''s accepted format'
      USING ERRCODE = 'HB170',
            HINT = 'country_dial_codes.e164_pattern decides the shape of a mobile there';
  END IF;

  RETURN d;
END
$fn$;

COMMENT ON FUNCTION hbh.canonical_mobile(text, text) IS
  'The single place a typed mobile becomes the stored one. Returns E.164 or raises HB170 / HB173. SECURITY DEFINER because request_otp calls it before a session exists.';

REVOKE ALL ON FUNCTION hbh.canonical_mobile(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.canonical_mobile(text, text) TO hbh_app;

-- =====================================================================
-- 3. MOBILE_PATTERN NOW MEANS "WHAT A PERSON MAY TYPE", AND ONLY THAT
--
-- It keeps its job and loses a different one. The API reads it at the
-- edge (auth_handlers.go) before the database is called at all, so it
-- has to stay permissive enough to accept the national form an Egyptian
-- parent has typed for a year, AND the international form a family in
-- Riyadh will type tomorrow.
--
-- What may be STORED is E.164, and that is decided in section 4 below,
-- where no handler can hold a weaker opinion about it. Conflating the
-- two in one parameter is what made this look like a one-line change.
--
-- THE UPDATE IS HERE AND NOT ONLY IN THE SEED. db/seed/0001_reference.sql
-- ends its sys_params insert with ON CONFLICT DO NOTHING, on purpose:
-- "the seed guarantees a floor, it does not overwrite a decision". So
-- editing the seed alone changes fresh builds and leaves every existing
-- database on the Egypt-only pattern. Both are edited; this is the half
-- that reaches production.
-- =====================================================================
UPDATE hbh.sys_params
   SET param_value    = '^(\+[1-9][0-9]{7,14}|00[1-9][0-9]{7,14}|0[0-9]{6,14})$',
       description_ar = 'نمط رقم الجوّال كما يُكتَب — محلي أو دولي. شكل التخزين E.164 ويُفرَض في القاعدة',
       updated_at     = now(),
       updated_by     = hbh.current_app_user()
 WHERE param_code = 'MOBILE_PATTERN';

-- =====================================================================
-- 4. THE CANONICALISING TRIGGER
--
-- A BEFORE trigger may change NEW, and this is the case that wants it.
-- Reception typing +201500000093 for a family already stored as
-- 01500000093 used to create a second account; both spellings now
-- collapse to one value before the write, and uix_users_mobile_active
-- sees the duplicate it was built to see.
--
-- ON EVERY TABLE THAT HOLDS A PERSON'S MOBILE, NOT ONLY THE ONES WITH A
-- SCREEN TODAY. "No path writes it" is a property of the router, and the
-- router changes faster than the schema - the same reasoning that put
-- the centre guard on publish_assessment before it had a route.
--
-- WHY IT DOES NOTHING WHEN THE VALUE IS UNCHANGED: the two legacy rows
-- named at the top of this file cannot be canonicalised. An UPDATE that
-- touches a guardian's ADDRESS must not fail because their number was
-- typed wrong in 2026 - the edit that fixes it is the edit that has to
-- satisfy this.
--
-- TRIGGER ORDER IS ALPHABETICAL AND THAT IS LOAD-BEARING:
-- trg_guardians_identity_format fires before trg_guardians_mobile_canon
-- (i < m), so the typed value is held to MOBILE_PATTERN first and
-- canonicalised second. Rename either one and the pattern would be
-- applied to a value that had already been rewritten.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_canonical_mobile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  col   text := TG_ARGV[0];
  raw   text;
  canon text;
  cc    text;
BEGIN
  raw := to_jsonb(NEW) ->> col;
  IF raw IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' AND raw IS NOT DISTINCT FROM (to_jsonb(OLD) ->> col) THEN
    RETURN NEW;
  END IF;

  -- The centre's own country is what a national number is read against.
  -- It is a column on hbh.centers, not a constant here: the day this
  -- schema serves a centre in Jeddah, nothing in this function is the
  -- thing that has to change.
  SELECT c.country_code INTO cc
    FROM hbh.centers c WHERE c.center_id = NEW.center_id;

  canon := hbh.canonical_mobile(raw, cc);
  IF canon IS NULL THEN
    RETURN NEW;
  END IF;

  NEW := jsonb_populate_record(NEW, jsonb_build_object(col, canon));
  RETURN NEW;
END
$fn$;

COMMENT ON FUNCTION hbh.trg_canonical_mobile() IS
  'Rewrites the mobile column named in TG_ARGV[0] to E.164 before the write. Attached to every table holding a person''s mobile.';

DROP TRIGGER IF EXISTS trg_guardians_mobile_canon ON hbh.guardians;
CREATE TRIGGER trg_guardians_mobile_canon
  BEFORE INSERT OR UPDATE ON hbh.guardians
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_mobile('mobile');

DROP TRIGGER IF EXISTS trg_users_mobile_canon ON hbh.users;
CREATE TRIGGER trg_users_mobile_canon
  BEFORE INSERT OR UPDATE ON hbh.users
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_mobile('mobile');

DROP TRIGGER IF EXISTS trg_therapists_mobile_canon ON hbh.therapists;
CREATE TRIGGER trg_therapists_mobile_canon
  BEFORE INSERT OR UPDATE ON hbh.therapists
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_mobile('mobile');

DROP TRIGGER IF EXISTS trg_enr_mobile_canon ON hbh.enrolment_applications;
CREATE TRIGGER trg_enr_mobile_canon
  BEFORE INSERT OR UPDATE ON hbh.enrolment_applications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_canonical_mobile('parent_mobile');

-- =====================================================================
-- 5. THE STORED SHAPE, SAID BY THE SCHEMA RATHER THAN ONLY BY A TRIGGER
--
-- NOT VALID on purpose, and it is the reason this is a CHECK at all. The
-- two legacy rows cannot be converted and must not be invented; a
-- validating constraint would refuse to be created and take the whole
-- migration with it. NOT VALID binds every insert and every update from
-- this moment while leaving the past alone - which is exactly the truth
-- of the situation, written where the next person reads it instead of in
-- a comment.
--
-- VALIDATE CONSTRAINT is the one-line migration to write on the day
-- those two rows are corrected.
--
-- THIS COMES BEFORE THE BACKFILL, AND IT HAS TO. ALTER TABLE after a
-- large UPDATE in the same transaction fails with "cannot ALTER TABLE
-- because it has pending trigger events" - the row triggers the UPDATE
-- queued have not fired yet, and ALTER will not step over them. Written
-- the other way round first, and that is what it said.
--
-- Nothing is lost by the order: NOT VALID does not scan what is already
-- there, and what the backfill writes below is E.164 by construction, so
-- these constraints hold it to exactly what it produces.
-- =====================================================================
ALTER TABLE hbh.guardians
  ADD CONSTRAINT ck_guardians_mobile_e164
  CHECK (mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.users
  ADD CONSTRAINT ck_users_mobile_e164
  CHECK (mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.therapists
  ADD CONSTRAINT ck_therapists_mobile_e164
  CHECK (mobile IS NULL OR mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

ALTER TABLE hbh.enrolment_applications
  ADD CONSTRAINT ck_enr_mobile_e164
  CHECK (parent_mobile ~ '^\+[1-9][0-9]{7,14}$') NOT VALID;

-- =====================================================================
-- 6. THE BACKFILL
--
-- Only rows matching the pattern that was ENFORCED until this migration
-- are converted. Everything else is a number nobody can vouch for, and
-- there is no safe conversion of one - see the header.
--
-- hbh.canonical_mobile is called rather than string concatenation so
-- that this conversion and every future write go through the same code.
-- A backfill that builds the value its own way is a second definition of
-- correct, and the two drift.
--
-- ORDER MATTERS AND IT IS NOT ALPHABETICAL. hbh.users.mobile is a copy
-- of hbh.guardians.mobile made by grant_portal_access, and
-- enrolment_applications.parent_mobile is matched against
-- guardians.mobile by string equality in convert_enrolment (0018, line
-- 311). Any moment where one is converted and another is not is a moment
-- those comparisons silently stop matching - so all of them land in this
-- one transaction, which is what --single-transaction already
-- guarantees for a migration.
-- =====================================================================
UPDATE hbh.guardians g
   SET mobile = hbh.canonical_mobile(g.mobile, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = g.center_id
   AND g.mobile ~ '^01[0-9]{9}$';

UPDATE hbh.users u
   SET mobile = hbh.canonical_mobile(u.mobile, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = u.center_id
   AND u.mobile ~ '^01[0-9]{9}$';

UPDATE hbh.therapists t
   SET mobile = hbh.canonical_mobile(t.mobile, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = t.center_id
   AND t.mobile ~ '^01[0-9]{9}$';

UPDATE hbh.enrolment_applications a
   SET parent_mobile = hbh.canonical_mobile(a.parent_mobile, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = a.center_id
   AND a.parent_mobile ~ '^01[0-9]{9}$';

-- otp_codes holds the number a live code was issued to. A parent holding
-- an unexpired code while this lands would otherwise fail to verify it,
-- burn an attempt, and be told the code was wrong. It is a credential
-- table with no canonicalising trigger by design - nothing types into
-- it - so it is converted directly.
UPDATE hbh.otp_codes o
   SET mobile = hbh.canonical_mobile(o.mobile, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = o.center_id
   AND o.mobile ~ '^01[0-9]{9}$';

-- sms_outbox.destination is what the worker dials. Its own comment says
-- the provider shape is produced at the boundary and never written back
-- - that stays true, and what changes is that the stored form is now
-- already international, so the boundary has nothing left to convert.
UPDATE hbh.sms_outbox s
   SET destination = hbh.canonical_mobile(s.destination, c.country_code)
  FROM hbh.centers c
 WHERE c.center_id = s.center_id
   AND s.destination ~ '^01[0-9]{9}$';

-- =====================================================================
-- 7. SIGN-IN CANONICALISES ITS OWN ARGUMENT
--
-- This is what lets the API lag. Both functions are otherwise unchanged
-- from 0095 / 0097 and the bodies below are those bodies.
--
-- WHAT THE EXCEPTION BLOCK CATCHES, AND WHY IT IS NOT `WHEN OTHERS`:
-- CLAUDE.md has a paid-for lesson about a handler wrapping a whole
-- function body and swallowing the function's own errors. This one wraps
-- THE SINGLE CALL THAT CAN FAIL and names the two codes it expects. A
-- number that cannot be canonicalised is certainly not registered, and
-- NOT_REGISTERED is what this function already answers for a number it
-- does not know - it fails closed and tells the caller nothing it did
-- not already know.
--
-- request_otp GAINS AN OUT COLUMN AND THAT IS BACKWARD COMPATIBLE. The
-- API selects its columns by name:
--   SELECT ok, reason, code, expires_at, center_id FROM hbh.request_otp($1)
-- so a build that has never heard of mobile_e164 keeps working. The next
-- build selects it and sends the code to the canonical number instead of
-- to whatever shape the parent happened to type.
-- =====================================================================
DROP FUNCTION IF EXISTS hbh.request_otp(text);

CREATE FUNCTION hbh.request_otp(p_mobile text)
RETURNS TABLE(ok boolean, reason text, code text,
              expires_at timestamptz, center_id integer, mobile_e164 text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user    hbh.users%ROWTYPE;
  l_len     integer;
  l_ttl     integer;
  l_resend  integer;
  l_last    timestamptz;
  l_code    text;
  l_fixed   text;
  l_expires timestamptz;
  l_appl    text;
BEGIN
  BEGIN
    p_mobile := hbh.canonical_mobile(p_mobile, NULL);
  EXCEPTION
    WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
      RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text,
                          NULL::timestamptz, NULL::integer, NULL::text;
      RETURN;
  END;

  IF p_mobile IS NULL THEN
    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text,
                        NULL::timestamptz, NULL::integer, NULL::text;
    RETURN;
  END IF;

  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    -- No account. Before answering "we do not know you", ask whether
    -- they are already waiting on us.
    SELECT a.status INTO l_appl
    FROM   hbh.enrolment_applications a
    WHERE  a.parent_mobile = p_mobile AND a.active_flg
    ORDER  BY a.application_id DESC
    LIMIT  1;

    IF l_appl IN ('NEW', 'CONTACTED', 'ASSESSMENT_BOOKED') THEN
      RETURN QUERY SELECT false, 'ENROLMENT_PENDING', NULL::text,
                          NULL::timestamptz, NULL::integer, NULL::text;
      RETURN;
    END IF;

    RETURN QUERY SELECT false, 'NOT_REGISTERED', NULL::text,
                        NULL::timestamptz, NULL::integer, NULL::text;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    -- Still withheld, and THE CENTRE IS WITHHELD TOO. Returning it for a
    -- locked account would let a caller distinguish "locked" from
    -- "unknown" by whether a number came back, which is the fact the
    -- handler is deliberately collapsing.
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::text,
                        NULL::timestamptz, NULL::integer, NULL::text;
    RETURN;
  END IF;

  l_len    := hbh.param(l_user.center_id, 'OTP_LENGTH',         '6')::integer;
  l_ttl    := hbh.param(l_user.center_id, 'OTP_TTL_MINUTES',   '15')::integer;
  l_resend := hbh.param(l_user.center_id, 'OTP_RESEND_SECONDS','60')::integer;

  SELECT max(o.issued_at) INTO l_last
  FROM   hbh.otp_codes o
  WHERE  o.user_id = l_user.user_id AND o.purpose = 'LOGIN';

  IF l_last IS NOT NULL AND l_last > now() - make_interval(secs => l_resend) THEN
    RETURN QUERY SELECT false, 'RESEND_TOO_SOON', NULL::text,
                        NULL::timestamptz, NULL::integer, NULL::text;
    RETURN;
  END IF;

  -- A new code invalidates any code still outstanding, so two codes are
  -- never live for one account at the same time.
  UPDATE hbh.otp_codes o
     SET consumed_at = now()
   WHERE o.user_id = l_user.user_id AND o.consumed_at IS NULL;

  -- The default is the empty string, which is what makes absence mean
  -- random rather than meaning something nobody wrote down.
  l_fixed := hbh.param(l_user.center_id, 'OTP_FIXED_CODE', '');

  IF l_fixed ~ ('^[0-9]{' || l_len || '}$') THEN
    l_code := l_fixed;
  ELSE
    l_code := hbh.random_digits(l_len);
  END IF;

  l_expires := now() + make_interval(mins => l_ttl);

  -- Only the hash is stored. The plaintext leaves in the return value,
  -- goes to the SMS gateway, and is never written anywhere.
  INSERT INTO hbh.otp_codes (center_id, user_id, mobile, code_hash, purpose, expires_at)
  VALUES (l_user.center_id, l_user.user_id, p_mobile,
          public.crypt(l_code, public.gen_salt('bf', 8)), 'LOGIN', l_expires);

  RETURN QUERY SELECT true, 'OK', l_code, l_expires, l_user.center_id, p_mobile;
END
$fn$;

COMMENT ON FUNCTION hbh.request_otp(text) IS
  'Issues a login code. Canonicalises the mobile first, so a caller may send either the national or the international form. mobile_e164 is the number the code should be delivered to.';

REVOKE ALL ON FUNCTION hbh.request_otp(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_otp(text) TO hbh_app;

CREATE OR REPLACE FUNCTION hbh.verify_otp(p_mobile text, p_code text)
RETURNS TABLE(ok boolean, reason text, user_id integer, attempts_left integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_otp  hbh.otp_codes%ROWTYPE;
  l_max  integer;
BEGIN
  BEGIN
    p_mobile := hbh.canonical_mobile(p_mobile, NULL);
  EXCEPTION
    WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
      RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
      RETURN;
  END;

  IF p_mobile IS NULL THEN
    RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  SELECT * INTO l_user
  FROM   hbh.users u
  WHERE  u.mobile = p_mobile AND u.active_flg
  ORDER  BY u.user_id
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_user.status <> 'ACTIVE' THEN
    RETURN QUERY SELECT false, 'USER_LOCKED', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  l_max := hbh.param(l_user.center_id, 'OTP_MAX_ATTEMPTS', '5')::integer;

  -- FOR UPDATE: two requests arriving together must not each see four
  -- attempts used and each allow a fifth.
  SELECT * INTO l_otp
  FROM   hbh.otp_codes o
  WHERE  o.user_id = l_user.user_id
  AND    o.consumed_at IS NULL
  ORDER  BY o.issued_at DESC
  LIMIT  1
  FOR    UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_PENDING_CODE', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_otp.expires_at <= now() THEN
    UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'EXPIRED', NULL::integer, NULL::integer;
    RETURN;
  END IF;

  IF l_otp.attempts >= l_max THEN
    UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
    UPDATE hbh.users SET status = 'LOCKED' WHERE hbh.users.user_id = l_user.user_id;
    RETURN QUERY SELECT false, 'TOO_MANY_ATTEMPTS', NULL::integer, 0;
    RETURN;
  END IF;

  -- FROM 0097. A NULL or blank code is a wrong code and it COSTS AN
  -- ATTEMPT like any other. Refusing it as a validation error instead
  -- would leave an unlimited supply of free guesses to whoever found
  -- that path, and public.crypt(NULL, hash) is NULL, so `hash <> NULL`
  -- is UNKNOWN rather than false and the "wrong code" branch is skipped
  -- entirely. IS DISTINCT FROM is what makes the comparison decide.
  IF p_code IS NULL OR btrim(p_code) = ''
     OR l_otp.code_hash IS DISTINCT FROM public.crypt(p_code, l_otp.code_hash) THEN
    UPDATE hbh.otp_codes SET attempts = attempts + 1 WHERE otp_id = l_otp.otp_id;
    RETURN QUERY SELECT false, 'WRONG_CODE', NULL::integer,
                        greatest(l_max - (l_otp.attempts + 1), 0);
    RETURN;
  END IF;

  UPDATE hbh.otp_codes SET consumed_at = now() WHERE otp_id = l_otp.otp_id;
  RETURN QUERY SELECT true, 'OK', l_user.user_id, NULL::integer;
END
$fn$;

COMMENT ON FUNCTION hbh.verify_otp(text, text) IS
  'Checks and consumes a login code. Canonicalises the mobile first, so a caller may send either the national or the international form.';

REVOKE ALL ON FUNCTION hbh.verify_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.verify_otp(text, text) TO hbh_app;

-- =====================================================================
-- 8. SAY OUT LOUD WHAT WAS LEFT BEHIND
--
-- A migration that converts most of a column and says nothing about the
-- rest leaves somebody to discover the remainder as a constraint
-- violation months later. This names them now, with their keys, in the
-- output of the migrate run.
-- =====================================================================
DO $report$
DECLARE
  r record;
  n integer := 0;
BEGIN
  FOR r IN
    SELECT 'guardians.guardian_id' AS where_, g.guardian_id::text AS id
      FROM hbh.guardians g WHERE g.mobile !~ '^\+[1-9][0-9]{7,14}$'
    UNION ALL
    SELECT 'users.user_id', u.user_id::text
      FROM hbh.users u
     WHERE u.mobile IS NOT NULL AND u.mobile !~ '^\+[1-9][0-9]{7,14}$'
    UNION ALL
    SELECT 'therapists.therapist_id', t.therapist_id::text
      FROM hbh.therapists t
     WHERE t.mobile IS NOT NULL AND t.mobile !~ '^\+[1-9][0-9]{7,14}$'
    UNION ALL
    SELECT 'enrolment_applications.application_id', a.application_id::text
      FROM hbh.enrolment_applications a
     WHERE a.parent_mobile !~ '^\+[1-9][0-9]{7,14}$'
  LOOP
    n := n + 1;
    RAISE WARNING '0112: not converted, number is not a valid national mobile: % = %',
      r.where_, r.id;
  END LOOP;

  IF n = 0 THEN
    RAISE NOTICE '0112: every stored mobile is E.164. The NOT VALID checks can be validated.';
  ELSE
    RAISE NOTICE '0112: % row(s) left in their original form - see the warnings above. They are unreachable by SMS today and were unreachable before this migration too.', n;
  END IF;
END
$report$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0112');
