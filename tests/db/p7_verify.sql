-- =====================================================================
-- Hand By Hand (new) - PHASE 7 acceptance suite
--
-- Must print:  PHASE 7 ACCEPTED
--
-- This is a SECURITY GATE, and the most sensitive one in the system: a
-- parent watching their child in a therapy session. The suite has to
-- make good on five claims, and each is tested as a real refusal:
--
--   * live only, and no recording anywhere in the model;
--   * the database holds no camera secret;
--   * the browser gets an opaque token, never an address;
--   * fifteen minutes, capped in code and not only in a parameter;
--   * a temporary gateway refuses to serve, and a fresh install IS
--     temporary - so the system fails closed by default.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.run (started timestamptz NOT NULL DEFAULT now());
INSERT INTO hbh_test.run DEFAULT VALUES;

CREATE TABLE hbh_test.results (
  seq integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp text NOT NULL, name text NOT NULL, ok boolean NOT NULL, detail text);
CREATE TABLE hbh_test.fx  (k text PRIMARY KEY, v integer);
CREATE TABLE hbh_test.tok (k text PRIMARY KEY, v text);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL' ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_raises(p_grp text, p_name text, p_sql text, p_sqlstate text)
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, 'expected ' || p_sqlstate || ', statement succeeded');
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, SQLSTATE = p_sqlstate,
            'expected ' || p_sqlstate || ', got ' || SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

CREATE PROCEDURE hbh_test.chk_empty(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_bad text;
BEGIN
  BEGIN
    EXECUTE 'SELECT string_agg(x::text, '', '' ORDER BY x::text) FROM (' || p_sql || ') s(x)'
      INTO v_bad;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, v_bad IS NULL, coalesce('offenders: ' || v_bad, 'ok'));
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

GRANT USAGE ON SCHEMA hbh_test TO hbh_app;
GRANT INSERT, SELECT ON hbh_test.results TO hbh_app;
GRANT SELECT ON hbh_test.fx, hbh_test.tok TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh_test TO hbh_app;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA hbh_test TO hbh_app;

-- =====================================================================
-- FIXTURE - a live session, two families, one camera
-- =====================================================================
INSERT INTO hbh_test.fx (k, v) SELECT 'center', center_id FROM hbh.centers  WHERE code = 'HBH';
INSERT INTO hbh_test.fx (k, v) SELECT 'branch', branch_id FROM hbh.branches WHERE code = 'MAIN';

INSERT INTO hbh.services (center_id, branch_id, code, name_ar, kind_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P7-SPEECH', 'تخاطب — اختبار ٧', 'SPEECH');
INSERT INTO hbh_test.fx (k, v) SELECT 'svc', service_id FROM hbh.services WHERE code='P7-SPEECH';

INSERT INTO hbh.rooms (center_id, branch_id, code, name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P7-R1', 'غرفة اختبار ٧');
INSERT INTO hbh_test.fx (k, v) SELECT 'room', room_id FROM hbh.rooms WHERE code='P7-R1';

INSERT INTO hbh.cameras (center_id, branch_id, room_id, code, name_ar, gateway_path, credential_ref, status)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='room'), 'P7-CAM1', 'كاميرا غرفة ٧',
        'rooms/p7-r1', 'vault/hbh/cam-p7-r1', 'ONLINE');
INSERT INTO hbh_test.fx (k, v) SELECT 'cam', camera_id FROM hbh.cameras WHERE code='P7-CAM1';

INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, mobile)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
       u.username, u.name, u.utype, u.mobile
FROM (VALUES
       ('p7.therapist', 'أخصائي اختبار ٧',      'THERAPIST', '+201700000001'),
       ('p7.allowed',   'ولي أمر مسموح له',      'GUARDIAN',  '+201700000002'),
       ('p7.blocked',   'ولي أمر غير مسموح له',  'GUARDIAN',  '+201700000003'),
       ('p7.other',     'ولي أمر طفل آخر',       'GUARDIAN',  '+201700000004')
     ) AS u(username, name, utype, mobile);

INSERT INTO hbh_test.fx (k, v) SELECT 'user_th',  user_id FROM hbh.users WHERE username='p7.therapist';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_ok',  user_id FROM hbh.users WHERE username='p7.allowed';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_no',  user_id FROM hbh.users WHERE username='p7.blocked';
INSERT INTO hbh_test.fx (k, v) SELECT 'user_oth', user_id FROM hbh.users WHERE username='p7.other';

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT f.v, r.role_id
FROM   hbh_test.fx f
JOIN   hbh.roles r ON r.center_id = (SELECT v FROM hbh_test.fx WHERE k='center')
WHERE  (f.k = 'user_th' AND r.code = 'THERAPIST')
   OR  (f.k IN ('user_ok','user_no','user_oth') AND r.code = 'GUARDIAN');

INSERT INTO hbh.therapists (center_id, branch_id, user_id, full_name_ar)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_th'), 'أخصائي اختبار ٧');
INSERT INTO hbh_test.fx (k, v) SELECT 'th', therapist_id FROM hbh.therapists WHERE full_name_ar='أخصائي اختبار ٧';

INSERT INTO hbh.therapist_services (therapist_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='th'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh.therapist_working_hours (center_id, therapist_id, weekday, start_time, end_time)
SELECT (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
       d, TIME '09:00', TIME '17:00'
FROM unnest(ARRAY[7,1,2,3,4]::smallint[]) AS d;

INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P7-A', 'طفل اختبار ٧ أ', DATE '2020-06-06', 'M'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        'P7-B', 'طفل اختبار ٧ ب', DATE '2021-02-02', 'F');
INSERT INTO hbh_test.fx (k, v) SELECT 'child_a', child_id FROM hbh.children WHERE child_no='P7-A';
INSERT INTO hbh_test.fx (k, v) SELECT 'child_b', child_id FROM hbh.children WHERE child_no='P7-B';

INSERT INTO hbh.guardians (center_id, branch_id, user_id, full_name_ar, mobile)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_ok'),  'ولي أمر مسموح له',     '+201700000002'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_no'),  'ولي أمر غير مسموح له', '+201700000003'),
       ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
        (SELECT v FROM hbh_test.fx WHERE k='user_oth'), 'ولي أمر طفل آخر',      '+201700000004');
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_ok',  guardian_id FROM hbh.guardians WHERE mobile='+201700000002';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_no',  guardian_id FROM hbh.guardians WHERE mobile='+201700000003';
INSERT INTO hbh_test.fx (k, v) SELECT 'gd_oth', guardian_id FROM hbh.guardians WHERE mobile='+201700000004';

-- Both are guardians of the SAME child. One will have the live flag and
-- one will not - the only difference between them, and the whole point.
--
-- Every link starts with the flag at its default of false. From
-- migration 0015 the flag may ONLY be set through a recorded consent,
-- so the two who may watch are granted one below, as the administrator
-- would when entering a signed form.
INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='gd_ok'),  (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'FATHER'),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_no'),  (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'MOTHER'),
       ((SELECT v FROM hbh_test.fx WHERE k='gd_oth'), (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'FATHER');

SET hbh.user_id = 'admin';
SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_ok'),  'LIVE_VIEW',
                         (SELECT v FROM hbh_test.fx WHERE k='child_a'), 'v1', 'نموذج موقّع');
SELECT hbh.grant_consent((SELECT v FROM hbh_test.fx WHERE k='gd_oth'), 'LIVE_VIEW',
                         (SELECT v FROM hbh_test.fx WHERE k='child_b'), 'v1', 'نموذج موقّع');
RESET hbh.user_id;

INSERT INTO hbh.caseload (center_id, therapist_id, child_id, service_id)
VALUES ((SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='th'),
        (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='svc'));

INSERT INTO hbh_test.fx (k, v)
SELECT 'appt', hbh.book_appointment(
  (SELECT v FROM hbh_test.fx WHERE k='center'), (SELECT v FROM hbh_test.fx WHERE k='branch'),
  (SELECT v FROM hbh_test.fx WHERE k='child_a'), (SELECT v FROM hbh_test.fx WHERE k='th'),
  (SELECT v FROM hbh_test.fx WHERE k='room'),    (SELECT v FROM hbh_test.fx WHERE k='svc'),
  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours')
    AT TIME ZONE 'Africa/Cairo',
  (date_trunc('week', now() AT TIME ZONE 'Africa/Cairo') + interval '7 days' + interval '10 hours 45 minutes')
    AT TIME ZONE 'Africa/Cairo');

UPDATE hbh.appointments SET status = 'CONFIRMED'  WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');
UPDATE hbh.appointments SET status = 'CHECKED_IN' WHERE appointment_id = (SELECT v FROM hbh_test.fx WHERE k='appt');

-- As the therapist who owns it. Migration 0087 gave hbh.start_session
-- the authorization it shipped without - SESSION.START, and whose
-- appointment this is - so a call with no identity now fails closed with
-- HB028 and this fixture would build no session at all.
SET hbh.user_id = 'p7.therapist';

INSERT INTO hbh_test.fx (k, v)
SELECT 'sess', hbh.start_session((SELECT v FROM hbh_test.fx WHERE k='appt'));

RESET hbh.user_id;

-- ---------------------------------------------------------------------
CALL hbh_test.chk('fixture', 'migration 0009 recorded',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0009') $q$);

CALL hbh_test.chk('fixture', 'the room has one online camera',
  $q$ SELECT status = 'ONLINE' FROM hbh.cameras
      WHERE camera_id = (SELECT v FROM hbh_test.fx WHERE k='cam') $q$);

CALL hbh_test.chk('fixture', 'the session is running',
  $q$ SELECT status = 'IN_PROGRESS' FROM hbh.therapy_sessions
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

-- The record is the only route. Turning the flag on by hand is refused
-- even for a guardian who IS linked to the child - the link is not the
-- permission, the recorded consent is.
CALL hbh_test.chk_raises('fixture', 'the flag cannot be raised without a recorded consent - HB081',
  $q$ UPDATE hbh.guardian_children SET can_view_live_flg = true
      WHERE guardian_id = (SELECT v FROM hbh_test.fx WHERE k='gd_no')
        AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$, 'HB081');

CALL hbh_test.chk('fixture', 'two guardians share the child, one flagged and one not',
  $q$ SELECT count(*) FILTER (WHERE can_view_live_flg) = 1
         AND count(*) FILTER (WHERE NOT can_view_live_flg) = 1
      FROM hbh.guardian_children WHERE child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a') $q$);

CALL hbh_test.chk('fixture', 'the gateway starts unconfigured and temporary',
  $q$ SELECT hbh.param(NULL, 'MEDIA_GATEWAY_BASE_URL', 'x') = ''
         AND hbh.param(NULL, 'MEDIA_GATEWAY_IS_TEMPORARY', 'x') = 'true' $q$);

-- =====================================================================
-- 1. NO RECORDING. ANYWHERE.
--
-- The three structural checks that used to be here now live in
-- tests/db/p00_verify.sql, in the 'shape' group. They are schema-wide -
-- they read information_schema and know nothing about streaming - and a
-- schema-wide rule kept in a phase suite is one the schema can outgrow
-- unwatched. Migration 0055 added six columns naming a video, and the
-- regression surfaced here, under phase seven, which had not changed.
--
-- They also now consult hbh.convention_exemptions, which is where the
-- one registered exception lives with its written reason (migration
-- 0057, a staff introduction film on the public marketing page), along
-- with the check that bounds it: an exempted table may hold no child,
-- session, appointment or camera reference.
--
-- WHAT STAYS HERE IS WHAT IS ABOUT STREAMING - the checks below, which
-- test that a live token cannot outlive its session and that this phase
-- introduced no way to keep what it shows.
-- =====================================================================

-- =====================================================================
-- 2. THE DATABASE HOLDS NO CAMERA SECRET
-- =====================================================================
CALL hbh_test.chk_empty('secret', 'the camera table has no address or credential column',
  $q$ SELECT column_name FROM information_schema.columns
      WHERE table_schema = 'hbh' AND table_name = 'cameras'
        AND column_name ~* '(rtsp|url|ip_|_ip$|host|password|passwd|secret|username|user_name)'
        AND column_name <> 'credential_ref' $q$);

CALL hbh_test.chk('secret', 'and credential_ref holds a reference, not a credential',
  $q$ SELECT credential_ref NOT ILIKE '%://%' AND credential_ref NOT ILIKE '%:%@%'
      FROM hbh.cameras WHERE camera_id = (SELECT v FROM hbh_test.fx WHERE k='cam') $q$);

CALL hbh_test.chk_raises('secret', 'an rtsp address cannot be pasted into gateway_path',
  $q$ UPDATE hbh.cameras SET gateway_path = 'rtsp://10.0.0.5:554/stream'
      WHERE camera_id = (SELECT v FROM hbh_test.fx WHERE k='cam') $q$, '23514');

-- =====================================================================
-- 3. A TEMPORARY GATEWAY REFUSES TO SERVE
--
-- The install default. Everything below this point had to be unlocked
-- deliberately, which is what fail-closed means.
-- =====================================================================
SET hbh.user_id = 'p7.allowed';

CALL hbh_test.chk('gateway', 'the permitted guardian passes the gate',
  $q$ SELECT hbh.can_view_live((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk_raises('gateway', 'and is STILL refused a token - the gateway is temporary',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB063');

RESET hbh.user_id;
UPDATE hbh.sys_params SET param_value = 'https://quiet-hills-1234.trycloudflare.com'
 WHERE param_code = 'MEDIA_GATEWAY_BASE_URL' AND center_id IS NULL;
UPDATE hbh.sys_params SET param_value = 'false'
 WHERE param_code = 'MEDIA_GATEWAY_IS_TEMPORARY' AND center_id IS NULL;

SET hbh.user_id = 'p7.allowed';
CALL hbh_test.chk_raises('gateway', 'a quick tunnel is refused even with the flag cleared',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB063');

RESET hbh.user_id;
UPDATE hbh.sys_params SET param_value = 'https://live.handbyhand.example'
 WHERE param_code = 'MEDIA_GATEWAY_BASE_URL' AND center_id IS NULL;

-- =====================================================================
-- 4. WHO MAY WATCH
-- =====================================================================
SET hbh.user_id = 'p7.blocked';
CALL hbh_test.chk('gate', 'the guardian WITHOUT the live flag fails the gate',
  $q$ SELECT NOT hbh.can_view_live((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk_raises('gate', 'and is refused a token with HB060',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB060');

CALL hbh_test.chk('gate', 'the refusal was written to the audit log and survived',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.audit_log
        WHERE action = 'DENY' AND detail LIKE 'live view refused%'
          AND changed_at >= (SELECT started FROM hbh_test.run)) $q$);

SET hbh.user_id = 'p7.other';
CALL hbh_test.chk('gate', 'a guardian of ANOTHER child fails the gate',
  $q$ SELECT NOT hbh.can_view_live((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk_raises('gate', 'and is refused by session id directly',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB060');

SET hbh.user_id = 'p7.therapist';
CALL hbh_test.chk('gate', 'the therapist with LIVE.VIEW passes',
  $q$ SELECT hbh.can_view_live((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

RESET hbh.user_id;
CALL hbh_test.chk('gate', 'and with no identity, nobody passes',
  $q$ SELECT NOT hbh.can_view_live((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$);

CALL hbh_test.chk_raises('gate', 'an anonymous request is refused',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB060');

-- =====================================================================
-- 5. THE TOKEN
-- =====================================================================
SET hbh.user_id = 'p7.allowed';

CALL hbh_test.chk('token', 'the permitted guardian is issued a token',
  $q$ WITH t AS (SELECT * FROM hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess'))),
           i AS (INSERT INTO hbh_test.tok (k, v) SELECT 'a', t.token FROM t RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('token', 'it is 64 hex characters of randomness',
  $q$ SELECT v ~ '^[0-9a-f]{64}$' FROM hbh_test.tok WHERE k = 'a' $q$);

CALL hbh_test.chk('token', 'it names neither the gateway nor the camera nor the room',
  $q$ SELECT v NOT ILIKE '%handbyhand%' AND v NOT ILIKE '%p7%' AND v NOT ILIKE '%room%'
      FROM hbh_test.tok WHERE k = 'a' $q$);

CALL hbh_test.chk('token', 'it is stored hashed, never in plaintext',
  $q$ SELECT NOT EXISTS (SELECT 1 FROM hbh.stream_tokens s, hbh_test.tok t
        WHERE t.k = 'a' AND encode(s.token_hash, 'hex') = t.v) $q$);

-- The cap is in the code, not only in the parameter.
CALL hbh_test.chk('token', 'its life is at most fifteen minutes',
  $q$ SELECT expires_at <= issued_at + interval '15 minutes' FROM hbh.stream_tokens
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

RESET hbh.user_id;
UPDATE hbh.sys_params SET param_value = '600'
 WHERE param_code = 'STREAM_TOKEN_TTL_MIN' AND center_id IS NULL;

SET hbh.user_id = 'p7.allowed';
CALL hbh_test.chk('token', 'a parameter asking for ten hours is issued anyway',
  $q$ WITH t AS (SELECT * FROM hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess'))),
           i AS (INSERT INTO hbh_test.tok (k, v) SELECT 'long', t.token FROM t RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('token', 'but the cap held it to fifteen minutes',
  $q$ SELECT max(expires_at - issued_at) <= interval '15 minutes' FROM hbh.stream_tokens
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

RESET hbh.user_id;
UPDATE hbh.sys_params SET param_value = '15'
 WHERE param_code = 'STREAM_TOKEN_TTL_MIN' AND center_id IS NULL;

-- =====================================================================
-- 6. REDEEMING IT
-- =====================================================================
CALL hbh_test.chk('redeem', 'a live token resolves to the camera path',
  $q$ SELECT ok AND gateway_path = 'rooms/p7-r1'
      FROM hbh.resolve_stream_token((SELECT v FROM hbh_test.tok WHERE k='a')) $q$);

CALL hbh_test.chk('redeem', 'an unknown token resolves to NO_TOKEN',
  $q$ SELECT reason = 'NO_TOKEN' FROM hbh.resolve_stream_token('not-a-real-token') $q$);

CALL hbh_test.chk('redeem', 'revoking returns true the first time',
  $q$ SELECT hbh.revoke_stream_token((SELECT v FROM hbh_test.tok WHERE k='long')) $q$);

CALL hbh_test.chk('redeem', 'and a revoked token stops resolving at once',
  $q$ SELECT reason = 'REVOKED'
      FROM hbh.resolve_stream_token((SELECT v FROM hbh_test.tok WHERE k='long')) $q$);

-- An expired token, forced rather than waited for. The window is
-- shrunk rather than dragged into the past, because ck_tok_window
-- insists expires_at is after issued_at.
CALL hbh_test.chk('redeem', 'a token is pushed past its expiry',
  $q$ WITH u AS (UPDATE hbh.stream_tokens SET expires_at = issued_at + interval '1 millisecond'
                  WHERE token_hash = public.digest((SELECT v FROM hbh_test.tok WHERE k='a'), 'sha256')
                  RETURNING 1)
      SELECT count(*) = 1 FROM u $q$);

CALL hbh_test.chk('redeem', 'and reports EXPIRED, not a path',
  $q$ SELECT reason = 'EXPIRED' AND gateway_path IS NULL
      FROM hbh.resolve_stream_token((SELECT v FROM hbh_test.tok WHERE k='a')) $q$);

-- =====================================================================
-- 7. THE SESSION ENDING ENDS THE STREAM
-- =====================================================================
SET hbh.user_id = 'p7.allowed';
CALL hbh_test.chk('close', 'a fresh token is issued while the session still runs',
  $q$ WITH t AS (SELECT * FROM hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess'))),
           i AS (INSERT INTO hbh_test.tok (k, v) SELECT 'live', t.token FROM t RETURNING 1)
      SELECT (SELECT count(*) FROM i) = 1 $q$);

CALL hbh_test.chk('close', 'and it resolves',
  $q$ SELECT ok FROM hbh.resolve_stream_token((SELECT v FROM hbh_test.tok WHERE k='live')) $q$);

SET hbh.user_id = 'p7.therapist';
CALL hbh_test.chk('close', 'the therapist closes the session',
  $q$ WITH c AS (SELECT hbh.close_session((SELECT v FROM hbh_test.fx WHERE k='sess'), 'COMPLETED'))
      SELECT count(*) = 1 FROM c $q$);

CALL hbh_test.chk('close', 'and the live token stops resolving',
  $q$ SELECT reason = 'SESSION_ENDED'
      FROM hbh.resolve_stream_token((SELECT v FROM hbh_test.tok WHERE k='live')) $q$);

CALL hbh_test.chk('close', 'close_session_streams revokes what is left and stamps the views',
  $q$ SELECT hbh.close_session_streams((SELECT v FROM hbh_test.fx WHERE k='sess')) >= 1 $q$);

CALL hbh_test.chk('close', 'no viewing record is left open',
  $q$ SELECT count(*) = 0 FROM hbh.stream_views
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') AND ended_at IS NULL $q$);

CALL hbh_test.chk_raises('close', 'and a token cannot be issued for a finished session',
  $q$ SELECT hbh.issue_stream_token((SELECT v FROM hbh_test.fx WHERE k='sess')) $q$, 'HB060');

-- =====================================================================
-- 8. EVERY VIEW IS LOGGED, AND THE LOG CANNOT BE EDITED
-- =====================================================================
CALL hbh_test.chk('log', 'three viewings were recorded',
  $q$ SELECT count(*) = 3 FROM hbh.stream_views
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

CALL hbh_test.chk('log', 'each names the watcher and the child',
  $q$ SELECT bool_and(user_id = (SELECT v FROM hbh_test.fx WHERE k='user_ok')
                      AND child_id = (SELECT v FROM hbh_test.fx WHERE k='child_a'))
      FROM hbh.stream_views WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$);

CALL hbh_test.chk_raises('log', 'a viewing record cannot be reassigned',
  $q$ UPDATE hbh.stream_views SET user_id = (SELECT v FROM hbh_test.fx WHERE k='user_th')
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$, 'HB001');

CALL hbh_test.chk_raises('log', 'and cannot be deleted',
  $q$ DELETE FROM hbh.stream_views
      WHERE session_id = (SELECT v FROM hbh_test.fx WHERE k='sess') $q$, 'HB001');

-- =====================================================================
-- 9. WHAT EACH SIDE CAN SEE
-- =====================================================================
SET ROLE hbh_app;

SET hbh.user_id = 'p7.allowed';
CALL hbh_test.chk('visible', 'the family can see who watched their child',
  $q$ SELECT count(*) = 3 FROM hbh.stream_views $q$);

CALL hbh_test.chk('visible', 'and cannot see the camera row at all',
  $q$ SELECT count(*) = 0 FROM hbh.cameras $q$);

CALL hbh_test.chk_raises('visible', 'nor read a stream token',
  $q$ SELECT count(*) FROM hbh.stream_tokens $q$, '42501');

SET hbh.user_id = 'p7.other';
CALL hbh_test.chk('visible', 'the other family sees no viewing of this child',
  $q$ SELECT count(*) = 0 FROM hbh.stream_views $q$);

SET hbh.user_id = 'p7.therapist';
CALL hbh_test.chk('visible', 'the therapist sees the camera',
  $q$ SELECT count(*) >= 1 FROM hbh.cameras $q$);

RESET hbh.user_id;
CALL hbh_test.chk('visible', 'no identity sees no cameras and no viewings',
  $q$ SELECT (SELECT count(*) FROM hbh.cameras) = 0
         AND (SELECT count(*) FROM hbh.stream_views) = 0 $q$);

RESET ROLE;

-- =====================================================================
-- CLEANUP
-- =====================================================================
RESET hbh.user_id;
UPDATE hbh.sys_params SET param_value = ''
 WHERE param_code = 'MEDIA_GATEWAY_BASE_URL' AND center_id IS NULL;
UPDATE hbh.sys_params SET param_value = 'true'
 WHERE param_code = 'MEDIA_GATEWAY_IS_TEMPORARY' AND center_id IS NULL;

CALL hbh_test.chk('cleanup', 'the gateway is left unconfigured and temporary again',
  $q$ SELECT hbh.param(NULL, 'MEDIA_GATEWAY_BASE_URL', 'x') = ''
         AND hbh.param(NULL, 'MEDIA_GATEWAY_IS_TEMPORARY', 'x') = 'true' $q$);

ALTER TABLE hbh.stream_views DISABLE TRIGGER trg_view_no_delete;
CALL hbh_test.chk('cleanup', 'tokens and viewing records removed',
  $q$ WITH v AS (DELETE FROM hbh.stream_views WHERE session_id =
                   (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           t AS (DELETE FROM hbh.stream_tokens WHERE session_id =
                   (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1)
      SELECT (SELECT count(*) FROM v) = 3 AND (SELECT count(*) FROM t) = 3 $q$);
ALTER TABLE hbh.stream_views ENABLE TRIGGER trg_view_no_delete;

ALTER TABLE hbh.session_status_history     DISABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history DISABLE TRIGGER trg_ash_append_only;
CALL hbh_test.chk('cleanup', 'session, appointment and their history removed',
  $q$ WITH sh AS (DELETE FROM hbh.session_status_history WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           s AS (DELETE FROM hbh.therapy_sessions WHERE session_id =
                    (SELECT v FROM hbh_test.fx WHERE k='sess') RETURNING 1),
           ah AS (DELETE FROM hbh.appointment_status_history WHERE appointment_id =
                    (SELECT v FROM hbh_test.fx WHERE k='appt') RETURNING 1),
           a AS (DELETE FROM hbh.appointments WHERE appointment_id =
                    (SELECT v FROM hbh_test.fx WHERE k='appt') RETURNING 1)
      SELECT (SELECT count(*) FROM s) = 1 AND (SELECT count(*) FROM a) = 1 $q$);
ALTER TABLE hbh.session_status_history     ENABLE TRIGGER trg_ssh_append_only;
ALTER TABLE hbh.appointment_status_history ENABLE TRIGGER trg_ash_append_only;

ALTER TABLE hbh.consent_events DISABLE TRIGGER trg_cev_append_only;
CALL hbh_test.chk('cleanup', 'consents, their events and notifications removed',
  $q$ WITH n AS (DELETE FROM hbh.notifications WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p7.%') RETURNING 1),
           e AS (DELETE FROM hbh.consent_events WHERE guardian_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('gd_ok','gd_no','gd_oth')) RETURNING 1),
           c AS (DELETE FROM hbh.consents WHERE guardian_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('gd_ok','gd_no','gd_oth')) RETURNING 1)
      SELECT (SELECT count(*) FROM c) = 2 AND (SELECT count(*) FROM e) = 2 $q$);
ALTER TABLE hbh.consent_events ENABLE TRIGGER trg_cev_append_only;

CALL hbh_test.chk('cleanup', 'the rest removed',
  $q$ WITH cam AS (DELETE FROM hbh.cameras WHERE code LIKE 'P7-%' RETURNING 1),
           c AS (DELETE FROM hbh.caseload WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           g AS (DELETE FROM hbh.guardian_children WHERE child_id IN
                   (SELECT v FROM hbh_test.fx WHERE k IN ('child_a','child_b')) RETURNING 1),
           k AS (DELETE FROM hbh.children WHERE child_no LIKE 'P7-%' RETURNING 1),
           q AS (DELETE FROM hbh.guardians WHERE mobile LIKE '+2017000000%' AND user_id IN (SELECT user_id FROM hbh.users WHERE username LIKE 'p7.%') RETURNING 1),
           w AS (DELETE FROM hbh.therapist_working_hours WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           ts AS (DELETE FROM hbh.therapist_services WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           t AS (DELETE FROM hbh.therapists WHERE therapist_id =
                   (SELECT v FROM hbh_test.fx WHERE k='th') RETURNING 1),
           r AS (DELETE FROM hbh.rooms    WHERE code LIKE 'P7-%' RETURNING 1),
           sv AS (DELETE FROM hbh.services WHERE code LIKE 'P7-%' RETURNING 1),
           ur AS (DELETE FROM hbh.user_roles WHERE user_id IN
                   (SELECT user_id FROM hbh.users WHERE username LIKE 'p7.%') RETURNING 1),
           u AS (DELETE FROM hbh.users WHERE username LIKE 'p7.%' RETURNING 1)
      SELECT (SELECT count(*) FROM k) = 2 AND (SELECT count(*) FROM u) = 4
         AND (SELECT count(*) FROM cam) = 1 $q$);

CALL hbh_test.chk('cleanup', 'every append-only trigger is enabled again',
  $q$ SELECT count(*) = 3 FROM pg_trigger
      WHERE tgname IN ('trg_view_no_delete','trg_ssh_append_only','trg_ash_append_only')
        AND tgenabled = 'O' $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة", count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM hbh_test.results GROUP BY grp ORDER BY min(seq);

\echo ''
SELECT seq, grp, name, detail FROM hbh_test.results WHERE NOT ok ORDER BY seq;

DO $verdict$
DECLARE v_total integer; v_fail integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN RAISE NOTICE '  PHASE 7 ACCEPTED';
  ELSE RAISE NOTICE '  *** PHASE 7 NOT ACCEPTED'; END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'acceptance suite failed';
  END IF;
END
$exit$;
