BEGIN;
-- A caller can address active colleagues, or staff/guardian pairs, in their own centre.
CREATE FUNCTION hbh.can_chat(p_peer integer) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM hbh.users me JOIN hbh.users peer ON peer.center_id=me.center_id
 WHERE me.user_id=hbh.current_user_id() AND peer.user_id=p_peer AND me.user_id<>peer.user_id
 AND me.active_flg AND peer.active_flg AND me.status='ACTIVE' AND peer.status='ACTIVE'
 AND (me.user_type IN ('STAFF','THERAPIST') OR peer.user_type IN ('STAFF','THERAPIST')))
$$;
REVOKE ALL ON FUNCTION hbh.can_chat(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.can_chat(integer) TO hbh_app;
CREATE TABLE hbh.direct_messages(
 message_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 center_id integer NOT NULL REFERENCES hbh.centers(center_id),
 sender_id integer NOT NULL REFERENCES hbh.users(user_id),
 recipient_id integer NOT NULL REFERENCES hbh.users(user_id),
 body_ar text NOT NULL CHECK(length(trim(body_ar)) BETWEEN 1 AND 4000),
 request_id uuid NOT NULL,
 read_at timestamptz,
 active_flg boolean NOT NULL DEFAULT true,deleted_at timestamptz,
 created_at timestamptz NOT NULL DEFAULT now(),created_by text NOT NULL DEFAULT hbh.current_app_user(),updated_at timestamptz,updated_by text,
 CHECK(sender_id<>recipient_id),CHECK(active_flg=(deleted_at IS NULL)),
 UNIQUE(sender_id,recipient_id,request_id)
);
CREATE INDEX ix_direct_messages_center ON hbh.direct_messages(center_id,message_id DESC);
CREATE INDEX ix_direct_messages_sender ON hbh.direct_messages(sender_id,recipient_id,message_id DESC);
CREATE INDEX ix_direct_messages_recipient ON hbh.direct_messages(recipient_id,sender_id,message_id DESC);
ALTER TABLE hbh.direct_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.direct_messages FORCE ROW LEVEL SECURITY;
CREATE POLICY direct_read ON hbh.direct_messages FOR SELECT TO hbh_app USING(
 center_id=hbh.current_center_id() AND active_flg AND
 ((sender_id=hbh.current_user_id() AND hbh.can_chat(recipient_id)) OR (recipient_id=hbh.current_user_id() AND hbh.can_chat(sender_id))));
CREATE POLICY direct_send ON hbh.direct_messages FOR INSERT TO hbh_app WITH CHECK(
 center_id=hbh.current_center_id() AND sender_id=hbh.current_user_id() AND hbh.can_chat(recipient_id) AND active_flg AND deleted_at IS NULL AND read_at IS NULL);
CREATE POLICY direct_read_receipt ON hbh.direct_messages FOR UPDATE TO hbh_app USING(
 center_id=hbh.current_center_id() AND recipient_id=hbh.current_user_id() AND active_flg AND hbh.can_chat(sender_id))
 WITH CHECK(center_id=hbh.current_center_id() AND recipient_id=hbh.current_user_id() AND active_flg AND hbh.can_chat(sender_id));
GRANT SELECT,INSERT ON hbh.direct_messages TO hbh_app;
GRANT UPDATE(read_at) ON hbh.direct_messages TO hbh_app;
GRANT USAGE ON SEQUENCE hbh.direct_messages_message_id_seq TO hbh_app;
CREATE TRIGGER trg_direct_touch BEFORE UPDATE ON hbh.direct_messages FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_direct_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.direct_messages FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit();
-- Return only contact metadata, never the user directory's sensitive fields.
CREATE FUNCTION hbh.chat_peers() RETURNS TABLE(user_id integer,name text,kind text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT u.user_id,u.full_name_ar,CASE WHEN u.user_type='GUARDIAN' THEN 'guardian' ELSE 'staff' END
 FROM hbh.users u WHERE u.center_id=hbh.current_center_id() AND hbh.can_chat(u.user_id)
$$;
REVOKE ALL ON FUNCTION hbh.chat_peers() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.chat_peers() TO hbh_app;
-- Extend the current kind constraint without discarding kinds introduced by earlier migrations.
DO $$ DECLARE definition text; BEGIN
 SELECT pg_get_constraintdef(oid) INTO definition FROM pg_constraint WHERE conrelid='hbh.notifications'::regclass AND conname='ck_ntf_kind';
 ALTER TABLE hbh.notifications DROP CONSTRAINT ck_ntf_kind;
 EXECUTE 'ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code=''CHAT_MESSAGE'' OR ' || substring(definition FROM 7) || ')';
END $$;
ALTER TABLE hbh.notifications ADD COLUMN chat_message_id bigint REFERENCES hbh.direct_messages(message_id);
CREATE INDEX ix_ntf_chat_message ON hbh.notifications(chat_message_id);
CREATE FUNCTION hbh.trg_direct_notification() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
BEGIN
 IF TG_OP='INSERT' THEN
  INSERT INTO hbh.notifications(center_id,user_id,kind_code,title_ar,body_ar,link_kind,link_id,chat_message_id)
  SELECT NEW.center_id,NEW.recipient_id,'CHAT_MESSAGE',u.full_name_ar,left(NEW.body_ar,160),'CHAT',NEW.sender_id,NEW.message_id FROM hbh.users u WHERE u.user_id=NEW.sender_id;
 ELSE
  UPDATE hbh.notifications SET read_at=coalesce(read_at,now()) WHERE user_id=NEW.recipient_id AND center_id=NEW.center_id AND link_kind='CHAT' AND link_id=NEW.sender_id AND chat_message_id=NEW.message_id;
 END IF;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION hbh.trg_direct_notification() FROM PUBLIC;
CREATE TRIGGER trg_direct_notification AFTER INSERT OR UPDATE OF read_at ON hbh.direct_messages FOR EACH ROW EXECUTE FUNCTION hbh.trg_direct_notification();
CREATE FUNCTION hbh.broadcast_staff(p_body text,p_request uuid) RETURNS integer LANGUAGE plpgsql SECURITY INVOKER SET search_path=hbh,pg_catalog AS $$
DECLARE n integer;
BEGIN
 IF NOT hbh.has_permission('REQUEST.MANAGE') THEN RAISE EXCEPTION 'Not allowed' USING ERRCODE='42501'; END IF;
 INSERT INTO hbh.direct_messages(center_id,sender_id,recipient_id,body_ar,request_id)
 SELECT hbh.current_center_id(),hbh.current_user_id(),user_id,p_body,p_request FROM hbh.chat_peers() WHERE kind='staff'
 ON CONFLICT(sender_id,recipient_id,request_id) DO NOTHING;
 SELECT count(*) INTO n FROM hbh.direct_messages WHERE sender_id=hbh.current_user_id() AND request_id=p_request AND body_ar=p_body;
 RETURN n;
END $$;
REVOKE ALL ON FUNCTION hbh.broadcast_staff(text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.broadcast_staff(text,uuid) TO hbh_app;
INSERT INTO hbh.schema_migrations(version) VALUES('0143');
COMMIT;
