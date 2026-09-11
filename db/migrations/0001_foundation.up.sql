-- =====================================================================
-- Hand By Hand (new) - migration 0001: foundation
--
-- Forward-only. Once applied it is never edited; a correction is a new
-- migration. Run with:  scripts/db-migrate.sh
--
-- Requires the psql variable :app_password (the password for the role
-- the API connects as). The runner script supplies it.
--
-- What this migration establishes, in order of importance:
--
--   1. The identity mechanism. hbh.current_portal_user() reads the
--      per-transaction setting the API sets and has NO fallback to the
--      database user, so every policy built on it fails CLOSED.
--   2. A separate login role, hbh_app, that is not the table owner.
--      Row level security is bypassed by the owner, so an API that
--      connected as hbh_owner would make every policy decorative.
--   3. Reference tables, the audit log, and RLS over both.
--
-- Naming: snake_case, plural tables. No hbh_ prefix on objects - that
-- prefix existed in Oracle only because the schema was shared with an
-- application that was not ours. Here the schema is our own.
--
-- Conventions carried over from the Oracle system:
--   *_id  identity / foreign key      *_flg  boolean
--   *_at  timestamptz (always UTC)    *_amt  numeric
--   name_ar / name_en                 pk_ fk_ uq_ ck_ ix_ uix_
--
-- Error classes raised by this schema:
--   HB001  append-only table was updated or deleted from
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS hbh;

CREATE TABLE IF NOT EXISTS hbh.schema_migrations (
  version     text        NOT NULL,
  applied_at  timestamptz NOT NULL DEFAULT now(),
  applied_by  text        NOT NULL DEFAULT session_user,
  CONSTRAINT pk_schema_migrations PRIMARY KEY (version)
);

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0001') THEN
    RAISE EXCEPTION 'migration 0001 is already applied - migrations are forward-only';
  END IF;
END
$guard$;

-- ---------------------------------------------------------------------
-- Extensions
--
-- pgcrypto: digest() for hashing one-time codes and stream tokens.
-- Both are used from the next migration onward, but a missing extension
-- must fail here, at install time, not on the first login attempt.
-- ---------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;

-- ---------------------------------------------------------------------
-- The application login role
--
-- NOSUPERUSER and NOBYPASSRLS are the whole point: policies only bind a
-- role that cannot step around them. The acceptance suite asserts all
-- three properties, because losing any one of them disables every
-- policy in the schema silently.
-- ---------------------------------------------------------------------
DO $role$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hbh_app') THEN
    CREATE ROLE hbh_app LOGIN;
  END IF;
END
$role$;

ALTER ROLE hbh_app WITH
  LOGIN PASSWORD :'app_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOBYPASSRLS NOREPLICATION INHERIT;

GRANT USAGE ON SCHEMA hbh TO hbh_app;

-- =====================================================================
-- IDENTITY
-- =====================================================================

-- The logged-in portal user, or NULL.
--
-- Deliberately NO fallback to session_user. Opening psql against this
-- database must not make anybody look like an authenticated parent:
-- with no setting, this returns NULL, current_center_id() then returns
-- NULL, and every policy comparison yields NULL - which is not true, so
-- no row is returned. That is the fail-closed guarantee, and it is a
-- property of this function alone. Do not add a fallback.
CREATE OR REPLACE FUNCTION hbh.current_portal_user()
RETURNS text
LANGUAGE sql
STABLE
PARALLEL SAFE
AS $$
  SELECT nullif(current_setting('hbh.user_id', true), '')
$$;

COMMENT ON FUNCTION hbh.current_portal_user() IS
  'Access control identity. NULL outside an authenticated request. Never falls back to the database user.';

-- The audit-column variant. This one DOES fall back to the database
-- user so that a migration or a maintenance script is attributable.
-- Never use it in a policy or a permission check.
CREATE OR REPLACE FUNCTION hbh.current_app_user()
RETURNS text
LANGUAGE sql
STABLE
AS $$
  SELECT coalesce(nullif(current_setting('hbh.user_id', true), ''), session_user)
$$;

COMMENT ON FUNCTION hbh.current_app_user() IS
  'Audit attribution only. Falls back to the database user. NEVER use for access control.';

-- =====================================================================
-- UTILITIES
-- =====================================================================

-- Arabic name folding for search: strips diacritics and tatweel, folds
-- alef/ya/ta-marbuta variants, collapses whitespace, lowercases.
--
-- IMMUTABLE is what makes it indexable. The Oracle version had to be
-- wrapped in CAST(... AS VARCHAR2(200)) because an unbounded key made
-- Oracle size the index at ~16000 bytes and raise ORA-01450. Postgres
-- has no such cliff, so the CAST does not port - do not carry it over.
CREATE OR REPLACE FUNCTION hbh.normalize_arabic(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
STRICT
PARALLEL SAFE
AS $$
  SELECT btrim(regexp_replace(
           translate(
             translate(lower(p_text), 'ًٌٍَُِّْـ', ''),
             'أإآٱىةؤئ', 'اااايهوي'),
           '\s+', ' ', 'g'))
$$;

COMMENT ON FUNCTION hbh.normalize_arabic(text) IS
  'Fold an Arabic name for search. IMMUTABLE so an expression index can use it.';

-- Maintains updated_at / updated_by on every row change.
CREATE OR REPLACE FUNCTION hbh.trg_touch()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  NEW.updated_by := hbh.current_app_user();
  RETURN NEW;
END
$$;

-- Refuses UPDATE and DELETE. Attached to append-only tables.
CREATE OR REPLACE FUNCTION hbh.trg_append_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'table %.% is append-only (attempted %)',
                  TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
    USING ERRCODE = 'HB001';
END
$$;

-- =====================================================================
-- TABLES
-- =====================================================================

-- ---------------------------------------------------------------------
-- centers
--
-- The only table without center_id / branch_id, for the obvious reason.
-- Country, currency, timezone and weekend live here as data, not in
-- code, so a second centre in another country needs no code change.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.centers (
  center_id       integer     GENERATED ALWAYS AS IDENTITY,
  code            text        NOT NULL,
  name_ar         text        NOT NULL,
  name_en         text,
  country_code    char(2)     NOT NULL DEFAULT 'EG',
  currency_code   char(3)     NOT NULL DEFAULT 'EGP',
  time_zone       text        NOT NULL DEFAULT 'Africa/Cairo',
  -- ISO day numbers: 1=Monday .. 7=Sunday. Egypt rests Friday+Saturday.
  weekend_days    smallint[]  NOT NULL DEFAULT '{5,6}',
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_centers PRIMARY KEY (center_id),
  CONSTRAINT uq_centers_code UNIQUE (code),
  CONSTRAINT ck_centers_country  CHECK (country_code  ~ '^[A-Z]{2}$'),
  CONSTRAINT ck_centers_currency CHECK (currency_code ~ '^[A-Z]{3}$'),
  CONSTRAINT ck_centers_weekend  CHECK (weekend_days <@ ARRAY[1,2,3,4,5,6,7]::smallint[])
);

-- ---------------------------------------------------------------------
-- branches
-- ---------------------------------------------------------------------
CREATE TABLE hbh.branches (
  branch_id    integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  code         text        NOT NULL,
  name_ar      text        NOT NULL,
  name_en      text,
  phone        text,
  address_ar   text,
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_branches PRIMARY KEY (branch_id),
  CONSTRAINT fk_branches_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_branches_code UNIQUE (center_id, code)
);

-- Every foreign key gets an index.
CREATE INDEX ix_branches_center ON hbh.branches (center_id);

-- ---------------------------------------------------------------------
-- sys_params
--
-- center_id NULL means a global default; a row with a center_id
-- overrides it for that centre.
--
-- NULLS NOT DISTINCT is load-bearing. A plain UNIQUE (center_id,
-- param_code) treats every NULL as distinct, so two global rows with
-- the same code would both be accepted - the same trap that let two
-- children share a NULL national id in the Oracle system. Postgres 15+
-- states the intent directly instead of hiding it in a coalesce().
-- ---------------------------------------------------------------------
CREATE TABLE hbh.sys_params (
  param_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id      integer,
  param_code     text        NOT NULL,
  param_value    text,
  data_type      text        NOT NULL DEFAULT 'STRING',
  description_ar text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_sys_params PRIMARY KEY (param_id),
  CONSTRAINT fk_sys_params_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_sys_params UNIQUE NULLS NOT DISTINCT (center_id, param_code),
  CONSTRAINT ck_sys_params_type CHECK (data_type IN ('STRING','NUMBER','BOOLEAN','DATE','JSON')),
  CONSTRAINT ck_sys_params_code CHECK (param_code ~ '^[A-Z][A-Z0-9_]{2,49}$')
);

CREATE INDEX ix_sys_params_center ON hbh.sys_params (center_id);

-- ---------------------------------------------------------------------
-- lookup_types / lookup_values
-- ---------------------------------------------------------------------
CREATE TABLE hbh.lookup_types (
  lookup_type_id integer     GENERATED ALWAYS AS IDENTITY,
  code           text        NOT NULL,
  name_ar        text        NOT NULL,
  name_en        text,
  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,
  CONSTRAINT pk_lookup_types PRIMARY KEY (lookup_type_id),
  CONSTRAINT uq_lookup_types_code UNIQUE (code),
  CONSTRAINT ck_lookup_types_code CHECK (code ~ '^[A-Z][A-Z0-9_]{2,49}$')
);

CREATE TABLE hbh.lookup_values (
  lookup_value_id integer     GENERATED ALWAYS AS IDENTITY,
  lookup_type_id  integer     NOT NULL,
  center_id       integer,
  code            text        NOT NULL,
  name_ar         text        NOT NULL,
  name_en         text,
  sort_order      integer     NOT NULL DEFAULT 100,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_lookup_values PRIMARY KEY (lookup_value_id),
  CONSTRAINT fk_lookup_values_type   FOREIGN KEY (lookup_type_id) REFERENCES hbh.lookup_types (lookup_type_id),
  CONSTRAINT fk_lookup_values_center FOREIGN KEY (center_id)      REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_lookup_values UNIQUE NULLS NOT DISTINCT (lookup_type_id, center_id, code)
);

CREATE INDEX ix_lookup_values_type   ON hbh.lookup_values (lookup_type_id);
CREATE INDEX ix_lookup_values_center ON hbh.lookup_values (center_id);

-- ---------------------------------------------------------------------
-- users
--
-- Minimal in this migration: enough to anchor identity and derive the
-- centre. Roles, permissions and one-time codes arrive in 0002.
--
-- The mobile CHECK is deliberately generic. The Egyptian pattern
-- (01XXXXXXXXX) is a sys_params value the API enforces, so a second
-- country needs a parameter change and not a migration.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.users (
  user_id      integer     GENERATED ALWAYS AS IDENTITY,
  center_id    integer     NOT NULL,
  branch_id    integer,
  username     text        NOT NULL,
  full_name_ar text        NOT NULL,
  user_type    text        NOT NULL,
  mobile       text,
  status       text        NOT NULL DEFAULT 'ACTIVE',
  active_flg   boolean     NOT NULL DEFAULT true,
  deleted_at   timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at   timestamptz,
  updated_by   text,
  CONSTRAINT pk_users PRIMARY KEY (user_id),
  CONSTRAINT fk_users_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_users_branch FOREIGN KEY (branch_id) REFERENCES hbh.branches (branch_id),
  CONSTRAINT ck_users_type   CHECK (user_type IN ('STAFF','THERAPIST','GUARDIAN')),
  CONSTRAINT ck_users_status CHECK (status IN ('ACTIVE','SUSPENDED','LOCKED')),
  CONSTRAINT ck_users_mobile CHECK (mobile IS NULL OR mobile ~ '^[0-9+]{6,20}$')
);

-- Username is the identity current_portal_user() returns, so it is
-- unique across the whole database and compared case-insensitively.
CREATE UNIQUE INDEX uix_users_username ON hbh.users (lower(username));
CREATE INDEX ix_users_center      ON hbh.users (center_id);
CREATE INDEX ix_users_branch      ON hbh.users (branch_id);
CREATE INDEX ix_users_name_srch   ON hbh.users (hbh.normalize_arabic(full_name_ar));

-- ---------------------------------------------------------------------
-- audit_log
--
-- Append-only, enforced by trigger rather than by convention.
--
-- NOTE - autonomous transactions do not exist in Postgres. A row
-- written here is rolled back with its transaction. For a data-change
-- record that is correct: the change did not happen, so the record of
-- it must not survive. For an ATTEMPT record - a failed login, a denied
-- access - it is wrong, because the attempt did happen. Those events
-- are written outside the transaction by the API, never by a trigger.
-- Decision recorded in docs/01-stack-decisions.md.
-- ---------------------------------------------------------------------
CREATE TABLE hbh.audit_log (
  audit_id    bigint      GENERATED ALWAYS AS IDENTITY,
  center_id   integer,
  table_name  text        NOT NULL,
  row_pk      text,
  action      text        NOT NULL,
  old_data    jsonb,
  new_data    jsonb,
  changed_by  text        NOT NULL DEFAULT hbh.current_app_user(),
  changed_at  timestamptz NOT NULL DEFAULT now(),
  client_ip   inet,
  detail      text,
  CONSTRAINT pk_audit_log PRIMARY KEY (audit_id),
  CONSTRAINT ck_audit_log_action CHECK (action IN ('INSERT','UPDATE','DELETE','READ','LOGIN','DENY'))
);

CREATE INDEX ix_audit_log_table ON hbh.audit_log (table_name, changed_at DESC);
CREATE INDEX ix_audit_log_by    ON hbh.audit_log (changed_by, changed_at DESC);
CREATE INDEX ix_audit_log_center ON hbh.audit_log (center_id, changed_at DESC);

CREATE TRIGGER trg_audit_log_append_only
  BEFORE UPDATE OR DELETE ON hbh.audit_log
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- =====================================================================
-- CENTRE DERIVATION
--
-- Declared after users because it reads that table.
--
-- SECURITY DEFINER so the lookup is not itself filtered by the policies
-- that call it - without it, the policy on users would recurse into
-- this function which reads users, and Postgres would raise
-- "infinite recursion detected in policy".
--
-- search_path is pinned: a SECURITY DEFINER function with a mutable
-- search_path is a privilege escalation waiting to happen.
--
-- The centre is DERIVED from the user row and never read from a
-- client-supplied setting. The API sets hbh.user_id and nothing else,
-- so a client cannot claim to belong to another centre.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.current_center_id()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
  SELECT u.center_id
  FROM   hbh.users u
  WHERE  lower(u.username) = lower(hbh.current_portal_user())
  AND    u.active_flg
  AND    u.status = 'ACTIVE'
$$;

COMMENT ON FUNCTION hbh.current_center_id() IS
  'The centre of the authenticated user, derived from the user row. NULL when unauthenticated, which makes every policy fail closed.';

REVOKE ALL ON FUNCTION hbh.current_center_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.current_center_id()   TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.current_portal_user() TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.current_app_user()    TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.normalize_arabic(text) TO hbh_app;

-- =====================================================================
-- CHANGE AUDIT
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_new    jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) END;
  l_old    jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) END;
  l_pk_col text  := TG_ARGV[0];
BEGIN
  INSERT INTO hbh.audit_log (center_id, table_name, row_pk, action, old_data, new_data, changed_by)
  VALUES (
    nullif(coalesce(l_new, l_old) ->> 'center_id', '')::integer,
    TG_TABLE_NAME,
    coalesce(l_new, l_old) ->> l_pk_col,
    TG_OP,
    l_old,
    l_new,
    hbh.current_app_user()
  );
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

CREATE TRIGGER trg_centers_touch  BEFORE UPDATE ON hbh.centers  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_branches_touch BEFORE UPDATE ON hbh.branches FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_sys_params_touch BEFORE UPDATE ON hbh.sys_params FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_lookup_values_touch BEFORE UPDATE ON hbh.lookup_values FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_users_touch    BEFORE UPDATE ON hbh.users    FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_centers_audit    AFTER INSERT OR UPDATE OR DELETE ON hbh.centers    FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('center_id');
CREATE TRIGGER trg_branches_audit   AFTER INSERT OR UPDATE OR DELETE ON hbh.branches   FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('branch_id');
CREATE TRIGGER trg_sys_params_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.sys_params FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('param_id');
CREATE TRIGGER trg_users_audit      AFTER INSERT OR UPDATE OR DELETE ON hbh.users      FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('user_id');

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- Read this before adding a policy anywhere in this schema.
--
-- Each policy requires current_center_id() to be NOT NULL before it
-- grants anything. Without that guard a row whose center_id IS NULL - a
-- global parameter, a global lookup value - would be visible to an
-- unauthenticated connection, because "center_id IS NULL" is true
-- regardless of who is asking. The centre check alone is not enough;
-- the identity check is what closes the door.
-- =====================================================================

ALTER TABLE hbh.centers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.branches      ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.sys_params    ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.lookup_types  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.lookup_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.users         ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.audit_log     ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_centers_select ON hbh.centers
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id());

CREATE POLICY p_branches_select ON hbh.branches
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_sys_params_select ON hbh.sys_params
  FOR SELECT TO hbh_app
  USING (
    hbh.current_center_id() IS NOT NULL
    AND (center_id IS NULL OR center_id = hbh.current_center_id())
    AND active_flg
  );

CREATE POLICY p_lookup_types_select ON hbh.lookup_types
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL AND active_flg);

CREATE POLICY p_lookup_values_select ON hbh.lookup_values
  FOR SELECT TO hbh_app
  USING (
    hbh.current_center_id() IS NOT NULL
    AND (center_id IS NULL OR center_id = hbh.current_center_id())
    AND active_flg
  );

CREATE POLICY p_users_select ON hbh.users
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

-- The API writes attempt records here. It never reads them: no SELECT
-- policy exists, so a SELECT by hbh_app returns nothing at all.
CREATE POLICY p_audit_log_insert ON hbh.audit_log
  FOR INSERT TO hbh_app
  WITH CHECK (true);

-- =====================================================================
-- GRANTS
-- =====================================================================
GRANT SELECT ON hbh.centers, hbh.branches, hbh.sys_params,
                hbh.lookup_types, hbh.lookup_values, hbh.users TO hbh_app;
GRANT INSERT ON hbh.audit_log TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0001');
