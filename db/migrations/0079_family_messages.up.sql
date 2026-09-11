BEGIN;
CREATE TABLE hbh.family_messages (
 message_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 center_id integer NOT NULL REFERENCES hbh.centers(center_id),
 guardian_id integer NOT NULL REFERENCES hbh.guardians(guardian_id),
 sender_id integer NOT NULL REFERENCES hbh.users(user_id),
 body_ar text NOT NULL CHECK (length(trim(body_ar)) BETWEEN 1 AND 4000),
 request_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(sender_id,request_id)
);
CREATE INDEX ix_family_messages_thread ON hbh.family_messages(center_id,guardian_id,message_id DESC);
ALTER TABLE hbh.family_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.family_messages FORCE ROW LEVEL SECURITY;
CREATE POLICY family_messages_read ON hbh.family_messages FOR SELECT TO hbh_app USING (
 center_id=hbh.current_center_id() AND EXISTS (
 SELECT 1 FROM hbh.guardians g WHERE g.guardian_id=family_messages.guardian_id AND g.center_id=family_messages.center_id AND g.active_flg
 AND (hbh.has_permission('REQUEST.MANAGE') OR g.user_id=hbh.current_user_id())));
CREATE POLICY family_messages_send ON hbh.family_messages FOR INSERT TO hbh_app WITH CHECK (
 center_id=hbh.current_center_id() AND sender_id=hbh.current_user_id() AND EXISTS (
 SELECT 1 FROM hbh.guardians g WHERE g.guardian_id=family_messages.guardian_id AND g.center_id=family_messages.center_id AND g.active_flg
 AND g.user_id IS NOT NULL AND (hbh.has_permission('REQUEST.MANAGE') OR g.user_id=hbh.current_user_id())));
GRANT SELECT,INSERT ON hbh.family_messages TO hbh_app;
GRANT USAGE ON SEQUENCE hbh.family_messages_message_id_seq TO hbh_app;
INSERT INTO hbh.schema_migrations (version) VALUES ('0079');
COMMIT;
