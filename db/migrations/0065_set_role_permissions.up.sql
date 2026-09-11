-- =====================================================================
-- 0065 - hbh.set_role_permissions
--
-- The counterpart of hbh.set_user_roles, and written the same way for
-- the same reason: the rule belongs in PL/pgSQL, and the API's job is to
-- carry the answer rather than to decide it. A screen that assembled
-- these UPDATEs itself would be a second definition of what "setting a
-- role" means, and the weaker copy is the one that would drift.
--
-- REPLACE, NOT MERGE. The caller sends the complete list it wants the
-- role to have. Anything not named is archived; anything named is
-- granted or reinstated. A merge API would have no way to express
-- "remove this" without a second verb, and two verbs is how a screen
-- ends up sending one of them and forgetting the other.
--
-- NULL AND EMPTY ARE DIFFERENT, and the difference matters more here
-- than almost anywhere. An empty array means "this role grants nothing"
-- and is a legitimate thing to ask for. A NULL means the caller forgot
-- to send the field - and stripping a role bare because a JSON key was
-- absent is exactly the failure this must never have. NULL is refused.
--
-- WHAT IT DOES NOT CHECK. Whether the change leaves anybody able to
-- grant permissions - that is the deferred constraint trigger from 0064,
-- which runs at COMMIT when the whole intended state exists. Checking it
-- here as well would refuse a legitimate edit halfway through: this
-- function archives before it grants, so between the two statements
-- there is an instant where nobody holds USER.MANAGE and the state is
-- not yet what anybody asked for.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.set_role_permissions(
  p_role_code   text,
  p_perm_codes  text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_center  integer := hbh.current_center_id();
  l_role_id integer;
  l_bad     text;
BEGIN
  IF l_center IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'editing a role needs USER.MANAGE' USING ERRCODE = 'HB150';
  END IF;

  IF p_perm_codes IS NULL THEN
    RAISE EXCEPTION 'the permission list is required'
      USING ERRCODE = 'HB191',
            HINT = 'an empty array means "grants nothing"; a missing field '
                   'means the screen forgot, and the two must not be one';
  END IF;

  SELECT r.role_id INTO l_role_id
  FROM   hbh.roles r
  WHERE  r.code = p_role_code AND r.center_id = l_center AND r.active_flg;
  IF l_role_id IS NULL THEN
    RAISE EXCEPTION 'no such role in this centre: %', p_role_code
      USING ERRCODE = 'HB156';
  END IF;

  -- Named explicitly rather than silently skipped: a screen that asked
  -- for eight permissions and got seven has to be told which one it did
  -- not get.
  SELECT string_agg(c, ', ') INTO l_bad
  FROM   unnest(p_perm_codes) AS c
  WHERE  NOT EXISTS (SELECT 1 FROM hbh.permissions p
                      WHERE p.code = c AND p.active_flg);
  IF l_bad IS NOT NULL THEN
    RAISE EXCEPTION 'no such permission: %', l_bad USING ERRCODE = 'HB192';
  END IF;

  -- Archive what is no longer named.
  UPDATE hbh.role_permissions rp
     SET active_flg = false, deleted_at = now()
   WHERE rp.role_id = l_role_id
     AND rp.active_flg
     AND NOT EXISTS (SELECT 1 FROM hbh.permissions p
                      WHERE p.permission_id = rp.permission_id
                        AND p.code = ANY (p_perm_codes));

  -- Reinstate what was archived and is named again. A grant that comes
  -- back is the SAME row - the composite key leaves no room for a second
  -- one, and the audit trail reads as one thing revoked and restored
  -- rather than two unrelated grants.
  UPDATE hbh.role_permissions rp
     SET active_flg = true, deleted_at = NULL
    FROM hbh.permissions p
   WHERE p.permission_id = rp.permission_id
     AND rp.role_id = l_role_id
     AND NOT rp.active_flg
     AND p.code = ANY (p_perm_codes);

  -- Grant what was never there.
  INSERT INTO hbh.role_permissions (role_id, permission_id)
  SELECT l_role_id, p.permission_id
  FROM   hbh.permissions p
  WHERE  p.code = ANY (p_perm_codes)
    AND  NOT EXISTS (SELECT 1 FROM hbh.role_permissions rp
                      WHERE rp.role_id = l_role_id
                        AND rp.permission_id = p.permission_id);
END;
$fn$;

REVOKE ALL ON FUNCTION hbh.set_role_permissions(text, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_role_permissions(text, text[]) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0065');
