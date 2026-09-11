-- =====================================================================
-- 0056 - archiving a website row, which has never once worked
--
-- THE DEFECT. Pressing archive on anything under "الموقع التعريفي"
-- answered 403. So did restoring it. Every site table, since the day
-- each was added - 0041, 0045, 0047, 0048 - and hbh.nps_surveys with
-- them. Nobody had pressed the button.
--
-- WHY, and it is not the write policy. Archiving is
--
--   UPDATE ... SET active_flg = false
--
-- and PostgreSQL requires the row to STILL BE VISIBLE UNDER THE SELECT
-- POLICY after an UPDATE, not only before it. The select policies read
--
--   center_id = current_center_id() AND active_flg AND has_permission(...)
--
-- so the moment active_flg goes false the new row fails the read the
-- engine performs on it, and the whole statement is refused with
-- 42501 - "new row violates row-level security policy". The message
-- names row level security, so it reads as a permission problem, and
-- the permission is fine. The caller holds SITE.EDIT, the write policy
-- passes, and the refusal comes from the READ policy on a row the
-- caller was in the middle of hiding.
--
-- Restore fails from the other side: it looks for a row WHERE NOT
-- active_flg, and the select policy makes that row invisible, so it
-- matches nothing and answers 404. Archived and unarchivable, invisible
-- and unrestorable.
--
-- Confirmed on a scratch table before writing this: the same UPDATE
-- passes with active_flg removed from the SELECT policy and fails with
-- it there, everything else held identical.
--
-- THE FIX IS THE ONE THIS PROJECT ALREADY CHOSE. Migration 0013 -
-- "seeing what you archived" - added a second, permissive SELECT policy
-- to the catalogue tables: whoever may archive a row may see archived
-- rows. Policies are OR'd, so the ordinary reader still sees only live
-- rows and the manager sees both. The site tables and the satisfaction
-- surveys were simply never given theirs.
--
-- The permission on each matches the one that may WRITE the table, so
-- this widens nothing: anybody who can already archive a row can now
-- see it afterwards, and nobody else gains anything.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- The public site. SITE.EDIT, the same code its write policies require.
-- ---------------------------------------------------------------------
CREATE POLICY p_site_contact_select_archived ON hbh.site_contact
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_faq_select_archived ON hbh.site_faq
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_services_select_archived ON hbh.site_services
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_programs_select_archived ON hbh.site_programs
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_select_archived ON hbh.site_team
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_facts_select_archived ON hbh.site_team_facts
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_team_certificates_select_archived ON hbh.site_team_certificates
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

-- A testimonial is a family's words, and guardian_id ties it to them.
-- The archived view is no wider than the live one - same centre, same
-- permission - so withdrawing a review still hides it from the site and
-- still leaves it findable by the person who withdrew it.
CREATE POLICY p_site_reviews_select_archived ON hbh.site_reviews
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'));

-- ---------------------------------------------------------------------
-- The satisfaction surveys, which had the same defect for the same
-- reason and are not part of the site at all.
--
-- NPS.MANAGE: p_nps_select carries no permission test, but the console
-- screen and the resource description both require NPS.MANAGE to reach
-- this table, and the archived view should not be the wider of the two.
-- ---------------------------------------------------------------------
CREATE POLICY p_nps_select_archived ON hbh.nps_surveys
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('NPS.MANAGE'));

INSERT INTO hbh.schema_migrations (version) VALUES ('0056');
