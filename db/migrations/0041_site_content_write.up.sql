-- =====================================================================
-- 0041 - writing the site's content, and who may publish it
--
-- 0040 created the tables and granted SELECT only, deliberately: a write
-- grant without a matching policy is a window in which a client can
-- insert a row nothing has decided the rules for. The policies and the
-- grants arrive together, here, with the screens that use them.
--
-- TWO GATES, TWO MECHANISMS, and the split is the point.
--
--   SITE.EDIT is a POLICY. Whether this row may be written at all is a
--   question about the row, which is what row level security answers.
--
--   SITE.PUBLISH is a TRIGGER. "You may change every column except this
--   one" is not a question about a row, and RLS cannot ask it: a policy
--   sees the finished row, not which column moved. Column-level GRANT
--   cannot do it either - it is granted to a database ROLE, and every
--   request in this system arrives as the same role, hbh_app, with the
--   person's identity set inside the transaction.
--
--   So the trigger compares OLD.status with NEW.status and refuses the
--   change itself. It is the only construct here that can see a
--   transition, which is exactly what is being controlled.
--
-- NO DELETE GRANT, on any of these or anything else. Rule 3: removal is
-- active_flg = false, which is an UPDATE and goes through the same gate
-- as any other edit.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- Publishing is a separate act from writing
--
-- SECURITY DEFINER with a pinned search_path, like every other function
-- in this schema that reads permissions: unpinned it is a privilege
-- escalation waiting for somebody to create a table that shadows a name.
--
-- It refuses in BOTH directions. Taking something OFF the site is as
-- much a publishing decision as putting it on: a member of staff who
-- could quietly unpublish the centre's phone number could take the
-- contact section off the page without being allowed to change it.
-- ---------------------------------------------------------------------
CREATE FUNCTION hbh.trg_site_publish_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'PUBLISHED' AND NOT hbh.has_permission('SITE.PUBLISH') THEN
      RAISE EXCEPTION 'publishing site content needs SITE.PUBLISH'
        USING ERRCODE = 'HB100';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.has_permission('SITE.PUBLISH') THEN
    RAISE EXCEPTION 'changing site content between draft and published needs SITE.PUBLISH'
      USING ERRCODE = 'HB100';
  END IF;

  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_contact_publish BEFORE INSERT OR UPDATE ON hbh.site_contact
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_faq_publish     BEFORE INSERT OR UPDATE ON hbh.site_faq
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_team_publish    BEFORE INSERT OR UPDATE ON hbh.site_team
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_reviews_publish BEFORE INSERT OR UPDATE ON hbh.site_reviews
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();

-- A section becoming visible is a publishing act by any other name: it
-- is the difference between the page carrying a testimonials block and
-- not carrying one.
CREATE FUNCTION hbh.trg_site_section_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NEW.visible_flg IS DISTINCT FROM OLD.visible_flg
     AND NOT hbh.has_permission('SITE.PUBLISH') THEN
    RAISE EXCEPTION 'showing or hiding a site section needs SITE.PUBLISH'
      USING ERRCODE = 'HB100';
  END IF;
  RETURN NEW;
END;
$fn$;

CREATE TRIGGER trg_site_sections_publish BEFORE UPDATE ON hbh.site_sections
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_section_guard();

-- ---------------------------------------------------------------------
-- WRITE POLICIES
--
-- Every one begins with the identity check, before the centre and before
-- the permission. A policy whose first term is the centre hands
-- everything to an unauthenticated connection the moment
-- current_center_id() is NULL on both sides of the comparison.
--
-- WITH CHECK pins center_id to the caller's own centre on the way in, so
-- a client cannot write a row into another centre by naming it.
-- ---------------------------------------------------------------------
CREATE POLICY p_site_sections_update ON hbh.site_sections
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_site_contact_insert ON hbh.site_contact
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_contact_update ON hbh.site_contact
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_site_faq_insert ON hbh.site_faq
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_faq_update ON hbh.site_faq
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_site_team_insert ON hbh.site_team
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_update ON hbh.site_team
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

CREATE POLICY p_site_reviews_insert ON hbh.site_reviews
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_reviews_update ON hbh.site_reviews
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

-- ---------------------------------------------------------------------
-- GRANTS
--
-- INSERT and UPDATE. No DELETE anywhere, on purpose and by rule.
--
-- A note for whoever writes the acceptance suite: after this migration a
-- refusal changes SHAPE. Before the grant, a write by somebody without
-- SITE.EDIT failed with 42501 - no privilege. After it, the privilege
-- exists and the POLICY decides, so a refused UPDATE matches zero rows
-- and reports success. Assert the row count, never the absence of an
-- exception, or the test passes the day somebody widens the policy.
-- ---------------------------------------------------------------------
GRANT INSERT, UPDATE ON hbh.site_contact, hbh.site_faq,
                        hbh.site_team, hbh.site_reviews
  TO hbh_app;
GRANT UPDATE ON hbh.site_sections TO hbh_app;

REVOKE ALL ON FUNCTION hbh.trg_site_publish_guard() FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.trg_site_section_guard() FROM PUBLIC;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0041');
