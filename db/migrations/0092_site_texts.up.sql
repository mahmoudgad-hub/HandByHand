-- =====================================================================
-- 0092 - the marketing page's own words
--
-- Every editable sentence on site/index.html already carries a unique
-- data-i18n key - 179 of them. So this is ONE table keyed by that
-- string, not a table per section: the key is the position, and a map
-- of keys reaches the headings, the top menu, the footer and the
-- accessibility strings alike.
--
-- NO sort_order. There is no ordering here. Where a text appears is
-- decided by the page, and a column that pretended otherwise would be a
-- number nobody could act on.
--
-- A MISSING ROW MEANS "LEAVE WHAT IS WRITTEN", like every other site
-- table. So a half-filled table is a page half-managed, never a page
-- with holes in it - and the centre can adopt this one sentence at a
-- time instead of having to fill 179 before the first one works.
--
-- THE 61 KEYS THAT OTHER TABLES ALREADY OWN ARE NOT SEEDED HERE.
-- site_team (26), site_programs (30), the contact block and site_faq
-- (13) each answer for their own words. Seeding them here as well would
-- give one sentence two sources, and the resolver would decide which -
-- silently, and differently from whoever last edited the other screen.
--
-- text_en IS NULLABLE AND STAYS. The owner hid the language switch on
-- 2026-09-10, so the page is Arabic-only today; the switch is one
-- attribute in index.html and the English dictionary is untouched
-- behind it. A required English column would make this table the reason
-- the site cannot go back.
--
-- =====================================================================
-- THE SIX `live.*` KEYS ARE NOT EDITABLE FROM THE SCREEN.
--
-- They are the page's statement that a session is streamed live and
-- never recorded. That is not marketing copy - it is the promise made
-- to a family about their child, and the rule behind it is enforced in
-- this schema (no recordings table, no clip reference, and a p00 check
-- that fails if a column so much as names one).
--
-- A screen that let somebody reword those six could weaken the promise
-- in public while every guard in the database stayed green, BECAUSE
-- NOTHING IN THE SYSTEM VALIDATES PROSE. The words would no longer
-- describe the system, and nothing would notice.
--
-- So they are seeded with is_locked = true. The screen may show them -
-- reading what the page says about recording is exactly what an
-- administrator should be able to do - and the database refuses the
-- edit. Enforced by trigger, not by hiding the field: hiding a control
-- is not a control.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE hbh.site_texts (
  text_id     integer     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  center_id   integer     NOT NULL REFERENCES hbh.centers (center_id),
  text_key    text        NOT NULL,
  text_ar     text        NOT NULL,
  text_en     text,
  -- Draft until somebody publishes it, like every other site table: a
  -- sentence is written in one act and put on the internet in another.
  status      text        NOT NULL DEFAULT 'DRAFT',
  published_at timestamptz,
  published_by integer    REFERENCES hbh.users (user_id),

  -- The permanent rule's own words. See the header.
  is_locked   boolean     NOT NULL DEFAULT false,

  active_flg  boolean     NOT NULL DEFAULT true,
  deleted_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at  timestamptz,
  updated_by  text,

  CONSTRAINT ck_site_texts_status CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_site_texts_published CHECK (
    (status = 'PUBLISHED') = (published_at IS NOT NULL)),
  -- A key is a dotted path into the page: `hero.title`, `nav.services`.
  CONSTRAINT ck_site_texts_key CHECK (text_key ~ '^[a-z][a-zA-Z0-9]*(\.[a-zA-Z0-9]+)+$'),
  CONSTRAINT ck_site_texts_ar CHECK (length(btrim(text_ar)) > 0)
);

-- One row per key per centre, among the LIVE rows only.
--
-- Partial, because a soft-deleted row keeps its key and a new row must
-- be allowed to take the same one: "this key was edited, archived, and
-- written again" is ordinary, and a plain unique index would refuse it
-- forever after the first archive.
CREATE UNIQUE INDEX uix_site_texts_key
  ON hbh.site_texts (center_id, text_key) WHERE active_flg;

CREATE INDEX ix_site_texts_center ON hbh.site_texts (center_id, text_key);
CREATE INDEX ix_site_texts_publisher ON hbh.site_texts (published_by);

COMMENT ON TABLE hbh.site_texts IS
  'Editable copy for the public page, keyed by its data-i18n attribute. '
  'A missing key leaves whatever is written in index.html.';
COMMENT ON COLUMN hbh.site_texts.is_locked IS
  'Set on the live-streaming statements. They describe a permanent rule '
  'about a child''s privacy, and no screen may reword them - see 0092.';

-- ---------------------------------------------------------------------
-- The lock, enforced rather than hidden.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.guard_site_text_locked()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.is_locked THEN
    -- The words themselves, and the flag that protects them. Everything
    -- else on a locked row - archiving it, publishing it - is somebody
    -- managing the page, not rewording the promise.
    IF NEW.text_ar IS DISTINCT FROM OLD.text_ar
       OR NEW.text_en IS DISTINCT FROM OLD.text_en
       OR NEW.is_locked IS DISTINCT FROM OLD.is_locked THEN
      RAISE EXCEPTION
        'this text states a permanent rule and cannot be reworded: %', OLD.text_key
        USING ERRCODE = 'HB203',
              HINT = 'live streaming is never recorded; the page says so because '
                     'the schema enforces it, and prose is the one part no '
                     'constraint can check';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_texts_locked
  BEFORE UPDATE ON hbh.site_texts
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_site_text_locked();

CREATE TRIGGER trg_site_texts_touch
  BEFORE UPDATE ON hbh.site_texts
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_site_texts_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.site_texts
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('text_id');

-- ---------------------------------------------------------------------
-- Access. Copied in shape from site_faq, which is the closest sibling.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.site_texts ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_site_texts_select ON hbh.site_texts
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

-- The archived rows, for the same reader. Without this an UPDATE that
-- sets active_flg false produces a row that fails the read policy, and
-- row level security refuses the whole statement - the defect 0056 was
-- written to fix, on eight tables at once.
CREATE POLICY p_site_texts_select_archived ON hbh.site_texts
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_texts_insert ON hbh.site_texts
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_texts_update ON hbh.site_texts
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

GRANT SELECT, INSERT, UPDATE ON hbh.site_texts TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0092');
