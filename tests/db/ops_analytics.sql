-- Run after 0145, inside a transaction; fixtures never survive this test.
BEGIN;
DO $test$
DECLARE admin_user text; admin_id integer; c integer; other_c integer; guardian_id integer;
  g text := 'analytics_probe_guardian'; j jsonb; dt jsonb; boundary timestamptz; n integer;
BEGIN
  SELECT u.username,u.user_id,u.center_id INTO admin_user,admin_id,c
  FROM hbh.users u JOIN hbh.user_roles ur USING(user_id)
  JOIN hbh.role_permissions rp USING(role_id) JOIN hbh.permissions p USING(permission_id)
  WHERE u.active_flg AND ur.active_flg AND rp.active_flg AND p.code='OPS.VIEW' LIMIT 1;
  IF admin_user IS NULL THEN RAISE EXCEPTION 'OPS.VIEW fixture required'; END IF;
  INSERT INTO hbh.users(center_id,username,full_name_ar,user_type,created_by)
    VALUES(c,g,'Analytics test guardian','GUARDIAN','analytics-test') RETURNING user_id INTO guardian_id;
  INSERT INTO hbh.centers(code,name_ar,created_by) VALUES('ANALYTICS_PROBE','Analytics test centre','analytics-test') RETURNING center_id INTO other_c;
  SELECT '2098-02-10'::date::timestamp AT TIME ZONE time_zone INTO boundary FROM hbh.centers WHERE center_id=c;
  INSERT INTO hbh.usage_events(center_id,user_id,app,feature,kind,action,occurred_at) VALUES
    (c,guardian_id,'portal','portal.nav.home','page','view',boundary),
    (c,guardian_id,'portal','portal.nav.home','page','view',boundary+interval '1 hour'),
    (c,guardian_id,'portal','portal.nav.home','action','POST',boundary+interval '2 hours'),
    (c,admin_id,'ops','ops.nav.dashboard','page','view',boundary),
    (c,admin_id,'ops','ops.nav.dashboard','page','view',boundary+interval '3 hours'),
    (other_c,admin_id,'ops','ops.secret','page','view',boundary),
    (c,guardian_id,'portal','portal.outside','page','view',boundary-interval '1 second'),
    (c,guardian_id,'portal','portal.outside','page','view',boundary+interval '1 day');
  INSERT INTO hbh.request_log(center_id,user_id,method,route,status_code,duration_ms,error_code,occurred_at) VALUES
    (c,admin_id,'GET','/test/analytics',200,100,NULL,boundary),
    (c,admin_id,'GET','/test/analytics',500,300,'TEST',boundary+interval '1 hour'),
    (c,admin_id,'GET','/api/v1/ops/analytics',200,1000,NULL,boundary),
    (other_c,admin_id,'GET','/test/secret',200,1000,NULL,boundary);
  PERFORM set_config('hbh.user_id',admin_user,true);
  EXECUTE 'SET LOCAL ROLE hbh_app';
  j := hbh.ops_analytics('2098-02-10','2098-02-10');
  IF (j->>'requests')::int<>2 OR (j->>'successes')::int<>1 OR (j->>'errors')::int<>1 THEN RAISE EXCEPTION 'request counts / centre isolation failed: %',j; END IF;
  IF (j->>'portal_users')::int<>1 OR jsonb_array_length(j->'portal_features')<>1 OR (j#>>'{portal_features,0,visits}')::int<>2 OR (j#>>'{portal_features,0,actions}')::int<>1 THEN RAISE EXCEPTION 'distinct guardians / date boundary failed'; END IF;
  IF (j->>'staff_pages')::int<>1 OR (j->>'staff_active')::int<>1 OR (j#>>'{pages,0,visits}')::int<>2 THEN RAISE EXCEPTION 'page / distinct user count failed'; END IF;
  dt := hbh.ops_analytics('2098-02-10','2098-02-10','portal_features','portal.nav.home',0);
  IF (dt->>'total')::int<>2 OR jsonb_array_length(dt->'rows')<>2 THEN RAISE EXCEPTION 'feature drilldown failed'; END IF;
  dt := hbh.ops_analytics('2098-02-10','2098-02-10','errors','',0);
  IF (dt->>'total')::int<>1 OR (dt#>>'{rows,0,status}')::int<>500 THEN RAISE EXCEPTION 'error drilldown failed'; END IF;
  dt := hbh.ops_analytics('2098-02-10','2098-02-10','performance','GET /test/analytics',50);
  IF (dt->>'total')::int<>2 OR jsonb_array_length(dt->'rows')<>0 THEN RAISE EXCEPTION 'pagination totals failed'; END IF;
  -- Exercise every union branch, including empty details.
  FOREACH g IN ARRAY ARRAY['registrations','applications','first_logins','staff_logins','staff_active','staff_pages','successes'] LOOP
    dt := hbh.ops_analytics('2098-02-10','2098-02-10',g,'',0);
    IF jsonb_typeof(dt->'rows')<>'array' THEN RAISE EXCEPTION 'invalid detail shape: %',g; END IF;
  END LOOP;
  BEGIN
    PERFORM hbh.ops_analytics('2098-02-11','2098-02-10');
    RAISE EXCEPTION 'reversed dates accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM set_config('hbh.user_id','analytics_probe_guardian',true);
  BEGIN
    PERFORM hbh.ops_analytics('2098-02-10','2098-02-10');
    RAISE EXCEPTION 'guardian can read analytics';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  SELECT count(*) INTO n FROM hbh.usage_events;
  IF n<>0 THEN RAISE EXCEPTION 'guardian can read raw telemetry'; END IF;
  PERFORM hbh.record_usage('portal','portal.nav.home','page','view');
  BEGIN
    PERFORM hbh.record_usage('ops','ops.nav.dashboard','page','view');
    RAISE EXCEPTION 'guardian forged staff event';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('hbh.user_id','',true);
  BEGIN
    PERFORM hbh.ops_analytics('2098-02-10','2098-02-10');
    RAISE EXCEPTION 'anonymous can read analytics';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  EXECUTE 'RESET ROLE';
END $test$;
ROLLBACK;
