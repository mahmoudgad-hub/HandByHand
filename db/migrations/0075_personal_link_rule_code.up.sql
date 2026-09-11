-- =====================================================================
-- 0075 - the register learns the rule "no personal data in a link"
--
-- CLAUDE.md has carried that sentence since the first day and nothing
-- ever enforced it. p00 now does, and this migration is what makes the
-- rule EXEMPTABLE - which is not a loophole, it is the half that makes
-- a convention usable.
--
-- WHY THE CHECK CONSTRAINT HAD TO CHANGE AT ALL. rule_code is confined
-- to a declared set, so nobody can invent a code and file an
-- inconvenient table under it. That is a good design and it means a new
-- rule cannot be exempted until the schema has heard of it: without
-- this line the p00 check would be un-exemptable, and a rule with no
-- legitimate way out is a rule people delete rather than argue with.
--
-- WHAT THE RULE SAYS. On any table holding a child's or a guardian's
-- data - the two tables themselves, and anything with a foreign key to
-- either - a column may not be a URL or an href.
--
-- WHY URL AND NOT PATH, which is the whole distinction:
--
--   path   an internal key the SERVICE resolves and serves after it has
--          authorised the caller. It is useless to anybody who holds it
--          without also holding a session that may read it.
--   url    an address fetched directly by whoever has it. Row level
--          security protects the ROW; nothing in this schema reaches
--          the address once it has been pasted into a chat message or
--          left in a referrer header.
--
-- The schema already used the two words that way in all sixteen columns
-- that match either - staff_documents.path, site_team_media.path and
-- cameras.gateway_path on one side, site_contact.map_url on the other -
-- so the rule names an existing habit rather than imposing a new one.
--
-- NO EXEMPTION IS ADDED HERE. hbh.children.photo_url is the one column
-- the rule catches today, and whether it stays is the owner's decision,
-- pending. p00 is red until it is answered - deliberately: the check is
-- naming an open question, and an exemption row would need a written
-- reason that nobody has written yet.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.convention_exemptions
  DROP CONSTRAINT IF EXISTS ck_convention_exemptions_rule;

ALTER TABLE hbh.convention_exemptions
  ADD CONSTRAINT ck_convention_exemptions_rule
  CHECK (rule_code = ANY (ARRAY[
    'AUDIT_COLUMNS',
    'SOFT_DELETE',
    'NO_RECORDING',
    'NO_PERSONAL_LINK'
  ]));

INSERT INTO hbh.schema_migrations (version) VALUES ('0075');
