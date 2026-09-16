\set ON_ERROR_STOP on
BEGIN;
SELECT user_id AS admin_id,center_id AS center FROM hbh.users WHERE username='dev_admin' \gset
SELECT user_id AS parent_id FROM hbh.users WHERE username='dev_parent' \gset
SELECT user_id AS therapist_id FROM hbh.users WHERE username='dev_therapist' \gset
INSERT INTO hbh.users(center_id,username,full_name_ar,user_type) VALUES(:center,'chat_check_parent','Chat check','GUARDIAN') RETURNING user_id AS other_parent \gset
SELECT set_config('chat.check.other',:'other_parent',true);
SET LOCAL ROLE hbh_app;
SELECT set_config('hbh.user_id','dev_admin',true);
INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id) VALUES(hbh.current_center_id(),hbh.current_user_id(),:parent_id,'rollback check','dacdc4af-ceb1-4c8f-8fa9-84f50d320132') RETURNING message_id AS mid \gset
INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id) VALUES(hbh.current_center_id(),hbh.current_user_id(),:parent_id,'rollback check','dacdc4af-ceb1-4c8f-8fa9-84f50d320132') ON CONFLICT(sender_id,recipient_id,request_id) DO NOTHING;
DO $$ BEGIN IF (SELECT count(*) FROM hbh.direct_messages WHERE request_id='dacdc4af-ceb1-4c8f-8fa9-84f50d320132')<>1 THEN RAISE EXCEPTION 'idempotency failed'; END IF; END $$;
SELECT set_config('hbh.user_id','dev_therapist',true);
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hbh.direct_messages WHERE request_id='dacdc4af-ceb1-4c8f-8fa9-84f50d320132') THEN RAISE EXCEPTION 'private conversation leaked'; END IF; END $$;
INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id) VALUES(hbh.current_center_id(),hbh.current_user_id(),:admin_id,'staff check','2888376e-fefb-428a-bded-e3290801e4cd');
SELECT set_config('hbh.user_id','dev_parent',true);
DO $$ BEGIN
 IF NOT EXISTS(SELECT 1 FROM hbh.direct_messages WHERE request_id='dacdc4af-ceb1-4c8f-8fa9-84f50d320132') THEN RAISE EXCEPTION 'recipient cannot read'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hbh.notifications WHERE kind_code='CHAT_MESSAGE' AND read_at IS NULL AND chat_message_id IS NOT NULL) THEN RAISE EXCEPTION 'notification missing'; END IF;
 IF hbh.can_chat(current_setting('chat.check.other')::integer) THEN RAISE EXCEPTION 'guardian discovery leak'; END IF;
 BEGIN
  INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id) VALUES(hbh.current_center_id(),hbh.current_user_id(),current_setting('chat.check.other')::integer,'forbidden','025be65b-1c45-4e50-a991-3f8275e10f6d');
  RAISE EXCEPTION 'guardian-to-guardian write allowed';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN PERFORM hbh.broadcast_staff('forbidden','91eb10d9-d20d-4368-a8a8-b90e88f106a3');RAISE EXCEPTION 'unauthorized broadcast';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END $$;
UPDATE hbh.direct_messages SET read_at=now() WHERE message_id=:mid;
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hbh.notifications WHERE chat_message_id IS NOT NULL AND read_at IS NULL) THEN RAISE EXCEPTION 'notification not marked read'; END IF; END $$;
INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id) VALUES(hbh.current_center_id(),hbh.current_user_id(),:therapist_id,'parent reply check','9f5a1c3e-fc13-4825-aee9-426ee70c3be7');
SELECT set_config('hbh.user_id','dev_admin',true);
SELECT hbh.broadcast_staff('rollback broadcast','79c703d8-f86c-4cc9-9c36-7be78d1144fd') AS sent \gset
SELECT hbh.broadcast_staff('rollback broadcast','79c703d8-f86c-4cc9-9c36-7be78d1144fd') AS retried \gset
SELECT :'sent'::integer=:'retried'::integer AND :'sent'::integer>0 AS broadcast_ok \gset
\if :broadcast_ok
\else
\quit 1
\endif
SELECT set_config('hbh.user_id','unknown_chat_identity',true);
DO $$ BEGIN IF EXISTS(SELECT 1 FROM hbh.direct_messages) OR EXISTS(SELECT 1 FROM hbh.chat_peers()) THEN RAISE EXCEPTION 'missing identity leaked data'; END IF; END $$;
ROLLBACK;
\echo 'CHAT CHECKS PASSED (all writes rolled back)'
