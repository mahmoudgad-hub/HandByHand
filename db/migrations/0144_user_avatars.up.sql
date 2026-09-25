BEGIN;
CREATE FUNCTION hbh.can_view_avatar(p_user integer) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=hbh,pg_catalog AS $$
 SELECT EXISTS(SELECT 1 FROM hbh.users me JOIN hbh.users peer ON peer.center_id=me.center_id
 WHERE me.user_id=hbh.current_user_id() AND peer.user_id=p_user
 AND me.active_flg AND peer.active_flg AND me.status='ACTIVE' AND peer.status='ACTIVE'
 AND (me.user_id=peer.user_id OR me.user_type IN ('STAFF','THERAPIST') OR peer.user_type IN ('STAFF','THERAPIST')))
$$;
REVOKE ALL ON FUNCTION hbh.can_view_avatar(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.can_view_avatar(integer) TO hbh_app;
-- User-selected application avatars are separate from private personnel photographs.
CREATE TABLE hbh.user_avatars (
 user_id integer PRIMARY KEY REFERENCES hbh.users(user_id),
 center_id integer NOT NULL REFERENCES hbh.centers(center_id),
 file_name text NOT NULL,
 updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE hbh.user_avatars ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.user_avatars FORCE ROW LEVEL SECURITY;
CREATE POLICY avatar_read ON hbh.user_avatars FOR SELECT TO hbh_app USING (
 center_id=hbh.current_center_id() AND hbh.can_view_avatar(user_id)
);
CREATE POLICY avatar_insert ON hbh.user_avatars FOR INSERT TO hbh_app WITH CHECK (
 center_id=hbh.current_center_id() AND user_id=hbh.current_user_id()
);
CREATE POLICY avatar_update ON hbh.user_avatars FOR UPDATE TO hbh_app USING (
 center_id=hbh.current_center_id() AND user_id=hbh.current_user_id()
) WITH CHECK (center_id=hbh.current_center_id() AND user_id=hbh.current_user_id());
GRANT SELECT,INSERT,UPDATE ON hbh.user_avatars TO hbh_app;
INSERT INTO hbh.schema_migrations(version) VALUES('0144');
COMMIT;
