BEGIN;
-- Preserve every old file reference. Users/roles photographs take precedence;
-- an account avatar fills only a missing photograph. No files are removed.
ALTER TABLE hbh.user_avatars NO FORCE ROW LEVEL SECURITY;
INSERT INTO hbh.staff_profiles(center_id,user_id,photo_path)
SELECT center_id,user_id,file_name FROM hbh.user_avatars
ON CONFLICT(user_id) DO UPDATE SET photo_path=EXCLUDED.photo_path
WHERE hbh.staff_profiles.photo_path IS NULL OR hbh.staff_profiles.photo_path='';
ALTER TABLE hbh.user_avatars RENAME TO user_avatars_legacy;
REVOKE ALL ON hbh.user_avatars_legacy FROM hbh_app;
ALTER TABLE hbh.user_avatars_legacy FORCE ROW LEVEL SECURITY;
-- This projection exposes only the shared photo, never personnel PII.
CREATE VIEW hbh.user_avatars WITH (security_barrier=true) AS
SELECT p.user_id,p.center_id,p.photo_path AS file_name,p.updated_at
FROM hbh.staff_profiles p
WHERE p.active_flg AND p.photo_path IS NOT NULL AND p.photo_path<>''
AND p.center_id=hbh.current_center_id()
AND (hbh.can_view_avatar(p.user_id) OR hbh.has_permission('STAFF.PII'));
GRANT SELECT ON hbh.user_avatars TO hbh_app;
COMMENT ON VIEW hbh.user_avatars IS 'Shared photograph projection of the user personnel record. No independent avatar storage.';
INSERT INTO hbh.schema_migrations(version) VALUES('0146');
COMMIT;
