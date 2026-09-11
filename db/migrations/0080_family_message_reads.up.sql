BEGIN;
CREATE TABLE hbh.family_message_reads (
 user_id integer NOT NULL REFERENCES hbh.users(user_id),
 guardian_id integer NOT NULL REFERENCES hbh.guardians(guardian_id),
 message_id bigint NOT NULL REFERENCES hbh.family_messages(message_id),
 PRIMARY KEY(user_id,guardian_id)
);
ALTER TABLE hbh.family_message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.family_message_reads FORCE ROW LEVEL SECURITY;
CREATE POLICY family_reads_self ON hbh.family_message_reads FOR ALL TO hbh_app
 USING (user_id=hbh.current_user_id())
 WITH CHECK (user_id=hbh.current_user_id() AND EXISTS (SELECT 1 FROM hbh.family_messages m WHERE m.message_id=family_message_reads.message_id AND m.guardian_id=family_message_reads.guardian_id));
GRANT SELECT,INSERT,UPDATE ON hbh.family_message_reads TO hbh_app;
INSERT INTO hbh.schema_migrations (version) VALUES ('0080');
COMMIT;
