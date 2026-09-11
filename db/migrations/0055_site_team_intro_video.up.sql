-- =====================================================================
-- 0055 - a member's introduction film
--
-- WHY THIS IS NOT THE RECORDING THE PROJECT REFUSES.
--
-- CLAUDE.md carries a permanent rule: the centre streams a session to
-- the family live and NEVER records it. No recordings table, no clip
-- library, no pointer into a clip. That rule is about CHILDREN IN
-- THERAPY, and it is not weakened here.
--
-- What this adds is a film of a consenting adult member of staff saying
-- who they are, on a marketing page. The distinction is not a promise
-- in a comment - it is the shape of the table:
--
--   these columns live on hbh.site_team, which has no child_id, no
--   session_id, no camera and no appointment, and cannot be joined to
--   one. There is no field to hang a session on, so a session cannot be
--   hung on it.
--
-- site/app.js draws the same line from the other side, and says so: the
-- player is rendered on a person's card "and NOWHERE ELSE, and in
-- particular never in or beside the `live` section", because a video
-- player two screens from the sentence "we never record" is how a
-- visitor decides the sentence is marketing.
--
-- A SECOND CONSENT, NOT THE FIRST ONE STRETCHED.
--
-- The row already carries consent_given_at, and that consent was for a
-- name, a photograph and a list of credentials. A film is a different
-- thing to agree to - a person may be happy to have their photograph on
-- a page and not want to be watched speaking on it, and the reverse is
-- rarer but real. One consent covering both would decide, silently,
-- something nobody was asked.
--
-- So publishing a member WITH a video needs both. Without a video the
-- second gate is not consulted at all, which is what lets the four
-- members already in the table stay exactly as they are.
--
-- This is the same shape as the certificates in 0048: consent and the
-- redaction attestation are separate gates because they answer separate
-- questions.
--
-- THE PATH MUST BE LOCAL.
--
-- ck_st_video_local refuses anything with a scheme. A public URL in
-- this column would put a third party - whoever hosts it - in front of
-- every visitor to a page about children's therapy, receiving their
-- address and their referrer, and it would arrive through a text box
-- rather than through a decision. Files land under the centre's own
-- assets and are served from the same origin as the page.
-- =====================================================================

\set ON_ERROR_STOP on

ALTER TABLE hbh.site_team
  -- Relative to the site root, exactly like photo_path.
  ADD COLUMN intro_video_path        text,
  -- The still shown before it plays. Falls back to photo_path in the
  -- page when absent, so it is optional here.
  ADD COLUMN intro_video_poster_path text,
  ADD COLUMN intro_video_caption_ar  text,
  ADD COLUMN intro_video_caption_en  text,

  -- Consent for the FILM. See the note above.
  ADD COLUMN video_consent_given_at    timestamptz,
  ADD COLUMN video_consent_obtained_by integer
    REFERENCES hbh.users(user_id);

-- Both halves or neither. A date with nobody behind it records that
-- somebody was asked and loses who asked them, which is not a consent
-- record - it is the appearance of one.
ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_video_consent_pair
    CHECK ((video_consent_given_at IS NULL) = (video_consent_obtained_by IS NULL));

-- A published member with a film needs the film's own consent.
ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_video_consent
    CHECK (status = 'DRAFT'
           OR intro_video_path IS NULL
           OR (video_consent_given_at IS NOT NULL
               AND video_consent_obtained_by IS NOT NULL));

-- Local paths only - no scheme, no protocol-relative "//host/x", and no
-- walking out of the assets directory.
ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_video_local
    CHECK (
      (intro_video_path IS NULL
       OR (intro_video_path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
           AND intro_video_path !~ '^//'
           AND position('..' in intro_video_path) = 0))
      AND
      (intro_video_poster_path IS NULL
       OR (intro_video_poster_path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
           AND intro_video_poster_path !~ '^//'
           AND position('..' in intro_video_poster_path) = 0)));

-- The same rule for the photograph, which never had one. It is the same
-- column doing the same job, and leaving it open would mean the safer
-- of the two is the one nobody thought about.
ALTER TABLE hbh.site_team
  ADD CONSTRAINT ck_st_photo_local
    CHECK (photo_path IS NULL
           OR (photo_path !~ '^[a-zA-Z][a-zA-Z0-9+.-]*:'
               AND photo_path !~ '^//'
               AND position('..' in photo_path) = 0));

COMMENT ON COLUMN hbh.site_team.intro_video_path IS
  'Staff introduction film, relative to the site root. Never a session.';
COMMENT ON COLUMN hbh.site_team.video_consent_given_at IS
  'Consent for the FILM specifically. Not the same as consent_given_at.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0055');
