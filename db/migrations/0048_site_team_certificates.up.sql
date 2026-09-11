-- =====================================================================
-- 0048 - scanned certificates on the public site
--
-- The owner decided, asked directly, that certificate images are shown
-- on the site rather than kept as internal evidence behind the written
-- claim. This table is that decision, with the guard they also asked
-- for.
--
-- WHAT THIS TABLE ACTUALLY IS, said plainly because the name hides it: a
-- store of scanned identity-bearing documents belonging to named members
-- of staff. An Egyptian certificate commonly carries a national
-- identity number, an address, sometimes a telephone. This project's own
-- rule keeps the national identity number off a child's printed card -
-- a card that leaves the building with the family - so a scan of one on
-- the open internet is the larger exposure, not the smaller.
--
-- TWO INDEPENDENT GATES, and neither inherits from the member row.
--
--   consent_given_at / consent_obtained_by
--     Agreeing to have your photograph on a page is not agreeing to have
--     your certificate published. Different document, different
--     decision, own columns.
--
--   redaction_checked_at / redaction_checked_by
--     Somebody looked at this scan and states it carries no national
--     identity number, no address and no telephone. Recorded against
--     their name.
--
-- WHY BOTH, WHEN ONE SOUNDS LIKE ENOUGH. Because we watched the
-- difference cost something today. A family consented to publishing a
-- testimonial, and the testimonial names their child four times. Consent
-- to publish is not an inspection of what is published. The person who
-- agrees and the person who checks are answering different questions,
-- and a table with one column cannot tell which was answered.
--
-- AND IT IS AN ATTESTATION, NOT A SCAN. No code here reads the image. A
-- machine that claimed to find identity numbers in a photograph would be
-- worse than nothing: whoever pressed publish would believe it had
-- looked. A person looked, and their name is on it.
--
-- CHANGING THE FILE RETRACTS THE CHECK. Somebody attested to a
-- particular image. A different image has been inspected by nobody, and
-- swapping the file under an approved row is the obvious way to get an
-- unredacted scan published.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE hbh.site_team_certificates (
  certificate_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  member_id      integer     NOT NULL,

  -- A path relative to site/, like photo_path. NEVER built from
  -- member_id: a certificate appears because a row ties it to that
  -- person, not because a file in assets/ happened to match a name.
  path           text        NOT NULL,

  -- What the document is, not whose it is. The heading above the card
  -- already says whose; repeating the name inside every image's
  -- description writes it into places read out of context.
  caption_ar     text,
  caption_en     text,

  sort_order     integer     NOT NULL DEFAULT 0,

  consent_given_at      timestamptz,
  consent_obtained_by   integer,
  redaction_checked_at  timestamptz,
  redaction_checked_by  integer,

  status         text        NOT NULL DEFAULT 'DRAFT',
  published_at   timestamptz,
  published_by   integer,

  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,

  CONSTRAINT pk_site_team_certificates PRIMARY KEY (certificate_id),
  CONSTRAINT fk_stc_center    FOREIGN KEY (center_id)            REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_stc_member    FOREIGN KEY (member_id)            REFERENCES hbh.site_team (member_id),
  CONSTRAINT fk_stc_consenter FOREIGN KEY (consent_obtained_by)  REFERENCES hbh.users (user_id),
  CONSTRAINT fk_stc_checker   FOREIGN KEY (redaction_checked_by) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_stc_publisher FOREIGN KEY (published_by)         REFERENCES hbh.users (user_id),

  CONSTRAINT ck_stc_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_stc_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),

  -- Both gates, and both required to publish.
  CONSTRAINT ck_stc_consent CHECK (
    status = 'DRAFT' OR (consent_given_at IS NOT NULL AND consent_obtained_by IS NOT NULL)
  ),
  CONSTRAINT ck_stc_redaction CHECK (
    status = 'DRAFT' OR (redaction_checked_at IS NOT NULL AND redaction_checked_by IS NOT NULL)
  ),

  -- Half a record is not a record. The same pair rule 0046 added after a
  -- raw insert produced a consent with a date and no person.
  CONSTRAINT ck_stc_consent_pair CHECK (
    (consent_given_at IS NULL) = (consent_obtained_by IS NULL)
  ),
  CONSTRAINT ck_stc_redaction_pair CHECK (
    (redaction_checked_at IS NULL) = (redaction_checked_by IS NULL)
  ),

  CONSTRAINT ck_stc_path CHECK (length(btrim(path)) BETWEEN 1 AND 200)
);

CREATE INDEX ix_site_team_certificates ON hbh.site_team_certificates (member_id, sort_order)
  WHERE active_flg;

-- ---------------------------------------------------------------------
-- The redaction attestation, stamped by the database
--
-- Same shape as the consent and the testimonial's text review: the value
-- the client sends means "I have checked this", and the columns are
-- filled from the session. A request that could name the checker could
-- name somebody who never opened the file.
-- ---------------------------------------------------------------------
CREATE FUNCTION hbh.trg_site_redaction_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.redaction_checked_at IS NOT NULL THEN
    IF TG_OP = 'INSERT'
       OR OLD.redaction_checked_at IS NULL
       OR OLD.redaction_checked_by IS NULL THEN
      NEW.redaction_checked_at := now();
      NEW.redaction_checked_by := hbh.current_user_id();
    ELSE
      NEW.redaction_checked_at := OLD.redaction_checked_at;
      NEW.redaction_checked_by := OLD.redaction_checked_by;
    END IF;
  ELSE
    NEW.redaction_checked_by := NULL;
  END IF;

  -- A DIFFERENT FILE HAS BEEN CHECKED BY NOBODY. Without this, the way
  -- to publish an unredacted scan is to get a clean one approved and
  -- then change the path.
  IF TG_OP = 'UPDATE' AND NEW.path IS DISTINCT FROM OLD.path THEN
    NEW.redaction_checked_at := NULL;
    NEW.redaction_checked_by := NULL;
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_certs_touch BEFORE UPDATE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_certs_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('certificate_id');

-- Name order decides firing order, and it has to be: publish (permission)
-- before consent and redaction (stamps) before stamp (the publish stamp).
-- `_publish` < `_redact` < `_stampconsent` < `_stamppub` alphabetically.
CREATE TRIGGER trg_site_certs_publish BEFORE INSERT OR UPDATE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_certs_redact BEFORE INSERT OR UPDATE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_redaction_stamp();
CREATE TRIGGER trg_site_certs_stampconsent BEFORE INSERT OR UPDATE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_consent_stamp();
CREATE TRIGGER trg_site_certs_stamppub BEFORE INSERT OR UPDATE ON hbh.site_team_certificates
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();

ALTER TABLE hbh.site_team_certificates ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_site_certs_select ON hbh.site_team_certificates
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_certs_insert ON hbh.site_team_certificates
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_certs_update ON hbh.site_team_certificates
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

GRANT SELECT, INSERT, UPDATE ON hbh.site_team_certificates TO hbh_app;
REVOKE ALL ON FUNCTION hbh.trg_site_redaction_stamp() FROM PUBLIC;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0048');
