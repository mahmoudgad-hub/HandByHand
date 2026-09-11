-- Run against the local development seed; all message writes are rolled back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE hbh_app;
SELECT set_config('hbh.user_id','dev_admin',true);
SELECT g.guardian_id AS test_guardian FROM hbh.guardians g JOIN hbh.users u ON u.user_id=g.user_id WHERE u.username='dev_parent' AND g.active_flg LIMIT 1 \gset
INSERT INTO hbh.family_messages(center_id,guardian_id,sender_id,body_ar,request_id) VALUES(hbh.current_center_id(),:test_guardian,hbh.current_user_id(),'transaction-only verification','ad205e11-0e80-4a74-9a92-7fc4b8ac1a90');
INSERT INTO hbh.family_messages(center_id,guardian_id,sender_id,body_ar,request_id) VALUES(hbh.current_center_id(),:test_guardian,hbh.current_user_id(),'transaction-only verification','ad205e11-0e80-4a74-9a92-7fc4b8ac1a90') ON CONFLICT(sender_id,request_id) DO NOTHING;
DO $$ BEGIN IF (SELECT count(*) FROM hbh.family_messages WHERE request_id='ad205e11-0e80-4a74-9a92-7fc4b8ac1a90')<>1 THEN RAISE EXCEPTION 'dedup failed'; END IF; END $$;
SELECT set_config('hbh.user_id','dev_parent',true);
DO $$ BEGIN IF (SELECT count(*) FROM hbh.family_messages WHERE request_id='ad205e11-0e80-4a74-9a92-7fc4b8ac1a90')<>1 THEN RAISE EXCEPTION 'guardian read failed'; END IF; END $$;
INSERT INTO hbh.family_messages(center_id,guardian_id,sender_id,body_ar,request_id) VALUES(hbh.current_center_id(),:test_guardian,hbh.current_user_id(),'guardian transaction-only reply','337ba824-4ff2-4f7c-8cfe-727a31e22c42');
INSERT INTO hbh.family_message_reads(user_id,guardian_id,message_id)
 SELECT hbh.current_user_id(),guardian_id,message_id FROM hbh.family_messages WHERE request_id='ad205e11-0e80-4a74-9a92-7fc4b8ac1a90'
 ON CONFLICT(user_id,guardian_id) DO UPDATE SET message_id=greatest(family_message_reads.message_id,excluded.message_id);
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM hbh.family_message_reads WHERE user_id=hbh.current_user_id()) THEN RAISE EXCEPTION 'read marker failed'; END IF; END $$;
SELECT set_config('hbh.user_id','dev_admin',true);
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hbh.family_message_reads WHERE user_id<>hbh.current_user_id()) THEN RAISE EXCEPTION 'read marker leaked'; END IF; END $$;
SELECT set_config('hbh.user_id','dev_therapist',true);
DO $$ DECLARE g integer; BEGIN
IF EXISTS(SELECT 1 FROM hbh.family_messages) THEN RAISE EXCEPTION 'unauthorized read'; END IF;
SELECT guardian_id INTO g FROM hbh.guardians WHERE active_flg LIMIT 1;
IF g IS NOT NULL THEN
 BEGIN
 INSERT INTO hbh.family_messages(center_id,guardian_id,sender_id,body_ar,request_id) VALUES(hbh.current_center_id(),g,hbh.current_user_id(),'forbidden','15e3a003-1d21-423c-9454-1d28dd113fb9');
 RAISE EXCEPTION 'unauthorized write';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END IF;
END $$;
ROLLBACK;
