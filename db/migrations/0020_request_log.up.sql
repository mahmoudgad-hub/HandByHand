-- =====================================================================
-- Hand By Hand (new) - migration 0020: who used it, how fast, what broke
--
-- One row per HTTP request: who made it, which route, how long it took,
-- what came back, and - when something failed - the code, the message
-- and whatever detail the service could add.
--
-- Four decisions worth stating, because each one is a trade the obvious
-- design gets wrong:
--
-- 1. NO FOREIGN KEYS.
--    Not to users, not to centres. A log records what HAPPENED,
--    including requests by an account later removed, and a request that
--    had no centre because nobody was signed in. A foreign key here
--    would either block those deletions or quietly rewrite history, and
--    it costs a constraint check on the hottest insert in the system.
--    user_id and username are both kept: the id to join while the user
--    exists, the name to read afterwards.
--
-- 2. ROUTE AND PATH ARE DIFFERENT COLUMNS.
--    route is the template - /api/children/{id} - and path is what was
--    actually asked for. Grouping by path gives one row per child and
--    no idea which endpoint is slow.
--
-- 3. IT IS PURGED, AND THE AUDIT LOG IS NOT.
--    This is operational telemetry and it grows faster than anything
--    else here, so run_maintenance deletes rows past a retention set in
--    sys_params. hbh.audit_log is NOT touched: deleting a clinical
--    audit trail is a compliance decision for the owner to take
--    deliberately, not a side effect of a housekeeping job.
--
-- 4. NO PERSONAL DATA IN error_message.
--    The service writes a code and a short technical message. A child's
--    name in a stack trace would put clinical data in a table the
--    operations screen shows to anyone holding OPS.VIEW.
--
-- Error classes added here: none. Logging never raises - see log_request.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0020') THEN
    RAISE EXCEPTION 'migration 0020 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0019') THEN
    RAISE EXCEPTION 'migration 0019 must be applied first';
  END IF;
END
$guard$;

CREATE TABLE hbh.request_log (
  log_id        bigint      GENERATED ALWAYS AS IDENTITY,
  occurred_at   timestamptz NOT NULL DEFAULT now(),
  request_id    text,
  center_id     integer,
  user_id       integer,
  username      text,
  user_type     text,
  method        text        NOT NULL,
  route         text        NOT NULL,
  path          text,
  status_code   smallint    NOT NULL,
  duration_ms   integer     NOT NULL,
  client_ip     inet,
  user_agent    text,
  error_code    text,
  error_message text,
  detail        jsonb,
  CONSTRAINT pk_request_log PRIMARY KEY (log_id),
  CONSTRAINT ck_rlog_method CHECK (method IN ('GET','POST','PUT','PATCH','DELETE','HEAD','OPTIONS')),
  CONSTRAINT ck_rlog_status CHECK (status_code BETWEEN 100 AND 599),
  CONSTRAINT ck_rlog_duration CHECK (duration_ms >= 0),
  -- A failure without a code is a failure nobody can group, count or
  -- alert on.
  CONSTRAINT ck_rlog_error CHECK (status_code < 400 OR error_code IS NOT NULL)
);

CREATE INDEX ix_rlog_time   ON hbh.request_log (occurred_at DESC);
CREATE INDEX ix_rlog_route  ON hbh.request_log (route, occurred_at DESC);
CREATE INDEX ix_rlog_user   ON hbh.request_log (user_id, occurred_at DESC);
CREATE INDEX ix_rlog_center ON hbh.request_log (center_id, occurred_at DESC);
CREATE INDEX ix_rlog_req    ON hbh.request_log (request_id);
-- The two queries the operations screen actually runs.
CREATE INDEX ix_rlog_errors ON hbh.request_log (occurred_at DESC)
  WHERE status_code >= 400;
CREATE INDEX ix_rlog_slow   ON hbh.request_log (route, duration_ms DESC);

-- Nobody edits a request log. Not the centre, not the operator.
CREATE TRIGGER trg_rlog_append_only
  BEFORE UPDATE ON hbh.request_log
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- WRITING ONE
--
-- Never raises. A logging failure must not turn a request that WORKED
-- into a request that failed - the API calls this after the response is
-- decided, and a broken log line is a warning in the server log and
-- nothing more.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.log_request(
  p_method        text,
  p_route         text,
  p_status_code   smallint,
  p_duration_ms   integer,
  p_path          text    DEFAULT NULL,
  p_request_id    text    DEFAULT NULL,
  p_client_ip     inet    DEFAULT NULL,
  p_user_agent    text    DEFAULT NULL,
  p_error_code    text    DEFAULT NULL,
  p_error_message text    DEFAULT NULL,
  p_detail        jsonb   DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
BEGIN
  -- The identity is read from the request, not passed in: a caller
  -- cannot log a request as somebody else.
  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = hbh.current_user_id();

  INSERT INTO hbh.request_log (request_id, center_id, user_id, username, user_type,
                               method, route, path, status_code, duration_ms,
                               client_ip, user_agent, error_code, error_message, detail)
  VALUES (p_request_id, l_user.center_id, l_user.user_id, l_user.username, l_user.user_type,
          upper(p_method), p_route, p_path, p_status_code, p_duration_ms,
          p_client_ip, p_user_agent, p_error_code, left(p_error_message, 2000), p_detail);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'log_request could not write: % %', SQLSTATE, SQLERRM;
END
$$;

-- =====================================================================
-- WHAT THE OPERATIONS SCREEN READS
-- =====================================================================

-- Per route: how often, how fast, how often it breaks.
CREATE VIEW hbh.v_api_health
WITH (security_invoker = true)
AS
SELECT r.route,
       r.method,
       count(*)                                                       AS calls,
       count(*) FILTER (WHERE r.status_code >= 500)                   AS server_errors,
       count(*) FILTER (WHERE r.status_code BETWEEN 400 AND 499)      AS client_errors,
       round(100.0 * count(*) FILTER (WHERE r.status_code >= 400)
             / greatest(count(*), 1), 2)                              AS error_pct,
       round(percentile_cont(0.50) WITHIN GROUP (ORDER BY r.duration_ms)::numeric, 0) AS p50_ms,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY r.duration_ms)::numeric, 0) AS p95_ms,
       max(r.duration_ms)                                             AS max_ms,
       max(r.occurred_at)                                             AS last_call_at,
       max(r.occurred_at) FILTER (WHERE r.status_code >= 400)         AS last_error_at
FROM   hbh.request_log r
GROUP  BY r.route, r.method;

COMMENT ON VIEW hbh.v_api_health IS
  'Per endpoint: calls, p50/p95 latency and error rate. Grouped by ROUTE, not path - grouping by path gives one row per child.';

-- The last failures, in full.
CREATE VIEW hbh.v_recent_errors
WITH (security_invoker = true)
AS
SELECT r.log_id, r.occurred_at, r.request_id, r.username, r.user_type,
       r.method, r.route, r.path, r.status_code, r.duration_ms,
       r.error_code, r.error_message, r.detail, r.client_ip
FROM   hbh.request_log r
WHERE  r.status_code >= 400
ORDER  BY r.occurred_at DESC;

-- Who is actually using it.
CREATE VIEW hbh.v_user_activity
WITH (security_invoker = true)
AS
SELECT r.user_id,
       r.username,
       r.user_type,
       r.center_id,
       count(*)                                            AS requests,
       count(*) FILTER (WHERE r.status_code >= 400)         AS failed_requests,
       count(DISTINCT date_trunc('day', r.occurred_at))     AS active_days,
       min(r.occurred_at)                                   AS first_seen_at,
       max(r.occurred_at)                                   AS last_seen_at,
       max(r.client_ip::text)                               AS last_ip
FROM   hbh.request_log r
WHERE  r.user_id IS NOT NULL
GROUP  BY r.user_id, r.username, r.user_type, r.center_id;

COMMENT ON VIEW hbh.v_user_activity IS
  'Who used the application, how much, and when they were last seen.';

-- =====================================================================
-- RETENTION
--
-- run_maintenance is redefined here rather than extended, because a
-- function has one definition and splitting it across two migrations
-- would leave the reader guessing which one is live.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.run_maintenance()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_run      bigint;
  l_expired  integer := 0;
  l_streams  integer := 0;
  l_purged   integer := 0;
  l_keep     integer;
  l_detail   text    := '';
BEGIN
  INSERT INTO hbh.maintenance_runs DEFAULT VALUES RETURNING run_id INTO l_run;

  -- Each task in its own handler. One failing task must not stop the
  -- others, and must not vanish either.
  BEGIN
    l_expired := hbh.expire_packages();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'expire_packages: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  BEGIN
    UPDATE hbh.stream_tokens t
       SET revoked_at = now()
     WHERE t.revoked_at IS NULL
       AND t.expires_at > now()
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = t.session_id AND s.status <> 'IN_PROGRESS');
    GET DIAGNOSTICS l_streams = ROW_COUNT;

    UPDATE hbh.stream_views v
       SET ended_at = now()
     WHERE v.ended_at IS NULL
       AND EXISTS (SELECT 1 FROM hbh.therapy_sessions s
                   WHERE s.session_id = v.session_id AND s.status <> 'IN_PROGRESS');
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'stream cleanup: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  -- Telemetry only. hbh.audit_log is deliberately NOT purged here:
  -- deleting a clinical audit trail is a decision for the owner, not a
  -- side effect of housekeeping.
  BEGIN
    l_keep := hbh.param(NULL, 'REQUEST_LOG_RETENTION_DAYS', '30')::integer;
    IF l_keep > 0 THEN
      DELETE FROM hbh.request_log
       WHERE occurred_at < now() - make_interval(days => l_keep);
      GET DIAGNOSTICS l_purged = ROW_COUNT;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'request_log purge: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail           = nullif(l_detail || CASE WHEN l_purged > 0
                                      THEN 'request_log purged: ' || l_purged || '; '
                                      ELSE '' END, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$$;

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- OPS.VIEW and nothing less. The log names every user and every path
-- they touched; a guardian must never reach it, and neither should a
-- therapist who has no operational role.
-- =====================================================================
ALTER TABLE hbh.request_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_rlog_select ON hbh.request_log
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL AND hbh.has_permission('OPS.VIEW'));

GRANT SELECT ON hbh.request_log, hbh.v_api_health, hbh.v_recent_errors, hbh.v_user_activity
  TO hbh_app;

REVOKE ALL ON FUNCTION hbh.log_request(text, text, smallint, integer, text, text, inet, text, text, text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.log_request(text, text, smallint, integer, text, text, inet, text, text, text, jsonb) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'REQUEST_LOG_RETENTION_DAYS', '30', 'NUMBER',
   'كم يومًا يُحتفظ بسجلّ الطلبات — صفر يعني بلا حذف. سجلّ التدقيق السريري لا يُحذف هنا إطلاقًا')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('request_log', 'AUDIT_COLUMNS',
   'Operational telemetry, one row per HTTP request. occurred_at and username ARE its attribution, and nobody edits a log line - an update trail would double the write cost of the hottest table here.'),
  ('request_log', 'SOFT_DELETE',
   'Append-only, and purged wholesale by retention rather than hidden one row at a time. A deactivated log line is a request that happened and can no longer be counted.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0020');
