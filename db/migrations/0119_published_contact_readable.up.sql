-- =====================================================================
-- 0119 — A SIGNED-IN FAMILY MAY READ THE CENTRE'S OWN CONTACT ROW
--
-- NUMBER RESERVED BEFORE WRITING. 0101-0104, 0106 and 0117-0118 belong to
-- other sessions in this tree; 0100, 0105 and 0107 are mine.
--
-- NO NEW SQLSTATE and no function: one permissive policy.
--
-- ---------------------------------------------------------------------
-- WHAT WAS WRONG
--
-- hbh.site_contact holds the centre's phone, address, map link and
-- opening hours, and the row is PUBLISHED - it is served to anonymous
-- visitors on the public site, today, without a login.
--
-- And a signed-in PARENT could not read it. The only SELECT policy asks
-- for SITE.EDIT, which exists to decide who may see and change DRAFTS.
-- A family got an empty list: a 200 with nothing in it, which is the
-- worst shape a refusal can take because it reads as "the centre has no
-- phone number".
--
-- That is an accident of where the row lives, not a decision anybody
-- made. Nothing here is private by any measure: it is on a public web
-- page, and the family has the number already - they were called from it.
--
-- ---------------------------------------------------------------------
-- WHY A SECOND POLICY AND NOT AN EDIT TO THE FIRST
--
-- The two answer different questions and must keep answering them
-- separately:
--
--   p_site_contact_select        who may see the row AT ALL, drafts
--                                included, in order to edit it.
--   this one                     who may see it once it is PUBLISHED.
--
-- Widening the first would have let anyone signed in read a DRAFT - an
-- address the centre is still deciding on, or one being corrected. RLS
-- policies are OR'd, so adding one grants strictly what it names and
-- changes nothing about the other.
--
-- PUBLISHED IS PART OF THE CONDITION, not an afterthought. The status
-- column is the whole difference between "the centre says this" and
-- "somebody is drafting this", and a screen that showed the second to a
-- family would publish it on the centre's behalf.
-- =====================================================================

DROP POLICY IF EXISTS p_site_contact_read_published ON hbh.site_contact;

CREATE POLICY p_site_contact_read_published ON hbh.site_contact
  FOR SELECT
  USING (
    -- Identity first, before any other condition. A row whose centre
    -- matches NULL would otherwise reach an unauthenticated connection.
    hbh.current_center_id() IS NOT NULL
    AND center_id = hbh.current_center_id()
    AND active_flg
    AND status = 'PUBLISHED'
  );

COMMENT ON POLICY p_site_contact_read_published ON hbh.site_contact IS
  'Anyone signed in to this centre may read its PUBLISHED contact row - the same text anonymous visitors already read on the public site. Drafts stay behind SITE.EDIT.';

INSERT INTO hbh.schema_migrations (version) VALUES ('0119');
