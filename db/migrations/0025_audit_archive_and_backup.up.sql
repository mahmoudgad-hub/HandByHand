-- =====================================================================
-- Hand By Hand (new) - migration 0025: keeping the audit trail, and
-- knowing whether the backup ran.
--
-- Two operational gaps, and both have an obvious answer that is wrong.
--
-- 1. THE AUDIT LOG GROWS FOR EVER, AND MUST NOT BE PURGED.
--    The obvious fix is a retention that deletes. That is the one thing
--    that may not happen to a clinical audit trail: "who read this
--    child's file" has to survive longer than the convenience of a
--    small table.
--
--    So the rows MOVE. audit_log stays hot and small; audit_log_archive
--    holds everything older, in the same shape, append-only, in the
--    same database and the same backup. Nothing is destroyed - it is
--    the difference between filing and shredding.
--
--    And it is OFF by default: AUDIT_ARCHIVE_AFTER_DAYS is 0, meaning
--    never. Moving a clinical record is a decision the owner takes.
--
-- 2. A BACKUP NOBODY VERIFIED IS NOT A BACKUP.
--    A dump that has never been restored is a file, and the day you
--    find out whether it was a backup is the worst possible day. So
--    scripts/backup.sh restores every dump it takes into a scratch
--    database, counts what came back, and records the result here.
--    v_backup_health then answers "are we backed up" with a row rather
--    than with somebody's memory.
--
-- Error classes added here:
--   HB130  not permitted
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0025') THEN
    RAISE EXCEPTION 'migration 0025 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0024') THEN
    RAISE EXCEPTION 'migration 0024 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE ARCHIVE
--
-- Same shape as audit_log, deliberately. A question asked of the trail
-- must be answerable across both with a UNION and no translation.
-- =====================================================================
CREATE TABLE hbh.audit_log_archive (
  audit_id    bigint      NOT NULL,
  center_id   integer,
  table_name  text        NOT NULL,
  row_pk      text,
  action      text        NOT NULL,
  old_data    jsonb,
  new_data    jsonb,
  changed_by  text        NOT NULL,
  changed_at  timestamptz NOT NULL,
  client_ip   inet,
  detail      text,
  archived_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT pk_audit_log_archive PRIMARY KEY (audit_id)
);

CREATE INDEX ix_arch_table  ON hbh.audit_log_archive (table_name, changed_at DESC);
CREATE INDEX ix_arch_by     ON hbh.audit_log_archive (changed_by, changed_at DESC);
CREATE INDEX ix_arch_center ON hbh.audit_log_archive (center_id, changed_at DESC);

CREATE TRIGGER trg_arch_append_only
  BEFORE UPDATE OR DELETE ON hbh.audit_log_archive
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_append_only();

-- The whole trail, wherever it lives. Nobody querying history should
-- have to know which half of it a row is in.
CREATE VIEW hbh.v_audit_trail
WITH (security_invoker = true)
AS
SELECT audit_id, center_id, table_name, row_pk, action, old_data, new_data,
       changed_by, changed_at, client_ip, detail, false AS archived
FROM   hbh.audit_log
UNION ALL
SELECT audit_id, center_id, table_name, row_pk, action, old_data, new_data,
       changed_by, changed_at, client_ip, detail, true AS archived
FROM   hbh.audit_log_archive;

COMMENT ON VIEW hbh.v_audit_trail IS
  'The complete audit trail, hot rows and archived ones. Nothing is ever deleted from either.';

-- ---------------------------------------------------------------------
-- Moving, not deleting
--
-- audit_log refuses DELETE by trigger, which is exactly the guarantee
-- worth having - so this function disables that trigger for the move
-- and turns it back on, and REFUSES TO RETURN until it has verified it
-- is back on. The alternative designs were both worse: a permanent
-- conditional inside the trigger is a back door anybody can find, and a
-- retention that deletes destroys the thing being protected.
--
-- Off by default. AUDIT_ARCHIVE_AFTER_DAYS = 0 means never, and a fresh
-- install therefore archives nothing until somebody decides otherwise.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.archive_audit(p_days integer DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_days    integer;
  l_moved   integer := 0;
  l_enabled char(1);
BEGIN
  l_days := coalesce(p_days, hbh.param(NULL, 'AUDIT_ARCHIVE_AFTER_DAYS', '0')::integer);
  IF l_days <= 0 THEN
    RETURN 0;   -- never, and that is the default
  END IF;

  INSERT INTO hbh.audit_log_archive (audit_id, center_id, table_name, row_pk, action,
                                     old_data, new_data, changed_by, changed_at,
                                     client_ip, detail)
  SELECT a.audit_id, a.center_id, a.table_name, a.row_pk, a.action,
         a.old_data, a.new_data, a.changed_by, a.changed_at, a.client_ip, a.detail
  FROM   hbh.audit_log a
  WHERE  a.changed_at < now() - make_interval(days => l_days)
  ON CONFLICT (audit_id) DO NOTHING;

  GET DIAGNOSTICS l_moved = ROW_COUNT;

  IF l_moved > 0 THEN
    ALTER TABLE hbh.audit_log DISABLE TRIGGER trg_audit_log_append_only;
    BEGIN
      DELETE FROM hbh.audit_log a
       WHERE a.changed_at < now() - make_interval(days => l_days)
         AND EXISTS (SELECT 1 FROM hbh.audit_log_archive x WHERE x.audit_id = a.audit_id);
    EXCEPTION WHEN OTHERS THEN
      ALTER TABLE hbh.audit_log ENABLE TRIGGER trg_audit_log_append_only;
      RAISE;
    END;
    ALTER TABLE hbh.audit_log ENABLE TRIGGER trg_audit_log_append_only;
  END IF;

  -- The check that makes the above bounded rather than a hole. If the
  -- trigger is not back on, this call has left the audit log writable
  -- and must say so rather than return quietly.
  SELECT tgenabled INTO l_enabled FROM pg_trigger
  WHERE tgname = 'trg_audit_log_append_only';

  IF l_enabled <> 'O' THEN
    RAISE EXCEPTION 'archive_audit left the audit log append-only trigger disabled'
      USING ERRCODE = 'HB130';
  END IF;

  RETURN l_moved;
END
$$;

-- =====================================================================
-- BACKUPS
--
-- The table exists so that "are we backed up" is a query. A dump that
-- has never been restored is a file; verified_flg is the difference.
-- =====================================================================
CREATE TABLE hbh.backup_runs (
  backup_id      bigint      GENERATED ALWAYS AS IDENTITY,
  started_at     timestamptz NOT NULL DEFAULT now(),
  finished_at    timestamptz,
  kind           text        NOT NULL DEFAULT 'FULL',
  file_name      text,
  size_bytes     bigint,
  sha256_hex     text,
  verified_flg   boolean     NOT NULL DEFAULT false,
  verified_tables integer,
  verified_rows  bigint,
  ok_flg         boolean     NOT NULL DEFAULT false,
  detail         text,
  run_by         text        NOT NULL DEFAULT hbh.current_app_user(),
  CONSTRAINT pk_backup_runs PRIMARY KEY (backup_id),
  CONSTRAINT ck_backup_kind CHECK (kind IN ('FULL','SCHEMA','TEST')),
  CONSTRAINT ck_backup_window CHECK (finished_at IS NULL OR finished_at >= started_at),
  -- A run that claims success must have been verified. This is the
  -- whole point of the table.
  CONSTRAINT ck_backup_ok CHECK (NOT ok_flg OR verified_flg)
);

CREATE INDEX ix_backup_started ON hbh.backup_runs (started_at DESC);
CREATE INDEX ix_backup_good    ON hbh.backup_runs (finished_at DESC)
  WHERE ok_flg AND verified_flg;

ALTER TABLE hbh.backup_runs ENABLE ROW LEVEL SECURITY;
-- No policy and no grant: operational metadata, like maintenance_runs.

CREATE OR REPLACE FUNCTION hbh.record_backup(
  p_kind            text,
  p_file_name       text,
  p_size_bytes      bigint,
  p_sha256_hex      text,
  p_verified        boolean,
  p_verified_tables integer DEFAULT NULL,
  p_verified_rows   bigint  DEFAULT NULL,
  p_ok              boolean DEFAULT false,
  p_detail          text    DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_id bigint;
BEGIN
  INSERT INTO hbh.backup_runs (finished_at, kind, file_name, size_bytes, sha256_hex,
                               verified_flg, verified_tables, verified_rows, ok_flg, detail)
  VALUES (now(), p_kind, p_file_name, p_size_bytes, p_sha256_hex,
          p_verified, p_verified_tables, p_verified_rows, p_ok, p_detail)
  RETURNING backup_id INTO l_id;
  RETURN l_id;
END
$$;

CREATE VIEW hbh.v_backup_health
WITH (security_invoker = true)
AS
SELECT (SELECT max(finished_at) FROM hbh.backup_runs WHERE ok_flg AND verified_flg)
         AS last_verified_at,
       (SELECT max(finished_at) FROM hbh.backup_runs) AS last_attempt_at,
       (SELECT count(*) FROM hbh.backup_runs
        WHERE started_at > now() - interval '7 days' AND NOT ok_flg) AS failures_this_week,
       CASE
         WHEN (SELECT max(finished_at) FROM hbh.backup_runs WHERE ok_flg AND verified_flg) IS NULL
           THEN true
         WHEN (SELECT max(finished_at) FROM hbh.backup_runs WHERE ok_flg AND verified_flg)
              < now() - make_interval(hours => hbh.param(NULL, 'BACKUP_MAX_AGE_HOURS', '36')::integer)
           THEN true
         ELSE false
       END AS is_stale;

COMMENT ON VIEW hbh.v_backup_health IS
  'Whether a VERIFIED backup exists and how old it is. is_stale is true on a database that has never had one.';

-- =====================================================================
-- MAINTENANCE, WITH THE ARCHIVE ADDED
--
-- Redefined rather than extended: a function has one definition, and
-- splitting it across migrations leaves the reader guessing which is
-- live.
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
  l_archived integer := 0;
  l_offers   integer := 0;
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

  BEGIN
    l_offers := hbh.release_expired_offers();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'waiting offers: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  -- Telemetry is deleted; the clinical audit trail is MOVED.
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

  BEGIN
    l_archived := hbh.archive_audit();
  EXCEPTION WHEN OTHERS THEN
    l_detail := l_detail || 'audit archive: ' || SQLSTATE || ' ' || SQLERRM || '; ';
  END;

  UPDATE hbh.maintenance_runs
     SET finished_at      = now(),
         packages_expired = l_expired,
         streams_closed   = l_streams,
         detail = nullif(l_detail
                    || CASE WHEN l_purged   > 0 THEN 'request_log purged: '  || l_purged   || '; ' ELSE '' END
                    || CASE WHEN l_archived > 0 THEN 'audit archived: '      || l_archived || '; ' ELSE '' END
                    || CASE WHEN l_offers   > 0 THEN 'offers released: '     || l_offers   || '; ' ELSE '' END, '')
   WHERE run_id = l_run;

  RETURN l_run;
END
$$;

-- =====================================================================
-- ACCESS
-- =====================================================================
ALTER TABLE hbh.audit_log_archive ENABLE ROW LEVEL SECURITY;
-- No policy and no grant, exactly like audit_log: the API writes
-- attempt records and never reads the trail.

REVOKE ALL ON FUNCTION hbh.archive_audit(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.record_backup(text, text, bigint, text, boolean, integer, bigint, boolean, text) FROM PUBLIC;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'AUDIT_ARCHIVE_AFTER_DAYS', '0',  'NUMBER',
   'بعد كم يوم تُنقَل صفوف التدقيق للأرشيف — صفر يعني أبدًا. النقل ليس حذفًا؛ لا شيء يُمحى'),
  (NULL, 'BACKUP_MAX_AGE_HOURS',     '36', 'NUMBER',
   'بعدها تُعتبر النسخة الاحتياطية قديمة في hbh.v_backup_health')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('audit_log_archive', 'AUDIT_COLUMNS',
   'The audit trail auditing itself is a loop, and this is the same table as audit_log by another name. changed_by and changed_at are its attribution.'),
  ('audit_log_archive', 'SOFT_DELETE',
   'Append-only. A hidden archived row is a clinical audit record that can no longer be found, which is the one thing archiving exists to prevent.'),
  ('backup_runs', 'AUDIT_COLUMNS',
   'An operational log. started_at, finished_at and run_by are its attribution, and a row is written once and completed once.'),
  ('backup_runs', 'SOFT_DELETE',
   'A backup happened or it did not. A deactivated run would make the staleness view lie about the last verified one.');

INSERT INTO hbh.schema_migrations (version) VALUES ('0025');
