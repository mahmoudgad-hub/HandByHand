-- =====================================================================
-- 0045 - the site turned out to hold real people, and a real child
--
-- 0040 was designed on the understanding that the team and the
-- testimonials on site/index.html were placeholders. They are not. The
-- owner replaced them, and the page now carries four named staff with
-- specific credential claims - "ABAT certified", "VB-MAPP certified",
-- "certified by the Air Force Hospital's psychiatry unit" - and three
-- testimonials in real parents' words, two naming therapists.
--
-- AND ONE NAMES A CHILD. A testimonial on the page uses a child's given
-- name four times beside an account of his progress over two months at
-- the centre. Nothing in 0040 would have stopped it: the consent columns
-- ask whether the family agreed to publish, and this family may well
-- have. Consent and safety are different questions, and the row that
-- proves it already exists.
--
-- So this migration adds the second question, as a column:
--
--   text_reviewed_at / text_reviewed_by - somebody read this text and
--   states that it names no child and points at none. Recorded against
--   their name, required before publishing, exactly like the consent.
--
-- IT IS AN ATTESTATION, NOT A CHECK. No pattern match can find a child's
-- name: "مازن" is a name, a word, and thousands of adults. A regular
-- expression here would refuse ordinary sentences and miss "ابن أختي"
-- - and, worse, it would let whoever clicks publish believe the machine
-- had looked. A person looked, and their name is on it.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- The section codes were wrong, and wrong in the silent direction
--
-- 0040 wrote them in capitals: FAQ, TEAM, REVIEWS, CONTACT. The site
-- matches them against the section ids in index.html, which are
-- lowercase - so every one of them missed, and hiding a section from the
-- console would have done nothing at all, with no error anywhere. The
-- list below is the page's own ids, copied exactly.
--
-- No rows have been written yet, so this is a straight replacement.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_sections DROP CONSTRAINT ck_ss_code;
ALTER TABLE hbh.site_sections ADD CONSTRAINT ck_ss_code CHECK (
  code IN ('home', 'services', 'programs', 'how', 'why', 'live',
           'portal', 'team', 'reviews', 'contact', 'faq')
);

-- ---------------------------------------------------------------------
-- A testimonial has to be read before it is published
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_reviews
  ADD COLUMN text_reviewed_at timestamptz,
  ADD COLUMN text_reviewed_by integer,
  -- 0 to 5, and nullable. The written cards show five stars; a row with
  -- no rating shows none rather than inventing one.
  ADD COLUMN rating smallint;

ALTER TABLE hbh.site_reviews
  ADD CONSTRAINT fk_sr_text_reviewer FOREIGN KEY (text_reviewed_by)
    REFERENCES hbh.users (user_id),
  ADD CONSTRAINT ck_sr_rating CHECK (rating IS NULL OR rating BETWEEN 0 AND 5),
  -- The second gate, beside the consent and independent of it. A family
  -- may have agreed to publish a sentence that still names their child.
  ADD CONSTRAINT ck_sr_text_reviewed CHECK (
    status = 'DRAFT' OR (text_reviewed_at IS NOT NULL AND text_reviewed_by IS NOT NULL)
  );

-- ---------------------------------------------------------------------
-- The team cards carry more than a name and a role
--
-- Today the exporter replaces the two text lines and leaves the rest of
-- the card as written, so a member added from the console appears with
-- their name above SOMEBODY ELSE'S photograph and qualifications. One
-- person's name over another person's certificates.
--
-- photo_path is a path into site/assets, not an upload. The images there
-- are the centre's own promotional posters - one has the centre's
-- address printed inside it - and uploads are a later batch.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_team
  ADD COLUMN photo_path   text,
  ADD COLUMN profile_href text;

-- Qualifications, one per row.
--
-- ROWS AND NOT A TEXT BLOCK, because the card lists them as separate
-- lines and because of what they are: "certified by the Air Force
-- Hospital's psychiatry unit" is a claim about a named person's
-- credentials, published under the centre's name. One per row means one
-- can be corrected or withdrawn without rewriting the rest, and the
-- audit trail records exactly which claim changed.
CREATE TABLE hbh.site_team_facts (
  fact_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  member_id    integer     NOT NULL,
  text_ar      text        NOT NULL,
  text_en      text,
  sort_order   integer     NOT NULL DEFAULT 0,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_site_team_facts PRIMARY KEY (fact_id),
  CONSTRAINT fk_stf_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_stf_member FOREIGN KEY (member_id) REFERENCES hbh.site_team (member_id),
  CONSTRAINT ck_stf_text   CHECK (length(btrim(text_ar)) BETWEEN 1 AND 120)
);

CREATE INDEX ix_site_team_facts ON hbh.site_team_facts (member_id, sort_order)
  WHERE active_flg;

-- ---------------------------------------------------------------------
-- The programmes section
--
-- New on the page since this work started: foreign-language speech
-- sessions, family counselling, music therapy, Qur'an memorisation,
-- online training, arts and music.
--
-- IT OVERLAPS hbh.services AND THAT IS UNRESOLVED. "Music therapy" is
-- now in both, and two independent lists of the same thing drift until
-- the site advertises something the centre cannot book. The owner has
-- been asked which is the source of truth. Until that is answered this
-- table carries marketing copy only - no price, no duration, no link to
-- a bookable service - so that nothing here can become a promise the
-- booking system cannot keep.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.site_programs (
  program_id   integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  title_ar     text        NOT NULL,
  title_en     text,
  desc_ar      text,
  desc_en      text,
  detail_ar    text,
  detail_en    text,
  -- One of the icons already drawn into the page. Not an upload: the
  -- icons are inline SVG in index.html and a free-text value here would
  -- render nothing at all.
  icon_key     text,
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
  CONSTRAINT pk_site_programs PRIMARY KEY (program_id),
  CONSTRAINT fk_sp_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_sp_publisher FOREIGN KEY (published_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_sp_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_sp_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),
  CONSTRAINT ck_sp_title     CHECK (length(btrim(title_ar)) BETWEEN 1 AND 80)
);

CREATE INDEX ix_site_programs_order ON hbh.site_programs (center_id, sort_order)
  WHERE active_flg;

-- ---------------------------------------------------------------------
-- Triggers, policies and grants, matching 0040 to 0043
-- ---------------------------------------------------------------------
CREATE TRIGGER trg_site_team_facts_touch BEFORE UPDATE ON hbh.site_team_facts
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_programs_touch   BEFORE UPDATE ON hbh.site_programs
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_site_team_facts_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.site_team_facts
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('fact_id');
CREATE TRIGGER trg_site_programs_audit   AFTER INSERT OR UPDATE OR DELETE ON hbh.site_programs
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('program_id');

-- Sorts after trg_site_programs_publish would - there is none yet, so
-- the publish guard is added here for this table.
CREATE TRIGGER trg_site_programs_publish BEFORE INSERT OR UPDATE ON hbh.site_programs
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_programs_stamp   BEFORE INSERT OR UPDATE ON hbh.site_programs
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();

-- The text review is stamped the same way a consent is: the value sent
-- means "I have read it", and the database records who and when.
CREATE FUNCTION hbh.trg_site_text_review_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.text_reviewed_at IS NOT NULL THEN
    IF TG_OP = 'INSERT' OR OLD.text_reviewed_at IS NULL THEN
      NEW.text_reviewed_at := now();
      NEW.text_reviewed_by := hbh.current_user_id();
    ELSE
      NEW.text_reviewed_at := OLD.text_reviewed_at;
      NEW.text_reviewed_by := OLD.text_reviewed_by;
    END IF;
  ELSE
    NEW.text_reviewed_by := NULL;
  END IF;

  -- CHANGING THE WORDS RETRACTS THE READING. Somebody attested to a
  -- particular sentence; a different sentence has not been read by
  -- anybody, and ck_sr_text_reviewed then refuses to publish it until
  -- somebody reads it again. Without this, a reviewed row could be
  -- edited to name a child and stay published.
  IF TG_OP = 'UPDATE' AND NEW.body_ar IS DISTINCT FROM OLD.body_ar THEN
    NEW.text_reviewed_at := NULL;
    NEW.text_reviewed_by := NULL;
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_reviews_textreview BEFORE INSERT OR UPDATE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_text_review_stamp();

ALTER TABLE hbh.site_team_facts ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.site_programs   ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_site_team_facts_select ON hbh.site_team_facts
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_facts_insert ON hbh.site_team_facts
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_facts_update ON hbh.site_team_facts
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_site_programs_select ON hbh.site_programs
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_programs_insert ON hbh.site_programs
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_programs_update ON hbh.site_programs
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

GRANT SELECT, INSERT, UPDATE ON hbh.site_team_facts, hbh.site_programs TO hbh_app;
REVOKE ALL ON FUNCTION hbh.trg_site_text_review_stamp() FROM PUBLIC;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0045');
