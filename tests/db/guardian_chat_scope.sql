-- Run after 0147. Every fixture and notification is rolled back.
BEGIN;
DO $test$
DECLARE c integer; parent_id integer; own_child integer; other_child integer;
  staff_id integer; therapist_id integer; outsider_id integer; other_parent integer; service integer;
BEGIN
 SELECT user_id,center_id INTO parent_id,c FROM hbh.users WHERE username='dev_parent';
 SELECT gc.child_id INTO own_child FROM hbh.guardians g JOIN hbh.guardian_children gc USING(guardian_id)
 WHERE g.user_id=parent_id AND g.active_flg AND gc.active_flg LIMIT 1;
 SELECT ch.child_id INTO other_child FROM hbh.children ch WHERE ch.center_id=c AND ch.active_flg
 AND NOT EXISTS(SELECT 1 FROM hbh.guardians g JOIN hbh.guardian_children gc USING(guardian_id) WHERE g.user_id=parent_id AND gc.child_id=ch.child_id) LIMIT 1;
 SELECT service_id INTO service FROM hbh.services WHERE center_id=c AND active_flg LIMIT 1;
 IF own_child IS NULL OR other_child IS NULL OR service IS NULL THEN RAISE EXCEPTION 'dev child/service fixtures required'; END IF;
 INSERT INTO hbh.users(center_id,username,full_name_ar,user_type) VALUES(c,'chat_scope_specialist','Chat scope test','THERAPIST') RETURNING user_id INTO staff_id;
 INSERT INTO hbh.therapists(center_id,user_id,full_name_ar) VALUES(c,staff_id,'Chat scope test') RETURNING hbh.therapists.therapist_id INTO therapist_id;
 INSERT INTO hbh.caseload(center_id,therapist_id,child_id,service_id) VALUES(c,therapist_id,own_child,service);
 INSERT INTO hbh.users(center_id,username,full_name_ar,user_type) VALUES(c,'chat_scope_unrelated','Unrelated test','THERAPIST') RETURNING user_id INTO outsider_id;
 INSERT INTO hbh.therapists(center_id,user_id,full_name_ar) VALUES(c,outsider_id,'Unrelated test') RETURNING hbh.therapists.therapist_id INTO therapist_id;
 INSERT INTO hbh.caseload(center_id,therapist_id,child_id,service_id) VALUES(c,therapist_id,other_child,service);
 INSERT INTO hbh.users(center_id,username,full_name_ar,user_type) VALUES(c,'chat_scope_parent','Other parent test','GUARDIAN') RETURNING user_id INTO other_parent;
 PERFORM set_config('hbh.user_id','dev_parent',true);
 EXECUTE 'SET LOCAL ROLE hbh_app';
 IF NOT hbh.can_chat(staff_id) OR hbh.chat_recipient_role(staff_id)<>'therapist' THEN RAISE EXCEPTION 'own assigned therapist missing'; END IF;
 IF hbh.can_chat(outsider_id) OR hbh.can_chat(other_parent) THEN RAISE EXCEPTION 'unrelated recipient allowed'; END IF;
 IF EXISTS(SELECT 1 FROM hbh.chat_peers() WHERE user_id IN (outsider_id,other_parent)) THEN RAISE EXCEPTION 'recipient directory leaked'; END IF;
 IF (SELECT count(*) FROM hbh.chat_peers() WHERE user_id=staff_id)<>1 THEN RAISE EXCEPTION 'duplicate specialist'; END IF;
 INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id)
 VALUES(c,parent_id,staff_id,'rolled back scope test','aabbccdd-1122-3344-5566-778899001122');
 BEGIN
  INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id)
  VALUES(c,parent_id,outsider_id,'forbidden','aabbccdd-1122-3344-5566-778899001133');
  RAISE EXCEPTION 'RLS accepted unrelated therapist';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 BEGIN
  INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id)
  VALUES(c,parent_id,other_parent,'forbidden','aabbccdd-1122-3344-5566-778899001144');
  RAISE EXCEPTION 'RLS accepted other guardian';
 EXCEPTION WHEN insufficient_privilege THEN NULL; END;
 PERFORM set_config('hbh.user_id','chat_scope_specialist',true);
 IF NOT hbh.can_chat(parent_id) THEN RAISE EXCEPTION 'reply direction blocked'; END IF;
 PERFORM set_config('hbh.user_id','chat_scope_unrelated',true);
 IF hbh.can_chat(parent_id) OR EXISTS(SELECT 1 FROM hbh.direct_messages WHERE request_id='aabbccdd-1122-3344-5566-778899001122') THEN RAISE EXCEPTION 'private conversation leaked'; END IF;
 EXECUTE 'RESET ROLE';
 UPDATE hbh.caseload SET assigned_date=current_date-2,ended_date=current_date-1 WHERE child_id=own_child AND caseload.therapist_id=(SELECT t.therapist_id FROM hbh.therapists t WHERE t.user_id=staff_id);
 PERFORM set_config('hbh.user_id','dev_parent',true);
 EXECUTE 'SET LOCAL ROLE hbh_app';
 IF hbh.can_chat(staff_id) THEN RAISE EXCEPTION 'ended assignment still allowed'; END IF;
 IF NOT EXISTS(SELECT 1 FROM hbh.chat_peers() p WHERE hbh.chat_recipient_role(p.user_id)='manager')
 OR NOT EXISTS(SELECT 1 FROM hbh.chat_peers() p WHERE hbh.chat_recipient_role(p.user_id)='reception') THEN RAISE EXCEPTION 'manager/reception missing'; END IF;
 PERFORM set_config('hbh.user_id','unknown_chat_identity',true);
 IF EXISTS(SELECT 1 FROM hbh.chat_peers()) THEN RAISE EXCEPTION 'unknown identity leaked'; END IF;
END $test$;
ROLLBACK;
