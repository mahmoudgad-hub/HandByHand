-- Restores the state 0064 left: the direct write grant and the two
-- policies that gated it. The audit trigger goes last, so the table is
-- never writable-and-unrecorded at any point during the rollback.
\set ON_ERROR_STOP on

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

GRANT INSERT, UPDATE ON hbh.role_permissions TO hbh_app;

DROP TRIGGER IF EXISTS trg_role_permissions_audit ON hbh.role_permissions;

DELETE FROM hbh.schema_migrations WHERE version = '0072';
