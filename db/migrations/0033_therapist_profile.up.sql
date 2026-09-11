-- =====================================================================
-- Hand By Hand (new) - migration 0033: the therapist's profile
--
-- A family choosing an appointment sees a name and a title and nothing
-- else. This is what the centre may say about the person who will sit
-- with their child: a few words in their own voice, the languages they
-- work in, what they trained in, what they are certified to do.
--
-- BEHIND THE LOGIN, ALWAYS. The owner decided this: a guardian reads
-- the profile while signed in, not before they have an account. So no
-- unauthenticated read enters this schema - enrolment stays the only
-- anonymous path and it is write-only. Every policy below still opens
-- with hbh.current_center_id() IS NOT NULL, because a policy that
-- admits a row on any other ground admits it to a connection with no
-- identity at all.
--
-- =====================================================================
-- THE FOUR DECISIONS THAT COULD NOT BE MADE LATER
-- =====================================================================
--
-- 1. is_image_public DEFAULTS TO false, PER CERTIFICATE.
--
--    An Egyptian certificate, photographed, usually carries a national
--    ID number, a date of birth and a signature. Publishing that to
--    every family at the centre is publishing an employee's identity
--    documents, which nobody asked for when they said "put my
--    certificate on the page". The TEXT - what it is, who issued it,
--    which year - is what reassures a parent, and it is always shown.
--
--    The default cannot be fixed afterwards: a column defaulting to
--    true, corrected next month, means rows that were already published
--    and images that already left. Same shape as can_view_live_flg.
--
-- 2. PUBLISHING NEEDS THE THERAPIST'S OWN RECORDED CONSENT.
--
--    This profile leaves the centre and reaches families. A person's
--    photograph and qualifications are theirs, and an administrator
--    holding a permission is not the same as the person agreeing.
--
--    RECORDED means a name, an instant and the version of the text they
--    agreed to - consent_by, consent_at, consent_text_version - not a
--    boolean. A boolean says somebody once clicked; these three say who
--    agreed to what and when, which is the only form that answers a
--    question asked a year later.
--
--    A NOTE ON WHERE THIS LIVES. hbh.consents was the obvious home and
--    it does not fit: guardian_id is NOT NULL there, and both check
--    constraints are shaped around a family consenting about a child.
--    A therapist consenting about themselves is a different subject,
--    and forcing it in would have meant widening a table that means
--    something specific until it meant nothing.
--
-- 3. THE ADMIN OVERRIDE IS PINNED TO user_type, NOT TO A PERMISSION.
--
--    A therapist edits their own profile; the centre edits anybody's.
--    Two different justifications, so two different branches - and the
--    second is hbh.current_user_is_staff(), not a permission.
--
--    This is the can_close_session defect, avoided rather than
--    rediscovered: CHILD.VIEW_ALL and SESSION.COMPLETE both sit in
--    THERAPIST for good reasons, and together they let any therapist
--    close any colleague's session. A profile gate resting on a
--    permission would let any therapist rewrite a colleague's page.
--
-- 4. THE YEAR IS STORED, THE EXPERIENCE IS DERIVED.
--
--    practice_since_year, never years_of_experience. A stored count
--    goes stale every January, silently, and nothing in the system
--    knows it has. Same reason a child's age is derived from
--    birth_date.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0033') THEN
    RAISE EXCEPTION 'migration 0033 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0031') THEN
    RAISE EXCEPTION 'migration 0031 must be applied first - the profile gate uses hbh.current_user_is_staff()';
  END IF;
END
$guard$;

-- =====================================================================
-- THE PROFILE ITSELF, on hbh.therapists
-- =====================================================================
ALTER TABLE hbh.therapists
  ADD COLUMN bio_ar                text,
  ADD COLUMN practice_since_year   smallint,
  ADD COLUMN age_from_mon          smallint,
  ADD COLUMN age_to_mon            smallint,
  ADD COLUMN profile_status        text NOT NULL DEFAULT 'DRAFT',
  ADD COLUMN published_at          timestamptz,
  ADD COLUMN published_by          integer REFERENCES hbh.users(user_id),
  ADD COLUMN consent_at            timestamptz,
  ADD COLUMN consent_by            integer REFERENCES hbh.users(user_id),
  ADD COLUMN consent_text_version  text;

ALTER TABLE hbh.therapists
  ADD CONSTRAINT ck_th_profile_status
    CHECK (profile_status IN ('DRAFT', 'PUBLISHED', 'WITHDRAWN')),
  -- A published profile has a publisher and an instant, or it is not
  -- published. The three move together or the row is lying.
  ADD CONSTRAINT ck_th_published
    CHECK ((profile_status = 'PUBLISHED') = (published_at IS NOT NULL)
           AND (published_at IS NULL) = (published_by IS NULL)),
  -- Consent is the same shape: all three or none. A consent_at with no
  -- consent_by records that somebody agreed and not who.
  ADD CONSTRAINT ck_th_consent
    CHECK ((consent_at IS NULL) = (consent_by IS NULL)
           AND (consent_at IS NULL) = (consent_text_version IS NULL)),
  -- A year somebody could type as 20 or 202. The lower bound is a
  -- working life, not a birthday.
  ADD CONSTRAINT ck_th_practice_year
    CHECK (practice_since_year IS NULL
           OR practice_since_year BETWEEN 1950
              AND extract(year FROM now() AT TIME ZONE 'UTC')::smallint),
  -- Months, not years: this centre works with children under three, and
  -- "from 1 year" cannot say eighteen months.
  ADD CONSTRAINT ck_th_age_range
    CHECK (age_from_mon IS NULL OR age_to_mon IS NULL OR age_from_mon <= age_to_mon),
  ADD CONSTRAINT ck_th_age_bounds
    CHECK ((age_from_mon IS NULL OR age_from_mon BETWEEN 0 AND 300)
           AND (age_to_mon IS NULL OR age_to_mon BETWEEN 0 AND 300));

COMMENT ON COLUMN hbh.therapists.practice_since_year IS
  'The year they began practising. Experience is DERIVED from it and never stored: a stored count goes stale every January (0033).';
COMMENT ON COLUMN hbh.therapists.consent_text_version IS
  'Which version of the publication text they agreed to. A consent without it cannot answer what they agreed to (0033).';

-- =====================================================================
-- LANGUAGES
--
-- "Reads English" and "runs a session in English" are different facts,
-- and in a speech therapy centre the second is a clinical matching
-- criterion. They are separate columns because collapsing them would
-- match a family to a therapist who cannot treat their child.
-- =====================================================================
CREATE TABLE hbh.therapist_languages (
  therapist_id      integer     NOT NULL REFERENCES hbh.therapists(therapist_id),
  lang_code         text        NOT NULL,
  level_code        text        NOT NULL DEFAULT 'FLUENT',
  is_native_flg     boolean     NOT NULL DEFAULT false,
  runs_sessions_flg boolean     NOT NULL DEFAULT false,
  active_flg        boolean     NOT NULL DEFAULT true,
  deleted_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at        timestamptz,
  updated_by        text,
  CONSTRAINT pk_therapist_languages PRIMARY KEY (therapist_id, lang_code),
  CONSTRAINT ck_thl_level CHECK (level_code IN ('BASIC', 'GOOD', 'FLUENT', 'NATIVE')),
  CONSTRAINT ck_thl_lang  CHECK (lang_code ~ '^[a-z]{2,3}$')
);

-- At most one native language, among LIVE rows.
--
-- A partial UNIQUE index rather than a CHECK: a CHECK sees one row and
-- cannot count the others. And active_flg is in the predicate for the
-- reason migration 0032 spelled out - deletion here is soft, so an
-- archived row keeps its flag and would block every future one.
CREATE UNIQUE INDEX uix_thl_one_native
  ON hbh.therapist_languages (therapist_id)
  WHERE is_native_flg AND active_flg;

CREATE INDEX ix_thl_runs ON hbh.therapist_languages (lang_code)
  WHERE runs_sessions_flg AND active_flg;

-- =====================================================================
-- QUALIFICATIONS - text, always. No attachment, deliberately.
-- =====================================================================
CREATE TABLE hbh.therapist_qualifications (
  qualification_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id        integer     NOT NULL REFERENCES hbh.centers(center_id),
  therapist_id     integer     NOT NULL REFERENCES hbh.therapists(therapist_id),
  title_ar         text        NOT NULL,
  issuer_ar        text,
  year_awarded     smallint,
  sort_order       integer     NOT NULL DEFAULT 100,
  active_flg       boolean     NOT NULL DEFAULT true,
  deleted_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at       timestamptz,
  updated_by       text,
  CONSTRAINT pk_therapist_qualifications PRIMARY KEY (qualification_id),
  CONSTRAINT ck_thq_year CHECK (year_awarded IS NULL
    OR year_awarded BETWEEN 1950 AND extract(year FROM now() AT TIME ZONE 'UTC')::smallint)
);

CREATE INDEX ix_thq_therapist ON hbh.therapist_qualifications (therapist_id, sort_order);
CREATE INDEX ix_thq_center    ON hbh.therapist_qualifications (center_id);

-- =====================================================================
-- CERTIFICATES - the one that carries an image
-- =====================================================================
CREATE TABLE hbh.therapist_certificates (
  certificate_id  integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL REFERENCES hbh.centers(center_id),
  therapist_id    integer     NOT NULL REFERENCES hbh.therapists(therapist_id),
  title_ar        text        NOT NULL,
  issuer_ar       text,
  year_awarded    smallint,
  expires_on      date,
  -- The scan lives in hbh.attachments like every other file in this
  -- schema. A second attachment mechanism means a second publish guard,
  -- and the two would drift.
  attachment_id   integer     REFERENCES hbh.attachments(attachment_id),
  -- SEPARATE FROM WHETHER THERE IS AN IMAGE, and false until somebody
  -- says otherwise for THIS certificate. See decision 1 in the header.
  is_image_public boolean     NOT NULL DEFAULT false,
  -- A professional registration number. NULL here means "not recorded
  -- yet", which is ABSENCE and not a value - so the uniqueness below is
  -- a partial index and not NULLS NOT DISTINCT. Two unrecorded numbers
  -- are not a duplicate, and treating them as one is the defect that
  -- reached production in Oracle by refusing the SECOND child with no
  -- national ID.
  registration_no text,
  sort_order      integer     NOT NULL DEFAULT 100,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_therapist_certificates PRIMARY KEY (certificate_id),
  CONSTRAINT ck_thc_year CHECK (year_awarded IS NULL
    OR year_awarded BETWEEN 1950 AND extract(year FROM now() AT TIME ZONE 'UTC')::smallint),
  -- An image cannot be public when there is no image. Without this the
  -- flag can be set on a row with nothing behind it, and it then means
  -- something the moment a scan is attached.
  CONSTRAINT ck_thc_image_public CHECK (NOT is_image_public OR attachment_id IS NOT NULL)
);

CREATE UNIQUE INDEX uix_thc_registration
  ON hbh.therapist_certificates (center_id, registration_no)
  WHERE registration_no IS NOT NULL AND active_flg;

CREATE INDEX ix_thc_therapist  ON hbh.therapist_certificates (therapist_id, sort_order);
CREATE INDEX ix_thc_center     ON hbh.therapist_certificates (center_id);
CREATE INDEX ix_thc_attachment ON hbh.therapist_certificates (attachment_id);

-- =====================================================================
-- WHO MAY EDIT WHAT
-- =====================================================================

-- can_edit_therapist answers "may this caller change this profile", and
-- it is the ONE statement of that rule. It has two branches because
-- there are two justifications, and it never rests on a permission
-- alone for the second - see decision 3.
CREATE OR REPLACE FUNCTION hbh.can_edit_therapist(p_therapist_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT hbh.current_center_id() IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM hbh.therapists t
       WHERE  t.therapist_id = p_therapist_id
       AND    t.center_id = hbh.current_center_id()
       AND    (
              -- their own profile
              t.user_id = hbh.current_user_id()
              -- or the centre acting: STAFF, and holding the right
              OR (hbh.current_user_is_staff() AND hbh.has_permission('STAFF.MANAGE'))
              ));
$$;

COMMENT ON FUNCTION hbh.can_edit_therapist(integer) IS
  'Their own profile, or the centre''s if the caller is STAFF with STAFF.MANAGE. Pinned to user_type, not to a permission alone (0033).';

GRANT EXECUTE ON FUNCTION hbh.can_edit_therapist(integer) TO hbh_app;

-- publish_therapist_profile is the only way a profile becomes visible
-- to families, and it refuses without the therapist's own recorded
-- consent. A permission is not consent.
CREATE OR REPLACE FUNCTION hbh.publish_therapist_profile(p_therapist_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_row hbh.therapists%ROWTYPE;
BEGIN
  SELECT * INTO l_row FROM hbh.therapists
   WHERE therapist_id = p_therapist_id
     AND center_id = hbh.current_center_id()
     AND active_flg
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such therapist %', p_therapist_id USING ERRCODE = 'HB140';
  END IF;

  IF NOT hbh.can_edit_therapist(p_therapist_id) THEN
    RAISE EXCEPTION 'not permitted to publish this profile' USING ERRCODE = 'HB141';
  END IF;

  -- The check this function exists for.
  IF l_row.consent_at IS NULL THEN
    RAISE EXCEPTION 'therapist % has not consented to publication', p_therapist_id
      USING ERRCODE = 'HB142';
  END IF;

  IF l_row.profile_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'profile % is already published', p_therapist_id USING ERRCODE = 'HB143';
  END IF;

  UPDATE hbh.therapists
     SET profile_status = 'PUBLISHED',
         published_at   = now(),
         published_by   = hbh.current_user_id()
   WHERE therapist_id = p_therapist_id;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.publish_therapist_profile(integer) TO hbh_app;

-- record_therapist_consent is a SEPARATE act from publishing, and the
-- separation is the point: consenting and publishing on one call would
-- let the publisher supply the consent.
--
-- Only the therapist themselves may consent. Not the centre, not an
-- administrator, whatever they hold - a consent given on somebody's
-- behalf is not a consent.
CREATE OR REPLACE FUNCTION hbh.record_therapist_consent(
  p_therapist_id integer,
  p_text_version text DEFAULT 'v1')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_user integer := hbh.current_user_id();
BEGIN
  IF l_user IS NULL THEN
    RAISE EXCEPTION 'a consent needs somebody to give it' USING ERRCODE = 'HB144';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                  WHERE t.therapist_id = p_therapist_id
                  AND   t.center_id = hbh.current_center_id()
                  AND   t.user_id = l_user
                  AND   t.active_flg) THEN
    RAISE EXCEPTION 'only the therapist themselves may consent to publishing their profile'
      USING ERRCODE = 'HB144';
  END IF;

  UPDATE hbh.therapists
     SET consent_at = now(),
         consent_by = l_user,
         consent_text_version = p_text_version
   WHERE therapist_id = p_therapist_id;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.record_therapist_consent(integer, text) TO hbh_app;

-- Withdrawing consent takes the profile down with it, in one statement.
-- A consent that can be withdrawn while the page stays up is not a
-- consent, and leaving the two to be done separately means the second
-- gets forgotten.
CREATE OR REPLACE FUNCTION hbh.withdraw_therapist_consent(p_therapist_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_user integer := hbh.current_user_id();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.therapists t
                  WHERE t.therapist_id = p_therapist_id
                  AND   t.center_id = hbh.current_center_id()
                  AND   t.user_id = l_user) THEN
    RAISE EXCEPTION 'only the therapist themselves may withdraw their consent'
      USING ERRCODE = 'HB144';
  END IF;

  UPDATE hbh.therapists
     SET consent_at = NULL, consent_by = NULL, consent_text_version = NULL,
         profile_status = CASE WHEN profile_status = 'PUBLISHED' THEN 'WITHDRAWN'
                               ELSE profile_status END,
         published_at = NULL, published_by = NULL
   WHERE therapist_id = p_therapist_id;
END
$$;

GRANT EXECUTE ON FUNCTION hbh.withdraw_therapist_consent(integer) TO hbh_app;

-- =====================================================================
-- POLICIES
--
-- Every one opens with current_center_id() IS NOT NULL. A policy whose
-- first condition is anything else admits its rows to a connection that
-- has no identity at all.
-- =====================================================================
ALTER TABLE hbh.therapist_languages      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapist_qualifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.therapist_certificates   ENABLE ROW LEVEL SECURITY;

-- Read: anybody signed in at the centre, for a PUBLISHED profile; and
-- staff, and the therapist themselves, for any.
--
-- The published/draft split is the same ladder as a progress report: a
-- family reads the version the centre released, not the paragraph
-- somebody is editing at lunchtime.
CREATE POLICY p_thl_select ON hbh.therapist_languages
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND active_flg
         AND EXISTS (SELECT 1 FROM hbh.therapists t
                      WHERE t.therapist_id = therapist_languages.therapist_id
                      AND   t.center_id = hbh.current_center_id()
                      AND   (t.profile_status = 'PUBLISHED'
                             OR hbh.current_user_is_staff()
                             OR t.user_id = hbh.current_user_id())));

CREATE POLICY p_thq_select ON hbh.therapist_qualifications
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND EXISTS (SELECT 1 FROM hbh.therapists t
                      WHERE t.therapist_id = therapist_qualifications.therapist_id
                      AND   t.center_id = hbh.current_center_id()
                      AND   (t.profile_status = 'PUBLISHED'
                             OR hbh.current_user_is_staff()
                             OR t.user_id = hbh.current_user_id())));

CREATE POLICY p_thc_select ON hbh.therapist_certificates
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND EXISTS (SELECT 1 FROM hbh.therapists t
                      WHERE t.therapist_id = therapist_certificates.therapist_id
                      AND   t.center_id = hbh.current_center_id()
                      AND   (t.profile_status = 'PUBLISHED'
                             OR hbh.current_user_is_staff()
                             OR t.user_id = hbh.current_user_id())));

-- Write: whoever may edit the profile.
CREATE POLICY p_thl_write ON hbh.therapist_languages
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.can_edit_therapist(therapist_id));
CREATE POLICY p_thl_edit ON hbh.therapist_languages
  FOR UPDATE TO hbh_app
  USING (hbh.can_edit_therapist(therapist_id))
  WITH CHECK (hbh.can_edit_therapist(therapist_id));

CREATE POLICY p_thq_write ON hbh.therapist_qualifications
  FOR INSERT TO hbh_app
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id));
CREATE POLICY p_thq_edit ON hbh.therapist_qualifications
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id));

CREATE POLICY p_thc_write ON hbh.therapist_certificates
  FOR INSERT TO hbh_app
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id));
CREATE POLICY p_thc_edit ON hbh.therapist_certificates
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.can_edit_therapist(therapist_id));

-- No DELETE grant anywhere. Rule 3.
GRANT SELECT, INSERT, UPDATE ON hbh.therapist_languages      TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.therapist_qualifications TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.therapist_certificates   TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.therapist_qualifications_qualification_id_seq TO hbh_app;
GRANT USAGE, SELECT ON SEQUENCE hbh.therapist_certificates_certificate_id_seq     TO hbh_app;

-- =====================================================================
-- TRIGGERS
--
-- The audit ones are not optional: the phase-4 acceptance suite asserts
-- that EVERY table hbh_app may write has a change audit, and it would
-- go red on the next run without these. That check is why this is here
-- now rather than being discovered in a month.
-- =====================================================================
CREATE TRIGGER trg_thl_touch BEFORE UPDATE ON hbh.therapist_languages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_thl_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.therapist_languages
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

CREATE TRIGGER trg_thq_touch BEFORE UPDATE ON hbh.therapist_qualifications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_thq_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.therapist_qualifications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

CREATE TRIGGER trg_thc_touch BEFORE UPDATE ON hbh.therapist_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_thc_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.therapist_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

-- The profile status is a state machine, and this is its transition
-- guard. Editing profile_status by hand is how a page goes live without
-- the consent check ever running.
CREATE OR REPLACE FUNCTION hbh.trg_therapist_profile_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.profile_status IS DISTINCT FROM OLD.profile_status THEN
    IF NOT (
      (OLD.profile_status = 'DRAFT'     AND NEW.profile_status = 'PUBLISHED') OR
      (OLD.profile_status = 'PUBLISHED' AND NEW.profile_status IN ('WITHDRAWN', 'DRAFT')) OR
      (OLD.profile_status = 'WITHDRAWN' AND NEW.profile_status IN ('DRAFT', 'PUBLISHED'))
    ) THEN
      RAISE EXCEPTION 'a profile cannot go from % to %', OLD.profile_status, NEW.profile_status
        USING ERRCODE = 'HB145';
    END IF;

    -- Belt and braces on the decision this migration exists for: even a
    -- direct UPDATE that slips past the function cannot publish a
    -- profile nobody consented to.
    IF NEW.profile_status = 'PUBLISHED' AND NEW.consent_at IS NULL THEN
      RAISE EXCEPTION 'a profile cannot be published without a recorded consent'
        USING ERRCODE = 'HB142';
    END IF;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_th_profile_status BEFORE UPDATE ON hbh.therapists
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_therapist_profile_status();

-- =====================================================================
-- IT PROVES THE TWO DECISIONS THAT MATTER
-- =====================================================================
DO $prove$
DECLARE
  l_th   integer;
  l_ok   boolean := false;
BEGIN
  SELECT therapist_id INTO l_th FROM hbh.therapists WHERE active_flg LIMIT 1;
  IF l_th IS NULL THEN
    RAISE WARNING 'no therapist exists yet, so the publication guard was not exercised';
  ELSE
    BEGIN
      UPDATE hbh.therapists SET profile_status = 'PUBLISHED' WHERE therapist_id = l_th;
    EXCEPTION WHEN sqlstate 'HB142' THEN
      l_ok := true;
    END;
    IF NOT l_ok THEN
      RAISE EXCEPTION 'a profile was published with no consent - the guard does not work';
    END IF;
  END IF;

  -- The default. Stated as a test, because "we chose false" in a
  -- comment and "it is false" in the catalogue are different claims.
  IF (SELECT column_default FROM information_schema.columns
       WHERE table_schema = 'hbh' AND table_name = 'therapist_certificates'
       AND   column_name = 'is_image_public') <> 'false' THEN
    RAISE EXCEPTION 'is_image_public does not default to false';
  END IF;
END
$prove$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0033');
