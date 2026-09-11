-- =====================================================================
-- 0051 - the settings screen becomes writable
--
-- Everything on that screen is a PARAMETER - the currency, the time
-- zone, the weekend - and the screen says so in its own subtitle. But
-- hbh_app held SELECT on hbh.centers and nothing else, so the row could
-- only be changed by a developer with the owner's credentials. A
-- parameter nobody can set is a constant with extra steps.
--
-- THREE GATES, and they answer three different questions.
--
-- 1. WHICH COLUMNS CAN MOVE AT ALL - a column-level GRANT.
--
--    `code` is not granted, and that is the whole mechanism protecting
--    it. It is the centre's identity OUTSIDE this database:
--    scripts/site-export.sh selects `WHERE c.code = 'HBH'`, and so do
--    the seeds. Renaming it through a screen would leave every one of
--    them matching nothing - and matching nothing is not an error, it
--    is an empty result reported as success. The site would export an
--    empty file and say it wrote one.
--
--    Column grants cannot tell one user from another here - every
--    request arrives as hbh_app - so this is not authorisation. It is
--    the coarser statement that this column is not editable by anybody
--    through the API, which is exactly what is wanted.
--
-- 2. WHO MAY WRITE THE REST - RLS, checking the permission inside the
--    policy rather than in Go, per rule 4.
--
-- 3. WHETHER A PARTICULAR CHANGE IS SOUND - a BEFORE trigger, because
--    RLS cannot see a transition. It compares OLD to NEW; a policy only
--    ever sees one row state.
--
--    currency_code is the one that needs it. Nothing converts stored
--    amounts, so changing EGP to USD does not restate the ledger - it
--    RELABELS it. A 600 invoice stays 600 and silently becomes six
--    hundred dollars. That is not a setting, it is a rewrite of every
--    historical amount, and no screen should be able to do it by
--    accident on a centre that has already billed anybody.
--
--    So: free to set while no money exists, refused once it does. A
--    centre being configured can still pick its currency; a centre with
--    a ledger needs a migration and a conversion, which is a decision
--    with a person behind it.
--
-- WHAT IS DELIBERATELY NOT GUARDED. time_zone and weekend_days change
-- freely. Every instant is stored UTC and converted for display only,
-- so a time zone change moves what is shown and nothing that is
-- recorded; and the weekend is read live by the booking screens, which
-- is the point of it being a row.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. The columns that may move. `code` and every audit column are
--    absent on purpose.
-- ---------------------------------------------------------------------
GRANT UPDATE (name_ar, name_en, country_code, currency_code,
              time_zone, weekend_days, updated_at, updated_by)
  ON hbh.centers TO hbh_app;

-- ---------------------------------------------------------------------
-- 2. Who may write. current_center_id() IS NOT NULL comes first, before
--    any other condition: identity is what closes the door, and a
--    policy that checks the centre alone lets an unauthenticated
--    connection through on any row where the comparison happens to
--    hold.
--
--    The USING clause carries the permission; the WITH CHECK clause
--    only pins the row to the caller's own centre, so a settings write
--    can never move the row to another centre.
-- ---------------------------------------------------------------------
CREATE POLICY p_centers_update ON hbh.centers
  FOR UPDATE
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SETTINGS.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id());

-- ---------------------------------------------------------------------
-- 3. Whether the change is sound.
--
--    SECURITY DEFINER with a pinned search_path: without the pin this
--    is a privilege escalation waiting for somebody to put a table
--    called `invoices` earlier on the path.
--
--    It RAISES and changes nothing, which keeps it on the right side of
--    the rule this project has paid for twice: a function either
--    changes state or refuses, never both, because the RAISE unwinds
--    the transaction and takes the change with it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.guard_center_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  has_money boolean;
BEGIN
  -- The code is ungranted, so a change here means the owner or a
  -- superuser, not the API. Refused anyway: the reason it cannot move
  -- is that things outside this database match on it, and that is as
  -- true for a psql session as for a screen.
  IF NEW.code IS DISTINCT FROM OLD.code THEN
    RAISE EXCEPTION 'HB061: center code is immutable'
      USING HINT = 'scripts and seeds match on it; renaming it breaks them silently';
  END IF;

  IF NEW.currency_code IS DISTINCT FROM OLD.currency_code THEN
    SELECT EXISTS (
      SELECT 1 FROM hbh.invoices  WHERE center_id = OLD.center_id
      UNION ALL
      SELECT 1 FROM hbh.payments  WHERE center_id = OLD.center_id
    ) INTO has_money;

    IF has_money THEN
      RAISE EXCEPTION 'HB062: currency cannot change once amounts exist'
        USING HINT = 'nothing converts stored amounts; changing it relabels every past invoice';
    END IF;
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_guard_center_settings
  BEFORE UPDATE ON hbh.centers
  FOR EACH ROW
  EXECUTE FUNCTION hbh.guard_center_settings();

INSERT INTO hbh.schema_migrations (version) VALUES ('0051');
