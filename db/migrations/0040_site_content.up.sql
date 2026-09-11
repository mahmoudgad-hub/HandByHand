-- =====================================================================
-- 0040 - the public site's content, edited from the staff console
--
-- WHAT THIS IS. The marketing site in site/ ships as plain files. Its
-- words live in index.html and its phone number in site/config.js, so
-- changing either means editing a file and redeploying. These tables put
-- the parts that actually change into the database, behind a screen.
--
-- HOW IT REACHES THE SITE, AND WHY IT IS NOT AN API.
-- An exporter writes site/content.js; the site loads it with a plain
-- <script> tag. There is deliberately NO endpoint a visitor can call.
--
-- The reason is not "an API is a bigger attack surface", though it is.
-- It is that the site is publishable TODAY precisely because nothing on
-- its origin talks to the service: deploy/server/site.native.mjs has no
-- proxy, and its nginx block has none either, both written as decisions
-- rather than omissions. The API still runs with OTP_ECHO=true and
-- returns the login code in the response body, which is why the portal
-- and console stay on loopback. A public read endpoint puts a route
-- back from the open internet to the service, and the first person to
-- add `location /api/` for it opens /api/v1/auth alongside.
--
-- And this project's own rule bites here: "a policy that admits
-- center_id IS NULL rows leaks them to an unauthenticated connection".
-- Site content IS that shape of data - public, ownerless. Exporting
-- makes the number of unauthenticated connections that read these
-- tables zero, so the trap is never laid.
--
-- WHAT IS NOT HERE, AND WILL NOT BE.
--
--   The live-stream section. It promises that streaming is live only and
--   never recorded - a permanent rule enforced in this schema by the
--   absence of a recordings table. A screen that lets somebody reword it
--   is a screen that lets a member of staff weaken a promise about
--   disabled children's privacy, and nothing in the system would refuse
--   the new sentence. It stays in index.html.
--
--   Services. hbh.services already exists and the enrolment form carries
--   preferred_service_id. A second list of services here would let
--   somebody advertise a service that cannot be booked - a promise to a
--   family with nothing behind it. When the site's services become
--   editable they must be marketing TEXT attached to catalogue rows, not
--   rows of their own.
--
--   Image uploads. The whole site serves two files, logo.png and
--   hero.webp. A bytea column, a size limit and an upload path is a lot
--   of machinery for a picture that changes once. When it comes, note
--   that the audit trigger copies the whole row: an attachments table
--   needs its own trigger that subtracts the content column, or every
--   image lands in audit_log twice.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Whether a section appears on the site at all
--
-- Not a nicety. site/README.md is explicit: if there are no approved
-- reviews, DELETE the section rather than fill it. Without a switch at
-- section level the only way to act on that from a screen is to leave
-- the section empty - and an empty section on a live page is an
-- invitation to somebody to write three testimonials that nobody said.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_sections (
  section_id   integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  code         text        NOT NULL,
  visible_flg  boolean     NOT NULL DEFAULT false,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_site_sections PRIMARY KEY (section_id),
  CONSTRAINT fk_ss_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_site_sections UNIQUE (center_id, code),
  CONSTRAINT ck_ss_code CHECK (code IN ('FAQ', 'TEAM', 'REVIEWS', 'CONTACT'))
);

-- ---------------------------------------------------------------------
-- How to reach the centre - one row per centre
--
-- These fields exist today, by these names, in site/config.js. The
-- screen writes them and the exporter writes that same file, which makes
-- this the smallest change to the site and the largest return: a phone
-- number that changes is a redeploy today.
--
-- WEEKEND IS FRIDAY AND SATURDAY. It is a parameter and not a literal,
-- but the default has to be right: "Saturday and Sunday" is the mistake
-- an unthinking default makes, and every Egyptian visitor would see it.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_contact (
  contact_id   integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,

  -- Local form, 01XXXXXXXXX, the way it is written and dialled here.
  phone        text,
  -- International, no plus: what a wa.me link needs.
  whatsapp     text,
  email        text,

  -- NOT translated by anything automatic, and the two are written
  -- separately on purpose: a translated street name is a street name
  -- that does not find the building.
  address_ar   text,
  address_en   text,

  -- A link that opens a map application. Never an iframe: an embedded
  -- map is a third party watching every visitor to a page about
  -- children's therapy.
  map_url      text,

  hours_ar     text,
  hours_en     text,
  weekend_ar   text,
  weekend_en   text,

  status       text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer,

  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,

  CONSTRAINT pk_site_contact PRIMARY KEY (contact_id),
  CONSTRAINT fk_sc_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_sc_publisher FOREIGN KEY (published_by) REFERENCES hbh.users (user_id),
  CONSTRAINT uq_site_contact UNIQUE (center_id),
  CONSTRAINT ck_sc_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_sc_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  )
);

-- ---------------------------------------------------------------------
-- Questions families ask
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_faq (
  faq_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,

  question_ar  text        NOT NULL,
  question_en  text,
  answer_ar    text        NOT NULL,
  answer_en    text,

  -- Explicit, never alphabetical. Arabic collation ordering shifts under
  -- you when the collation changes, and the order of questions is an
  -- editorial decision anyway.
  sort_order   integer     NOT NULL DEFAULT 0,

  status       text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer,

  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,

  CONSTRAINT pk_site_faq     PRIMARY KEY (faq_id),
  CONSTRAINT fk_sf_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_sf_publisher FOREIGN KEY (published_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_sf_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_sf_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),
  CONSTRAINT ck_sf_question  CHECK (length(btrim(question_ar)) BETWEEN 1 AND 150),
  CONSTRAINT ck_sf_answer    CHECK (length(btrim(answer_ar))   BETWEEN 1 AND 800)
);

-- ---------------------------------------------------------------------
-- The people who work here
--
-- CONSENT IS A COLUMN AND A CONSTRAINT, not a rule in a screen. A named
-- therapist on a public page is a real person whose employment, face and
-- speciality are being published; ck_st_consent makes a PUBLISHED row
-- without a recorded consent impossible to write at all.
--
-- consent_obtained_by sits beside the date because "who took this
-- consent" is asked a year later and nobody remembers.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_team (
  member_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,

  name_ar      text        NOT NULL,
  name_en      text,
  role_ar      text        NOT NULL,
  role_en      text,

  -- Reserved for the day photographs are uploaded. Nullable and unused
  -- today: the site serves two images and neither is a portrait.
  photo_id     integer,

  sort_order   integer     NOT NULL DEFAULT 0,

  -- Who agreed, when, and who asked them.
  consent_given_at    timestamptz,
  consent_obtained_by integer,

  status       text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer,

  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,

  CONSTRAINT pk_site_team    PRIMARY KEY (member_id),
  CONSTRAINT fk_st_center    FOREIGN KEY (center_id)           REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_st_consenter FOREIGN KEY (consent_obtained_by) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_st_publisher FOREIGN KEY (published_by)        REFERENCES hbh.users (user_id),
  CONSTRAINT ck_st_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_st_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),
  CONSTRAINT ck_st_consent   CHECK (
    status = 'DRAFT' OR (consent_given_at IS NOT NULL AND consent_obtained_by IS NOT NULL)
  ),
  CONSTRAINT ck_st_name      CHECK (length(btrim(name_ar)) BETWEEN 1 AND 80),
  CONSTRAINT ck_st_role      CHECK (length(btrim(role_ar)) BETWEEN 1 AND 80)
);

-- ---------------------------------------------------------------------
-- What families have said
--
-- THE MOST DANGEROUS TABLE IN THIS MIGRATION, and it holds no clinical
-- data at all. A parent's words about their child's progress, published
-- beside anything that identifies them, tells everyone who knows that
-- family that their child attends a therapy centre - which is a
-- disclosure about a disabled child that nobody asked the child.
--
-- Three defences, and none of them is a screen:
--
--   display_name is FREE TEXT the guardian chooses, never derived from
--   their name in the system. "أم يوسف" is not anonymous to anybody who
--   knows them, so the choice has to be theirs and it has to be recorded
--   as what they chose.
--
--   guardian_id links the row to the family so the consent is
--   attributable and so a withdrawal can find the review to remove. It
--   never leaves the database: the exporter writes display_name and the
--   text, nothing else.
--
--   ck_sr_consent makes a published review without consent unwritable.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_reviews (
  review_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,

  -- Who this family is, for accountability. Never exported.
  guardian_id  integer,

  -- What they asked to be called on the page. Their choice, their words.
  display_name text        NOT NULL,
  body_ar      text        NOT NULL,
  body_en      text,

  sort_order   integer     NOT NULL DEFAULT 0,

  consent_given_at    timestamptz,
  consent_obtained_by integer,

  status       text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer,

  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,

  CONSTRAINT pk_site_reviews PRIMARY KEY (review_id),
  CONSTRAINT fk_sr_center    FOREIGN KEY (center_id)           REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_sr_guardian  FOREIGN KEY (guardian_id)         REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_sr_consenter FOREIGN KEY (consent_obtained_by) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_sr_publisher FOREIGN KEY (published_by)        REFERENCES hbh.users (user_id),
  CONSTRAINT ck_sr_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_sr_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),
  CONSTRAINT ck_sr_consent   CHECK (
    status = 'DRAFT' OR (consent_given_at IS NOT NULL AND consent_obtained_by IS NOT NULL)
  ),
  CONSTRAINT ck_sr_name      CHECK (length(btrim(display_name)) BETWEEN 1 AND 60),
  CONSTRAINT ck_sr_body      CHECK (length(btrim(body_ar))      BETWEEN 1 AND 600)
);

-- ---------------------------------------------------------------------
-- Indexes, touch and audit
-- ---------------------------------------------------------------------
CREATE INDEX ix_site_faq_order     ON hbh.site_faq     (center_id, sort_order) WHERE active_flg;
CREATE INDEX ix_site_team_order    ON hbh.site_team    (center_id, sort_order) WHERE active_flg;
CREATE INDEX ix_site_reviews_order ON hbh.site_reviews (center_id, sort_order) WHERE active_flg;
CREATE INDEX ix_site_reviews_guardian ON hbh.site_reviews (guardian_id);

CREATE TRIGGER trg_site_sections_touch BEFORE UPDATE ON hbh.site_sections
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_contact_touch  BEFORE UPDATE ON hbh.site_contact
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_faq_touch      BEFORE UPDATE ON hbh.site_faq
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_team_touch     BEFORE UPDATE ON hbh.site_team
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_reviews_touch  BEFORE UPDATE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- Every one of these is a public statement by the centre. Who changed
-- the phone number, who published a review, and when, are exactly the
-- questions asked afterwards.
CREATE TRIGGER trg_site_sections_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.site_sections
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('section_id');
CREATE TRIGGER trg_site_contact_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.site_contact
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('contact_id');
CREATE TRIGGER trg_site_faq_audit      AFTER INSERT OR UPDATE OR DELETE ON hbh.site_faq
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('faq_id');
CREATE TRIGGER trg_site_team_audit     AFTER INSERT OR UPDATE OR DELETE ON hbh.site_team
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('member_id');
CREATE TRIGGER trg_site_reviews_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('review_id');

-- ---------------------------------------------------------------------
-- ROW LEVEL SECURITY
--
-- NO ANONYMOUS READ, and that is the whole design. These tables hold the
-- text of a public page, but nothing public reads them: the exporter
-- runs as staff and writes a file. Every policy below therefore begins
-- with the identity check, and none of them has an "or it is public"
-- arm - which is the arm that, on a table of ownerless rows, would hand
-- everything to an unauthenticated connection.
--
-- SITE.EDIT to read and write, SITE.PUBLISH to make it live. Two codes,
-- two gates: one gate serving both would silently decide which of the
-- two grants it ignores.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_sections ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_contact  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_faq      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_team     ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_reviews  ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_site_sections_select ON hbh.site_sections
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_contact_select ON hbh.site_contact
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_faq_select ON hbh.site_faq
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_select ON hbh.site_team
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_reviews_select ON hbh.site_reviews
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

-- ---------------------------------------------------------------------
-- GRANTS
--
-- SELECT only for now, matching every other table a screen reads through
-- the CRUD layer; the write grants arrive with the write policies in the
-- same batch as the console screens, so there is never a window where a
-- client can insert a row no policy has been written for.
-- ---------------------------------------------------------------------
GRANT SELECT ON hbh.site_sections, hbh.site_contact, hbh.site_faq,
                hbh.site_team, hbh.site_reviews
  TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0040');
