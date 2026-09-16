-- =====================================================================
-- Hand By Hand (new) - migration 0131: proving a mobile without an
-- account (EN-D2 · EN-01 · EN-02, OD-01)
--
-- OD-01: the public site creates a guardian and a beneficiary only
-- AFTER the person has proved they hold the mobile, by a code. The
-- writer is then not anonymous, and 0018's rule - an anonymous request
-- cannot put a child into the clinical record - stays exactly as it
-- was, for the anonymous.
--
-- ---------------------------------------------------------------------
-- A VERIFICATION CODE IS NOT A LOGIN CODE
--
-- Everything below follows from that sentence.
--
--   * NO user_id. The whole point is that there may be no account yet.
--     hbh.otp_codes is keyed on a user; this table is keyed on a
--     number. Reusing otp_codes would mean inventing a user to hang the
--     code on, which is precisely the record OD-01 says must not exist
--     before verification.
--
--   * IT OPENS NO SESSION. verify_mobile answers "this person holds
--     this number" and nothing else. A verified mobile is evidence for
--     the NEXT call (submit_enrolment v2, phase 2), not a credential.
--
--   * request_otp IS NOT TOUCHED. The 09-05 decision about what the
--     login door discloses belongs to the login door. That function
--     looks the number up and answers differently for known and unknown
--     accounts; this one never looks anything up, so it has nothing to
--     disclose, and it sends to everyone.
--
-- ---------------------------------------------------------------------
-- WHAT IS REUSED, AND WHAT IS DELIBERATELY NOT
--
--   Reused: OTP_LENGTH · OTP_TTL_MINUTES · OTP_MAX_ATTEMPTS ·
--   OTP_RESEND_SECONDS · OTP_FIXED_CODE (the dev fixed code, same
--   gate), random_digits, pgcrypto's crypt, and the rate limits
--   submit_enrolment already enforces - ENROLMENT_MAX_PER_MOBILE_DAY and
--   ENROLMENT_MAX_PER_IP_HOUR. This is the only door into the schema a
--   caller reaches without a token; the IP limit is half its protection
--   and is not optional here.
--
--   Reused with care: hbh.sms_outbox. The login code is logged there
--   under OTP_LOGIN with body_ar forced NULL by ck_sms_body - the code
--   is never written down. A verification code gets its own purpose,
--   OTP_VERIFY, and the SAME guarantee, by widening that constraint
--   rather than adding a second one that could drift from it.
--
-- ---------------------------------------------------------------------
-- TWO LESSONS APPLIED BY NAME
--
--   0097: a NULL or blank code is a WRONG code and costs an attempt.
--   crypt(NULL, hash) is NULL, so `hash <> crypt(...)` is UNKNOWN, the
--   wrong-code branch is skipped, and the function falls through to
--   success. IS DISTINCT FROM is what makes the comparison decide.
--
--   D-1: a function that counts RETURNS a state; it does not raise
--   after counting. An UPDATE followed by RAISE is rolled back with the
--   exception - an attempt counter that never advances is unlimited
--   guessing.
--
-- Error classes added here (grepped free before use - see HB240, 0130):
--   HB254  bad argument to a verification function (programmer error)
-- Everything a CALLER can cause returns a reason instead of raising.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0131') THEN
    RAISE EXCEPTION 'migration 0131 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0130') THEN
    RAISE EXCEPTION 'migration 0130 must be applied first';
  END IF;
  -- The lesson of 0130, enforced instead of remembered.
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'hbh' AND p.prosrc LIKE '%HB254%') THEN
    RAISE EXCEPTION 'HB254 is already raised by some function - grep and pick another';
  END IF;
END
$guard$;

-- =====================================================================
-- THE TABLE
-- =====================================================================
CREATE TABLE hbh.mobile_verifications (
  verification_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  mobile_e164     text        NOT NULL,
  purpose         text        NOT NULL,
  code_hash       text        NOT NULL,
  expires_at      timestamptz NOT NULL,
  attempts        smallint    NOT NULL DEFAULT 0,
  verified_at     timestamptz,
  consumed_at     timestamptz,
  client_ip       inet,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_mobile_verifications PRIMARY KEY (verification_id),
  CONSTRAINT fk_mver_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT ck_mver_purpose CHECK (purpose IN ('ENROLMENT', 'CONSULTATION')),
  CONSTRAINT ck_mver_mobile  CHECK (mobile_e164 ~ '^\+[1-9][0-9]{7,14}$'),
  CONSTRAINT ck_mver_attempts CHECK (attempts >= 0),
  CONSTRAINT ck_mver_window  CHECK (expires_at > created_at),
  -- Verified means it was checked while it was still usable.
  CONSTRAINT ck_mver_verified CHECK (verified_at IS NULL OR verified_at <= expires_at)
);

CREATE INDEX ix_mver_center ON hbh.mobile_verifications (center_id);
-- The rate-limit and "outstanding code" lookups.
CREATE INDEX ix_mver_mobile ON hbh.mobile_verifications (center_id, mobile_e164, created_at DESC);
CREATE INDEX ix_mver_ip     ON hbh.mobile_verifications (client_ip, created_at DESC)
  WHERE client_ip IS NOT NULL;

-- No policy and no grant. Nothing but the two SECURITY DEFINER functions
-- below reads or writes it: a table of number-plus-code-hash is not
-- something any screen should be able to list.
ALTER TABLE hbh.mobile_verifications ENABLE ROW LEVEL SECURITY;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('mobile_verifications', 'AUDIT_COLUMNS',
   'A credential-proof record like otp_codes, not business data. created_at, verified_at and consumed_at ARE its lifecycle, and nobody but the system ever writes it, so updated_by would name the system on every row.'),
  ('mobile_verifications', 'SOFT_DELETE',
   'A code is consumed or it expires - consumed_at and expires_at carry that. A deactivated code is a code that still exists, which is the opposite of single-use.')
ON CONFLICT (table_name, rule_code) DO NOTHING;

-- =====================================================================
-- THE OUTBOX LEARNS A SECOND CODE THAT IS NEVER WRITTEN DOWN
-- =====================================================================
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT ck_sms_purpose;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_purpose
  CHECK (purpose IN ('OTP_LOGIN', 'OTP_VERIFY', 'NOTIFICATION', 'ENROLMENT_ASSESSMENT'));

-- Widened, not duplicated. One statement of "a code is never stored",
-- now covering both kinds of code.
ALTER TABLE hbh.sms_outbox DROP CONSTRAINT ck_sms_body;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_body
  CHECK ((purpose IN ('OTP_LOGIN', 'OTP_VERIFY')) = (body_ar IS NULL));

ALTER TABLE hbh.sms_outbox DROP CONSTRAINT ck_sms_vars_otp;
ALTER TABLE hbh.sms_outbox ADD CONSTRAINT ck_sms_vars_otp
  CHECK (NOT (purpose IN ('OTP_LOGIN', 'OTP_VERIFY') AND template_vars IS NOT NULL));

-- =====================================================================
-- EN-01 · ASKING FOR A CODE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.request_mobile_verification(
  p_center_code text,
  p_mobile      text,
  p_purpose     text,
  p_client_ip   inet DEFAULT NULL)
RETURNS TABLE (ok boolean, reason text, verification_id bigint,
               code text, expires_at timestamptz, mobile_e164 text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center  hbh.centers%ROWTYPE;
  l_mobile  text;
  l_len     integer;
  l_ttl     integer;
  l_resend  integer;
  l_per_mob integer;
  l_per_ip  integer;
  l_last    timestamptz;
  l_fixed   text;
  l_code    text;
  l_expires timestamptz;
  l_id      bigint;
BEGIN
  SELECT * INTO l_center FROM hbh.centers c
  WHERE c.code = p_center_code AND c.active_flg;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NO_CENTER', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  IF p_purpose IS NULL OR p_purpose NOT IN ('ENROLMENT', 'CONSULTATION') THEN
    RETURN QUERY SELECT false, 'BAD_PURPOSE', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  -- canonical_mobile RAISES on an unreadable number (HB170/HB173) AND
  -- RETURNS NULL on an empty one - both are real, measured, and both
  -- mean "not a number we can send to". Neither is a failure of the
  -- function; both are a bad request, answered as one.
  BEGIN
    l_mobile := hbh.canonical_mobile(p_mobile, l_center.country_code);
  EXCEPTION WHEN SQLSTATE 'HB170' OR SQLSTATE 'HB173' THEN
    l_mobile := NULL;
  END;

  IF l_mobile IS NULL THEN
    RETURN QUERY SELECT false, 'BAD_MOBILE', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  l_per_mob := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_MOBILE_DAY', '3')::integer;
  l_per_ip  := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_IP_HOUR',  '10')::integer;

  IF (SELECT count(*) FROM hbh.mobile_verifications v
      WHERE v.center_id = l_center.center_id AND v.mobile_e164 = l_mobile
        AND v.created_at > now() - interval '1 day') >= l_per_mob THEN
    RETURN QUERY SELECT false, 'RATE_LIMITED', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  IF p_client_ip IS NOT NULL
     AND (SELECT count(*) FROM hbh.mobile_verifications v
          WHERE v.client_ip = p_client_ip
            AND v.created_at > now() - interval '1 hour') >= l_per_ip THEN
    RETURN QUERY SELECT false, 'RATE_LIMITED', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  l_len    := hbh.param(l_center.center_id, 'OTP_LENGTH',          '6')::integer;
  l_ttl    := hbh.param(l_center.center_id, 'OTP_TTL_MINUTES',    '15')::integer;
  l_resend := hbh.param(l_center.center_id, 'OTP_RESEND_SECONDS', '60')::integer;

  SELECT max(v.created_at) INTO l_last FROM hbh.mobile_verifications v
  WHERE v.center_id = l_center.center_id AND v.mobile_e164 = l_mobile
    AND v.purpose = p_purpose;

  IF l_last IS NOT NULL AND l_last > now() - make_interval(secs => l_resend) THEN
    RETURN QUERY SELECT false, 'RESEND_TOO_SOON', NULL::bigint, NULL::text, NULL::timestamptz, NULL::text;
    RETURN;
  END IF;

  -- One live code per number and purpose. A new request retires the old
  -- one, so two codes are never valid for the same proof at once.
  UPDATE hbh.mobile_verifications v
     SET consumed_at = now()
   WHERE v.center_id = l_center.center_id AND v.mobile_e164 = l_mobile
     AND v.purpose = p_purpose AND v.consumed_at IS NULL AND v.verified_at IS NULL;

  -- Same fixed-code gate as request_otp: absent or malformed means random.
  l_fixed := hbh.param(l_center.center_id, 'OTP_FIXED_CODE', '');
  IF l_fixed ~ ('^[0-9]{' || l_len || '}$') THEN
    l_code := l_fixed;
  ELSE
    l_code := hbh.random_digits(l_len);
  END IF;

  l_expires := now() + make_interval(mins => l_ttl);

  -- Only the hash is stored. The plaintext leaves in the return value,
  -- goes to the SMS gateway, and is never written anywhere.
  INSERT INTO hbh.mobile_verifications (center_id, mobile_e164, purpose, code_hash,
                                        expires_at, client_ip)
  VALUES (l_center.center_id, l_mobile, p_purpose,
          public.crypt(l_code, public.gen_salt('bf', 8)), l_expires, p_client_ip)
  RETURNING hbh.mobile_verifications.verification_id INTO l_id;

  RETURN QUERY SELECT true, 'OK', l_id, l_code, l_expires, l_mobile;
END
$$;

COMMENT ON FUNCTION hbh.request_mobile_verification(text, text, text, inet) IS
  'Issues a code proving a caller holds a mobile. Looks nothing up, so it discloses nothing and sends to everyone. Opens no session. The login door (request_otp) is separate and untouched. EN-01.';

-- =====================================================================
-- EN-02 · CHECKING IT
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.verify_mobile(p_verification_id bigint, p_code text)
RETURNS TABLE (ok boolean, reason text, attempts_left integer, mobile_e164 text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_v   hbh.mobile_verifications%ROWTYPE;
  l_max integer;
BEGIN
  IF p_verification_id IS NULL THEN
    RETURN QUERY SELECT false, 'NOT_FOUND', NULL::integer, NULL::text;
    RETURN;
  END IF;

  -- FOR UPDATE: two submissions together must not each see four attempts
  -- used and each allow a fifth.
  SELECT * INTO l_v FROM hbh.mobile_verifications v
  WHERE v.verification_id = p_verification_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, 'NOT_FOUND', NULL::integer, NULL::text;
    RETURN;
  END IF;

  -- Idempotent: the same proof checked twice is still a proof. The
  -- screen cannot tell whether the first tap landed.
  IF l_v.verified_at IS NOT NULL THEN
    RETURN QUERY SELECT true, 'ALREADY_VERIFIED', NULL::integer, l_v.mobile_e164;
    RETURN;
  END IF;

  IF l_v.consumed_at IS NOT NULL THEN
    RETURN QUERY SELECT false, 'SUPERSEDED', NULL::integer, NULL::text;
    RETURN;
  END IF;

  l_max := hbh.param(l_v.center_id, 'OTP_MAX_ATTEMPTS', '5')::integer;

  IF l_v.expires_at <= now() THEN
    UPDATE hbh.mobile_verifications SET consumed_at = now()
    WHERE verification_id = l_v.verification_id;
    RETURN QUERY SELECT false, 'EXPIRED', NULL::integer, NULL::text;
    RETURN;
  END IF;

  IF l_v.attempts >= l_max THEN
    UPDATE hbh.mobile_verifications SET consumed_at = now()
    WHERE verification_id = l_v.verification_id;
    RETURN QUERY SELECT false, 'TOO_MANY_ATTEMPTS', 0, NULL::text;
    RETURN;
  END IF;

  -- 0097, by name. NULL and blank cost an attempt; IS DISTINCT FROM
  -- decides where <> would return UNKNOWN and fall through to success.
  IF p_code IS NULL OR btrim(p_code) = ''
     OR l_v.code_hash IS DISTINCT FROM public.crypt(p_code, l_v.code_hash) THEN
    UPDATE hbh.mobile_verifications SET attempts = attempts + 1
    WHERE verification_id = l_v.verification_id;
    -- D-1: the attempt is counted and the function RETURNS. Raising here
    -- would roll the counter back with the exception.
    RETURN QUERY SELECT false, 'WRONG_CODE',
                        greatest(l_max - (l_v.attempts + 1), 0), NULL::text;
    RETURN;
  END IF;

  UPDATE hbh.mobile_verifications SET verified_at = now()
  WHERE verification_id = l_v.verification_id;

  RETURN QUERY SELECT true, 'OK', NULL::integer, l_v.mobile_e164;
END
$$;

COMMENT ON FUNCTION hbh.verify_mobile(bigint, text) IS
  'Answers "this caller holds this mobile". Returns a state and never raises after counting (D-1). NULL/blank costs an attempt (0097). Opens no session - a verified row is evidence for submit_enrolment v2, not a credential. EN-02.';

-- ---------------------------------------------------------------------
-- The delivery record, a sibling of record_otp_delivery rather than a
-- new parameter on it. Adding an argument would CREATE A SECOND
-- OVERLOAD, not replace the first, and the API's existing six-argument
-- call would keep resolving to the old one - two functions with one
-- name, which is the confusion this avoids.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.record_verification_delivery(
  p_center_id     integer,
  p_mobile        text,
  p_provider_code text,
  p_provider_msg  text DEFAULT NULL,
  p_error_class   text DEFAULT NULL,
  p_error_detail  text DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_id     bigint;
  l_status text;
  l_dest   text;
BEGIN
  IF p_center_id IS NULL OR coalesce(p_mobile, '') = '' THEN
    RAISE EXCEPTION 'a delivery record needs a centre and a destination'
      USING ERRCODE = 'HB254';
  END IF;

  SELECT hbh.canonical_mobile_or_raw(p_mobile, c.country_code) INTO l_dest
    FROM hbh.centers c WHERE c.center_id = p_center_id;
  l_dest := coalesce(l_dest, p_mobile);

  l_status := CASE WHEN coalesce(p_error_class, '') = '' THEN 'SENT' ELSE 'DEAD' END;

  INSERT INTO hbh.sms_outbox (center_id, notification_id, purpose, template_code,
                              destination, body_ar, dedupe_key, status,
                              attempts, sent_at, failed_at,
                              provider_code, provider_msg_id,
                              error_class, error_detail)
  VALUES (p_center_id, NULL, 'OTP_VERIFY', 'OTP_VERIFY',
          l_dest, NULL,
          'VER:' || extract(epoch from clock_timestamp())::numeric(20,6)::text || ':' || l_dest,
          l_status, 1,
          CASE WHEN l_status = 'SENT' THEN now() END,
          CASE WHEN l_status = 'DEAD' THEN now() END,
          p_provider_code, nullif(p_provider_msg, ''),
          nullif(p_error_class, ''), left(coalesce(p_error_detail, ''), 500))
  RETURNING sms_id INTO l_id;

  RETURN l_id;
END
$$;

REVOKE ALL ON FUNCTION hbh.request_mobile_verification(text, text, text, inet) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.verify_mobile(bigint, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.record_verification_delivery(integer, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.request_mobile_verification(text, text, text, inet) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.verify_mobile(bigint, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.record_verification_delivery(integer, text, text, text, text, text) TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0131');
