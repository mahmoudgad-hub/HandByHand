-- =====================================================================
-- 0057 - registering the one video the model is allowed to name
--
-- The conventions suite refused 0055, exactly as it should have. It
-- carries a permanent check - "no column names a recording, clip or
-- video" - which is the no-recording rule made structural: the centre
-- streams a session to the family live and never records it, and the
-- schema is not allowed to grow a place to put one.
--
-- hbh.site_team.intro_video_path is a staff member's introduction on a
-- MARKETING PAGE. It is not a session and cannot become one - but the
-- check reads column names, and it was right to stop and ask.
--
-- SO THE EXCEPTION IS REGISTERED, NOT HIDDEN. CLAUDE.md: an exception
-- to a convention goes in hbh.convention_exemptions with a written
-- reason, never into the test file - "a rule whose exceptions live
-- inside its own test is a rule every phase edits in silence".
--
-- AND IT IS BOUNDED BY A RULE, NOT BY TRUST. A table-level exemption
-- would otherwise be a standing licence for any future video column on
-- this table. So p00 gains a companion check: a table exempted from
-- NO_RECORDING must carry no reference to a child, a session, an
-- appointment or a camera. site_team has none and can have none while
-- that check stands - the moment somebody adds one, the suite fails and
-- names this exemption. The permanent rule keeps its teeth; what is
-- exempted is a word in a column name, not the thing the rule protects.
--
-- The owner asked for this directly, and site/app.js draws the same
-- boundary from the page's side: the player renders on a person's card
-- and never in or beside the `live` section.
-- =====================================================================

\set ON_ERROR_STOP on

-- The register was built for the two conventions that existed when it
-- was written, and its CHECK lists them by name - which is why the
-- INSERT below was refused before this line was added. Widening the
-- vocabulary is deliberate and belongs in a migration: the point of the
-- list is that a new exemptable rule is a decision somebody made, not a
-- string somebody typed.
ALTER TABLE hbh.convention_exemptions
  DROP CONSTRAINT ck_convention_exemptions_rule;

ALTER TABLE hbh.convention_exemptions
  ADD CONSTRAINT ck_convention_exemptions_rule
    CHECK (rule_code IN ('AUDIT_COLUMNS', 'SOFT_DELETE', 'NO_RECORDING'));

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('site_team', 'NO_RECORDING',
   'A staff member''s introduction film for the public marketing page - '
   'not a session, and not able to become one: this table has no child, '
   'session, appointment or camera reference, which p00 enforces for any '
   'table holding this exemption. The film carries its own consent '
   '(video_consent_given_at), separate from the consent covering the name '
   'and photograph. Live streaming still has no recording anywhere in the '
   'model. Owner-authorised 2026-09-07.')
ON CONFLICT DO NOTHING;

-- The foreign key added in 0055 needs an index like every other one: a
-- parent delete on hbh.users otherwise takes a table-level lock here.
CREATE INDEX IF NOT EXISTS ix_site_team_video_consent_by
  ON hbh.site_team (video_consent_obtained_by);

INSERT INTO hbh.schema_migrations (version) VALUES ('0057');
