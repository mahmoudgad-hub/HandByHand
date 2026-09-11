-- =====================================================================
-- 0064 - editing what a role may do, and the one door that must never
--        lock behind everybody
--
-- hbh.role_permissions has had SELECT and nothing else since it was
-- created, so which screens a role opens could be read from a console
-- and changed only by a developer with the owner's credentials. This
-- opens it, gated on USER.MANAGE like the rest of identity.
--
-- IT IS THE MOST DANGEROUS WRITE IN THIS SCHEMA, for a reason that has
-- nothing to do with permissions and everything to do with reachability:
--
--   USER.MANAGE is the permission that lets somebody grant permissions.
--   Take it off the last role that carries it and NOBODY can put it
--   back - not the owner, not an administrator, nobody. Every screen in
--   identity closes at once and stays closed. The only way out is a
--   developer with the database password, which is precisely the
--   situation this screen was built to end.
--
--   It is not a mistake anybody makes twice, because after the first
--   time they cannot reach the screen to try.
--
-- SO IT IS REFUSED, NOT WARNED ABOUT. A warning is right for something
-- recoverable; this is not recoverable from inside the product.
--
-- WHY A DEFERRED CONSTRAINT TRIGGER and not a BEFORE trigger.
--
--   The question is about the STATE AT THE END of the transaction, not
--   about one row. Setting a role's permissions revokes some rows and
--   inserts others, and a per-row check would fire in the middle - after
--   the revoke and before the grant that puts it back - and refuse a
--   change that was going to be perfectly fine. DEFERRABLE INITIALLY
--   DEFERRED runs once, at commit, when the whole intended state exists.
--
-- THE SAME GUARD IS PUT ON user_roles, and that is not scope creep:
-- revoking the last administrator's ROLE locks the same door by the
-- other handle, and PUT /users/{id}/roles has been able to do it since
-- the day it shipped. One rule, both tables.
--
-- WHAT IS DELIBERATELY NOT BLOCKED. Stripping PORTAL.VIEW from GUARDIAN
-- locks every parent out of the portal, which is severe - and an
-- administrator can put it straight back, so it is the screen's job to
-- say who is affected, not this trigger's job to refuse. The line is
-- recoverability, not severity.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- The guard.
--
-- SECURITY DEFINER with a pinned search_path: it reads users and roles
-- regardless of who is asking, because the answer must be "does anybody
-- still hold this", not "does anybody I can see still hold this".
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.guard_last_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   hbh.users u
    JOIN   hbh.user_roles ur       ON ur.user_id = u.user_id AND ur.active_flg
    JOIN   hbh.role_permissions rp ON rp.role_id = ur.role_id AND rp.active_flg
    JOIN   hbh.permissions p       ON p.permission_id = rp.permission_id
    WHERE  u.active_flg
      AND  u.status = 'ACTIVE'
      AND  p.code = 'USER.MANAGE'
  ) THEN
    RAISE EXCEPTION 'this change would leave nobody able to grant permissions'
      USING ERRCODE = 'HB190',
            HINT = 'USER.MANAGE is what allows granting; with no active user '
                   'holding it, no screen in this product can ever restore it';
  END IF;
  RETURN NULL;  -- AFTER trigger: the return value is ignored
END;
$fn$;

CREATE CONSTRAINT TRIGGER trg_role_permissions_last_admin
  AFTER INSERT OR UPDATE OR DELETE ON hbh.role_permissions
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_last_admin();

CREATE CONSTRAINT TRIGGER trg_user_roles_last_admin
  AFTER INSERT OR UPDATE OR DELETE ON hbh.user_roles
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION hbh.guard_last_admin();

-- ---------------------------------------------------------------------
-- Who may write. USER.MANAGE, the same code that already gates granting
-- a role to a person - editing the role is the same authority reaching
-- further, not a different one.
-- ---------------------------------------------------------------------
CREATE POLICY p_role_permissions_insert ON hbh.role_permissions
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND hbh.has_permission('USER.MANAGE')
              AND EXISTS (SELECT 1 FROM hbh.roles r
                          WHERE r.role_id = role_permissions.role_id
                            AND r.center_id = hbh.current_center_id()));

CREATE POLICY p_role_permissions_update ON hbh.role_permissions
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND hbh.has_permission('USER.MANAGE')
         AND EXISTS (SELECT 1 FROM hbh.roles r
                     WHERE r.role_id = role_permissions.role_id
                       AND r.center_id = hbh.current_center_id()))
  WITH CHECK (EXISTS (SELECT 1 FROM hbh.roles r
                      WHERE r.role_id = role_permissions.role_id
                        AND r.center_id = hbh.current_center_id()));

-- Archiving a grant sets active_flg false, and a row that fails the
-- read policy afterwards makes the UPDATE that archives it violate row
-- level security - the defect 0056 was written to fix. The existing
-- select policy is checked for that shape before relying on it.
CREATE POLICY p_role_permissions_select_all ON hbh.role_permissions
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND hbh.has_permission('USER.MANAGE')
         AND EXISTS (SELECT 1 FROM hbh.roles r
                     WHERE r.role_id = role_permissions.role_id
                       AND r.center_id = hbh.current_center_id()));

GRANT INSERT, UPDATE ON hbh.role_permissions TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0064');
