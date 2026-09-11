-- =====================================================================
-- 0061 - a team member's full profile: many films, many photographs,
--        a biography, an affiliation and a list of specialities
--
-- 0055 gave a member ONE introduction film in four columns on the row
-- itself. The owner's design has a gallery: several films with their
-- own captions and lengths, several photographs beside the portrait,
-- and each one deletable on its own.
--
-- Columns cannot do that. Four more columns for a second film is the
-- shape that ends in intro_video_3_caption_en, and the day somebody
-- wants them reordered there is nothing to order.
--
-- ONE TABLE FOR BOTH KINDS, not two. A photograph and a film of the
-- same person, on the same card, differ in exactly one way that matters
-- here - what a browser does with the file - and in no way at all in
-- who consented, who published, or how they are ordered and withdrawn.
-- Two tables would be two copies of the same consent machinery, and the
-- day one of them learned something the other would not have.
--
-- CONSENT PER FILE, and this is the point of the table.
--
-- The member row's consent_given_at covers a name, a portrait and a
-- list of credentials - what was asked for when that row was made. It
-- does not cover a film taken later, or a second photograph from a
-- different day. Each file here is a separate thing a person agreed to,
-- so each carries its own consent and cannot be published without it.
-- Same shape as the certificates in 0048, for the same reason.
--
-- STILL NOT A RECORDING. These rows hang off site_team, which has no
-- child, no session, no appointment and no camera - and p00 refuses to
-- let it grow one while it holds the NO_RECORDING exemption registered
-- in 0057. A film here is a member of staff introducing themselves on
-- a marketing page. The live stream still has nowhere to be written.
--
-- THE PATH RULES ARE THE ONES FROM 0055: local only. A public URL in
-- one of these columns would put whoever hosts it in front of every
-- visitor to a page about children's therapy.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- The profile text the design asks for.
--
-- bio is a paragraph a person wrote about themselves; the console
-- counts characters against ck_st_bio so the limit is visible while
-- typing rather than discovered on save.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_team
  ADD COLUMN org_ar text,
  ADD COLUMN org_en text,
  ADD COLUMN bio_ar text,
  ADD COLUMN bio_en text;

ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_bio
    CHECK ((bio_ar IS NULL OR length(bio_ar) <= 500)
           AND (bio_en IS NULL OR length(bio_en) <= 500));

COMMENT ON COLUMN hbh.site_team.org_ar IS
  'The body they are affiliated with - a university, a hospital.';
COMMENT ON COLUMN hbh.site_team.bio_ar IS
  'A short profile paragraph. At most 500 characters.';

-- ---------------------------------------------------------------------
-- The gallery.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_team_media (
  media_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  member_id   integer     NOT NULL,

  -- What a browser should do with it, and nothing more. There is no
  -- 'SESSION' and there will not be one.
  kind        text        NOT NULL,

  -- Relative to the site root, exactly like photo_path.
  path        text        NOT NULL,
  -- The still shown before a film plays. Meaningless for a photograph,
  -- and ck_stm_poster says so rather than leaving it quietly ignorable.
  poster_path text,

  caption_ar  text,
  caption_en  text,

  -- Seconds, so the card can print 02:35 without opening the file.
  -- Nullable: a photograph has no length, and an unmeasured film is
  -- "not known", which is not the same as zero.
  duration_s  integer,

  sort_order  integer     NOT NULL DEFAULT 0,

  -- Consent for THIS file. See the note at the top.
  consent_given_at    timestamptz,
  consent_obtained_by integer REFERENCES hbh.users(user_id),

  status       text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer     REFERENCES hbh.users(user_id),

  active_flg  boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at  timestamptz,
  updated_by  text,

  CONSTRAINT pk_site_team_media PRIMARY KEY (media_id),
  CONSTRAINT fk_stm_center    FOREIGN KEY (center_id) REFERENCES hbh.centers(center_id),
  CONSTRAINT fk_stm_member    FOREIGN KEY (member_id) REFERENCES hbh.site_team(member_id),
  CONSTRAINT ck_stm_kind      CHECK (kind IN ('VIDEO', 'PHOTO')),
  CONSTRAINT ck_stm_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_stm_duration  CHECK (duration_s IS NULL OR duration_s BETWEEN 0 AND 86400),

  -- A poster belongs to a film. On a photograph it would be a second
  -- image nothing displays.
  CONSTRAINT ck_stm_poster    CHECK (kind = 'VIDEO' OR poster_path IS NULL),

  -- Both halves of a consent or neither: a date with nobody behind it
  -- records that somebody was asked and loses who asked them.
  CONSTRAINT ck_stm_consent_pair
    CHECK ((consent_given_at IS NULL) = (consent_obtained_by IS NULL)),

  -- Published needs a consent and a publisher. Draft needs neither.
  CONSTRAINT ck_stm_published
    CHECK (status = 'DRAFT'
           OR (published_at IS NOT NULL AND published_by IS NOT NULL)),
  CONSTRAINT ck_stm_consent
    CHECK (status = 'DRAFT'
           OR (consent_given_at IS NOT NULL AND consent_obtained_by IS NOT NULL)),

  -- Local paths only - no scheme, no protocol-relative host, no walking
  -- out of the media directory.
  CONSTRAINT ck_stm_local CHECK (
    path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
    AND path !~ '^//'
    AND position('..' in path) = 0
    AND (poster_path IS NULL
         OR (poster_path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
             AND poster_path !~ '^//'
             AND position('..' in poster_path) = 0)))
);

CREATE INDEX ix_stm_member ON hbh.site_team_media (member_id, kind, sort_order, media_id);
CREATE INDEX ix_stm_center ON hbh.site_team_media (center_id);
CREATE INDEX ix_stm_consent_by ON hbh.site_team_media (consent_obtained_by);
CREATE INDEX ix_stm_published_by ON hbh.site_team_media (published_by);

-- ---------------------------------------------------------------------
-- Specialities - the chips on the profile.
--
-- A row each rather than an array, so one can be withdrawn or corrected
-- on its own and the audit trail says which. Same reasoning as the
-- qualifications: these are claims published under a named person.
--
-- They are NOT tied to hbh.services on purpose. A speciality describes
-- what a therapist works with - autism, learning difficulties - and a
-- service is a thing the centre sells an appointment for. 0047 tied the
-- site's SERVICES to the catalogue because advertising a service nobody
-- can book is a promise the system cannot keep; naming an area of
-- expertise promises nothing bookable.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_team_specialties (
  specialty_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  member_id    integer     NOT NULL,
  name_ar      text        NOT NULL,
  name_en      text,
  sort_order   integer     NOT NULL DEFAULT 0,

  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,

  CONSTRAINT pk_site_team_specialties PRIMARY KEY (specialty_id),
  CONSTRAINT fk_sts_center FOREIGN KEY (center_id) REFERENCES hbh.centers(center_id),
  CONSTRAINT fk_sts_member FOREIGN KEY (member_id) REFERENCES hbh.site_team(member_id),
  CONSTRAINT ck_sts_name   CHECK (length(btrim(name_ar)) BETWEEN 1 AND 60)
);

CREATE INDEX ix_sts_member ON hbh.site_team_specialties (member_id, sort_order, specialty_id);
CREATE INDEX ix_sts_center ON hbh.site_team_specialties (center_id);

-- ---------------------------------------------------------------------
-- Audit and touch, like every other table.
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_site_team_media_touch
  BEFORE UPDATE ON hbh.site_team_media
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_team_media_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.site_team_media
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('media_id');

-- The same publish pair every other site table carries: the guard
-- refuses a publish by somebody without SITE.PUBLISH, and the stamp
-- writes who and when. Without these a media row could be marked
-- PUBLISHED by anybody holding SITE.EDIT - the split between drafting
-- and publishing is the whole reason there are two permissions.
CREATE TRIGGER trg_site_team_media_publish
  BEFORE INSERT OR UPDATE ON hbh.site_team_media
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_team_media_stamp
  BEFORE INSERT OR UPDATE ON hbh.site_team_media
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();

CREATE TRIGGER trg_site_team_specialties_touch
  BEFORE UPDATE ON hbh.site_team_specialties
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_team_specialties_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.site_team_specialties
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('specialty_id');

-- ---------------------------------------------------------------------
-- Policies. Read, write, and - learned the hard way in 0056 - a second
-- read policy so that archiving a row does not make the UPDATE that
-- archives it violate the read policy on its own new row.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_team_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_team_specialties ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_stm_select ON hbh.site_team_media
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_stm_select_archived ON hbh.site_team_media
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_stm_insert ON hbh.site_team_media
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_stm_update ON hbh.site_team_media
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_sts_select ON hbh.site_team_specialties
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_sts_select_archived ON hbh.site_team_specialties
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_sts_insert ON hbh.site_team_specialties
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_sts_update ON hbh.site_team_specialties
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

-- No DELETE grant, here as everywhere.
GRANT SELECT, INSERT, UPDATE ON hbh.site_team_media TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.site_team_specialties TO hbh_app;

-- The publish stamp is the service's to read and the database's to
-- write, so neither is granted for UPDATE by the application.
REVOKE UPDATE (published_at, published_by) ON hbh.site_team_media FROM hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0061');
