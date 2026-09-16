BEGIN;
-- Shared by both directions of a private conversation. No caller-supplied
-- centre or child list can expand the guardian's recipient set.
CREATE FUNCTION hbh.guardian_chat_role(p_guardian integer,p_staff integer)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT CASE
 WHEN EXISTS(SELECT 1 FROM hbh.user_roles ur JOIN hbh.roles r USING(role_id)
   WHERE ur.user_id=s.user_id AND ur.active_flg AND r.active_flg AND r.center_id=s.center_id AND r.code='CENTER_ADMIN') THEN 'manager'
 WHEN EXISTS(SELECT 1 FROM hbh.user_roles ur JOIN hbh.roles r USING(role_id)
   WHERE ur.user_id=s.user_id AND ur.active_flg AND r.active_flg AND r.center_id=s.center_id AND r.code='RECEPTION') THEN 'reception'
 WHEN EXISTS(SELECT 1 FROM hbh.guardians g
   JOIN hbh.guardian_children gc USING(guardian_id)
   JOIN hbh.children ch USING(child_id)
   JOIN hbh.caseload cl USING(child_id)
   JOIN hbh.therapists t USING(therapist_id)
   JOIN hbh.centers c ON c.center_id=g.center_id
   WHERE g.user_id=p_guardian AND g.active_flg AND gc.active_flg AND ch.active_flg
     AND g.center_id=s.center_id AND ch.center_id=s.center_id AND cl.center_id=s.center_id
     AND t.center_id=s.center_id AND t.user_id=s.user_id AND t.active_flg AND cl.active_flg
     AND cl.assigned_date<=(now() AT TIME ZONE c.time_zone)::date
     AND (cl.ended_date IS NULL OR cl.ended_date>=(now() AT TIME ZONE c.time_zone)::date)) THEN 'therapist'
 END
 FROM hbh.users g JOIN hbh.users s ON s.center_id=g.center_id
 WHERE g.user_id=p_guardian AND g.user_type='GUARDIAN' AND g.active_flg AND g.status='ACTIVE'
 AND s.user_id=p_staff AND s.user_type IN ('STAFF','THERAPIST') AND s.active_flg AND s.status='ACTIVE'
$$;
REVOKE ALL ON FUNCTION hbh.guardian_chat_role(integer,integer) FROM PUBLIC;

CREATE OR REPLACE FUNCTION hbh.can_chat(p_peer integer) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM hbh.users me JOIN hbh.users peer ON peer.center_id=me.center_id
 WHERE me.user_id=hbh.current_user_id() AND peer.user_id=p_peer AND me.user_id<>peer.user_id
 AND me.active_flg AND peer.active_flg AND me.status='ACTIVE' AND peer.status='ACTIVE'
 AND ((me.user_type IN ('STAFF','THERAPIST') AND peer.user_type IN ('STAFF','THERAPIST'))
   OR (me.user_type='GUARDIAN' AND hbh.guardian_chat_role(me.user_id,peer.user_id) IS NOT NULL)
   OR (peer.user_type='GUARDIAN' AND hbh.guardian_chat_role(peer.user_id,me.user_id) IS NOT NULL)))
$$;
CREATE FUNCTION hbh.chat_recipient_role(p_peer integer) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT hbh.guardian_chat_role(hbh.current_user_id(),p_peer) WHERE hbh.can_chat(p_peer)
$$;
REVOKE ALL ON FUNCTION hbh.chat_recipient_role(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.chat_recipient_role(integer) TO hbh_app;
INSERT INTO hbh.schema_migrations(version) VALUES('0147');
COMMIT;
