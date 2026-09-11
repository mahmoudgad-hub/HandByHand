-- =====================================================================
-- 0073 - a photograph on a child record  (SHAPE STILL UNDECIDED)
--
-- RENUMBERED FROM 0072, which was already taken and already recorded:
-- 0072_role_permissions_close_grant had been applied and written into
-- hbh.schema_migrations before this file was written. Two files with
-- one number is the failure CLAUDE.md describes - the first applies and
-- claims the number, the second is treated as "already applied" and
-- skipped without a word - and scripts/db.sh refuses to run at all
-- while it can see one. It refused for every session on this database
-- until this rename. The recorded number is the one that cannot move.
--
-- The registration line and the removal of the nested BEGIN/COMMIT are
-- the same two repairs made to 0071; see that file for why.
--
-- THIS MIGRATION IS KEPT AND RECORDED RATHER THAN DELETED. The column
-- reached the database - it was applied by hand, outside
-- scripts/db.sh, which is how it came to exist on a schema whose ledger
-- had never heard of it. A ledger that omits what happened is worse
-- than one that shows a thing being reconsidered.
--
-- THE COLUMN STANDS, AND ITS SHAPE IS AN OPEN QUESTION THE OWNER HAS
-- RESERVED. Three things about it are unsettled, and none of them is
-- settled by this file:
--
--   · CONSENT. Nothing records that a family agreed to the centre
--     holding a picture of their child. hbh.consents already carries
--     'PHOTO_USE' for exactly this, scoped to a child and refused for a
--     guardian with no link to them.
--   · THE READ IS NOT LOGGED. Every other sensitive read in this
--     schema is recorded explicitly, because triggers do not catch
--     reads.
--   · url VERSUS path. This project's rules say no personal data in a
--     link: a URL is a capability that keeps working wherever it is
--     pasted, and row level security protects the ROW, not the address
--     once it has been read out of it. Everywhere else - staff
--     documents, staff photographs, site media - the column is a `path`
--     the service resolves after it has authorised the caller.
--
-- Migrations 0074 and 0076 build the alternative on the rail that
-- already exists (hbh.attachments, which has the digest, the soft
-- delete, the approval gate, the row policies and an audit trigger that
-- strips the bytes) and it sits unused. 0074 also dropped this column
-- and should not have - that broke every child read on the shared
-- database; 0077 put it back and records why.
--
-- The p00 convention suite will name this column under NO_PERSONAL_LINK
-- while the question is open. That is the point of it: a red check is
-- how an unsettled decision stays visible instead of becoming a habit.
-- It ends one of two ways - the column goes, or it earns a row in
-- hbh.convention_exemptions with a written reason.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.children ADD COLUMN IF NOT EXISTS photo_url text;

INSERT INTO hbh.schema_migrations (version) VALUES ('0073')
ON CONFLICT DO NOTHING;
