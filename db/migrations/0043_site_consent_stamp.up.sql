-- =====================================================================
-- 0043 - recording a consent, without letting the client write one
--
-- 0040 made a published testimonial or photograph impossible without a
-- recorded consent, which was the point. It also left no way to record
-- one: consent_given_at and consent_obtained_by are not in any write
-- allow list, so the constraint could never be satisfied and nothing
-- could ever be published. A gate with no key is not a gate, it is a
-- wall - found by trying to publish through the real path rather than by
-- reading the migration back.
--
-- THE FIX IS NOT TO LET THE CLIENT WRITE THEM. Both columns answer
-- questions about an event that happened in a room: who asked this
-- family, and when. A request that carries the date can backdate it, and
-- a request that carries the person can name somebody who was not there
-- - and consent_obtained_by is a foreign key to hbh.users, so any valid
-- id would have been accepted.
--
-- So consent_given_at becomes writable and its VALUE is ignored. Sending
-- anything non-null means "I have taken this consent"; the database
-- stamps the real time and the real person from the session. Sending
-- null is a withdrawal and clears both.
--
-- The same shape as 0042's publish stamp, for the same reason, and the
-- same naming note applies: `_consent` sorts after `_publish` and before
-- `_stamp`, so the permission check still runs first.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE FUNCTION hbh.trg_site_consent_stamp()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.consent_given_at IS NOT NULL THEN
    -- Only on the transition. Re-stamping on every edit would move the
    -- date forward each time somebody fixed a typo, and the date is the
    -- record of when a family actually agreed.
    IF TG_OP = 'INSERT' OR OLD.consent_given_at IS NULL THEN
      NEW.consent_given_at    := now();
      NEW.consent_obtained_by := hbh.current_user_id();
    ELSE
      -- An existing consent keeps the values it was recorded with,
      -- whatever the request says.
      NEW.consent_given_at    := OLD.consent_given_at;
      NEW.consent_obtained_by := OLD.consent_obtained_by;
    END IF;
  ELSE
    -- Withdrawn. Both go together: a row that names who took a consent
    -- that no longer exists is a row that contradicts itself, and the
    -- audit trail holds the history of both.
    NEW.consent_obtained_by := NULL;
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_team_consent BEFORE INSERT OR UPDATE ON hbh.site_team
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_consent_stamp();
CREATE TRIGGER trg_site_reviews_consent BEFORE INSERT OR UPDATE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_consent_stamp();

REVOKE ALL ON FUNCTION hbh.trg_site_consent_stamp() FROM PUBLIC;

INSERT INTO hbh.schema_migrations (version) VALUES ('0043');
