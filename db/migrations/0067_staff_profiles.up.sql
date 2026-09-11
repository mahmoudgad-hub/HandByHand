-- =====================================================================
-- 0067 - a member of staff's own record: identity number, address,
--        date of birth, photograph, and their documents
--
-- WHY A SEPARATE TABLE AND NOT COLUMNS ON hbh.users.
--
-- hbh.users is read on nearly every request in this service: resolving
-- who is calling, answering GET /me, drawing the user list, joining to
-- name an author in an audit row. Putting a home address and a national
-- identity number on that row would carry them into every one of those
-- reads - into query results, into logs that print a row, into the
-- console's user list - for people who had no reason to see them and no
-- idea they had.
--
-- A separate table means the sensitive fields are fetched only when
-- somebody asks for them, by a query that can be audited when they do.
-- That is the whole reason for the split; it is not tidiness.
--
-- A SEPARATE PERMISSION, for the same reason. USER.MANAGE is the
-- authority to decide who may open which screen. Reading a colleague's
-- national identity number and where they live is a different question
-- with a different answer, and folding it into USER.MANAGE would mean
-- that everybody who can grant a role can also read every employee's
-- papers. STAFF.PII is its own code, and it is granted in the seed to
-- CENTER_ADMIN and to nobody else.
--
-- AND EVERYONE MAY READ THEIR OWN. A person looking at their own record
-- needs no permission, which is both right and the thing that keeps
-- STAFF.PII from having to be handed out widely.
--
-- THE DOCUMENTS DO NOT GO WHERE THE MARKETING PHOTOGRAPHS GO.
--
-- /api/v1/site-media serves the public site's files with no
-- authentication, deliberately: they are bound for a page with no login
-- on it, and the name is a content hash nobody can guess. A scan of
-- somebody's identity card is the exact opposite of that, and putting
-- one in a directory served by an open route because the route already
-- existed is how a leak happens without anybody deciding anything.
--
-- So staff_documents.path names a file in a DIFFERENT directory, served
-- by an authenticated route. The column carries a path only - the bytes
-- are never in the database, for the same reason as everywhere else
-- here: they would land in every pg_dump.
--
-- NULL ON national_id IS ABSENCE, NOT A VALUE, and the partial unique
-- index says so. Two members of staff whose number has not been
-- recorded yet are not duplicates of each other - the defect that
-- reached production in the Oracle system, in a centre where many
-- people did not have the number to hand.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE hbh.staff_profiles (
  profile_id  integer     GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  -- One profile per account, which is what UNIQUE (user_id) enforces.
  user_id     integer     NOT NULL,

  national_id text,
  birth_date  date,
  address_ar  text,
  -- Relative to the staff media directory, never to the public one.
  photo_path  text,

  active_flg  boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at  timestamptz,
  updated_by  text,

  CONSTRAINT pk_staff_profiles PRIMARY KEY (profile_id),
  CONSTRAINT uq_staff_profiles_user UNIQUE (user_id),
  CONSTRAINT fk_sp_center FOREIGN KEY (center_id) REFERENCES hbh.centers(center_id),
  CONSTRAINT fk_sp_user   FOREIGN KEY (user_id)   REFERENCES hbh.users(user_id),

  -- A birth date in the future is a typo, and one before 1900 is a
  -- different typo. Neither is a business rule worth a parameter.
  CONSTRAINT ck_sp_birth CHECK (birth_date IS NULL
                                OR (birth_date > DATE '1900-01-01'
                                    AND birth_date < current_date)),
  CONSTRAINT ck_sp_address CHECK (address_ar IS NULL OR length(address_ar) <= 400),
  -- Local paths only, exactly as on the site's media.
  CONSTRAINT ck_sp_photo_local CHECK (
    photo_path IS NULL
    OR (photo_path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
        AND photo_path !~ '^//'
        AND position('..' in photo_path) = 0))
);

-- Absence is not a duplicate. See the note at the top.
CREATE UNIQUE INDEX uix_staff_profiles_national
  ON hbh.staff_profiles (center_id, national_id)
  WHERE national_id IS NOT NULL;

CREATE INDEX ix_sp_center ON hbh.staff_profiles (center_id);

-- The centre's own format rules, from sys_params. The same trigger the
-- guardians and children carry - one definition of "a national id is
-- fourteen digits", not a third copy of it.
CREATE TRIGGER trg_staff_profiles_identity_format
  BEFORE INSERT OR UPDATE ON hbh.staff_profiles
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_identity_format();

CREATE TRIGGER trg_staff_profiles_touch
  BEFORE UPDATE ON hbh.staff_profiles
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_staff_profiles_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.staff_profiles
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('profile_id');

-- ---------------------------------------------------------------------
-- The documents. A qualification certificate, a copy of an identity
-- card, a contract.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.staff_documents (
  document_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  user_id     integer     NOT NULL,

  kind        text        NOT NULL,
  path        text        NOT NULL,
  title_ar    text,
  -- What the file is, in the centre's own words. Deliberately not
  -- "whose": the row already says whose.
  note_ar     text,
  mime_type   text,
  size_bytes  bigint,

  active_flg  boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at  timestamptz,
  updated_by  text,

  CONSTRAINT pk_staff_documents PRIMARY KEY (document_id),
  CONSTRAINT fk_sd_center FOREIGN KEY (center_id) REFERENCES hbh.centers(center_id),
  CONSTRAINT fk_sd_user   FOREIGN KEY (user_id)   REFERENCES hbh.users(user_id),
  CONSTRAINT ck_sd_kind CHECK (kind IN ('ID', 'QUALIFICATION', 'CONTRACT', 'OTHER')),
  CONSTRAINT ck_sd_local CHECK (
    path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
    AND path !~ '^//'
    AND position('..' in path) = 0)
);

CREATE INDEX ix_sd_user   ON hbh.staff_documents (user_id, kind, document_id);
CREATE INDEX ix_sd_center ON hbh.staff_documents (center_id);

CREATE TRIGGER trg_staff_documents_touch
  BEFORE UPDATE ON hbh.staff_documents
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_staff_documents_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.staff_documents
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('document_id');

-- ---------------------------------------------------------------------
-- Who may see any of it.
--
-- Two ways in and no third: STAFF.PII, or it is your own record. The
-- second is what keeps the first from having to be given to everybody
-- who might ever need to check their own date of birth.
--
-- The archived-row policy from 0056's lesson is included from the
-- start: without it, archiving a row makes the UPDATE that archives it
-- violate the read policy on its own new row.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.staff_profiles  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.staff_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_sp_select ON hbh.staff_profiles
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()));

CREATE POLICY p_sp_insert ON hbh.staff_profiles
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()));

CREATE POLICY p_sp_update ON hbh.staff_profiles
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_sd_select ON hbh.staff_documents
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()));

CREATE POLICY p_sd_insert ON hbh.staff_documents
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()));

CREATE POLICY p_sd_update ON hbh.staff_documents
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND (hbh.has_permission('STAFF.PII') OR user_id = hbh.current_user_id()))
  WITH CHECK (center_id = hbh.current_center_id());

-- No DELETE grant, here as everywhere.
GRANT SELECT, INSERT, UPDATE ON hbh.staff_profiles  TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.staff_documents TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

COMMENT ON TABLE hbh.staff_profiles IS
  'Personal data about a member of staff. Behind STAFF.PII, or your own row.';
COMMENT ON TABLE hbh.staff_documents IS
  'Scanned documents. Paths only; the files are NOT in the public media directory.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0067');
