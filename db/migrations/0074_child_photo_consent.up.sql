-- =====================================================================
-- 0074 - a child's photograph, on the rail that already existed
--
-- 0073 added hbh.children.photo_url. This removes it and puts the
-- photograph where every other file about a child already lives.
--
-- WHY THE COLUMN HAD TO GO.
--
--   A URL is a capability. Row level security protects the ROW, and the
--   moment the address inside it is read it works for whoever holds it,
--   from anywhere, with no identity and no expiry - which is why this
--   project's rules say no personal data in a link. A photograph of a
--   child is the most personal datum in the schema.
--
--   It also carried no consent and no record of who looked, and it
--   reimplemented - without any of them - a subsystem that was already
--   finished: hbh.attachments has the digest, the size, the soft
--   delete, the INTERNAL-by-default visibility, the approval gate
--   before anything reaches a parent, the row level policies, and the
--   audit trigger that records the upload while stripping the bytes
--   back out. None of that was missing. It was bypassed.
--
-- WHAT IS ACTUALLY NEW HERE: consent, and a way to say which file is
-- the photograph.
--
-- PURPOSE, NOT MIME TYPE. The obvious gate - "an image on a child needs
-- consent" - is wrong, and wrong in the direction that gets a rule
-- deleted. A scanned school report is image/jpeg. Refusing it would
-- produce false refusals in daily reception work, and a guard that
-- cries wolf is one somebody eventually removes. So the file says what
-- it is FOR, and the gate reads that: attachments.purpose.
--
-- MODELLED ON trg_live_flag_needs_consent, which has guarded live
-- viewing since 0009 in exactly this shape - a BEFORE trigger that
-- refuses the state rather than a check in a screen. One idea, one
-- shape, and a reader who knows one knows the other.
--
-- ANY GUARDIAN OF THE CHILD, not a particular one. LIVE_VIEW is keyed
-- to a guardian because it is about what THAT person may watch. A
-- photograph is about the child, so a recorded grant from a guardian
-- with an active link is the permission. Requiring every guardian to
-- agree would make one unreachable parent a permanent block; requiring
-- a named one would make the rule depend on who happens to be at the
-- desk.
--
-- AND ONE PHOTOGRAPH AT A TIME. A partial unique index, not a rule in
-- the function: two active portraits of one child is the state where a
-- screen picks whichever the planner returned first.
-- =====================================================================

\set ON_ERROR_STOP on

-- ---------------------------------------------------------------------
-- 1. The unguarded column goes.
--
--    Nothing read it. It reached the database by hand, outside
--    scripts/db.sh, and 0073 records that it existed - this records
--    that it stopped.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.children DROP COLUMN IF EXISTS photo_url;

-- ---------------------------------------------------------------------
-- 2. What a file is for.
--
--    Nullable, so every existing row keeps its meaning and nothing is
--    backfilled: a file with no purpose is a file somebody attached,
--    which is what they all are today.
-- ---------------------------------------------------------------------
ALTER TABLE hbh.attachments
  ADD COLUMN IF NOT EXISTS purpose text;

ALTER TABLE hbh.attachments
  DROP CONSTRAINT IF EXISTS ck_att_purpose;
ALTER TABLE hbh.attachments
  ADD CONSTRAINT ck_att_purpose
    CHECK (purpose IS NULL OR purpose IN ('PROFILE_PHOTO'));

-- A portrait is an image, and it is a picture OF somebody - so it names
-- the child. Enforced here rather than in the function, because the
-- function is a door and this is the shape of the thing itself.
ALTER TABLE hbh.attachments
  DROP CONSTRAINT IF EXISTS ck_att_photo_shape;
ALTER TABLE hbh.attachments
  ADD CONSTRAINT ck_att_photo_shape
    CHECK (purpose IS DISTINCT FROM 'PROFILE_PHOTO'
           OR (child_id IS NOT NULL AND mime_type LIKE 'image/%'));

-- One at a time. Partial, because "no photograph" is the ordinary state
-- for most children and must never be a duplicate of anything.
CREATE UNIQUE INDEX IF NOT EXISTS uix_att_child_photo
  ON hbh.attachments (child_id)
  WHERE purpose = 'PROFILE_PHOTO' AND active_flg;

-- ---------------------------------------------------------------------
-- 3. The consent gate.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.trg_child_photo_needs_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  -- Only on the way IN to being a portrait. A photograph that is
  -- already stored and is being renamed, archived or approved must not
  -- be re-checked: consent can be withdrawn, and withdrawing it has to
  -- leave the record archivable rather than frozen in place.
  IF NEW.purpose IS DISTINCT FROM 'PROFILE_PHOTO'
     OR (TG_OP = 'UPDATE' AND OLD.purpose IS NOT DISTINCT FROM 'PROFILE_PHOTO') THEN
    RETURN NEW;
  END IF;

  -- SECURITY DEFINER because the answer must be "has anybody with
  -- parental authority agreed", not "has anybody I am allowed to see
  -- agreed". A receptionist who cannot read a guardian row would
  -- otherwise get a refusal that reads as a missing consent.
  IF NOT EXISTS (
    SELECT 1
    FROM   hbh.consents c
    JOIN   hbh.guardian_children gc ON gc.guardian_id = c.guardian_id
                                   AND gc.child_id    = c.child_id
    WHERE  c.child_id     = NEW.child_id
      AND  c.consent_type = 'PHOTO'
      AND  c.granted_flg
      AND  c.active_flg
      AND  c.withdrawn_at IS NULL
      AND  gc.active_flg
  ) THEN
    RAISE EXCEPTION
      'a photograph of child % needs a recorded PHOTO consent', NEW.child_id
      USING ERRCODE = 'HB123',
            HINT = 'record the guardian''s consent with hbh.grant_consent('
                   'guardian_id, ''PHOTO'', child_id) before storing the picture';
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_att_photo_consent ON hbh.attachments;

CREATE TRIGGER trg_att_photo_consent
  BEFORE INSERT OR UPDATE ON hbh.attachments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_child_photo_needs_consent();

-- ---------------------------------------------------------------------
-- 4. The one door.
--
--    Replace, not add: setting a child's photograph archives whatever
--    portrait was there. Without that, the unique index above would
--    refuse the second upload and a receptionist would be told the
--    picture is a duplicate when what she meant was "use this one now".
--
--    It does NOT delete the old row. The soft delete keeps the history
--    of which picture the centre held and when, which is part of what
--    makes a consent withdrawal answerable later.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION hbh.set_child_photo(
  p_child_id  integer,
  p_file_name text,
  p_mime_type text,
  p_content   bytea
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
DECLARE
  l_id integer;
BEGIN
  IF p_mime_type IS NULL OR p_mime_type NOT LIKE 'image/%' THEN
    RAISE EXCEPTION 'a profile photograph must be an image, not %', p_mime_type
      USING ERRCODE = 'HB124';
  END IF;

  -- Archive first, then attach. The other order would hit the unique
  -- index while both rows are live.
  UPDATE hbh.attachments
     SET active_flg = false, deleted_at = now()
   WHERE child_id = p_child_id
     AND purpose  = 'PROFILE_PHOTO'
     AND active_flg;

  -- Through attach_file, not a direct INSERT: that is where the digest,
  -- the size and the born-INTERNAL rule live, and a second way in would
  -- be a second definition of them.
  l_id := hbh.attach_file('CHILD', p_child_id, p_child_id,
                          p_file_name, p_mime_type, p_content, NULL);

  -- Two statements, not one. A row cannot be updated twice in a single
  -- statement, and marking the purpose is what arms the consent gate.
  UPDATE hbh.attachments SET purpose = 'PROFILE_PHOTO'
   WHERE attachment_id = l_id;

  RETURN l_id;
END;
$fn$;

REVOKE ALL ON FUNCTION hbh.set_child_photo(integer, text, text, bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION hbh.set_child_photo(integer, text, text, bytea) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0074');
