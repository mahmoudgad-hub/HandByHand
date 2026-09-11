-- =====================================================================
-- 0068 - how a member of staff gets their first password
--
-- THE PROBLEM THIS SOLVES, AND THE RULE IT REFUSES TO BREAK.
--
-- An account opened from the console has no password and no way in.
-- hbh.set_password has always allowed an administrator to set one for
-- somebody else, and the API has always refused to expose that, with
-- the reason written in api/internal/store/identity.go:
--
--   "A password field on a creation screen is a password read aloud and
--    written on paper."
--
-- That reason is right and this migration does not touch it. What it
-- adds is the missing third option: a SINGLE-USE, SHORT-LIVED TOKEN
-- that the administrator hands over and the PERSON redeems by choosing
-- their own password. The administrator learns a code that stops
-- working the moment it is used; they never learn the password.
--
-- WHY THAT IS BETTER THAN A TEMPORARY PASSWORD, which is the usual
-- answer. A temporary password is a password: it can be reused, it gets
-- written down, it is often never changed, and the administrator who
-- issued it can sign in as that person for as long as it stands. This
-- cannot be used twice and cannot be used late.
--
-- THE TOKEN IS STORED HASHED, like the one-time codes beside it. A
-- table of live tokens in plaintext is a table of temporary passwords,
-- and a backup of it is a backup of them.
--
-- NO GRANTS ON THIS TABLE, also like otp_codes. Everything goes through
-- the two SECURITY DEFINER functions below, so hbh_app cannot read a
-- token hash even by accident - and nothing that reaches a client ever
-- carries one.
--
-- IT DOES NOT APPLY TO FAMILIES. A guardian signs in with a one-time
-- code to their mobile and has no password at all; issuing one of these
-- for a GUARDIAN would create a credential for an account that has no
-- use for it.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE hbh.password_setups (
  setup_id    bigint      GENERATED ALWAYS AS IDENTITY,
  center_id   integer     NOT NULL,
  user_id     integer     NOT NULL,
  token_hash  text        NOT NULL,
  attempts    smallint    NOT NULL DEFAULT 0,
  issued_at   timestamptz NOT NULL DEFAULT now(),
  issued_by   integer     NOT NULL,
  expires_at  timestamptz NOT NULL,
  consumed_at timestamptz,

  CONSTRAINT pk_password_setups PRIMARY KEY (setup_id),
  CONSTRAINT fk_ps_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ps_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT fk_ps_issuer FOREIGN KEY (issued_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_ps_window CHECK (expires_at > issued_at)
);

CREATE INDEX ix_ps_user   ON hbh.password_setups (user_id, issued_at DESC);
CREATE INDEX ix_ps_center ON hbh.password_setups (center_id);
CREATE INDEX ix_ps_issuer ON hbh.password_setups (issued_by);
CREATE INDEX ix_ps_live   ON hbh.password_setups (user_id) WHERE consumed_at IS NULL;

-- Same shape as otp_codes and for the same reasons: issued_at and
-- consumed_at ARE the lifecycle of a credential, and one that is merely
-- deactivated is one that still exists - the opposite of single use.
INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('password_setups', 'AUDIT_COLUMNS',
   'A credential record, not business data. issued_at, issued_by and '
   'consumed_at are its lifecycle and its attribution; created_at would '
   'duplicate issued_at and updated_by would name the system on every row.'),
  ('password_setups', 'SOFT_DELETE',
   'A setup token is consumed or it expires - consumed_at and expires_at '
   'carry that. A token that is merely deactivated is a token that still '
   'exists, which is the opposite of what single-use means.')
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------
-- Issuing one. Needs USER.MANAGE, and returns the token exactly once.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.issue_password_setup(p_user_id integer)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user  hbh.users%ROWTYPE;
  l_token text;
  l_mins  integer;
BEGIN
  IF hbh.current_center_id() IS NULL OR NOT hbh.has_permission('USER.MANAGE') THEN
    RAISE EXCEPTION 'issuing a password setup needs USER.MANAGE'
      USING ERRCODE = 'HB150';
  END IF;

  SELECT * INTO l_user FROM hbh.users
  WHERE user_id = p_user_id AND center_id = hbh.current_center_id() AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such user %', p_user_id USING ERRCODE = 'HB153';
  END IF;

  IF l_user.user_type NOT IN ('STAFF', 'THERAPIST') THEN
    RAISE EXCEPTION 'user % signs in with a one-time code, not a password', p_user_id
      USING ERRCODE = 'HB071';
  END IF;

  -- Any earlier token stops working now. Two live tokens for one account
  -- means one of them is a spare somebody kept.
  UPDATE hbh.password_setups
     SET consumed_at = now()
   WHERE user_id = p_user_id AND consumed_at IS NULL;

  -- 160 bits from the server's own generator. Long enough that guessing
  -- is not a strategy, so the attempt counter guards against noise
  -- rather than against a real search.
  l_token := encode(public.gen_random_bytes(20), 'hex');
  l_mins  := hbh.param(l_user.center_id, 'PASSWORD_SETUP_TTL_MINUTES', '1440')::integer;

  INSERT INTO hbh.password_setups
         (center_id, user_id, token_hash, issued_by, expires_at)
  VALUES (l_user.center_id, p_user_id,
          public.crypt(l_token, public.gen_salt('bf', 10)),
          hbh.current_user_id(), now() + make_interval(mins => l_mins));

  -- Returned once, to the caller who asked. It is never stored in the
  -- clear and there is no way to read it back.
  RETURN l_token;
END;
$fn$;

-- ---------------------------------------------------------------------
-- Redeeming one.
--
-- NOT authenticated, and it cannot be: the person has no way in yet.
-- The token IS the authorisation, which is why it is single use, short
-- lived, and counted.
--
-- The token is looked up by USER and then verified, exactly as the
-- one-time code is: crypt cannot be used as a lookup key, because each
-- hash carries its own salt.
-- ---------------------------------------------------------------------
-- IT RETURNS A STATUS AND NEVER RAISES, and that is not a style choice.
--
-- A wrong token has to be COUNTED, and this project has paid twice for
-- what happens when a function counts and then raises: the exception
-- unwinds the transaction and takes the increment with it, so the
-- counter never moves and the code can be guessed without limit. It was
-- verify_otp the first time and consume_package_session the second.
-- D-1 settled it: a function that counts returns a status.
--
-- So every outcome is a returned word, including success. The API turns
-- the word into an answer; nothing here raises except a genuine fault.
CREATE OR REPLACE FUNCTION hbh.redeem_password_setup(
  p_username text,
  p_token    text,
  p_password text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_user  hbh.users%ROWTYPE;
  l_setup hbh.password_setups%ROWTYPE;
  l_min   integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users
  WHERE username = p_username AND active_flg;
  -- ONE answer for every way of being wrong: no such account, no live
  -- token, an expired one, the wrong one. Telling them apart would make
  -- this a way to learn which usernames exist and which are waiting to
  -- be set up - and an account waiting to be set up is the most useful
  -- one to know about.
  IF NOT FOUND THEN
    RETURN 'INVALID';
  END IF;

  SELECT * INTO l_setup FROM hbh.password_setups
  WHERE user_id = l_user.user_id AND consumed_at IS NULL AND expires_at > now()
  ORDER BY issued_at DESC LIMIT 1;
  IF NOT FOUND THEN
    RETURN 'INVALID';
  END IF;

  IF l_setup.attempts >= 5 THEN
    RETURN 'INVALID';
  END IF;

  IF l_setup.token_hash <> public.crypt(p_token, l_setup.token_hash) THEN
    UPDATE hbh.password_setups SET attempts = attempts + 1
     WHERE setup_id = l_setup.setup_id;
    RETURN 'INVALID';
  END IF;

  l_min := hbh.param(l_user.center_id, 'MIN_PASSWORD_LENGTH', '10')::integer;
  IF length(coalesce(p_password, '')) < l_min THEN
    -- A DIFFERENT answer from INVALID. The token was right and the
    -- password is too short; saying the code is invalid when it is not
    -- would send somebody back to the administrator for a code that
    -- already worked. The token is NOT consumed here - they get to try
    -- a longer password with the same code.
    RETURN 'TOO_SHORT';
  END IF;

  UPDATE hbh.users
     SET password_hash    = public.crypt(p_password, public.gen_salt('bf', 10)),
         password_set_at  = now(),
         failed_login_cnt = 0,
         locked_until     = NULL
   WHERE user_id = l_user.user_id;

  UPDATE hbh.password_setups SET consumed_at = now()
   WHERE setup_id = l_setup.setup_id;

  RETURN 'OK';
END;
$fn$;

REVOKE ALL ON FUNCTION hbh.issue_password_setup(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.redeem_password_setup(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.issue_password_setup(integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.redeem_password_setup(text, text, text) TO hbh_app;

-- No grants on the table itself. hbh_app cannot read a token hash.
ALTER TABLE hbh.password_setups ENABLE ROW LEVEL SECURITY;

INSERT INTO hbh.schema_migrations (version) VALUES ('0068');
