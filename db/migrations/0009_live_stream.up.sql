-- =====================================================================
-- Hand By Hand (new) - migration 0009: live viewing.
--
-- This is the most sensitive thing the system does: a parent watching
-- their child in a therapy session. Five rules, and none of them is a
-- preference.
--
-- 1. LIVE ONLY. NO RECORDING, EVER.
--    There is no recordings table, no clip reference, no retention
--    column, and nothing here that could become one. The conventions
--    suite fails on any column whose name contains recording, clip or
--    video. "Mark an important moment" is a timestamped clinical note,
--    not a pointer into a file.
--
-- 2. THE DATABASE HOLDS NO CAMERA SECRET.
--    A gateway path and a credential REFERENCE, and that is all. No
--    RTSP url, no IP address, no username, no password - not even
--    encrypted, because a column that can hold one eventually does.
--
-- 3. THE BROWSER GETS AN OPAQUE TOKEN, NOT AN ADDRESS.
--    32 random bytes, SHA-256 at rest, naming neither the gateway nor
--    the camera. A URL that is merely unguessable is not access
--    control: it leaks through history, Referer, page source and the
--    first message anybody forwards.
--
-- 4. FIFTEEN MINUTES, AND THE CAP IS IN THE CODE.
--    The TTL is read from a parameter and then capped at fifteen
--    minutes regardless of what the parameter says. A misconfiguration
--    can make the window shorter and can never make it longer.
--
-- 5. A TEMPORARY GATEWAY REFUSES TO SERVE.
--    A trycloudflare quick tunnel has no authentication - whoever holds
--    the URL watches children in therapy - and its hostname changes on
--    every restart. So a gateway marked temporary, or not configured at
--    all, cannot issue a token. A fresh install is temporary, which
--    means the system fails CLOSED until somebody configures it
--    deliberately.
--
-- Error classes added here:
--   HB060  not permitted to view this stream
--   HB061  the session is not live
--   HB062  the stream token is unknown, expired or revoked
--   HB063  the media gateway is not configured for production use
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0009') THEN
    RAISE EXCEPTION 'migration 0009 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0008') THEN
    RAISE EXCEPTION 'migration 0008 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- CAMERAS
--
-- Look at what this table does NOT have. There is no rtsp_url, no
-- ip_address, no username and no password column - encrypted or
-- otherwise. credential_ref names a secret held by the gateway; the
-- database never learns it, so a database compromise does not become a
-- camera compromise.
-- =====================================================================
CREATE TABLE hbh.cameras (
  camera_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  branch_id      integer,
  room_id        integer     NOT NULL,
  code           text        NOT NULL,
  name_ar        text        NOT NULL,
  -- The path the gateway publishes this camera on. Not an address, and
  -- never sent to a browser.
  gateway_path   text        NOT NULL,
  -- The NAME of a credential the gateway holds. Never the credential.
  credential_ref text,
  status         text        NOT NULL DEFAULT 'OFFLINE',
  last_seen_at   timestamptz,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_cameras PRIMARY KEY (camera_id),
  CONSTRAINT fk_cam_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_cam_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_cam_room   FOREIGN KEY (room_id)   REFERENCES hbh.rooms (room_id),
  CONSTRAINT uq_cam_code UNIQUE (center_id, code),
  CONSTRAINT ck_cam_status CHECK (status IN ('ONLINE','OFFLINE','FAULT','DISABLED')),
  -- A path, not a URL. The constraint is what stops somebody pasting an
  -- rtsp:// address in here on a busy afternoon.
  CONSTRAINT ck_cam_path CHECK (gateway_path ~ '^[A-Za-z0-9_/-]{1,120}$')
);

-- One camera per room keeps "which camera is this child's session on"
-- a question with one answer.
CREATE UNIQUE INDEX uix_cam_room ON hbh.cameras (room_id) WHERE active_flg;
CREATE INDEX ix_cam_center ON hbh.cameras (center_id);
CREATE INDEX ix_cam_branch ON hbh.cameras (branch_id);

-- =====================================================================
-- STREAM TOKENS
--
-- Not granted to hbh_app at all. The API reaches them only through the
-- functions below, so it cannot read a token hash even by accident.
-- =====================================================================
CREATE TABLE hbh.stream_tokens (
  stream_token_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  token_hash      bytea       NOT NULL,
  session_id      integer     NOT NULL,
  camera_id       integer     NOT NULL,
  user_id         integer     NOT NULL,
  issued_at       timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz,
  client_ip       inet,
  CONSTRAINT pk_stream_tokens PRIMARY KEY (stream_token_id),
  CONSTRAINT fk_tok_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_tok_session FOREIGN KEY (session_id) REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT fk_tok_camera  FOREIGN KEY (camera_id)  REFERENCES hbh.cameras (camera_id),
  CONSTRAINT fk_tok_user    FOREIGN KEY (user_id)    REFERENCES hbh.users (user_id),
  CONSTRAINT uq_tok_hash UNIQUE (token_hash),
  CONSTRAINT ck_tok_window CHECK (expires_at > issued_at),
  -- Fifteen minutes, stated on the row as well as in the function that
  -- writes it. A future caller cannot widen the window by passing a
  -- different parameter.
  CONSTRAINT ck_tok_ttl CHECK (expires_at <= issued_at + interval '15 minutes')
);

CREATE INDEX ix_tok_center  ON hbh.stream_tokens (center_id);
CREATE INDEX ix_tok_session ON hbh.stream_tokens (session_id, issued_at DESC);
CREATE INDEX ix_tok_camera  ON hbh.stream_tokens (camera_id);
CREATE INDEX ix_tok_user    ON hbh.stream_tokens (user_id, issued_at DESC);

-- =====================================================================
-- EVERY VIEW IS LOGGED
--
-- Triggers do not catch reads, so watching is recorded explicitly. The
-- portal tells the family this in as many words.
-- =====================================================================
CREATE TABLE hbh.stream_views (
  view_id     bigint      GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  session_id  integer     NOT NULL,
  camera_id   integer     NOT NULL,
  user_id     integer     NOT NULL,
  child_id    integer     NOT NULL,
  started_at  timestamptz NOT NULL DEFAULT now(),
  ended_at    timestamptz,
  client_ip   inet,
  user_agent  text,
  CONSTRAINT pk_stream_views PRIMARY KEY (view_id),
  CONSTRAINT fk_view_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_view_session FOREIGN KEY (session_id) REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT fk_view_camera  FOREIGN KEY (camera_id)  REFERENCES hbh.cameras (camera_id),
  CONSTRAINT fk_view_user    FOREIGN KEY (user_id)    REFERENCES hbh.users (user_id),
  CONSTRAINT fk_view_child   FOREIGN KEY (child_id)   REFERENCES hbh.children (child_id),
  CONSTRAINT ck_view_window  CHECK (ended_at IS NULL OR ended_at >= started_at)
);

CREATE INDEX ix_view_center  ON hbh.stream_views (center_id, started_at DESC);
CREATE INDEX ix_view_session ON hbh.stream_views (session_id, started_at DESC);
CREATE INDEX ix_view_camera  ON hbh.stream_views (camera_id);
CREATE INDEX ix_view_user    ON hbh.stream_views (user_id, started_at DESC);
CREATE INDEX ix_view_child   ON hbh.stream_views (child_id, started_at DESC);

-- Nobody edits a viewing record. Not the family, not the centre.
CREATE TRIGGER trg_view_append_only
  BEFORE UPDATE OF center_id, session_id, camera_id, user_id, child_id, started_at
  ON hbh.stream_views
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

CREATE TRIGGER trg_view_no_delete
  BEFORE DELETE ON hbh.stream_views
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- WHO MAY WATCH
--
-- A guardian needs THREE things at once: the link to the child, the
-- can_view_live_flg on that link, and a session that is actually
-- running. The flag defaults to false - granting it is a deliberate act
-- by the centre, recorded on the link row.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.can_view_live(p_session_id integer)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT EXISTS (
    -- a guardian, on their own child, with the flag granted
    SELECT 1
    FROM   hbh.therapy_sessions s
    JOIN   hbh.guardian_children gc ON gc.child_id = s.child_id AND gc.active_flg
    JOIN   hbh.guardians g          ON g.guardian_id = gc.guardian_id AND g.active_flg
    WHERE  s.session_id = p_session_id
    AND    s.status = 'IN_PROGRESS'
    AND    gc.can_view_live_flg
    AND    g.user_id = hbh.current_user_id()

    UNION ALL

    -- or centre staff holding LIVE.VIEW, in the session's own centre
    SELECT 1
    FROM   hbh.therapy_sessions s
    JOIN   hbh.users u ON u.user_id = hbh.current_user_id()
    WHERE  s.session_id = p_session_id
    AND    s.status = 'IN_PROGRESS'
    AND    s.center_id = u.center_id
    AND    u.user_type IN ('STAFF','THERAPIST')
    AND    hbh.has_permission('LIVE.VIEW')
  )
$$;

COMMENT ON FUNCTION hbh.can_view_live(integer) IS
  'Live viewing gate. A guardian needs the link, the can_view_live_flg on it, and a session that is running.';

-- =====================================================================
-- ISSUING A TOKEN
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.issue_stream_token(
  p_session_id integer,
  p_client_ip  inet DEFAULT NULL)
RETURNS TABLE (token text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_sess  hbh.therapy_sessions%ROWTYPE;
  l_cam   hbh.cameras%ROWTYPE;
  l_base  text;
  l_temp  text;
  l_ttl   integer;
  l_token text;
  l_exp   timestamptz;
BEGIN
  SELECT * INTO l_sess FROM hbh.therapy_sessions WHERE session_id = p_session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such session %', p_session_id USING ERRCODE = 'HB061';
  END IF;

  -- The gate first. Nothing below this line runs for somebody who may
  -- not watch, so a refusal leaks nothing about the room or the camera.
  IF NOT hbh.can_view_live(p_session_id) THEN
    PERFORM hbh.audit_attempt('DENY', l_sess.center_id, hbh.current_app_user(),
                              'live view refused for session ' || p_session_id, p_client_ip);
    RAISE EXCEPTION 'not permitted to watch session %', p_session_id USING ERRCODE = 'HB060';
  END IF;

  IF l_sess.status <> 'IN_PROGRESS' THEN
    RAISE EXCEPTION 'session % is % - there is nothing live to watch', p_session_id, l_sess.status
      USING ERRCODE = 'HB061';
  END IF;

  -- A quick tunnel has no authentication and a hostname that changes on
  -- every restart. A fresh install is marked temporary, so the system
  -- fails closed until somebody configures a named tunnel deliberately.
  l_base := hbh.param(l_sess.center_id, 'MEDIA_GATEWAY_BASE_URL', '');
  l_temp := hbh.param(l_sess.center_id, 'MEDIA_GATEWAY_IS_TEMPORARY', 'true');

  IF coalesce(btrim(l_base), '') = '' THEN
    RAISE EXCEPTION 'the media gateway is not configured' USING ERRCODE = 'HB063';
  END IF;
  IF lower(l_temp) = 'true' THEN
    RAISE EXCEPTION 'the media gateway is marked temporary and may not serve a family'
      USING ERRCODE = 'HB063';
  END IF;
  IF l_base ILIKE '%trycloudflare.com%' THEN
    RAISE EXCEPTION 'a quick tunnel is a test tool, not a delivery mechanism'
      USING ERRCODE = 'HB063';
  END IF;

  SELECT * INTO l_cam FROM hbh.cameras
  WHERE room_id = l_sess.room_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'room % has no camera', l_sess.room_id USING ERRCODE = 'HB063';
  END IF;

  -- The cap is here, not only in the parameter. A misconfiguration can
  -- make the window shorter; nothing can make it longer.
  l_ttl := least(hbh.param(l_sess.center_id, 'STREAM_TOKEN_TTL_MIN', '15')::integer, 15);
  l_ttl := greatest(l_ttl, 1);

  l_token := encode(public.gen_random_bytes(32), 'hex');
  l_exp   := now() + make_interval(mins => l_ttl);

  INSERT INTO hbh.stream_tokens (center_id, token_hash, session_id, camera_id, user_id,
                                 expires_at, client_ip)
  VALUES (l_sess.center_id, public.digest(l_token, 'sha256'), p_session_id,
          l_cam.camera_id, hbh.current_user_id(), l_exp, p_client_ip);

  -- Watching is a read, and triggers do not catch reads.
  INSERT INTO hbh.stream_views (center_id, session_id, camera_id, user_id, child_id, client_ip)
  VALUES (l_sess.center_id, p_session_id, l_cam.camera_id, hbh.current_user_id(),
          l_sess.child_id, p_client_ip);

  PERFORM hbh.audit_attempt('READ', l_sess.center_id, hbh.current_app_user(),
                            'live view opened on session ' || p_session_id, p_client_ip);

  RETURN QUERY SELECT l_token, l_exp;
END
$$;

-- =====================================================================
-- REDEEMING A TOKEN
--
-- Called by the gateway, not by the browser. It is the only place the
-- camera path is ever produced, and it produces it only for a token
-- that is live, unrevoked, and belongs to a session still running.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.resolve_stream_token(p_token text)
RETURNS TABLE (ok boolean, reason text, gateway_path text, camera_id integer, session_id integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE r record;
BEGIN
  SELECT t.stream_token_id, t.expires_at, t.revoked_at, t.camera_id, t.session_id,
         c.gateway_path, s.status
    INTO r
  FROM   hbh.stream_tokens t
  JOIN   hbh.cameras c          ON c.camera_id = t.camera_id
  JOIN   hbh.therapy_sessions s ON s.session_id = t.session_id
  WHERE  t.token_hash = public.digest(p_token, 'sha256');

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_TOKEN', NULL::text, NULL::integer, NULL::integer; RETURN;
  END IF;
  IF r.revoked_at IS NOT NULL THEN
    RETURN QUERY SELECT false, 'REVOKED', NULL::text, NULL::integer, NULL::integer; RETURN;
  END IF;
  IF r.expires_at <= now() THEN
    RETURN QUERY SELECT false, 'EXPIRED', NULL::text, NULL::integer, NULL::integer; RETURN;
  END IF;
  -- The session ending ends the stream. A token outliving the therapy
  -- would be a window into an empty room, or the next child's.
  IF r.status <> 'IN_PROGRESS' THEN
    RETURN QUERY SELECT false, 'SESSION_ENDED', NULL::text, NULL::integer, NULL::integer; RETURN;
  END IF;

  RETURN QUERY SELECT true, 'OK', r.gateway_path, r.camera_id, r.session_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.revoke_stream_token(p_token text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  UPDATE hbh.stream_tokens SET revoked_at = now()
   WHERE token_hash = public.digest(p_token, 'sha256') AND revoked_at IS NULL;
  GET DIAGNOSTICS l_n = ROW_COUNT;
  RETURN l_n > 0;
END
$$;

-- Ends every live token for a session. Called when the session closes,
-- so nobody keeps watching a room the child has left.
CREATE OR REPLACE FUNCTION hbh.close_session_streams(p_session_id integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_n integer;
BEGIN
  UPDATE hbh.stream_tokens SET revoked_at = now()
   WHERE session_id = p_session_id AND revoked_at IS NULL AND expires_at > now();
  GET DIAGNOSTICS l_n = ROW_COUNT;

  UPDATE hbh.stream_views SET ended_at = now()
   WHERE session_id = p_session_id AND ended_at IS NULL;

  RETURN l_n;
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_cam_touch BEFORE UPDATE ON hbh.cameras FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_cam_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.cameras FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('camera_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.cameras       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.stream_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.stream_views  ENABLE ROW LEVEL SECURITY;

-- Even the camera row is staff-only. A family has no reason to learn
-- which path a room publishes on.
CREATE POLICY p_cam_select ON hbh.cameras
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('LIVE.VIEW') AND hbh.has_permission('CHILD.VIEW_ALL'));

-- A family may see WHO watched their child, which is the point of
-- keeping the record. Nobody may see another family's.
CREATE POLICY p_view_select ON hbh.stream_views
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.can_access_child(child_id));

-- stream_tokens gets no policy and no grant at all.

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.cameras, hbh.stream_views TO hbh_app;

REVOKE ALL ON FUNCTION hbh.can_view_live(integer)                 FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.issue_stream_token(integer, inet)      FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.resolve_stream_token(text)             FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.revoke_stream_token(text)              FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.close_session_streams(integer)         FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.can_view_live(integer)              TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.issue_stream_token(integer, inet)   TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.resolve_stream_token(text)          TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.revoke_stream_token(text)           TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.close_session_streams(integer)      TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

-- =====================================================================
-- PARAMETERS
--
-- Both default to the safe answer: no gateway, and temporary. A fresh
-- install therefore refuses to stream until somebody configures a named
-- tunnel on a domain the centre owns and clears the flag by hand.
-- =====================================================================
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'MEDIA_GATEWAY_BASE_URL', '', 'STRING',
   'عنوان بوابة البث — يبقى فارغًا حتى يُضبط نفق مُسمّى على نطاق يملكه المركز'),
  (NULL, 'MEDIA_GATEWAY_IS_TEMPORARY', 'true', 'BOOLEAN',
   'البوابة مؤقّتة — ما دامت true فلا يُصدَر أي توكن بث. تُطفأ يدويًا بعد النفق المُسمّى')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('stream_tokens', 'AUDIT_COLUMNS',
   'A credential record. issued_at, expires_at and revoked_at ARE its lifecycle, and nobody edits a token row by hand.'),
  ('stream_tokens', 'SOFT_DELETE',
   'A token is revoked, not deactivated. revoked_at says when, which a flag cannot.'),
  ('stream_views', 'AUDIT_COLUMNS',
   'An append-only viewing record. user_id and started_at are its attribution; only ended_at is ever written afterwards.'),
  ('stream_views', 'SOFT_DELETE',
   'Append-only. A hidden viewing record is a person who watched a child in therapy and left no trace, which is the one thing this table exists to prevent.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0009');
