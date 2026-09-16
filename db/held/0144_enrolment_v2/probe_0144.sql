-- Rolled-back proof of 0144. The migration is expected at /tmp/0144_up.sql.
-- Leaves nothing behind - including in the attempt log: audit_attempt
-- writes through dblink OUTSIDE the transaction, so for the length of this
-- transaction it is replaced by a stand-in that records into a temp table.
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
-- 0142 and 0143 are not applied yet; 0144 touches nothing of theirs.
INSERT INTO hbh.schema_migrations (version)
SELECT x.v FROM (VALUES ('0142'), ('0143')) x(v)
WHERE NOT EXISTS (SELECT 1 FROM hbh.schema_migrations s WHERE s.version = x.v);
\i /tmp/0144_up.sql
;
CREATE TABLE pg_temp.attempts (action text, actor text, detail text);
GRANT ALL ON pg_temp.attempts TO hbh_app;
CREATE OR REPLACE FUNCTION hbh.audit_attempt(p_action text, p_center_id integer, p_actor text, p_detail text, p_client_ip inet DEFAULT NULL::inet)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = hbh, pg_catalog AS
$$ BEGIN EXECUTE 'INSERT INTO pg_temp.attempts VALUES ($1, $2, $3)' USING p_action, p_actor, p_detail; END $$;

CREATE TABLE pg_temp.r (n serial, what text, got text, want text);
GRANT ALL ON pg_temp.r TO hbh_app; GRANT ALL ON SEQUENCE pg_temp.r_n_seq TO hbh_app;

-- A verified proof is STATE, built directly: the functions that make one
-- are 0131's and are proved there.
CREATE FUNCTION pg_temp.proof(p_mobile text, p_purpose text DEFAULT 'ENROLMENT',
                              p_verified boolean DEFAULT true, p_ttl interval DEFAULT '10 min')
RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO hbh.mobile_verifications (center_id, mobile_e164, purpose, code_hash, created_at, expires_at, verified_at)
  SELECT c.center_id, p_mobile, p_purpose, 'x', now() - interval '1 hour', now() + p_ttl,
         CASE WHEN p_verified THEN least(now(), now() + p_ttl) END
  FROM hbh.centers c WHERE c.code = 'HBH'
  RETURNING verification_id
$$;

-- one call, as the API makes it
CREATE FUNCTION pg_temp.sub(p_mobile text, p_child text, p_dob date, p_vid bigint,
                            p_g integer DEFAULT NULL, p_c integer DEFAULT NULL, p_new boolean DEFAULT false)
RETURNS TABLE (ok boolean, reason text, application_no text, result text, candidates jsonb)
LANGUAGE sql AS $$
  SELECT * FROM hbh.submit_enrolment(
    p_center_code => 'HBH', p_parent_name_ar => 'ولي أمر فحص', p_parent_mobile => p_mobile,
    p_child_name_ar => p_child, p_child_birth_date => p_dob, p_child_gender => 'M',
    p_verification_id => p_vid, p_guardian_id => p_g, p_child_id => p_c, p_child_is_new => p_new)
$$;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA pg_temp TO hbh_app;

CREATE TABLE pg_temp.fx (k text PRIMARY KEY, v bigint, s text);
GRANT ALL ON pg_temp.fx TO hbh_app;

-- The mobile family used here: +2010999901xx. None exists before.
DO $f$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.guardians WHERE mobile LIKE '+2010999901__') THEN
    RAISE EXCEPTION 'fixture: +2010999901xx is already in use on this database';
  END IF;
END $f$;

INSERT INTO pg_temp.fx (k, v) VALUES
  ('v_new1',   pg_temp.proof('+201099990144')),
  ('v_retry2', pg_temp.proof('+201099990144')),
  ('v_amb',    pg_temp.proof('+201099990144')),
  ('v_amb2',   pg_temp.proof('+201099990144')),
  ('v_other',  pg_temp.proof('+201099990199')),
  ('v_unver',  pg_temp.proof('+201099990144', 'ENROLMENT', false)),
  ('v_consult',pg_temp.proof('+201099990144', 'CONSULTATION')),
  ('v_expired',pg_temp.proof('+201099990144', 'ENROLMENT', true, '-1 min')),
  ('v_twin',   pg_temp.proof('+201099990145')),
  ('v_twin2',  pg_temp.proof('+201099990145')),
  ('v_rej',    pg_temp.proof('+201099990144')),
  ('v_staff',  pg_temp.proof('+201500000091'));

-- Two guardians sharing +201099990145, neither with an account (BL-51).
WITH a AS (INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
           SELECT center_id, 'توأم أ', '+201099990145' FROM hbh.centers WHERE code = 'HBH' RETURNING guardian_id)
INSERT INTO pg_temp.fx (k, v) SELECT 'g_twin_a', guardian_id FROM a;
WITH b AS (INSERT INTO hbh.guardians (center_id, full_name_ar, mobile)
           SELECT center_id, 'توأم ب', '+201099990145' FROM hbh.centers WHERE code = 'HBH' RETURNING guardian_id)
INSERT INTO pg_temp.fx (k, v) SELECT 'g_twin_b', guardian_id FROM b;
-- somebody else's child, for NO_SUCH_CHOICE
INSERT INTO pg_temp.fx (k, v)
SELECT 'foreign_child', min(child_id) FROM hbh.children WHERE center_id = (SELECT center_id FROM hbh.centers WHERE code = 'HBH') AND active_flg;

-- ---------------------------------------------------------------------
-- The scenarios. Each call is as hbh_app with no identity (the API's
-- public route); each assertion is read as the owner.
-- ---------------------------------------------------------------------

-- helper: counts of this fixture's rows
CREATE FUNCTION pg_temp.counts() RETURNS text LANGUAGE sql AS $$
  SELECT (SELECT count(*) FROM hbh.guardians WHERE mobile IN ('+201099990144','+201099990145','+201500000091') AND active_flg)
         || '/' ||
         (SELECT count(*) FROM hbh.children c JOIN hbh.guardian_children gc ON gc.child_id = c.child_id
          JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id
          WHERE g.mobile IN ('+201099990144','+201099990145','+201500000091'))
         || '/' ||
         (SELECT count(*) FROM hbh.enrolment_applications WHERE parent_mobile IN ('+201099990144','+201099990145','+201500000091'))
$$;

INSERT INTO pg_temp.fx (k, s) VALUES ('counts0', pg_temp.counts());

-- S1 · UC-01: a new mobile, verified -> one guardian, one child, one linked request
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's1', ok || ':' || reason || ':' || result || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01099990144', 'أحمد فحص', '2020-01-15', (SELECT v FROM pg_temp.fx WHERE k = 'v_new1'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want) SELECT 'S1 created', split_part(s, ':', 1) || ':' || split_part(s, ':', 2) || ':' || split_part(s, ':', 3), 'true:OK:CREATED' FROM pg_temp.fx WHERE k = 's1';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S1 rows (guardians/children/requests)', pg_temp.counts(), '1/1/1';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S1 request linked, canonical, proof recorded',
       (a.guardian_id IS NOT NULL AND a.child_id IS NOT NULL AND a.verification_id = (SELECT v FROM pg_temp.fx WHERE k = 'v_new1')
        AND a.parent_mobile = '+201099990144' AND a.converted_guardian_id IS NULL)::text, 'true'
FROM hbh.enrolment_applications a WHERE a.application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S1 guardian source + child origin -> this request',
       g.registration_source || ' ' || c.origin_source || ' ' || (c.origin_reference_id = a.application_id),
       'ENROLMENT_REQUEST ENROLMENT_REQUEST true'
FROM hbh.enrolment_applications a JOIN hbh.guardians g ON g.guardian_id = a.guardian_id JOIN hbh.children c ON c.child_id = a.child_id
WHERE a.application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S1 proof consumed', (consumed_at IS NOT NULL)::text, 'true' FROM hbh.mobile_verifications WHERE verification_id = (SELECT v FROM pg_temp.fx WHERE k = 'v_new1');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S1 no live-view flag, no account', (NOT gc.can_view_live_flg AND g.user_id IS NULL)::text, 'true'
FROM hbh.enrolment_applications a JOIN hbh.guardian_children gc ON gc.child_id = a.child_id AND gc.guardian_id = a.guardian_id
JOIN hbh.guardians g ON g.guardian_id = a.guardian_id
WHERE a.application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S1 origin_reference_id now frozen (HB241)', 'probe below', 'probe below';

-- S2 · retry with the SAME proof -> the same request, nothing new
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's2', ok || ':' || reason || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01099990144', 'أحمد فحص', '2020-01-15', (SELECT v FROM pg_temp.fx WHERE k = 'v_new1'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S2 retry, same proof', (SELECT s FROM pg_temp.fx WHERE k = 's2'),
       'true:ALREADY_OPEN:' || (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
INSERT INTO pg_temp.r (what, got, want) SELECT 'S2 no new rows', pg_temp.counts(), '1/1/1';

-- S3 · UC-18: a NEW proof, same child (normalised name: أ -> ا) -> ALREADY_OPEN
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's3', ok || ':' || reason || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('+20 10 9999 0144', 'احمد فحص', '2020-01-15', (SELECT v FROM pg_temp.fx WHERE k = 'v_retry2'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S3 new proof, same child, spelled differently', (SELECT s FROM pg_temp.fx WHERE k = 's3'),
       'true:ALREADY_OPEN:' || (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
INSERT INTO pg_temp.r (what, got, want) SELECT 'S3 no new rows', pg_temp.counts(), '1/1/1';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S3 that proof NOT consumed', (consumed_at IS NULL)::text, 'true' FROM hbh.mobile_verifications WHERE verification_id = (SELECT v FROM pg_temp.fx WHERE k = 'v_retry2');

-- S4 · every proof that does not hold -> ONE answer
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's4', string_agg(k || '=' || (SELECT reason FROM pg_temp.sub(m, 'طفل آخر', '2021-01-01', vid)), ' ' ORDER BY k)
FROM (VALUES ('a_other_mobile', '01099990144', (SELECT v FROM pg_temp.fx WHERE k = 'v_other')),
             ('b_unverified',   '01099990144', (SELECT v FROM pg_temp.fx WHERE k = 'v_unver')),
             ('c_consultation', '01099990144', (SELECT v FROM pg_temp.fx WHERE k = 'v_consult')),
             ('d_expired',      '01099990144', (SELECT v FROM pg_temp.fx WHERE k = 'v_expired')),
             ('e_ghost',        '01099990144', 999999999999::bigint),
             ('f_bad_mobile',   'abc',         (SELECT v FROM pg_temp.fx WHERE k = 'v_amb'))) t(k, m, vid);
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S4 one answer for every broken proof', (SELECT s FROM pg_temp.fx WHERE k = 's4'),
       'a_other_mobile=VERIFICATION_REQUIRED b_unverified=VERIFICATION_REQUIRED c_consultation=VERIFICATION_REQUIRED d_expired=VERIFICATION_REQUIRED e_ghost=VERIFICATION_REQUIRED f_bad_mobile=VERIFICATION_REQUIRED';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S4 no new rows', pg_temp.counts(), '1/1/1';

-- S5 · UC-08: same name, another birth date -> AMBIGUOUS, nothing written, proof alive
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's5', ok || ':' || reason || ':' || result || ':' || jsonb_array_length(candidates)
FROM pg_temp.sub('01099990144', 'أحمد فحص', '2019-06-01', (SELECT v FROM pg_temp.fx WHERE k = 'v_amb'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want) SELECT 'S5 ambiguous child', (SELECT s FROM pg_temp.fx WHERE k = 's5'), 'false:AMBIGUOUS:AMBIGUOUS_CHILD:1';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S5 nothing written', pg_temp.counts(), '1/1/1';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S5 proof still alive', (consumed_at IS NULL)::text, 'true' FROM hbh.mobile_verifications WHERE verification_id = (SELECT v FROM pg_temp.fx WHERE k = 'v_amb');

-- S5b · someone else's child as the choice -> NO_SUCH_CHOICE
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's5b', reason FROM pg_temp.sub('01099990144', 'أحمد فحص', '2019-06-01', (SELECT v FROM pg_temp.fx WHERE k = 'v_amb'),
                                      NULL, (SELECT v::int FROM pg_temp.fx WHERE k = 'foreign_child'));
-- S5c · UC-09: "a new child" -> one new child, the first untouched
INSERT INTO pg_temp.fx (k, s)
SELECT 's5c', ok || ':' || reason || ':' || result || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01099990144', 'أحمد فحص', '2019-06-01', (SELECT v FROM pg_temp.fx WHERE k = 'v_amb'), NULL, NULL, true);
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want) SELECT 'S5b a child who is not theirs', (SELECT s FROM pg_temp.fx WHERE k = 's5b'), 'NO_SUCH_CHOICE';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S5c resubmitted as a new child', split_part(s, ':', 1) || ':' || split_part(s, ':', 2) || ':' || split_part(s, ':', 3), 'true:OK:CREATED'
FROM pg_temp.fx WHERE k = 's5c';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S5c one guardian, two children, two requests', pg_temp.counts(), '1/2/2';

-- S6 · two guardians on one number, no account -> AMBIGUOUS_GUARDIAN, then a choice
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's6', ok || ':' || reason || ':' || result || ':' || jsonb_array_length(candidates)
FROM pg_temp.sub('01099990145', 'سارة فحص', '2021-03-03', (SELECT v FROM pg_temp.fx WHERE k = 'v_twin'));
INSERT INTO pg_temp.fx (k, s)
SELECT 's6b', reason FROM pg_temp.sub('01099990145', 'سارة فحص', '2021-03-03', (SELECT v FROM pg_temp.fx WHERE k = 'v_twin'),
                                      (SELECT (SELECT guardian_id FROM hbh.enrolment_applications WHERE application_no = split_part(s, ':', 4))
                                       FROM pg_temp.fx WHERE k = 's1'));
INSERT INTO pg_temp.fx (k, s)
SELECT 's6c', ok || ':' || reason || ':' || result || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01099990145', 'سارة فحص', '2021-03-03', (SELECT v FROM pg_temp.fx WHERE k = 'v_twin'),
                 (SELECT v::int FROM pg_temp.fx WHERE k = 'g_twin_b'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want) SELECT 'S6 ambiguous guardian', (SELECT s FROM pg_temp.fx WHERE k = 's6'), 'false:AMBIGUOUS:AMBIGUOUS_GUARDIAN:2';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S6b the other number''s guardian as the choice', (SELECT s FROM pg_temp.fx WHERE k = 's6b'), 'NO_SUCH_CHOICE';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S6c chosen guardian used, no third guardian, no merge',
       split_part(f.s, ':', 2) || ' guardian=' || (a.guardian_id = (SELECT v FROM pg_temp.fx WHERE k = 'g_twin_b'))
       || ' twins=' || (SELECT count(*) FROM hbh.guardians WHERE mobile = '+201099990145' AND active_flg),
       'OK guardian=true twins=2'
FROM pg_temp.fx f JOIN hbh.enrolment_applications a ON a.application_no = split_part(f.s, ':', 4) WHERE f.k = 's6c';

-- S7 · a REJECTED request for this child -> CONTACT_CENTER, no detail
UPDATE hbh.enrolment_applications
   SET status = 'REJECTED', decided_at = now(),
       decided_by = (SELECT user_id FROM hbh.users WHERE username = 'dev_admin')
WHERE application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's1');
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's7', ok || ':' || reason || ':' || coalesce(application_no, '-') || ':' || coalesce(result, '-')
FROM pg_temp.sub('01099990144', 'أحمد فحص', '2020-01-15', (SELECT v FROM pg_temp.fx WHERE k = 'v_rej'));
RESET ROLE;
INSERT INTO pg_temp.r (what, got, want) SELECT 'S7 after rejection', (SELECT s FROM pg_temp.fx WHERE k = 's7'), 'false:CONTACT_CENTER:-:-';

-- S8 · no proof: v1 while the parameter is false, refused when true
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's8', ok || ':' || reason || ':' || result || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01099990146', 'طفل قديم', '2020-02-02', NULL);
RESET ROLE;
UPDATE hbh.sys_params SET param_value = 'true' WHERE center_id IS NULL AND param_code = 'ENROLMENT_REQUIRE_VERIFICATION';
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's8b', ok || ':' || reason FROM pg_temp.sub('01099990147', 'طفل قديم', '2020-02-02', NULL);
RESET ROLE;
UPDATE hbh.sys_params SET param_value = 'false' WHERE center_id IS NULL AND param_code = 'ENROLMENT_REQUIRE_VERIFICATION';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S8 no proof, parameter false: v1', split_part(s, ':', 1) || ':' || split_part(s, ':', 2) || ':' || split_part(s, ':', 3), 'true:OK:CREATED'
FROM pg_temp.fx WHERE k = 's8';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S8 v1 row is unlinked and nothing was created',
       (a.guardian_id IS NULL AND a.child_id IS NULL AND a.verification_id IS NULL
        AND NOT EXISTS (SELECT 1 FROM hbh.guardians WHERE mobile = '+201099990146'))::text, 'true'
FROM pg_temp.fx f JOIN hbh.enrolment_applications a ON a.application_no = split_part(f.s, ':', 4) WHERE f.k = 's8';
INSERT INTO pg_temp.r (what, got, want) SELECT 'S8b no proof, parameter true', (SELECT s FROM pg_temp.fx WHERE k = 's8b'), 'false:VERIFICATION_REQUIRED';

-- S9 · UC-12: converting a LINKED request creates nothing and grants the account
UPDATE hbh.enrolment_applications SET status = 'CONTACTED', contacted_at = now()
WHERE application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's5c');
INSERT INTO pg_temp.fx (k, s) VALUES ('children_before', (SELECT count(*)::text FROM hbh.children));
SELECT set_config('hbh.user_id', 'dev_reception', false);
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, v, s)
SELECT 's9', c.child_id, c.guardian_id || ':' || c.child_no
FROM hbh.convert_enrolment((SELECT application_id FROM hbh.enrolment_applications
                            WHERE application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's5c'))) c;
RESET ROLE;
SELECT set_config('hbh.user_id', '', false);
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S9 no child created', (SELECT count(*)::text FROM hbh.children), (SELECT s FROM pg_temp.fx WHERE k = 'children_before');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S9 returns the linked child, ENROLLED, converted_* = linked, account granted',
       (f.v = a.child_id AND a.status = 'ENROLLED' AND a.converted_child_id = a.child_id
        AND a.converted_guardian_id = a.guardian_id AND g.user_id IS NOT NULL)::text, 'true'
FROM pg_temp.fx f, hbh.enrolment_applications a JOIN hbh.guardians g ON g.guardian_id = a.guardian_id
WHERE f.k = 's9' AND a.application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's5c');
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S9 not marked historic', count(*)::text, '0' FROM pg_temp.attempts WHERE detail LIKE 'convert_enrolment: historic path%';

-- S10 · the v1 request converts through the historic path, marked
UPDATE hbh.enrolment_applications SET status = 'CONTACTED', contacted_at = now()
WHERE application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's8');
INSERT INTO pg_temp.fx (k, s) VALUES ('children_before10', (SELECT count(*)::text FROM hbh.children));
SELECT set_config('hbh.user_id', 'dev_reception', false);
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, v)
SELECT 's10', c.child_id FROM hbh.convert_enrolment((SELECT application_id FROM hbh.enrolment_applications
                            WHERE application_no = (SELECT split_part(s, ':', 4) FROM pg_temp.fx WHERE k = 's8'))) c;
RESET ROLE;
SELECT set_config('hbh.user_id', '', false);
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S10 historic path creates the child', ((SELECT count(*) FROM hbh.children) - (SELECT s::bigint FROM pg_temp.fx WHERE k = 'children_before10'))::text, '1';
INSERT INTO pg_temp.r (what, got, want)
SELECT 'S10 and says so in the attempt log', count(*)::text, '1' FROM pg_temp.attempts WHERE detail LIKE 'convert_enrolment: historic path%';

-- S11 · UC-03: a staff member's mobile -> the conversion is refused HB204
SET ROLE hbh_app;
INSERT INTO pg_temp.fx (k, s)
SELECT 's11', ok || ':' || reason || ':' || coalesce(application_no, '-')
FROM pg_temp.sub('01500000091', 'طفل موظّف', '2022-02-02', (SELECT v FROM pg_temp.fx WHERE k = 'v_staff'));
RESET ROLE;
UPDATE hbh.enrolment_applications SET status = 'CONTACTED', contacted_at = now()
WHERE application_no = (SELECT split_part(s, ':', 3) FROM pg_temp.fx WHERE k = 's11');
SELECT set_config('hbh.user_id', 'dev_reception', false);
SET ROLE hbh_app;
DO $s11$
DECLARE s text;
BEGIN
  BEGIN
    PERFORM hbh.convert_enrolment((SELECT application_id FROM hbh.enrolment_applications
                                   WHERE application_no = (SELECT split_part(f.s, ':', 3) FROM pg_temp.fx f WHERE f.k = 's11')));
    INSERT INTO pg_temp.r (what, got, want) VALUES ('S11 staff mobile conversion', 'OK', 'HB204');
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    INSERT INTO pg_temp.r (what, got, want) VALUES ('S11 staff mobile conversion', s, 'HB204');
  END;
END $s11$;
RESET ROLE;
SELECT set_config('hbh.user_id', '', false);

-- UC-10: the origin written by v2 is frozen
DO $o$
DECLARE s text;
BEGIN
  BEGIN
    UPDATE hbh.children SET origin_reference_id = origin_reference_id + 1
    WHERE child_id = (SELECT child_id FROM hbh.enrolment_applications
                      WHERE application_no = (SELECT split_part(f.s, ':', 4) FROM pg_temp.fx f WHERE f.k = 's1'));
    INSERT INTO pg_temp.r (what, got, want) VALUES ('UC-10 origin reference frozen', 'OK', 'HB241');
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    INSERT INTO pg_temp.r (what, got, want) VALUES ('UC-10 origin reference frozen', s, 'HB241');
  END;
END $o$;
DELETE FROM pg_temp.r WHERE what = 'S1 origin_reference_id now frozen (HB241)';

-- the internal matchers stay unreachable
SET ROLE hbh_app;
DO $m$
DECLARE s text;
BEGIN
  BEGIN
    PERFORM * FROM hbh.find_guardian_matches(1, '01099990144');
    INSERT INTO pg_temp.r (what, got, want) VALUES ('find_guardian_matches from hbh_app', 'OK', '42501');
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS s = RETURNED_SQLSTATE;
    INSERT INTO pg_temp.r (what, got, want) VALUES ('find_guardian_matches from hbh_app', s, '42501');
  END;
END $m$;
RESET ROLE;

SELECT n, CASE WHEN got = want THEN 'ok  ' ELSE 'FAIL' END AS v, what, got, want FROM pg_temp.r ORDER BY n;
SELECT count(*) FILTER (WHERE got = want) || ' ok, ' || count(*) FILTER (WHERE got <> want) || ' failed' FROM pg_temp.r;
ROLLBACK;
