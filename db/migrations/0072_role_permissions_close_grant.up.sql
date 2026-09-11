-- =====================================================================
-- 0072 - closing the door 0064 opened, and recording what goes through
--        the one that stays
--
-- Two defects in 0064, both found by the acceptance suites (a7 and a4),
-- and both mine.
--
-- 1. THE WRITE GRANT WAS NEVER NEEDED.
--
--    0064 granted INSERT and UPDATE on hbh.role_permissions to hbh_app
--    and wrote RLS policies to gate them. Then 0065 put the actual write
--    path in hbh.set_role_permissions - SECURITY DEFINER, which runs as
--    the owner and therefore needs neither the grant nor the policies.
--    api/internal/store/identity.go calls that function and nothing
--    else. So the grant was a second way in that nobody used and no
--    test covered, and its policies were decoration: they cannot be
--    reached from the path the product takes, and would not be noticed
--    if they drifted.
--
--    IT ALSO BROKE A RULE THAT WAS ALREADY WRITTEN DOWN. 0036 settled
--    how identity is written: no table grant, one SECURITY DEFINER
--    function per verb, "so there is no second path that skips the
--    centre check, the self-grant rule or the stamp" - its own words.
--    hbh.user_roles has SELECT policies and no write grant to this day.
--    I invented a different shape for the neighbouring table in the same
--    subsystem, and a7 asserts the settled one BY NAME across all five
--    identity tables. The check was right and the migration was wrong.
--
-- 2. AND THE TABLE HAD NO AUDIT TRIGGER.
--
--    That one is not fixed by revoking the grant, and revoking alone
--    would have turned a4 green while leaving the real hole open: a4
--    reads the grant list, so the table simply drops out of what it
--    examines. But changing which permissions a role carries is among
--    the most sensitive changes in this schema - it is the difference
--    between an account that can open a child's file and one that
--    cannot - and it was leaving nothing behind but the current value.
--    Exactly the defect migration 0014 closed for cameras.
--
--    The write runs as the owner through the function, and a trigger
--    fires for the owner too, so the audit works regardless of which
--    door is open. hbh.user_roles has carried trg_user_roles_audit since
--    0002; this is its pair, and should have been in 0064.
--
-- The last-admin constraint triggers from 0064 stay exactly as they are.
-- They are not about who may write - they are about the state at commit,
-- and they fire for the owner and the function alike.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. The audit trail. First, because it must already be recording
--    before anything else in this file changes.
--
--    Keyed on role_id like hbh.guardian_children is keyed on child_id:
--    the table has a composite primary key and no surrogate, and the
--    convention is to name the parent the row hangs from.
-- ---------------------------------------------------------------------
DROP TRIGGER IF EXISTS trg_role_permissions_audit ON hbh.role_permissions;

CREATE TRIGGER trg_role_permissions_audit
  AFTER INSERT OR UPDATE OR DELETE ON hbh.role_permissions
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('role_id');

-- ---------------------------------------------------------------------
-- 2. The grant, and the policies that only it could reach.
--
--    The policies go with it. A policy that no reachable path evaluates
--    is a claim of protection that nothing tests - it reads as a
--    safeguard while being unable to refuse anything, which is the worst
--    of the two states to leave the schema in. If a direct grant is ever
--    wanted here, it comes back with its policies and its tests in the
--    same migration.
--
--    p_role_permissions_select_all STAYS. Reading is granted, the screen
--    needs it, and the archived-row shape it fixes is real: 0056 exists
--    because an UPDATE whose new row fails the SELECT policy is refused
--    by row level security, and archiving a grant sets active_flg false.
-- ---------------------------------------------------------------------
REVOKE INSERT, UPDATE ON hbh.role_permissions FROM hbh_app;

DROP POLICY IF EXISTS p_role_permissions_insert ON hbh.role_permissions;
DROP POLICY IF EXISTS p_role_permissions_update ON hbh.role_permissions;

INSERT INTO hbh.schema_migrations (version) VALUES ('0072');
