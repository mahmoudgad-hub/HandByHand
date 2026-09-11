-- =====================================================================
-- Hand By Hand (new) - SCHEMA CONVENTIONS
--
-- Must print:  PHASE 00 ACCEPTED
--
-- This suite is not about a phase. It checks the schema AS IT STANDS,
-- so a rule broken by migration 0007 fails here and not inside the
-- phase-1 suite, where nobody would think to look for it.
--
-- It runs first, and every phase suite from here on leaves schema-wide
-- rules to this file rather than repeating them.
--
-- Exemptions come from hbh.convention_exemptions - a table, with a
-- written reason, next to the schema. Not from a list inside this file:
-- a rule whose exceptions live in its own test is a rule each phase
-- quietly edits.
-- =====================================================================

\set ON_ERROR_STOP off
\pset pager off

DROP SCHEMA IF EXISTS hbh_test CASCADE;
CREATE SCHEMA hbh_test;

CREATE TABLE hbh_test.results (
  seq    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  grp    text    NOT NULL,
  name   text    NOT NULL,
  ok     boolean NOT NULL,
  detail text
);

CREATE PROCEDURE hbh_test.chk(p_grp text, p_name text, p_sql text)
LANGUAGE plpgsql AS $$
DECLARE v_ok boolean;
BEGIN
  BEGIN
    EXECUTE p_sql INTO v_ok;
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, coalesce(v_ok, false),
            CASE WHEN coalesce(v_ok, false) THEN 'ok'
                 WHEN v_ok IS NULL THEN 'returned NULL'
                 ELSE 'returned false' END);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO hbh_test.results (grp, name, ok, detail)
    VALUES (p_grp, p_name, false, SQLSTATE || ' ' || SQLERRM);
  END;
END $$;

-- Names the offenders instead of only counting them. A structural rule
-- that reports "returned false" and nothing else costs an hour of
-- hunting every time it fires.
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

-- =====================================================================
-- 0. THE REGISTER ITSELF
-- =====================================================================
CALL hbh_test.chk('register', 'the exemption register exists',
  $q$ SELECT EXISTS (SELECT 1 FROM information_schema.tables
                     WHERE table_schema = 'hbh' AND table_name = 'convention_exemptions') $q$);

CALL hbh_test.chk_empty('register', 'no exemption names a table that does not exist',
  $q$ SELECT e.table_name || '/' || e.rule_code
      FROM hbh.convention_exemptions e
      WHERE NOT EXISTS (SELECT 1 FROM information_schema.tables t
                        WHERE t.table_schema = 'hbh' AND t.table_name = e.table_name) $q$);

CALL hbh_test.chk_empty('register', 'every exemption carries a real reason',
  $q$ SELECT table_name || '/' || rule_code
      FROM hbh.convention_exemptions
      WHERE length(btrim(reason)) < 20 $q$);

-- An exemption for a table that already complies is dead weight, and
-- dead weight is how a register turns into a place to hide things.
CALL hbh_test.chk_empty('register', 'no exemption is unnecessary',
  $q$ SELECT e.table_name || '/' || e.rule_code
      FROM hbh.convention_exemptions e
      WHERE (e.rule_code = 'SOFT_DELETE'
             AND EXISTS (SELECT 1 FROM information_schema.columns c
                         WHERE c.table_schema = 'hbh' AND c.table_name = e.table_name
                           AND c.column_name = 'active_flg'))
         OR (e.rule_code = 'AUDIT_COLUMNS'
             AND (SELECT count(*) FROM information_schema.columns c
                  WHERE c.table_schema = 'hbh' AND c.table_name = e.table_name
                    AND c.column_name IN ('created_at','created_by','updated_at','updated_by')) = 4) $q$);

-- =====================================================================
-- 0a2. THE LEDGER AND THE SCHEMA TELL THE SAME STORY
--
-- hbh.schema_migrations is the only record of what has been applied, and
-- a schema carrying a change the ledger does not explain is worse than a
-- ledger showing a decision taken and then reversed: the second can be
-- read, the first cannot.
--
-- IT HAPPENED. Two migrations were applied while the ledger stopped at
-- the number before them, and nothing anywhere said so. It was found by
-- a person reading files, which is the one method that does not scale.
-- Nothing broke that day only because ADD COLUMN IF NOT EXISTS is safe
-- to repeat - and that is exactly what makes it dangerous, because the
-- first line added there that is NOT repeatable fails with no visible
-- cause.
--
-- WHAT THIS CAN AND CANNOT SEE. A check inside the database cannot read
-- the migrations directory, so "every file has a row" is not answerable
-- here - scripts/db.sh migrate is where that belongs. What IS answerable
-- is the shape of the ledger itself, and the failure above has a shape:
-- a migration applied without recording its number leaves a GAP where
-- its number should be. So a gap is the symptom this catches.
--
-- A DELIBERATELY ABANDONED NUMBER WOULD ALSO SHOW AS A GAP, and that is
-- intended: a number reserved and never used is a claim on the sequence
-- that the next person has no way to distinguish from a lost migration.
-- If one is ever genuinely abandoned, the honest fix is a migration that
-- takes the number and does nothing but say why.
-- =====================================================================
CALL hbh_test.chk_empty('ledger', 'no gap in the applied migration numbers',
  $q$ WITH v AS (SELECT version::int AS n FROM hbh.schema_migrations)
      SELECT to_char(g, 'FM0000')
      FROM   generate_series((SELECT min(n) FROM v), (SELECT max(n) FROM v)) g
      WHERE  NOT EXISTS (SELECT 1 FROM v WHERE v.n = g) $q$);

-- The table has no primary key on version, so this is not free.
CALL hbh_test.chk_empty('ledger', 'no version recorded twice',
  $q$ SELECT version FROM hbh.schema_migrations
      GROUP BY version HAVING count(*) > 1 $q$);

-- A version that is not four digits sorts differently from every other,
-- and migrate applies them in sorted order.
CALL hbh_test.chk_empty('ledger', 'every version is four digits',
  $q$ SELECT version FROM hbh.schema_migrations
      WHERE version !~ '^[0-9]{4}$' $q$);

-- =====================================================================
-- 0b. THE SEED ACTUALLY LANDED
--
-- These exist because of a defect that reported success while doing
-- nothing. scripts/db.sh applies EVERY migration first and the seed
-- files afterwards, so a migration that seeds data by reading
-- hbh.roles or hbh.centers matches nothing on a rebuilt database -
-- inserts nothing, raises nothing, and the grants simply never happen.
-- Thirteen checks in the phase-4 suite failed with no hint of why.
--
-- These four are the cheapest way to notice it the next time.
-- =====================================================================
CALL hbh_test.chk('seed', 'the centre and its branch exist',
  $q$ SELECT EXISTS (SELECT 1 FROM hbh.centers WHERE code = 'HBH')
         AND EXISTS (SELECT 1 FROM hbh.branches WHERE code = 'MAIN') $q$);

CALL hbh_test.chk('seed', 'the four system roles exist',
  $q$ SELECT count(*) = 4 FROM hbh.roles
      WHERE code IN ('CENTER_ADMIN','RECEPTION','THERAPIST','GUARDIAN') $q$);

CALL hbh_test.chk_empty('seed', 'every role has at least one permission',
  $q$ SELECT r.code FROM hbh.roles r
      WHERE NOT EXISTS (SELECT 1 FROM hbh.role_permissions rp WHERE rp.role_id = r.role_id) $q$);

-- A permission nobody holds is either a mistake in the seed or a
-- migration that seeded it at the wrong moment.
CALL hbh_test.chk_empty('seed', 'every permission is granted to at least one role',
  $q$ SELECT p.code FROM hbh.permissions p
      WHERE NOT EXISTS (SELECT 1 FROM hbh.role_permissions rp
                        WHERE rp.permission_id = p.permission_id) $q$);

-- Every series a function asks for by name must exist, or the first
-- call raises HB010 in front of a receptionist.
CALL hbh_test.chk_empty('seed', 'every number series the code asks for exists',
  $q$ SELECT s.code
      FROM (VALUES ('CHILD'),('APPT'),('INVOICE'),('REQUEST'),('REPORT')) AS s(code)
      WHERE NOT EXISTS (SELECT 1 FROM hbh.number_series n WHERE n.code = s.code) $q$);

-- =====================================================================
-- 1. TABLE SHAPE
-- =====================================================================
CALL hbh_test.chk_empty('shape', 'every table carries the four audit columns',
  $q$ SELECT t.table_name
      FROM information_schema.tables t
      WHERE t.table_schema = 'hbh' AND t.table_type = 'BASE TABLE'
        AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                        WHERE e.table_name = t.table_name AND e.rule_code = 'AUDIT_COLUMNS')
        AND (SELECT count(*) FROM information_schema.columns c
             WHERE c.table_schema = 'hbh' AND c.table_name = t.table_name
               AND c.column_name IN ('created_at','created_by','updated_at','updated_by')) < 4 $q$);

CALL hbh_test.chk_empty('shape', 'every table supports soft delete',
  $q$ SELECT t.table_name
      FROM information_schema.tables t
      WHERE t.table_schema = 'hbh' AND t.table_type = 'BASE TABLE'
        AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                        WHERE e.table_name = t.table_name AND e.rule_code = 'SOFT_DELETE')
        AND NOT EXISTS (SELECT 1 FROM information_schema.columns c
                        WHERE c.table_schema = 'hbh' AND c.table_name = t.table_name
                          AND c.column_name = 'active_flg') $q$);

-- Every instant is UTC. A column without a zone is the defect that
-- silently disabled account lockout in the Oracle system.
CALL hbh_test.chk_empty('shape', 'no column is a timestamp without a time zone',
  $q$ SELECT table_name || '.' || column_name
      FROM information_schema.columns
      WHERE table_schema = 'hbh' AND data_type = 'timestamp without time zone' $q$);

CALL hbh_test.chk('shape', 'the database session is UTC',
  $q$ SELECT current_setting('TimeZone') = 'UTC' $q$);

-- =====================================================================
-- A MOBILE NUMBER IS STORED IN E.164, EVERYWHERE
--
-- 0112 made that true and this is what keeps it true. The rule is
-- schema-wide - it is about every column in the database that holds a
-- number, including the two nobody types into - so it lives here rather
-- than in the phase suite of whichever feature happens to touch one.
--
-- WHY IT ASKS FOR THE OLD SHAPE RATHER THAN FOR THE NEW ONE. Two rows
-- predate the format trigger and hold numbers that are not numbers -
-- seven digits, ten digits - and there is no honest conversion of
-- either, so they were left alone and named in 0112's own output. A
-- check for "everything matches E.164" would fail on them for ever and
-- be switched off. A check for "nothing is in the national form" is the
-- property that actually matters: it fires the day a writer puts
-- 01XXXXXXXXX back into a column, which is the regression, and says
-- nothing about two rows everybody already knows about.
-- =====================================================================
CALL hbh_test.chk_empty('shape', 'no stored mobile is in the national form',
  $q$ SELECT 'guardians.'  || guardian_id    FROM hbh.guardians              WHERE mobile        ~ '^01[0-9]{9}$'
      UNION ALL
      SELECT 'users.'      || user_id        FROM hbh.users                  WHERE mobile        ~ '^01[0-9]{9}$'
      UNION ALL
      SELECT 'therapists.' || therapist_id   FROM hbh.therapists             WHERE mobile        ~ '^01[0-9]{9}$'
      UNION ALL
      SELECT 'enrolment.'  || application_id FROM hbh.enrolment_applications WHERE parent_mobile ~ '^01[0-9]{9}$'
      UNION ALL
      SELECT 'otp_codes.'  || otp_id         FROM hbh.otp_codes              WHERE mobile        ~ '^01[0-9]{9}$'
      UNION ALL
      SELECT 'sms_outbox.' || sms_id         FROM hbh.sms_outbox             WHERE destination   ~ '^01[0-9]{9}$' $q$);

-- The canonicaliser and the constraint are one mechanism in two halves:
-- the trigger rewrites what was typed, the check refuses what the
-- trigger did not reach. A table with only one of them is a table where
-- either a national number is stored without complaint, or a perfectly
-- good typed number is refused with a constraint name instead of a
-- field. So the rule is not a list of tables - it is that the two halves
-- agree, whichever tables they are on.
CALL hbh_test.chk_empty('shape', 'the E.164 check and the canonicaliser are on the same tables',
  $q$ WITH checked AS (
        SELECT DISTINCT t.relname AS tbl
        FROM   pg_constraint k
        JOIN   pg_class t     ON t.oid = k.conrelid
        JOIN   pg_namespace n ON n.oid = t.relnamespace
        WHERE  n.nspname = 'hbh' AND k.contype = 'c'
          AND  pg_get_constraintdef(k.oid) LIKE '%[1-9][0-9]{7,14}%'
      ),
      triggered AS (
        SELECT DISTINCT t.relname AS tbl
        FROM   pg_trigger g
        JOIN   pg_class t     ON t.oid = g.tgrelid
        JOIN   pg_namespace n ON n.oid = t.relnamespace
        WHERE  n.nspname = 'hbh' AND NOT g.tgisinternal
          AND  g.tgfoid = 'hbh.trg_canonical_mobile()'::regprocedure
      )
      SELECT coalesce(c.tbl, r.tbl) || ' has ' ||
             CASE WHEN c.tbl IS NULL THEN 'the canonicaliser but no E.164 check'
                  ELSE 'an E.164 check but no canonicaliser' END
      FROM   checked c FULL JOIN triggered r ON r.tbl = c.tbl
      WHERE  c.tbl IS NULL OR r.tbl IS NULL $q$);

-- The dialling codes are the reason none of the above is hard-coded. An
-- empty table turns hbh.canonical_mobile into a function that refuses
-- every number with HB173 - the front door shut, on a database that
-- looks perfectly healthy.
CALL hbh_test.chk('seed', 'the dialling codes are loaded',
  $q$ SELECT count(*) >= 2 FROM hbh.country_dial_codes WHERE active_flg $q$);

-- "No personal data in a link." CLAUDE.md has said it since the first
-- day and nothing enforced it, which is how hbh.children.photo_url
-- reached a clinical table without anybody being stopped.
--
-- WHY A LINK IS DIFFERENT FROM A ROW. Row level security protects the
-- ROW. A URL is a capability: once it has left the system it keeps
-- working for whoever holds it, in a chat message, a browser history, a
-- referrer header. No policy in this schema reaches it there.
--
-- WHY `url`/`href` AND NOT `path` - and this is the load-bearing line.
-- The schema already uses the two words for two different things, and
-- the survey of all sixteen columns matching either bears it out:
--
--   path   an internal key the SERVICE resolves and serves after it has
--          authorised the caller - site_team_media.path,
--          staff_documents.path, staff_profiles.photo_path,
--          cameras.gateway_path (which reaches no client at all),
--          request_log.path (a route template)
--   url    an address that is fetched directly, by whoever has it -
--          site_contact.map_url, site_team.profile_href
--
-- Punishing `path` would put pressure on the correct pattern, which is
-- exactly how a convention gets weakened until it stops meaning
-- anything. The rule names the shape that actually leaks.
--
-- THE TABLES ARE DERIVED, NOT LISTED: children and guardians, and
-- anything carrying a foreign key to either. A list inside this file
-- would go stale the first time somebody adds a table.
--
-- An exemption is a row in hbh.convention_exemptions with a written
-- reason, under rule_code 'NO_PERSONAL_LINK', like every other
-- convention here.
CALL hbh_test.chk_empty('shape', 'no personal data is addressed by a link',
  $q$ WITH personal AS (
        SELECT t.table_name
          FROM information_schema.tables t
         WHERE t.table_schema = 'hbh' AND t.table_type = 'BASE TABLE'
           AND (t.table_name IN ('children', 'guardians')
                OR EXISTS (
                  SELECT 1
                    FROM information_schema.table_constraints tc
                    JOIN information_schema.constraint_column_usage ccu
                      ON ccu.constraint_name = tc.constraint_name
                     AND ccu.constraint_schema = tc.constraint_schema
                   WHERE tc.constraint_type = 'FOREIGN KEY'
                     AND tc.table_schema = 'hbh'
                     AND tc.table_name = t.table_name
                     AND ccu.table_schema = 'hbh'
                     AND ccu.table_name IN ('children', 'guardians')))
      )
      SELECT p.table_name || '.' || c.column_name
        FROM personal p
        JOIN information_schema.columns c
          ON c.table_schema = 'hbh' AND c.table_name = p.table_name
       WHERE (c.column_name LIKE '%url%' OR c.column_name LIKE '%href%')
         AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                         WHERE e.table_name = p.table_name
                           AND e.rule_code  = 'NO_PERSONAL_LINK') $q$);

-- Permanent, and unrelated to storage: live streaming only, with no
-- pointer to a recording anywhere in the model.
--
-- The exemption is read from the register, like every other convention
-- here, because a rule whose exceptions live inside its own test is a
-- rule each phase edits in silence. hbh.site_team holds one, for a
-- staff member's introduction film on the marketing page - see
-- migration 0057 for the written reason.
CALL hbh_test.chk_empty('shape', 'no column names a recording, clip or video',
  $q$ SELECT c.table_name || '.' || c.column_name
      FROM information_schema.columns c
      WHERE c.table_schema = 'hbh'
        AND c.column_name ~* '(recording|clip|video)'
        AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                        WHERE e.table_name = c.table_name
                          AND e.rule_code = 'NO_RECORDING') $q$);

-- The other two halves of the same rule, moved here from p7 - where
-- they had lived since the streaming phase, and where migration 0055
-- broke one of them.
--
-- THAT IS THE FAILURE THIS FILE EXISTS TO PREVENT, and it happened
-- again: a schema-wide invariant kept inside a phase suite is a rule
-- the schema can outgrow without anybody watching, and when it does
-- break, the regression is reported under a phase name that has nothing
-- to do with what changed. It was written down after migration 0002 did
-- it to P1; 0055 then did it to p7 while I was reading the same file.
-- The rule is schema-wide, so it belongs to the suite that grows with
-- the schema, and it belongs here ONCE.
CALL hbh_test.chk_empty('shape', 'no table names a recording, clip or video',
  $q$ SELECT t.table_name
      FROM information_schema.tables t
      WHERE t.table_schema = 'hbh'
        AND t.table_name ~* '(recording|clip|video)'
        AND NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                        WHERE e.table_name = t.table_name
                          AND e.rule_code = 'NO_RECORDING') $q$);

-- A retention period is the tell that something is being kept. Nothing
-- in this model is, so nothing needs a column saying for how long - and
-- the exemption does not extend here: the marketing film is published
-- or it is removed, and neither is an expiry the database counts down.
CALL hbh_test.chk_empty('shape', 'and no column could hold a retention period for one',
  $q$ SELECT table_name || '.' || column_name
      FROM information_schema.columns
      WHERE table_schema = 'hbh'
        AND column_name ~* '(retention|archive_days|keep_days)' $q$);

-- And the exemption is bounded by a rule rather than by trust.
--
-- A table allowed to name a video must have nothing to hang a session
-- on: no child, no session, no appointment, no camera. That is what
-- makes "this is marketing, not a recording" a property of the schema
-- instead of a promise in a comment - and the day somebody adds such a
-- column to an exempted table, this fails and names the exemption
-- rather than letting the permanent rule erode a column at a time.
CALL hbh_test.chk_empty('shape', 'a table exempt from NO_RECORDING cannot reach a session',
  $q$ SELECT e.table_name || '.' || c.column_name
      FROM hbh.convention_exemptions e
      JOIN information_schema.columns c
        ON c.table_schema = 'hbh' AND c.table_name = e.table_name
      WHERE e.rule_code = 'NO_RECORDING'
        AND c.column_name IN ('child_id', 'session_id', 'appointment_id',
                              'camera_id', 'therapy_session_id') $q$);

-- An identity column has a sequence behind it, and hbh_app cannot use
-- one until it is granted. A table created without that grant reads
-- perfectly and refuses every insert - "permission denied for sequence
-- ..." - which reads as a policy fault when the policies are fine.
-- Missed in 0061 and fixed in 0062; this is what would have caught it.
-- OFFSET 0 is doing real work here and must not be tidied away.
--
-- has_sequence_privilege raises 42809 on anything that is not a
-- sequence, and the planner is free to push a qual that references only
-- pg_class down to the pg_class scan - underneath the filter that was
-- supposed to keep indexes away from it. Both the relkind form and a
-- join to pg_sequence failed that way, on "uix_gc_one_primary".
-- OFFSET 0 is the optimisation fence: the subquery is evaluated first,
-- and only sequences reach the function.
CALL hbh_test.chk_empty('shape', 'every sequence is usable by hbh_app',
  $q$ SELECT q.relname
      FROM (SELECT c.relname, c.oid
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'hbh' AND c.relkind = 'S'
            OFFSET 0) q
      WHERE NOT has_sequence_privilege('hbh_app', q.oid, 'USAGE') $q$);

-- =====================================================================
-- 2. INDEXES
-- =====================================================================

-- A foreign key whose column does not LEAD an index makes a parent
-- delete take a table-level lock on the child.
CALL hbh_test.chk_empty('index', 'every foreign key has a supporting index',
  $q$ SELECT t.relname || '.' || c.conname
      FROM pg_constraint c
      JOIN pg_class t     ON t.oid = c.conrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      WHERE c.contype = 'f' AND n.nspname = 'hbh'
        AND NOT EXISTS (
          SELECT 1 FROM pg_index i
          WHERE i.indrelid = c.conrelid
            AND (string_to_array(i.indkey::text, ' ')::smallint[])[1] = c.conkey[1]) $q$);

-- =====================================================================
-- 3. ACCESS CONTROL
-- =====================================================================
CALL hbh_test.chk_empty('access', 'row level security is enabled on every table',
  $q$ SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relkind = 'r'
        AND c.relname <> 'schema_migrations'
        AND NOT c.relrowsecurity $q$);

-- Policies only bind a role that cannot walk around them. Losing any
-- one of these three makes every policy in the schema decorative, with
-- no error and no log line.
CALL hbh_test.chk('access', 'hbh_app is not a superuser',
  $q$ SELECT NOT rolsuper FROM pg_roles WHERE rolname = 'hbh_app' $q$);

CALL hbh_test.chk('access', 'hbh_app does not bypass RLS',
  $q$ SELECT NOT rolbypassrls FROM pg_roles WHERE rolname = 'hbh_app' $q$);

CALL hbh_test.chk_empty('access', 'hbh_app owns no table',
  $q$ SELECT c.relname FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'hbh' AND c.relkind = 'r'
        AND pg_get_userbyid(c.relowner) = 'hbh_app' $q$);

-- A SECURITY DEFINER function with a mutable search_path is a
-- privilege escalation waiting for someone to notice it.
CALL hbh_test.chk_empty('access', 'every SECURITY DEFINER function pins its search_path',
  $q$ SELECT p.proname
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'hbh' AND p.prosecdef
        AND NOT EXISTS (SELECT 1 FROM unnest(coalesce(p.proconfig, '{}')) cfg
                        WHERE cfg LIKE 'search\_path=%') $q$);

-- =====================================================================
-- A PERMISSION IS NOT AN ADDRESS
--
-- A SECURITY DEFINER function that MUTATES and takes a raw entity id
-- from its caller must ask BOTH questions:
--
--     has_permission(...)        what may this person do
--     AND an ownership question  is this row theirs to do it to
--
-- A permission says WHAT. It never says WHICH ROW. Row level security
-- normally supplies the second half - and SECURITY DEFINER is exactly
-- the place where it does not apply.
--
-- THIS RULE WAS WRITTEN AFTER EIGHT FUNCTIONS BROKE IT AT ONCE, and it
-- found every one of them: issue_invoice and decide_request were proven
-- first (0099), and the check named six more (0101), five of which were
-- then demonstrated to succeed across a tenant boundary - including
-- set_password, which is account takeover, and grant_consent, which
-- decides who may watch a child during a therapy session. Zero false
-- positives on its first run.
--
-- WHAT COUNTS AS AN OWNERSHIP QUESTION - the whole of the rule's
-- flexibility, and every entry resolves to a centre or a family link:
--
--   assert_same_center   the helper from 0099
--   can_access_child     centre-bound for staff, link-bound for families
--   can_start_session / can_close_session / check_session_edit
--   current_center_id    compared by hand - cancel_recurrence does this,
--                        because a recurrence group is a SET and the
--                        question is "are they ALL mine"
--
-- WHAT IT DOES NOT CATCH, deliberately: a CENTRE arriving as a
-- parameter. hbh.book_appointment and hbh.book_recurring take
-- p_center_id from the caller. That is "the function trusts a tenant"
-- rather than "the function trusts an id", and a rule covering both
-- would flag every function that writes a center_id column. Tracked
-- separately.
--
-- AN EXEMPTION HERE WOULD NEED A REASON THE RULE GENUINELY DOES NOT
-- APPLY - not "this one is inconvenient". There are none, and the list
-- below is empty rather than exempted.
CALL hbh_test.chk_empty('access', 'no SECURITY DEFINER mutator trusts a caller-supplied id',
  $q$ WITH f AS (
        SELECT p.proname,
               pg_get_functiondef(p.oid)                 AS def,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM   pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE  n.nspname = 'hbh' AND p.prosecdef AND p.prokind = 'f'
          AND  p.prorettype <> 'trigger'::regtype
      )
      SELECT proname
      FROM   f
      WHERE  def  ~* '\m(INSERT|UPDATE|DELETE)\M'
        AND  args ~  'p_[a-z_]*id\s+(integer|bigint)'
        AND  args !~ '^p_center_id'
        AND  def  ~  'has_permission'
        AND  def  !~ 'assert_same_center|can_access_child'
                     '|can_close_session|can_start_session|check_session_edit'
                     '|current_center_id'
        AND  NOT EXISTS (SELECT 1 FROM hbh.convention_exemptions e
                         WHERE e.table_name = f.proname
                           AND e.rule_code  = 'CENTER_OWNERSHIP') $q$);

-- The audit trail is evidence, and evidence the API role can write into
-- is weaker than it looks the day somebody reads it. Both writers run as
-- the OWNER - hbh.trg_audit is SECURITY DEFINER, hbh.audit_attempt lands
-- through dblink - so hbh_app needs nothing here at all.
--
-- This lives in p00 and not in a phase suite on purpose: it is a rule
-- about every migration still to come, and a grant handed back in 0044
-- would otherwise surface as a failure in whichever phase happened to
-- own the table. It was reopened once already - see 0039.
CALL hbh_test.chk_empty('access', 'hbh_app holds no privilege on the audit trail',
  $q$ SELECT privilege_type FROM information_schema.role_table_grants
      WHERE table_schema = 'hbh' AND table_name = 'audit_log'
        AND grantee = 'hbh_app' $q$);

CALL hbh_test.chk_empty('access', 'and no policy lets it write there either',
  $q$ SELECT polname FROM pg_policy
      WHERE polrelid = 'hbh.audit_log'::regclass
        AND 'hbh_app' = ANY (SELECT pg_get_userbyid(unnest(polroles))) $q$);

-- The identity function must never fall back to the database user.
-- Everything else in the schema fails closed because this one does.
CALL hbh_test.chk('access', 'current_portal_user has no fallback',
  $q$ SELECT set_config('hbh.user_id', '', true) IS NOT NULL
             AND hbh.current_portal_user() IS NULL $q$);

CALL hbh_test.chk('access', 'current_center_id fails closed',
  $q$ SELECT hbh.current_center_id() IS NULL $q$);

-- =====================================================================
-- VERDICT
-- =====================================================================
\echo ''
SELECT grp AS "المجموعة",
       count(*) AS "اختبارات",
       count(*) FILTER (WHERE NOT ok) AS "فشل"
FROM   hbh_test.results
GROUP  BY grp
ORDER  BY min(seq);

\echo ''
SELECT seq, grp, name, detail
FROM   hbh_test.results
WHERE  NOT ok
ORDER  BY seq;

DO $verdict$
DECLARE
  v_total integer;
  v_fail  integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE NOT ok) INTO v_total, v_fail FROM hbh_test.results;
  RAISE NOTICE '';
  RAISE NOTICE '--------------------------------------------------';
  RAISE NOTICE '  % checks, % failed', v_total, v_fail;
  IF v_fail = 0 AND v_total > 0 THEN
    RAISE NOTICE '  PHASE 00 ACCEPTED';
  ELSE
    RAISE NOTICE '  *** PHASE 00 NOT ACCEPTED';
  END IF;
  RAISE NOTICE '--------------------------------------------------';
END
$verdict$;

DO $exit$
BEGIN
  IF (SELECT count(*) FROM hbh_test.results WHERE NOT ok) > 0
     OR (SELECT count(*) FROM hbh_test.results) = 0 THEN
    RAISE EXCEPTION 'conventions suite failed';
  END IF;
END
$exit$;
