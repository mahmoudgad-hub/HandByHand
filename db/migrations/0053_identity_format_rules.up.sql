-- =====================================================================
-- 0053 - the Egyptian mobile and national id rules, enforced where
--        every path has to pass through them
--
-- WHAT WAS WRONG
-- sys_params has carried MOBILE_PATTERN = '^01[0-9]{9}$' and
-- NATIONAL_ID_LENGTH = '14' since the reference seed. Only ONE caller
-- ever read the first - api/internal/http/auth_handlers.go, on the two
-- OTP endpoints - and NOTHING at all read the second. So the rule held
-- on the door a family signs in through, and nowhere else.
--
-- The consequence was demonstrated through the console's own screen:
-- a guardian was created with mobile '999999' and national id '12',
-- accepted with 201 and no complaint. The same number on
-- POST /api/v1/auth/otp/request answers 400 {"mobile":"FORMAT"}.
--
-- That asymmetry is worse than either rule being absent. Reception
-- records a number the system will refuse later; the family never gets
-- a code; nothing on any screen says why; and the centre goes looking
-- at the family's handset. hbh.guardians row 668 is that defect on this
-- database already - mobile '0100000', inserted by dev_admin from this
-- screen on 2026-09-03.
--
-- WHY HERE AND NOT IN GO
-- CLAUDE.md rule 2. A check in a handler is a second copy of a rule,
-- and the weaker copy is the one that decides: the CRUD path would have
-- needed its own, the intake path a third, and a psql session none at
-- all. One trigger answers for every caller that can reach the row.
--
-- WHAT IS DELIBERATELY NOT COVERED
--   therapists.mobile - contact information, not a key. Staff sign in
--     with a password; no code is ever sent to it. Refusing a landline
--     or a number in another country would reject a real member of
--     staff to protect nothing.
--   enrolment_requests.mobile - a stranger's first message to the
--     centre. Reception rings it by hand. Refusing the application
--     because the digits look unusual loses the family and gains no
--     correctness: nothing authenticates against that row.
--
-- The line is: this rule guards the numbers the SYSTEM ITSELF will
-- later use to reach or identify a person.
--
-- NO DEFAULT WHEN THE PARAMETER IS MISSING. A fallback pattern written
-- here would be a business value in code wearing a disguise, and the
-- disguise is the dangerous part - it would quietly accept the wrong
-- shape on a database whose seed had not run. Missing parameter,
-- refused write. This is the same decision, for the same reason, as
-- api/internal/store/params.go:79.
--
-- VALIDATED ON CHANGE, NOT ON EVERY UPDATE. A row that predates this
-- migration stays editable in its other columns; only touching the
-- offending value itself has to satisfy the rule. Refusing every write
-- to row 668 would push somebody towards deleting it, and a row deleted
-- to unblock a rule takes its history with it.
--
-- BEFORE, so this fires ahead of the RLS WITH CHECK - a caller with no
-- permission AND a malformed number is told about the number. Same
-- ordering as every other business rule in this schema; the permission
-- refusal is still there, one correction later.
--
-- HB170/HB171: HB161 was the highest code in the schema, so this starts
-- a group of its own rather than filling the gap at HB062. A number
-- reused reads confidently wrong.
--
-- ORDER OF DEPLOYMENT: THE API GOES FIRST.
-- api/internal/store/pgerr.go has to know HB170 and HB171, or
-- crud_handlers.go falls through to its `default` and answers 500 with
-- the cause in the log. Applied ahead of that build, this migration
-- turns a clean "the format is wrong, here is the field" into "an
-- unexpected error occurred" - which is the message a person at the desk
-- reads as "the system is broken" rather than "fix the number". Seen,
-- exactly so, while this was being verified: the schema had the trigger
-- and the running container did not.
-- =====================================================================

\set ON_ERROR_STOP on

-- to_jsonb(NEW) reads the two columns by name, so one function serves
-- both tables. Do NOT attach this to a table holding a bytea: that call
-- copies the whole row, and the attachments trigger exists precisely
-- because to_jsonb on a file column is not free.
CREATE OR REPLACE FUNCTION hbh.guard_identity_format()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  new_row jsonb := to_jsonb(NEW);
  old_row jsonb;
  pattern text;
  want_len text;
  mobile  text;
  nid     text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    old_row := to_jsonb(OLD);
  END IF;

  -- ---------------------------------------------------------------
  -- Mobile
  -- ---------------------------------------------------------------
  IF new_row ? 'mobile' THEN
    mobile := new_row ->> 'mobile';
    IF old_row IS NULL OR mobile IS DISTINCT FROM (old_row ->> 'mobile') THEN
      pattern := hbh.param(NEW.center_id, 'MOBILE_PATTERN', NULL);
      IF pattern IS NULL OR pattern = '' THEN
        RAISE EXCEPTION 'sys_params.MOBILE_PATTERN is not set'
          USING ERRCODE = 'HB172',
                HINT = 'run scripts/db.sh migrate to load the reference seed';
      END IF;
      IF mobile IS NULL OR mobile !~ pattern THEN
        -- The value is not in the message. This text reaches a log an
        -- operator reads, and a mobile number is personal data.
        RAISE EXCEPTION 'mobile does not match the centre''s accepted format'
          USING ERRCODE = 'HB170',
                HINT = 'sys_params.MOBILE_PATTERN decides the shape';
      END IF;
    END IF;
  END IF;

  -- ---------------------------------------------------------------
  -- National id
  --
  -- NULL is absence, not a value: "not known yet" is the ordinary state
  -- for a small child in Egypt, and the partial unique index on this
  -- column exists for exactly that reason. Only a number that is
  -- actually there has to be the right length.
  -- ---------------------------------------------------------------
  IF new_row ? 'national_id' THEN
    nid := new_row ->> 'national_id';
    IF nid IS NOT NULL
       AND (old_row IS NULL OR nid IS DISTINCT FROM (old_row ->> 'national_id')) THEN
      want_len := hbh.param(NEW.center_id, 'NATIONAL_ID_LENGTH', NULL);
      IF want_len IS NULL OR want_len !~ '^[0-9]+$' THEN
        RAISE EXCEPTION 'sys_params.NATIONAL_ID_LENGTH is not set to a number'
          USING ERRCODE = 'HB172',
                HINT = 'run scripts/db.sh migrate to load the reference seed';
      END IF;
      IF nid !~ '^[0-9]+$' OR length(nid) <> want_len::int THEN
        RAISE EXCEPTION 'national id is not % digits', want_len
          USING ERRCODE = 'HB171',
                HINT = 'sys_params.NATIONAL_ID_LENGTH decides the length';
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END
$fn$;

COMMENT ON FUNCTION hbh.guard_identity_format() IS
  'Applies sys_params MOBILE_PATTERN and NATIONAL_ID_LENGTH to the numbers the system itself uses to reach or identify a person. Raises HB170 / HB171 / HB172.';

DROP TRIGGER IF EXISTS trg_guardians_identity_format ON hbh.guardians;
CREATE TRIGGER trg_guardians_identity_format
  BEFORE INSERT OR UPDATE ON hbh.guardians
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_identity_format();

DROP TRIGGER IF EXISTS trg_children_identity_format ON hbh.children;
CREATE TRIGGER trg_children_identity_format
  BEFORE INSERT OR UPDATE ON hbh.children
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_identity_format();

INSERT INTO hbh.schema_migrations (version) VALUES ('0053');
