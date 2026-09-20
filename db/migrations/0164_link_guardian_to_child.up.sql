-- =====================================================================
-- Hand By Hand (new) - migration 0164: a family can be given to a child
-- who already exists.
--
-- HBH-099. Everything that writes hbh.guardian_children today writes it at
-- CREATION time - submit_enrolment and convert_enrolment, the enrolment
-- path - so a child already in the system could only be given a family by
-- an INSERT as the owner. Two live children show it now; the first child
-- added from the console hits the same wall. Same shape as HBH-049's
-- caseload: policies, indexes, and no door.
--
-- THE OWNER'S RULES, answered 2026-09-18 and NOT guessed:
--   * a child may exist with NO guardian - so this is a later step, not a
--     condition of creating a child;
--   * MORE THAN ONE guardian may be linked to one child, and linking the
--     second does not end the first (a father and a mother, shared
--     custody).
--
-- AND THE PRIMARY, answered the same day: ONE primary and no more - the
-- one the invoice and the report go to - and the second guardian stays
-- linked with their own rights. LINKING DOES NOT MOVE THE TRAIT.
--
-- So it is built three ways at once, and each one matters:
--
--   * link_guardian_to_child DOES NOT TAKE p_is_primary AT ALL. A new link
--     is never primary. The trait cannot be acquired as a side effect of
--     an unrelated call, and there is no argument to get wrong.
--   * MOVING IT IS A NAMED ACT: set_primary_guardian, below. Whoever wants
--     to change who receives the invoice says so.
--   * THE DATABASE ENFORCES THE NUMBER, not the function: uix_gc_one_primary
--     (child_id WHERE is_primary_flg AND active_flg) is older than this
--     question and already says "at most one live primary per child". A
--     condition inside a function would be a second copy of a rule, and
--     the weaker copy decides (rule 4).
--
-- A CHILD WITH NO PRIMARY IS LEGAL. He allowed a child with no guardian at
-- all, so the index forbids TWO and does not demand ONE. Nothing here
-- rejects zero. Measured before writing: no child in this database has two
-- live primaries, and none with a live link has none.
--
-- THE LIVE-VIEW FLAG IS NOT THIS FUNCTION'S TO RAISE. can_view_live_flg
-- stays at its default false: trg_live_flag_needs_consent refuses it
-- without a recorded consent (HB081), and consent is grant_consent's job.
-- A link is not a consent.
--
-- RELATIONSHIP IS REQUIRED AND VALIDATED against the RELATIONSHIP lookup
-- (FATHER, MOTHER, GUARDIAN today). No default: "who is this person to the
-- child" is a fact about a family, and a default would invent it.
--
-- NO NEW SQLSTATE:
--   HB092 -> 403  the caller lacks GUARDIAN.MANAGE, asked before any id
--   HB051 -> 404  no such child / guardian / link IN THIS CENTRE
--   HB021 -> 400  a relationship code that is not in the lookup
--
-- RE-LINKING is not an error: the primary key is (guardian_id, child_id),
-- so a pair that was unlinked is REVIVED rather than inserted twice, and a
-- live pair is returned as it stands.
--
-- UNLINKING IS SOFT (rule 3). is_primary_flg is left as it was on the
-- ended row: the index only counts live rows, and who used to be the
-- primary contact is part of a child's history.
-- =====================================================================

DO $guard$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0163') THEN
    RAISE EXCEPTION 'migration 0163 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.proname IN ('link_guardian_to_child',
                                                       'unlink_guardian_from_child',
                                                       'set_primary_guardian')) THEN
    RAISE EXCEPTION 'somebody built these elsewhere - read them before this runs';
  END IF;
END
$guard$;

CREATE FUNCTION hbh.link_guardian_to_child(p_guardian_id       integer,
                                           p_child_id          integer,
                                           p_relationship_code text,
                                           p_can_view_reports  boolean DEFAULT true)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_n      integer;
BEGIN
  -- 1. The permission, before any id is read.
  IF NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'linking a family needs GUARDIAN.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  -- 2. The rows, each with the centre in its condition.
  IF NOT EXISTS (SELECT 1 FROM hbh.children c
                  WHERE c.child_id = p_child_id AND c.center_id = l_center AND c.active_flg) THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB051';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.guardians g
                  WHERE g.guardian_id = p_guardian_id AND g.center_id = l_center AND g.active_flg) THEN
    RAISE EXCEPTION 'no such guardian %', p_guardian_id USING ERRCODE = 'HB051';
  END IF;

  -- 3. The relationship is a fact, and the lookup is what says which facts
  --    this centre recognises.
  IF NOT EXISTS (SELECT 1 FROM hbh.lookup_values lv
                 JOIN hbh.lookup_types lt ON lt.lookup_type_id = lv.lookup_type_id
                 WHERE lt.code = 'RELATIONSHIP' AND lv.code = p_relationship_code AND lv.active_flg) THEN
    RAISE EXCEPTION 'relationship % is not one this centre recognises', p_relationship_code
      USING ERRCODE = 'HB021';
  END IF;

  -- 4. The write. The pair is the primary key, so a link that was ended
  --    comes back rather than colliding, and a live one is left as it is.
  --    A NEW link takes the column default (false).
  --
  --    AND A REVIVED ONE IS DEMOTED, which the first draft of this
  --    migration did not do - it left is_primary_flg at whatever the
  --    ended row carried, and that broke the rule in this header twice
  --    over. Measured, both of them:
  --
  --      * the mother is primary, she is unlinked (her row keeps the flag
  --        on purpose - that is history), the centre moves the invoice to
  --        the father, and then she is linked again: the revived true
  --        meets his live true and uix_gc_one_primary raises
  --        23505 - a raw SQLSTATE, not an HB code, so the API answers 500
  --        and the screen says "an unexpected error" about an ordinary
  --        reception action;
  --      * and where nothing collides it is quieter and no better: the
  --        link comes back PRIMARY although nobody called
  --        set_primary_guardian, so linking DID move the trait.
  --
  --    The first probe missed both because it relinked at the one moment
  --    when no other live primary existed - a revived true landing on
  --    empty ground. Two rows on the same side of the rule.
  --
  --    So the flag is set here, and CONDITIONALLY: an already-live row
  --    keeps what it has (correcting a relationship code must not demote
  --    the primary contact as a side effect), and only a row coming back
  --    from ended is demoted. Moving the trait stays one named act.
  INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code,
                                     can_view_reports_flg)
  VALUES (p_guardian_id, p_child_id, p_relationship_code, p_can_view_reports)
  ON CONFLICT (guardian_id, child_id) DO UPDATE
     SET active_flg           = true,
         deleted_at           = NULL,
         relationship_code    = EXCLUDED.relationship_code,
         can_view_reports_flg = EXCLUDED.can_view_reports_flg,
         is_primary_flg       = CASE WHEN hbh.guardian_children.active_flg
                                     THEN hbh.guardian_children.is_primary_flg
                                     ELSE false END
   WHERE NOT hbh.guardian_children.active_flg
      OR hbh.guardian_children.relationship_code    IS DISTINCT FROM EXCLUDED.relationship_code
      OR hbh.guardian_children.can_view_reports_flg IS DISTINCT FROM EXCLUDED.can_view_reports_flg;
  GET DIAGNOSTICS l_n = ROW_COUNT;

  -- true when this call changed something, false when the link already
  -- said exactly this. can_view_live_flg is never touched here.
  RETURN l_n > 0;
END
$$;

REVOKE ALL ON FUNCTION hbh.link_guardian_to_child(integer, integer, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.link_guardian_to_child(integer, integer, text, boolean) TO hbh_app;

COMMENT ON FUNCTION hbh.link_guardian_to_child(integer, integer, text, boolean) IS
  'Links a guardian to a child who already exists. GUARDIAN.MANAGE; centre-bound; several guardians per child are allowed and a new link is NEVER primary - use set_primary_guardian for that; can_view_live_flg is left to consent (0164, HBH-099).';

-- ---------------------------------------------------------------------
-- Moving the primary is its own act, with its own name.
--
-- Demote then promote, in TWO statements: the same row may not be updated
-- twice in one statement, and more importantly the index would see two
-- live primaries for an instant if both happened at once.
--
-- The child keeps at most one primary because uix_gc_one_primary says so,
-- not because this function is careful. If somebody ever writes a third
-- path, the index still holds.
-- ---------------------------------------------------------------------
CREATE FUNCTION hbh.set_primary_guardian(p_guardian_id integer, p_child_id integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_n      integer;
BEGIN
  IF NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'moving the primary contact needs GUARDIAN.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  -- The link must be live, and the child must be this centre's. An ended
  -- link is not a candidate: the invoice would go to somebody the centre
  -- has already said is no longer answering for this child.
  IF NOT EXISTS (SELECT 1 FROM hbh.guardian_children gc
                  JOIN hbh.children c ON c.child_id = gc.child_id
                  WHERE gc.guardian_id = p_guardian_id AND gc.child_id = p_child_id
                    AND gc.active_flg AND c.center_id = l_center) THEN
    RAISE EXCEPTION 'no such family link' USING ERRCODE = 'HB051';
  END IF;

  UPDATE hbh.guardian_children gc
     SET is_primary_flg = false
   WHERE gc.child_id     = p_child_id
   AND   gc.active_flg
   AND   gc.is_primary_flg
   AND   gc.guardian_id <> p_guardian_id;

  UPDATE hbh.guardian_children gc
     SET is_primary_flg = true
   WHERE gc.guardian_id = p_guardian_id
   AND   gc.child_id    = p_child_id
   AND   gc.active_flg
   AND   NOT gc.is_primary_flg;
  GET DIAGNOSTICS l_n = ROW_COUNT;

  -- false when they were already the primary: the state asked for holds.
  RETURN l_n > 0;
END
$$;

REVOKE ALL ON FUNCTION hbh.set_primary_guardian(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_primary_guardian(integer, integer) TO hbh_app;

COMMENT ON FUNCTION hbh.set_primary_guardian(integer, integer) IS
  'Moves the primary contact - the one the invoice and the report go to - to a guardian already linked to this child. GUARDIAN.MANAGE; centre-bound; the previous primary stays linked with their own rights; at most one live primary is the index''s rule, not this function''s (0164, HBH-099).';

CREATE FUNCTION hbh.unlink_guardian_from_child(p_guardian_id integer, p_child_id integer)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center integer := hbh.current_center_id();
  l_n      integer;
BEGIN
  IF NOT hbh.has_permission('GUARDIAN.MANAGE') THEN
    RAISE EXCEPTION 'ending a family link needs GUARDIAN.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.guardian_children gc
                  JOIN hbh.children c ON c.child_id = gc.child_id
                  WHERE gc.guardian_id = p_guardian_id AND gc.child_id = p_child_id
                    AND c.center_id = l_center) THEN
    RAISE EXCEPTION 'no such family link' USING ERRCODE = 'HB051';
  END IF;

  -- Soft, and the row keeps is_primary_flg: uix_gc_one_primary counts only
  -- live rows, and who used to be the primary contact is history.
  UPDATE hbh.guardian_children gc
     SET active_flg = false,
         deleted_at = now()
   WHERE gc.guardian_id = p_guardian_id
   AND   gc.child_id    = p_child_id
   AND   gc.active_flg;
  GET DIAGNOSTICS l_n = ROW_COUNT;

  RETURN l_n > 0;
END
$$;

REVOKE ALL ON FUNCTION hbh.unlink_guardian_from_child(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.unlink_guardian_from_child(integer, integer) TO hbh_app;

COMMENT ON FUNCTION hbh.unlink_guardian_from_child(integer, integer) IS
  'Ends one family link: soft, dated, and the row stays because a child''s history includes who used to answer for them. GUARDIAN.MANAGE; centre-bound; false when it had already ended (0164, HBH-099).';

INSERT INTO hbh.schema_migrations (version) VALUES ('0164');
