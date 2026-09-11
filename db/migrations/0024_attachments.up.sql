-- =====================================================================
-- Hand By Hand (new) - migration 0024: attachments
--
-- Deferred while Oracle was production, because the hosting plan capped
-- that schema at 100 MB. That constraint is gone; the rules that came
-- with it are not, because only one of them was ever about storage.
--
-- 1. NO VIDEO. EVER. AND NOW IT IS STRUCTURAL.
--    This was a policy sentence in a document. Here it is a CHECK
--    constraint that refuses any mime type beginning video/, so "live
--    streaming only, no recording" cannot be undone by a well-meaning
--    upload endpoint. It has nothing to do with quota and never did.
--
-- 2. THE AUDIT TRIGGER MUST NOT COPY THE FILE.
--    trg_audit stores to_jsonb(NEW), which for this table would put the
--    entire file into audit_log - twice for an update, and base64 into
--    the bargain. Attachments get their own audit trigger that strips
--    the bytes and keeps the metadata. Attaching the ordinary one here
--    would multiply the size of the database by the size of every file
--    anybody ever uploads.
--
-- 3. STORAGE IS A COLUMN, NOT A REWRITE.
--    storage_kind is DB or OBJECT. Today the bytes live in the row;
--    the day they move to an object store, object_key is already there
--    and the model, the policies and the gate do not change.
--
-- 4. A FILE IS BORN INTERNAL.
--    The same ladder as a clinical note. An x-ray or a school report
--    uploaded by a therapist does not appear in the parent portal
--    because it exists - somebody publishes it.
--
-- Error classes added here:
--   HB120  not permitted to attach to or publish this
--   HB121  the file is larger than the centre allows
--   HB122  that media type is not accepted
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0024') THEN
    RAISE EXCEPTION 'migration 0024 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0023') THEN
    RAISE EXCEPTION 'migration 0023 must be applied first';
  END IF;
END
$guard$;

CREATE TABLE hbh.attachments (
  attachment_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  branch_id     integer,

  -- What it hangs off. owner_id is deliberately NOT a foreign key: one
  -- column cannot reference six tables, and a check constraint per
  -- owner kind would be six triggers. child_id carries the gate.
  owner_kind    text        NOT NULL,
  owner_id      integer     NOT NULL,
  child_id      integer,

  file_name     text        NOT NULL,
  mime_type     text        NOT NULL,
  size_bytes    bigint      NOT NULL,
  sha256        bytea       NOT NULL,

  storage_kind  text        NOT NULL DEFAULT 'DB',
  content       bytea,
  object_key    text,

  visibility    text        NOT NULL DEFAULT 'INTERNAL',
  caption_ar    text,
  uploaded_by   integer,
  approved_by   integer,
  approved_at   timestamptz,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_attachments PRIMARY KEY (attachment_id),
  CONSTRAINT fk_att_center   FOREIGN KEY (center_id)   REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_att_branch   FOREIGN KEY (branch_id)   REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_att_child    FOREIGN KEY (child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT fk_att_uploader FOREIGN KEY (uploaded_by) REFERENCES hbh.users (user_id),
  CONSTRAINT fk_att_approver FOREIGN KEY (approved_by) REFERENCES hbh.users (user_id),
  CONSTRAINT ck_att_owner CHECK (owner_kind IN
    ('CHILD','SESSION','REPORT','ASSESSMENT','INVOICE','ENROLMENT','PLAN')),
  CONSTRAINT ck_att_visibility CHECK (visibility IN ('INTERNAL','PARENT')),
  CONSTRAINT ck_att_storage CHECK (storage_kind IN ('DB','OBJECT')),
  -- Exactly one place holds the bytes.
  CONSTRAINT ck_att_where CHECK (
    (storage_kind = 'DB'     AND content IS NOT NULL AND object_key IS NULL)
    OR (storage_kind = 'OBJECT' AND object_key IS NOT NULL AND content IS NULL)),
  CONSTRAINT ck_att_size CHECK (size_bytes > 0),
  CONSTRAINT ck_att_sha  CHECK (length(sha256) = 32),
  -- The permanent rule, as a constraint rather than a sentence in a
  -- document. Live streaming only; nothing recorded, ever.
  CONSTRAINT ck_att_no_video CHECK (mime_type !~* '^video/'),
  CONSTRAINT ck_att_mime CHECK (mime_type ~ '^[a-z]+/[a-zA-Z0-9.+_-]+$'),
  -- Published means somebody approved it, the same three facts a note
  -- has to agree on.
  CONSTRAINT ck_att_published CHECK (
    visibility = 'INTERNAL'
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  CONSTRAINT ck_att_approval CHECK ((approved_by IS NULL) = (approved_at IS NULL))
);

CREATE INDEX ix_att_center   ON hbh.attachments (center_id, created_at DESC);
CREATE INDEX ix_att_branch   ON hbh.attachments (branch_id);
CREATE INDEX ix_att_owner    ON hbh.attachments (owner_kind, owner_id);
CREATE INDEX ix_att_child    ON hbh.attachments (child_id, created_at DESC);
CREATE INDEX ix_att_uploader ON hbh.attachments (uploaded_by);
CREATE INDEX ix_att_approver ON hbh.attachments (approved_by);
CREATE INDEX ix_att_sha      ON hbh.attachments (sha256);
-- The portal's own query.
CREATE INDEX ix_att_published ON hbh.attachments (child_id, created_at DESC)
  WHERE visibility = 'PARENT' AND active_flg;

-- =====================================================================
-- A FILE IS BORN INTERNAL
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.trg_attachment_born_internal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.visibility  := 'INTERNAL';
  NEW.approved_by := NULL;
  NEW.approved_at := NULL;
  RETURN NEW;
END
$$;

CREATE OR REPLACE FUNCTION hbh.trg_attachment_publish_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.visibility = 'PARENT' AND OLD.visibility <> 'PARENT' THEN
    IF NOT hbh.has_permission('ATTACHMENT.PUBLISH') THEN
      RAISE EXCEPTION 'publishing a file to a guardian needs ATTACHMENT.PUBLISH'
        USING ERRCODE = 'HB120';
    END IF;
    IF NEW.approved_by IS NULL THEN
      RAISE EXCEPTION 'a published file must name its approver' USING ERRCODE = 'HB120';
    END IF;
  END IF;

  -- Withdrawing takes the signature with it.
  IF NEW.visibility = 'INTERNAL' AND OLD.visibility = 'PARENT' THEN
    NEW.approved_by := NULL;
    NEW.approved_at := NULL;
  END IF;

  -- The bytes are written once. Replacing the content of a file that
  -- has already been referenced elsewhere is how a report comes to cite
  -- a document that no longer says what it said.
  IF NEW.content IS DISTINCT FROM OLD.content
     OR NEW.sha256 IS DISTINCT FROM OLD.sha256
     OR NEW.object_key IS DISTINCT FROM OLD.object_key THEN
    RAISE EXCEPTION 'the contents of attachment % cannot be replaced - upload a new one',
                    OLD.attachment_id
      USING ERRCODE = 'HB120';
  END IF;

  RETURN NEW;
END
$$;

-- ---------------------------------------------------------------------
-- Its own audit trigger, and this is the whole reason it exists
--
-- trg_audit stores to_jsonb(NEW). On this table that would put the
-- entire file into audit_log - twice for an update, base64 encoded. The
-- metadata is what anybody auditing wants; the bytes are already in the
-- row being audited.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_attachment_audit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_new jsonb := CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) - 'content' END;
  l_old jsonb := CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) - 'content' END;
BEGIN
  INSERT INTO hbh.audit_log (center_id, table_name, row_pk, action, old_data, new_data, changed_by)
  VALUES (nullif(coalesce(l_new, l_old) ->> 'center_id', '')::integer,
          TG_TABLE_NAME,
          coalesce(l_new, l_old) ->> 'attachment_id',
          TG_OP, l_old, l_new, hbh.current_app_user());
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

-- =====================================================================
-- ATTACHING AND PUBLISHING
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.attach_file(
  p_owner_kind text,
  p_owner_id   integer,
  p_child_id   integer,
  p_file_name  text,
  p_mime_type  text,
  p_content    bytea,
  p_caption_ar text DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_max  integer;
  l_id   integer;
BEGIN
  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = hbh.current_user_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'attaching a file needs an identity' USING ERRCODE = 'HB120';
  END IF;

  IF NOT hbh.has_permission('ATTACHMENT.UPLOAD') THEN
    RAISE EXCEPTION 'attaching a file needs ATTACHMENT.UPLOAD' USING ERRCODE = 'HB120';
  END IF;

  -- A file about a child is reachable only by somebody who may reach
  -- the child. The gate composes here as everywhere else.
  IF p_child_id IS NOT NULL AND NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'not permitted to attach a file to child %', p_child_id
      USING ERRCODE = 'HB120';
  END IF;

  IF p_mime_type ~* '^video/' THEN
    RAISE EXCEPTION 'video is never stored - the system streams live and records nothing'
      USING ERRCODE = 'HB122';
  END IF;

  l_max := hbh.param(l_user.center_id, 'MAX_ATTACHMENT_MB', '5')::integer;
  IF length(p_content) > l_max * 1024 * 1024 THEN
    RAISE EXCEPTION 'the file is % bytes and the limit is % MB', length(p_content), l_max
      USING ERRCODE = 'HB121';
  END IF;

  INSERT INTO hbh.attachments (center_id, branch_id, owner_kind, owner_id, child_id,
                               file_name, mime_type, size_bytes, sha256,
                               storage_kind, content, caption_ar, uploaded_by)
  VALUES (l_user.center_id, l_user.branch_id, p_owner_kind, p_owner_id, p_child_id,
          p_file_name, lower(p_mime_type), length(p_content),
          public.digest(p_content, 'sha256'),
          'DB', p_content, p_caption_ar, l_user.user_id)
  RETURNING attachment_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.publish_attachment(p_attachment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
BEGIN
  IF NOT hbh.has_permission('ATTACHMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing a file to a guardian needs ATTACHMENT.PUBLISH'
      USING ERRCODE = 'HB120';
  END IF;

  UPDATE hbh.attachments
     SET visibility = 'PARENT', approved_by = hbh.current_user_id(), approved_at = now()
   WHERE attachment_id = p_attachment_id;
END
$$;

-- Metadata without the bytes, for every list screen. Fetching a file
-- list should not stream every file.
CREATE VIEW hbh.v_attachment_index
WITH (security_invoker = true)
AS
SELECT a.attachment_id, a.center_id, a.branch_id, a.owner_kind, a.owner_id, a.child_id,
       a.file_name, a.mime_type, a.size_bytes, encode(a.sha256, 'hex') AS sha256_hex,
       a.storage_kind, a.visibility, a.caption_ar, a.uploaded_by, a.approved_by,
       a.approved_at, a.created_at
FROM   hbh.attachments a
WHERE  a.active_flg;

COMMENT ON VIEW hbh.v_attachment_index IS
  'Attachment metadata without the bytes. A list screen must never stream every file it lists.';

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_att_touch   BEFORE UPDATE ON hbh.attachments FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_att_born    BEFORE INSERT ON hbh.attachments FOR EACH ROW EXECUTE FUNCTION hbh.trg_attachment_born_internal();
CREATE TRIGGER trg_att_publish BEFORE UPDATE ON hbh.attachments FOR EACH ROW EXECUTE FUNCTION hbh.trg_attachment_publish_guard();
-- NOT hbh.trg_audit - see the note on trg_attachment_audit.
CREATE TRIGGER trg_att_audit   AFTER INSERT OR UPDATE OR DELETE ON hbh.attachments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_attachment_audit();

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_att_select ON hbh.attachments
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id() AND active_flg
    AND (child_id IS NULL OR hbh.can_access_child(child_id))
    AND (hbh.has_permission('CHILD.VIEW_ALL')
         OR (visibility = 'PARENT' AND approved_by IS NOT NULL))
  );

CREATE POLICY p_att_update ON hbh.attachments
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ATTACHMENT.UPLOAD'))
  WITH CHECK (center_id = hbh.current_center_id()
         AND hbh.has_permission('ATTACHMENT.UPLOAD'));

GRANT SELECT, UPDATE ON hbh.attachments TO hbh_app;
GRANT SELECT ON hbh.v_attachment_index TO hbh_app;

REVOKE ALL ON FUNCTION hbh.attach_file(text, integer, integer, text, text, bytea, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.publish_attachment(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.attach_file(text, integer, integer, text, text, bytea, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.publish_attachment(integer) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0024');
