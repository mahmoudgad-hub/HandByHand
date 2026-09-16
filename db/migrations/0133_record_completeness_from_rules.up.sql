-- =====================================================================
-- Hand By Hand (new) - migration 0133: what "complete" means is data
-- (EN-D4 · EN-06, OD-10 · OD-11)
--
-- OD-11: the definition of a complete record comes from the database,
-- not from code - entity, field, required, active, order - and the
-- centre administrator sets it. OD-10: an incomplete record sends the
-- family to finish it on their next portal visit, prefilled, and does
-- NOT cancel anything already booked.
--
-- So: a table of rules, and a function that reads them and writes
-- guardians.record_completeness (added by 0129, empty until now).
--
-- ---------------------------------------------------------------------
-- THREE VALUES, EACH MEANING ONE THING
--
--   COMPLETE  every required field is filled - on the guardian and on
--             each of their active beneficiaries.
--   MINIMAL   nothing is filled beyond what the schema itself forces
--             (a guardian cannot exist without a name and a mobile).
--             This is exactly what an online consultation delivers, and
--             it is worth telling apart from "half done".
--   PARTIAL   everything in between.
--
-- ---------------------------------------------------------------------
-- TWO TRAPS, BOTH SEEN BEFORE THE FIRST LINE WAS WRITTEN
--
-- 1. THE FUNCTION WRITES THE TABLE WHOSE TRIGGER CALLS IT.
--    recompute_completeness updates hbh.guardians; the trigger that
--    recomputes fires on updates to hbh.guardians. Left alone that is a
--    loop. The guard is structural, not a depth counter: the trigger
--    fires only when record_completeness did NOT change - which is to
--    say, when some other field did - and the function writes only when
--    the value would actually differ. A recompute's own write changes
--    record_completeness, so it cannot wake itself.
--
-- 2. A FROZEN ROW WOULD KILL A CENTRE-WIDE RECOMPUTE.
--    0128 left hbh.guardians 668 writable only by retirement; 0129's
--    backfill died on it over an unrelated column. A rule change
--    recomputes every guardian of the centre, and one frozen row would
--    abort the rule change itself - an administrator unable to edit
--    the completeness rules because of a seven-digit phone number
--    nobody can fix. So the centre-wide pass skips rows it cannot write
--    and says how many.
--
-- ---------------------------------------------------------------------
-- AND A RULE MAY ONLY NAME A FIELD THAT EXISTS
--
-- A rule requiring a column that is not there can never be satisfied,
-- which makes every family in the centre permanently incomplete - and
-- nothing about the rule looks wrong. The name is checked against the
-- real columns when the rule is written.
--
-- Error classes added here (grepped free):
--   HB256  a completeness rule names a field that does not exist
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0133') THEN
    RAISE EXCEPTION 'migration 0133 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0132') THEN
    RAISE EXCEPTION 'migration 0132 must be applied first';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%HB256%') THEN
    RAISE EXCEPTION 'HB256 is already raised by some function - grep and pick another';
  END IF;
END
$guard$;

-- =====================================================================
-- THE RULES
-- =====================================================================
CREATE TABLE hbh.profile_field_rules (
  rule_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  entity        text        NOT NULL,
  field_name    text        NOT NULL,
  required_flg  boolean     NOT NULL DEFAULT true,
  display_order smallint    NOT NULL DEFAULT 100,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_profile_field_rules PRIMARY KEY (rule_id),
  CONSTRAINT fk_pfr_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT ck_pfr_entity CHECK (entity IN ('GUARDIAN', 'BENEFICIARY')),
  CONSTRAINT ck_pfr_field  CHECK (field_name ~ '^[a-z][a-z0-9_]*$')
);

-- One live rule per field. Two rules for the same field that disagree
-- about required_flg is a question with two answers.
CREATE UNIQUE INDEX uix_pfr_live ON hbh.profile_field_rules (center_id, entity, field_name)
  WHERE active_flg;
CREATE INDEX ix_pfr_center ON hbh.profile_field_rules (center_id);

-- ---------------------------------------------------------------------
-- A rule names a real field, or it is refused
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_pfr_field_exists()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- BENEFICIARY fields live on children, except the relationship, which
  -- lives on the link. Both are valid places for a beneficiary rule.
  IF NOT EXISTS (
       SELECT 1 FROM information_schema.columns c
       WHERE c.table_schema = 'hbh'
         AND c.column_name  = NEW.field_name
         AND c.table_name   = CASE NEW.entity WHEN 'GUARDIAN' THEN 'guardians' ELSE 'children' END)
     AND NOT (NEW.entity = 'BENEFICIARY' AND NEW.field_name = 'relationship_code') THEN
    RAISE EXCEPTION 'no % field named % - a rule nobody can satisfy makes every family incomplete for ever',
                    lower(NEW.entity), NEW.field_name
      USING ERRCODE = 'HB256';
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER trg_pfr_field_exists
  BEFORE INSERT OR UPDATE OF entity, field_name ON hbh.profile_field_rules
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_pfr_field_exists();

CREATE TRIGGER trg_pfr_touch
  BEFORE UPDATE ON hbh.profile_field_rules
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_pfr_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.profile_field_rules
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();

-- =====================================================================
-- EN-06 · THE COMPUTATION
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.completeness_of(p_guardian_id integer)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_g        hbh.guardians%ROWTYPE;
  l_total    integer := 0;
  l_filled   integer := 0;
  l_extra    integer := 0;  -- filled fields the schema does not force
BEGIN
  SELECT * INTO l_g FROM hbh.guardians g WHERE g.guardian_id = p_guardian_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- The guardian's own required fields. to_jsonb(row) ->> name reads a
  -- column by name WITHOUT building SQL from the rule - field_name is
  -- data typed in a console, and it never becomes a query.
  SELECT count(*),
         count(*) FILTER (WHERE coalesce(btrim(to_jsonb(l_g) ->> r.field_name), '') <> ''),
         count(*) FILTER (WHERE coalesce(btrim(to_jsonb(l_g) ->> r.field_name), '') <> ''
                            AND r.field_name NOT IN ('full_name_ar', 'mobile'))
    INTO l_total, l_filled, l_extra
  FROM hbh.profile_field_rules r
  WHERE r.center_id = l_g.center_id AND r.entity = 'GUARDIAN'
    AND r.required_flg AND r.active_flg;

  -- And each active beneficiary's. relationship_code comes from the
  -- link, merged into the child's row so one lookup reads both.
  SELECT l_total  + count(*),
         l_filled + count(*) FILTER (WHERE coalesce(btrim(b.rec ->> r.field_name), '') <> ''),
         l_extra  + count(*) FILTER (WHERE coalesce(btrim(b.rec ->> r.field_name), '') <> '')
    INTO l_total, l_filled, l_extra
  FROM (SELECT to_jsonb(c) || jsonb_build_object('relationship_code', gc.relationship_code) AS rec
        FROM   hbh.guardian_children gc
        JOIN   hbh.children c ON c.child_id = gc.child_id AND c.active_flg
        WHERE  gc.guardian_id = p_guardian_id AND gc.active_flg) b
  CROSS JOIN hbh.profile_field_rules r
  WHERE r.center_id = l_g.center_id AND r.entity = 'BENEFICIARY'
    AND r.required_flg AND r.active_flg;

  -- No rules means nothing is required, and a record with no
  -- requirements is complete - not "unknown". The seed gives every
  -- centre a default set, so this is the rare case, not the common one.
  IF l_total = 0 OR l_filled = l_total THEN
    RETURN 'COMPLETE';
  ELSIF l_extra = 0 THEN
    RETURN 'MINIMAL';
  ELSE
    RETURN 'PARTIAL';
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION hbh.recompute_completeness(p_guardian_id integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_new text := hbh.completeness_of(p_guardian_id);
BEGIN
  -- Writes only when it would differ. That is half of the loop guard
  -- (see the header), and it also keeps the audit log from recording a
  -- change that did not happen.
  UPDATE hbh.guardians g
     SET record_completeness = l_new
   WHERE g.guardian_id = p_guardian_id
     AND g.record_completeness IS DISTINCT FROM l_new;
  RETURN l_new;
END
$$;

-- A whole centre, after a rule changes. Skips what it cannot write.
CREATE OR REPLACE FUNCTION hbh.recompute_completeness_for_center(p_center_id integer)
RETURNS TABLE (recomputed integer, skipped_frozen integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_id   integer;
  l_done integer := 0;
  l_skip integer := 0;
BEGIN
  FOR l_id IN
    SELECT g.guardian_id FROM hbh.guardians g
    WHERE g.center_id = p_center_id AND g.active_flg
  LOOP
    BEGIN
      PERFORM hbh.recompute_completeness(l_id);
      l_done := l_done + 1;
    EXCEPTION WHEN check_violation THEN
      -- A row the schema has already frozen (0128). Counted, not fatal:
      -- a rule change must not fail over a phone number nobody can fix.
      l_skip := l_skip + 1;
    END;
  END LOOP;

  RETURN QUERY SELECT l_done, l_skip;
END
$$;

-- =====================================================================
-- THE TRIGGERS
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_completeness_guardian()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  PERFORM hbh.recompute_completeness(NEW.guardian_id);
  RETURN NULL;
END
$$;

-- TWO TRIGGERS, because the guard needs OLD and an INSERT has none.
--
-- The first draft of this file had ONE trigger with
-- WHEN (pg_trigger_depth() = 0 OR TRUE) - always true - while the
-- header above described a guard the code did not contain. It would
-- still have terminated, one wasted round later, because
-- recompute_completeness writes only when the value differs; but a
-- header promising a guard that is not there is exactly how the next
-- person removes the one that is.
CREATE TRIGGER trg_guardians_completeness_ins
  AFTER INSERT ON hbh.guardians
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_completeness_guardian();

-- Fires for an edit to any other field, and NEVER for recompute's own
-- write - that write is the one that changes record_completeness.
CREATE TRIGGER trg_guardians_completeness_upd
  AFTER UPDATE ON hbh.guardians
  FOR EACH ROW
  WHEN (OLD.record_completeness IS NOT DISTINCT FROM NEW.record_completeness)
  EXECUTE FUNCTION hbh.trg_completeness_guardian();

CREATE OR REPLACE FUNCTION hbh.trg_completeness_child()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_gid integer;
BEGIN
  FOR l_gid IN
    SELECT gc.guardian_id FROM hbh.guardian_children gc
    WHERE gc.child_id = coalesce(NEW.child_id, OLD.child_id)
  LOOP
    BEGIN
      PERFORM hbh.recompute_completeness(l_gid);
    EXCEPTION WHEN check_violation THEN
      NULL;  -- a frozen guardian must not block an edit to their child
    END;
  END LOOP;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_children_completeness
  AFTER INSERT OR UPDATE ON hbh.children
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_completeness_child();

CREATE OR REPLACE FUNCTION hbh.trg_completeness_link()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  BEGIN
    PERFORM hbh.recompute_completeness(coalesce(NEW.guardian_id, OLD.guardian_id));
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_guardian_children_completeness
  AFTER INSERT OR UPDATE OR DELETE ON hbh.guardian_children
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_completeness_link();

CREATE OR REPLACE FUNCTION hbh.trg_completeness_rule()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  -- ONLY the rule's own centre. A rule change in one centre recomputing
  -- another's families would be a write across a tenant boundary set
  -- off by an administrator who has no authority there.
  PERFORM hbh.recompute_completeness_for_center(coalesce(NEW.center_id, OLD.center_id));
  RETURN NULL;
END
$$;

CREATE TRIGGER trg_pfr_completeness
  AFTER INSERT OR UPDATE OR DELETE ON hbh.profile_field_rules
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_completeness_rule();

-- =====================================================================
-- ACCESS
-- =====================================================================
ALTER TABLE hbh.profile_field_rules ENABLE ROW LEVEL SECURITY;

-- Readable by anyone in the centre: the portal needs the rules to draw
-- the completion form (GET /me/profile-rules). They are not sensitive -
-- they say which fields exist, not what anyone wrote in them.
CREATE POLICY p_pfr_select ON hbh.profile_field_rules
  FOR SELECT TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND active_flg);

-- Writable only with SETTINGS.MANAGE (OD-11). The lifted form, because
-- that is the convention now, even on a table this small.
CREATE POLICY p_pfr_write ON hbh.profile_field_rules
  FOR ALL TO hbh_app
  USING ((SELECT hbh.current_center_id() IS NOT NULL)
         AND center_id = (SELECT hbh.current_center_id())
         AND (SELECT hbh.has_permission('SETTINGS.MANAGE')))
  WITH CHECK ((SELECT hbh.current_center_id() IS NOT NULL)
              AND center_id = (SELECT hbh.current_center_id())
              AND (SELECT hbh.has_permission('SETTINGS.MANAGE')));

GRANT SELECT, INSERT, UPDATE ON hbh.profile_field_rules TO hbh_app;
GRANT USAGE ON SEQUENCE hbh.profile_field_rules_rule_id_seq TO hbh_app;

REVOKE ALL ON FUNCTION hbh.completeness_of(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.recompute_completeness(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.recompute_completeness_for_center(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.completeness_of(integer) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0133');
