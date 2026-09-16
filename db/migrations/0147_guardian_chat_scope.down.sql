BEGIN;
CREATE OR REPLACE FUNCTION hbh.can_chat(p_peer integer) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM hbh.users me JOIN hbh.users peer ON peer.center_id=me.center_id
 WHERE me.user_id=hbh.current_user_id() AND peer.user_id=p_peer AND me.user_id<>peer.user_id
 AND me.active_flg AND peer.active_flg AND me.status='ACTIVE' AND peer.status='ACTIVE'
 AND (me.user_type IN ('STAFF','THERAPIST') OR peer.user_type IN ('STAFF','THERAPIST')))
$$;
DROP FUNCTION hbh.chat_recipient_role(integer);
DROP FUNCTION hbh.guardian_chat_role(integer,integer);
DELETE FROM hbh.schema_migrations WHERE version='0147';
COMMIT;
