-- =====================================================================
-- Hand By Hand (new) - migration 0084: the last p00 offender
--
-- TWO SESSIONS DISAGREED ABOUT THIS MIGRATION, AND THE DISAGREEMENT WAS
-- ABOUT TWO DIFFERENT THINGS WEARING ONE NAME.
--
--   Business analysis: do not write soft delete before BL-21 - whether
--     a message sent to a family in error can be withdrawn at all, or
--     is corrected by a following message the way a clinical note is.
--   Project manager: rule 3 of CLAUDE.md says soft delete always. This
--     is a rule breach, and a rule breach is fixed by a migration.
--
-- Both are right, because "soft delete" is a COLUMN and a CAPABILITY.
--
--   The column is schema convention. Every table carries active_flg;
--   0084 makes these two no different from the other seventy.
--   The capability is an UPDATE path - a grant, a function, a button -
--   and THAT is what BL-21 decides.
--
-- Adding the column creates no capability. hbh.family_messages holds
-- SELECT and INSERT and no UPDATE, and this migration does not change
-- that, does not write a withdraw function, and grants nothing. If the
-- owner rules that a message is final, active_flg simply stays true for
-- ever - inert, like active_flg on any table nobody deactivates rows
-- in. If the owner rules for withdrawal, the column is already here and
-- 0082's audit trigger already records the update that sets it false.
--
-- WHAT I DELIBERATELY DID NOT DO: grant UPDATE, write hbh.withdraw_
-- message, or touch the INSERT policy. Those are BL-21, and they stay
-- shut until the owner speaks.
--
-- AND ONE OF THE TWO TABLES GETS AN EXEMPTION INSTEAD, ON PURPOSE.
--
-- hbh.family_message_reads is a read WATERMARK - primary key
-- (user_id, guardian_id), message_id being how far that user has read.
-- A deactivated watermark does not hide anything; it makes messages the
-- family HAS read look unread. The row is not a record anybody could
-- want withdrawn, and the schema already has this shape: stream_views
-- and auth_sessions carry SOFT_DELETE exemptions for the same reason -
-- derived state, where hiding a row falsifies rather than conceals.
-- Writing a column there to satisfy a counter, then filtering nothing
-- by it, is how a schema starts telling small lies.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0084') THEN
    RAISE EXCEPTION 'migration 0084 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0082') THEN
    RAISE EXCEPTION 'migration 0082 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE COLUMN
-- =====================================================================
ALTER TABLE hbh.family_messages
  ADD COLUMN active_flg boolean     NOT NULL DEFAULT true,
  ADD COLUMN deleted_at timestamptz;

-- Not "may a message be hidden" - that is BL-21. This says only that a
-- hidden message must say WHEN, which is true under every answer BL-21
-- can give.
ALTER TABLE hbh.family_messages
  ADD CONSTRAINT ck_family_messages_deleted
  CHECK (active_flg OR deleted_at IS NOT NULL);

-- The policy filters on it, because a soft-delete column no policy
-- reads is decoration, and decoration is what people trust right up
-- until they need it. Today this changes nothing: every row is true and
-- nothing holds the UPDATE grant that could make one false. The day
-- BL-21 opens that grant, the portal already hides what it should.
DROP POLICY IF EXISTS family_messages_read ON hbh.family_messages;
CREATE POLICY family_messages_read ON hbh.family_messages
  FOR SELECT TO hbh_app
  USING (
    center_id = hbh.current_center_id()
    AND active_flg
    AND EXISTS (
      SELECT 1 FROM hbh.guardians g
      WHERE g.guardian_id = family_messages.guardian_id
        AND g.center_id   = family_messages.center_id
        AND g.active_flg
        AND (hbh.has_permission('REQUEST.MANAGE') OR g.user_id = hbh.current_user_id())));

-- =====================================================================
-- THE EXEMPTION
-- =====================================================================
INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('family_message_reads', 'SOFT_DELETE',
   'A read watermark, keyed (user_id, guardian_id), holding how far that user has read. Deactivating one hides nothing - it makes messages the family HAS read look unread. Derived state, like stream_views and auth_sessions: hiding a row here falsifies rather than conceals.')
ON CONFLICT (table_name, rule_code) DO NOTHING;

-- =====================================================================
-- AND THE PROOF, AT APPLY TIME
--
-- The acceptance suite is the judge, but a migration that claims to
-- close a convention gap should refuse to apply if it did not. Same
-- shape as the check 0082 carries.
-- =====================================================================
DO $verify$
DECLARE l_missing text;
BEGIN
  SELECT string_agg(t.table_name, ', ')
  INTO   l_missing
  FROM   information_schema.tables t
  WHERE  t.table_schema = 'hbh' AND t.table_type = 'BASE TABLE'
    AND  NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                     WHERE e.table_name = t.table_name AND e.rule_code = 'SOFT_DELETE')
    AND  NOT EXISTS (SELECT 1 FROM information_schema.columns c
                     WHERE c.table_schema = 'hbh' AND c.table_name = t.table_name
                       AND c.column_name = 'active_flg');

  IF l_missing IS NOT NULL THEN
    RAISE EXCEPTION 'table(s) with no soft delete and no SOFT_DELETE exemption: %', l_missing;
  END IF;
END
$verify$;

-- No GRANT. hbh.family_messages keeps SELECT and INSERT and nothing
-- else, and that is the point: the column exists, the capability does
-- not, and BL-21 remains the owner's to answer.

INSERT INTO hbh.schema_migrations (version) VALUES ('0084');
