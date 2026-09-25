BEGIN;

-- Product usage is separate from API polling and from the clinical audit log.
CREATE TABLE hbh.usage_events (
  event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  center_id integer NOT NULL REFERENCES hbh.centers(center_id),
  user_id integer NOT NULL REFERENCES hbh.users(user_id),
  app text NOT NULL CHECK (app IN ('portal','ops')),
  feature text NOT NULL CHECK (feature ~ '^[a-zA-Z0-9_.:-]{1,100}$'),
  kind text NOT NULL CHECK (kind IN ('page','action')),
  action text NOT NULL CHECK (action IN ('view','POST','PUT','PATCH','DELETE'))
);
CREATE INDEX ix_usage_center_time ON hbh.usage_events(center_id, occurred_at DESC);
ALTER TABLE hbh.usage_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_usage_select ON hbh.usage_events FOR SELECT TO hbh_app
  USING (center_id = (SELECT hbh.current_center_id()) AND (SELECT hbh.has_permission('OPS.VIEW')));
GRANT SELECT ON hbh.usage_events TO hbh_app;

CREATE FUNCTION hbh.record_usage(p_app text, p_feature text, p_kind text, p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = hbh, pg_catalog AS $$
DECLARE u hbh.users%ROWTYPE;
BEGIN
  SELECT * INTO u FROM hbh.users WHERE user_id = hbh.current_user_id() AND active_flg AND status = 'ACTIVE';
  IF u.user_id IS NULL THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN'; END IF;
  IF (p_app = 'portal' AND u.user_type <> 'GUARDIAN') OR (p_app = 'ops' AND u.user_type NOT IN ('STAFF','THERAPIST')) THEN
    RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN';
  END IF;
  IF (p_kind = 'page') <> (p_action = 'view') THEN RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION'; END IF;
  INSERT INTO hbh.usage_events(center_id,user_id,app,feature,kind,action)
  VALUES(u.center_id,u.user_id,p_app,p_feature,p_kind,p_action);
END $$;

-- Bounds are local calendar dates in the centre's zone, converted once to UTC.
-- This includes the whole end date, including DST days of 23 or 25 hours.
CREATE FUNCTION hbh.ops_analytics(p_from date, p_to date, p_kind text DEFAULT '', p_feature text DEFAULT '', p_offset integer DEFAULT 0)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = hbh, pg_catalog AS $$
DECLARE c integer := hbh.current_center_id(); z text; a timestamptz; b timestamptz; result jsonb;
BEGIN
  IF c IS NULL OR hbh.has_permission('OPS.VIEW') IS NOT TRUE THEN RAISE EXCEPTION USING ERRCODE='42501', MESSAGE='FORBIDDEN'; END IF;
  SELECT time_zone INTO z FROM hbh.centers WHERE center_id=c;
  IF p_from IS NULL OR p_to IS NULL OR p_to < p_from OR p_to - p_from > 365 OR p_offset < 0 THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION';
  END IF;
  a := p_from::timestamp AT TIME ZONE z;
  b := (p_to+1)::timestamp AT TIME ZONE z;
  IF p_kind = '' THEN
    WITH r AS MATERIALIZED (
      SELECT * FROM hbh.request_log WHERE center_id=c AND occurred_at>=a AND occurred_at<b
        AND route NOT LIKE '/api/v1/ops/%' AND route <> '/api/v1/usage-events'
    ), e AS MATERIALIZED (
      SELECT * FROM hbh.usage_events WHERE center_id=c AND occurred_at>=a AND occurred_at<b
    ), s AS MATERIALIZED (
      SELECT s.*,u.user_type FROM hbh.auth_sessions s JOIN hbh.users u USING(user_id)
      WHERE s.center_id=c AND s.issued_at>=a AND s.issued_at<b
    ), firsts AS (
      SELECT s.user_id,min(s.issued_at) AS at FROM hbh.auth_sessions s JOIN hbh.users u USING(user_id)
      WHERE s.center_id=c AND u.user_type='GUARDIAN' GROUP BY s.user_id
    )
    SELECT jsonb_build_object(
      'time_zone',z,
      'tracking_since',(SELECT min(occurred_at) FROM hbh.usage_events WHERE center_id=c),
      'requests', (SELECT count(*) FROM r),
      'successes',(SELECT count(*) FROM r WHERE status_code<400),
      'errors',(SELECT count(*) FROM r WHERE status_code>=400),
      'p50_ms',(SELECT round(percentile_cont(.5) WITHIN GROUP(ORDER BY duration_ms)::numeric,1) FROM r),
      'p95_ms',(SELECT round(percentile_cont(.95) WITHIN GROUP(ORDER BY duration_ms)::numeric,1) FROM r),
      'registrations',(SELECT count(*) FROM hbh.users WHERE center_id=c AND user_type='GUARDIAN' AND created_at>=a AND created_at<b),
      'applications',(SELECT count(DISTINCT parent_mobile) FROM hbh.enrolment_applications WHERE center_id=c AND source_code='WEB' AND submitted_at>=a AND submitted_at<b),
      'first_logins',(SELECT count(*) FROM firsts WHERE at>=a AND at<b),
      'staff_logins',(SELECT count(DISTINCT user_id) FROM s WHERE user_type IN ('STAFF','THERAPIST')),
      'staff_active',(SELECT count(DISTINCT user_id) FROM e WHERE app='ops'),
      'staff_pages',(SELECT count(DISTINCT feature) FROM e WHERE app='ops' AND kind='page'),
      'portal_users',(SELECT count(DISTINCT user_id) FROM e WHERE app='portal'),
      'portal_features',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY users DESC,feature) FROM (
        SELECT feature,count(DISTINCT user_id) AS users,count(*) FILTER(WHERE kind='page') AS visits,
          count(*) FILTER(WHERE kind='action') AS actions FROM e WHERE app='portal' GROUP BY feature) x),'[]'::jsonb),
      'pages',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY users DESC,feature) FROM (
        SELECT feature,count(DISTINCT user_id) AS users,count(*) AS visits FROM e WHERE app='ops' AND kind='page' GROUP BY feature) x),'[]'::jsonb),
      'performance',coalesce((SELECT jsonb_agg(to_jsonb(x) ORDER BY p95_ms DESC,route,method) FROM (
        SELECT route,method,count(*) AS calls,round(percentile_cont(.95) WITHIN GROUP(ORDER BY duration_ms)::numeric,1) AS p95_ms
        FROM r GROUP BY route,method) x),'[]'::jsonb)
    ) INTO result;
    RETURN result;
  END IF;
  IF p_kind NOT IN ('successes','errors','performance','registrations','applications','first_logins','staff_logins','staff_active','staff_pages','portal_features') THEN
    RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='VALIDATION';
  END IF;
  WITH details AS (
    SELECT r.occurred_at AS at,r.log_id::text AS id,coalesce(u.full_name_ar,r.username,'') AS name,
      coalesce(r.username,'') AS username,r.route AS feature,r.method AS action,1::bigint AS visits,
      r.status_code::integer AS status,r.duration_ms::numeric AS duration_ms
    FROM hbh.request_log r LEFT JOIN hbh.users u ON u.user_id=r.user_id AND u.center_id=c
    WHERE p_kind IN ('successes','errors','performance') AND r.center_id=c AND r.occurred_at>=a AND r.occurred_at<b
      AND r.route NOT LIKE '/api/v1/ops/%' AND r.route <> '/api/v1/usage-events'
      AND (p_kind='performance' OR (p_kind='errors' AND r.status_code>=400) OR (p_kind='successes' AND r.status_code<400))
      AND (p_feature='' OR r.method || ' ' || r.route=p_feature)
    UNION ALL
    SELECT max(submitted_at),min(application_id)::text,max(parent_name_ar),'','','application',count(*),NULL,NULL
      FROM hbh.enrolment_applications WHERE p_kind='applications' AND center_id=c AND source_code='WEB' AND submitted_at>=a AND submitted_at<b
      GROUP BY parent_mobile
    UNION ALL
    SELECT u.created_at,u.user_id::text,u.full_name_ar,u.username,'','registration',1,NULL,NULL
      FROM hbh.users u WHERE p_kind='registrations' AND u.center_id=c AND u.user_type='GUARDIAN' AND u.created_at>=a AND u.created_at<b
    UNION ALL
    SELECT min(s.issued_at),u.user_id::text,u.full_name_ar,u.username,'','first_login',1,NULL,NULL
      FROM hbh.auth_sessions s JOIN hbh.users u USING(user_id)
      WHERE p_kind='first_logins' AND s.center_id=c AND u.user_type='GUARDIAN'
      GROUP BY u.user_id HAVING min(s.issued_at)>=a AND min(s.issued_at)<b
    UNION ALL
    SELECT max(s.issued_at),u.user_id::text,u.full_name_ar,u.username,'','login',count(*),NULL,NULL
      FROM hbh.auth_sessions s JOIN hbh.users u USING(user_id)
      WHERE p_kind='staff_logins' AND s.center_id=c AND u.user_type IN ('STAFF','THERAPIST') AND s.issued_at>=a AND s.issued_at<b
      GROUP BY u.user_id
    UNION ALL
    SELECT max(e.occurred_at),u.user_id::text,u.full_name_ar,u.username,e.feature,e.action,count(*),NULL,NULL
      FROM hbh.usage_events e JOIN hbh.users u USING(user_id)
      WHERE e.center_id=c AND e.occurred_at>=a AND e.occurred_at<b AND (p_feature='' OR e.feature=p_feature)
      AND ((p_kind IN ('staff_pages','staff_active') AND e.app='ops' AND e.kind='page') OR (p_kind='portal_features' AND e.app='portal'))
      GROUP BY u.user_id,e.feature,e.action
  ), page AS (SELECT * FROM details ORDER BY at DESC,id,feature,action LIMIT 50 OFFSET p_offset)
  SELECT jsonb_build_object('total',(SELECT count(*) FROM details),'rows',coalesce((SELECT jsonb_agg(to_jsonb(page)) FROM page),'[]'::jsonb)) INTO result;
  RETURN result;
END $$;
REVOKE ALL ON FUNCTION hbh.record_usage(text,text,text,text),hbh.ops_analytics(date,date,text,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.record_usage(text,text,text,text),hbh.ops_analytics(date,date,text,text,integer) TO hbh_app;
INSERT INTO hbh.convention_exemptions(table_name,rule_code,reason) VALUES
 ('usage_events','AUDIT_COLUMNS','Append-only product telemetry; occurred_at and user_id provide attribution.'),
 ('usage_events','SOFT_DELETE','Append-only operational events, not clinical records.');
INSERT INTO hbh.schema_migrations(version) VALUES('0145');
COMMIT;
