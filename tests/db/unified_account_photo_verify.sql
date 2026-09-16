-- Run after migration 0146, inside a transaction owned by the test runner.
-- This fixture changes a photograph reference temporarily; the runner rolls back.
SELECT set_config('hbh.user_id', (SELECT username FROM hbh.users
 WHERE active_flg AND status='ACTIVE' AND user_type='STAFF' ORDER BY user_id LIMIT 1), true);
INSERT INTO hbh.staff_profiles(center_id,user_id,photo_path)
VALUES(hbh.current_center_id(),hbh.current_user_id(),'unified-photo-check.jpg')
ON CONFLICT(user_id) DO UPDATE SET photo_path=EXCLUDED.photo_path;
SET LOCAL ROLE hbh_app;
DO $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM hbh.user_avatars WHERE user_id=hbh.current_user_id()
 AND file_name='unified-photo-check.jpg') THEN
 RAISE EXCEPTION 'Shared photo does not read the users profile'; END IF;
 IF EXISTS(SELECT 1 FROM hbh.user_avatars WHERE center_id<>hbh.current_center_id()) THEN
 RAISE EXCEPTION 'Cross-center photo leak'; END IF;
 IF has_table_privilege('hbh_app','hbh.user_avatars_legacy','SELECT') THEN
 RAISE EXCEPTION 'Legacy photos remain accessible'; END IF;
 UPDATE hbh.staff_profiles SET photo_path=NULL WHERE user_id=hbh.current_user_id();
 IF EXISTS(SELECT 1 FROM hbh.user_avatars WHERE user_id=hbh.current_user_id()) THEN
 RAISE EXCEPTION 'Removed users photo is still returned'; END IF;
END $$;
RESET ROLE;
