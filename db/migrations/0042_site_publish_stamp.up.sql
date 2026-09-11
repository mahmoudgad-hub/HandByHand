-- =====================================================================
-- 0042 - the database stamps who published, not the client
--
-- 0041 put a gate on the transition and stopped there, which left the
-- rows unpublishable in practice: ck_*_published demands published_at
-- and published_by, and the only way to satisfy them was for the client
-- to send both.
--
-- A CLIENT MUST NOT NAME THE PUBLISHER. "Who put this on the open
-- internet" is a fact about a session, and a request that carries it is
-- a request that can lie about it - published_by is a foreign key to
-- hbh.users and any valid user id would have been accepted. The same
-- reasoning as hbh.record_nps taking no user id: the session already
-- knows.
--
-- So the stamp is filled in here, from hbh.current_user_id(), and
-- cleared on the way back to DRAFT. The client sends one field - status
-- - and the two columns that matter are not writable by anybody.
--
-- ORDER MATTERS AGAINST 0041. This trigger fills the columns; that one
-- refuses the transition without SITE.PUBLISH. Postgres fires BEFORE
-- triggers in name order, and `trg_site_*_publish` (0041) sorts before
-- `trg_site_*_stamp` (this one) on every table - so permission is
-- checked first and an unauthorised change is refused before anything
-- is written. That is the order it must be, and it is worth stating
-- because it rests on a naming coincidence: rename either trigger and
-- the guard could start running after the stamp.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE FUNCTION hbh.trg_site_publish_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.status = 'PUBLISHED'
     AND (TG_OP = 'INSERT' OR OLD.status IS DISTINCT FROM 'PUBLISHED') THEN
    NEW.published_at := now();
    NEW.published_by := hbh.current_user_id();
  ELSIF NEW.status = 'DRAFT' THEN
    -- Withdrawn. The stamp goes with it: a draft that still claims to
    -- have been published on a date is a row that contradicts itself,
    -- and the audit trail already holds the history of both.
    NEW.published_at := NULL;
    NEW.published_by := NULL;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_contact_stamp BEFORE INSERT OR UPDATE ON hbh.site_contact
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();
CREATE TRIGGER trg_site_faq_stamp     BEFORE INSERT OR UPDATE ON hbh.site_faq
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();
CREATE TRIGGER trg_site_team_stamp    BEFORE INSERT OR UPDATE ON hbh.site_team
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();
CREATE TRIGGER trg_site_reviews_stamp BEFORE INSERT OR UPDATE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();

REVOKE ALL ON FUNCTION hbh.trg_site_publish_stamp() FROM PUBLIC;

INSERT INTO hbh.schema_migrations (version) VALUES ('0042');
