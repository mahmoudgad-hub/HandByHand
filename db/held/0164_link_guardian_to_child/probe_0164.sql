-- Rolled-back proof of 0164 (HBH-099). Expects /tmp/0164_up.sql and /tmp/0164_down.sql.
\set ON_ERROR_STOP on
\pset pager off
BEGIN;
-- 0163 is held for the owner too, so the probe records it before the guard
-- reads the ledger. Rolled back with everything else.
INSERT INTO hbh.schema_migrations (version) SELECT '0163'
 WHERE NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0163');
\i /tmp/0164_up.sql
;
CREATE TEMP TABLE r (n serial, what text, got text, want text);
GRANT ALL ON r, r_n_seq TO hbh_app;

-- A second centre, so "not mine" is a real row rather than a missing one.
INSERT INTO hbh.centers (code, name_ar) VALUES ('P0164-ELSEWHERE', 'مركز آخر فحص ٠١٦٤');
CREATE TEMP TABLE fx AS
SELECT (SELECT center_id FROM hbh.centers WHERE code = 'P0164-ELSEWHERE') AS c2,
       (SELECT branch_id FROM hbh.branches WHERE center_id = 1 ORDER BY branch_id LIMIT 1) AS b1;
INSERT INTO hbh.branches (center_id, code, name_ar) SELECT c2, 'P0164B', 'فرع آخر' FROM fx;

-- Ours: a child with no family at all, and two guardians.
INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar, birth_date, gender)
SELECT 1, b1, 'P0164-CH', 'طفل بلا أسرة', DATE '2021-02-02', 'M' FROM fx;
INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile)
SELECT 1, b1, 'أب فحص ٠١٦٤', '+201066400001' FROM fx;
INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile)
SELECT 1, b1, 'أمّ فحص ٠١٦٤', '+201066400002' FROM fx;
-- Theirs.
INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile)
SELECT c2, (SELECT branch_id FROM hbh.branches WHERE code = 'P0164B'), 'وليّ أمر المركز الآخر', '+201066400003' FROM fx;

CREATE TEMP TABLE ids AS
SELECT (SELECT child_id    FROM hbh.children  WHERE child_no = 'P0164-CH')            AS child,
       (SELECT guardian_id FROM hbh.guardians WHERE mobile = '+201066400001')         AS g_dad,
       (SELECT guardian_id FROM hbh.guardians WHERE mobile = '+201066400002')         AS g_mum,
       (SELECT guardian_id FROM hbh.guardians WHERE mobile = '+201066400003')         AS g_foreign,
       (SELECT coalesce(max(child_id), 0) + 100000 FROM hbh.children)                 AS ghost_child;
GRANT SELECT ON fx, ids TO hbh_app;

CREATE FUNCTION pg_temp.try(p_who text, p_sql text) RETURNS text LANGUAGE plpgsql AS $fn$
DECLARE s text; st text; cn text;
BEGIN
  PERFORM set_config('hbh.user_id', p_who, false);
  EXECUTE 'SET ROLE hbh_app';
  BEGIN
    EXECUTE p_sql INTO s;
    s := coalesce(s, 'null');
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS st = RETURNED_SQLSTATE, cn = CONSTRAINT_NAME;
    s := st || coalesce(' ' || nullif(cn, ''), '');
  END;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('hbh.user_id', '', false);
  RETURN s;
END $fn$;

-- ---------------------------------------------------------------------
-- The gate, before any id is read.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'a therapist cannot link a family', pg_temp.try('dev_therapist',
  'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''FATHER'')'), 'HB092' FROM ids;
INSERT INTO r (what, got, want)
SELECT 'a guardian cannot link themselves to a child', pg_temp.try('dev_parent',
  'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''FATHER'')'), 'HB092' FROM ids;
INSERT INTO r (what, got, want)
SELECT 'no identity is refused the same way', pg_temp.try('',
  'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''FATHER'')'), 'HB092' FROM ids;

-- ---------------------------------------------------------------------
-- The rows and the lookup.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'another centre''s guardian and a child that does not exist are one answer',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_foreign || ',' || child || ', ''FATHER'')') || ' ' ||
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || ghost_child || ', ''FATHER'')'),
  'HB051 HB051' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'a relationship nobody recognises is refused',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''NEIGHBOUR'')'), 'HB021' FROM ids;

-- ---------------------------------------------------------------------
-- The owner's two answers, measured.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'the father is linked', pg_temp.try('dev_reception',
  'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''FATHER'')'), 'true' FROM ids;

-- TWO STATEMENTS, and the first draft was one: a count written beside the
-- call that changes it reads the snapshot taken when the statement began,
-- so it answered "true 1" while the row was being written. The lesson is
-- in CLAUDE.md about data-modifying CTEs; it applies to any count sitting
-- in the same statement as the write it is meant to observe.
INSERT INTO r (what, got, want)
SELECT 'and the mother is linked too',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_mum || ',' || child || ', ''MOTHER'')'), 'true' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'without ending his - two live links on one child',
  (SELECT count(*)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg), '2';

-- THE OWNER'S RULE: linking never makes anybody primary, so after two
-- links this child has none - which is legal, because he allowed a child
-- with no guardian at all. Neither may watch live: that is consent's job.
INSERT INTO r (what, got, want)
SELECT 'neither link is primary, and neither may watch live',
  (SELECT string_agg(gc.is_primary_flg::text || '/' || gc.can_view_live_flg::text, ' ' ORDER BY gc.guardian_id)
     FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg),
  'false/false false/false';

INSERT INTO r (what, got, want)
SELECT 'linking again with the same facts changes nothing and says so',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_mum || ',' || child || ', ''MOTHER'')'), 'false' FROM ids;

-- ---------------------------------------------------------------------
-- Moving the primary: a named act, and only one at a time.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'a therapist cannot move the primary contact', pg_temp.try('dev_therapist',
  'SELECT hbh.set_primary_guardian(' || g_dad || ',' || child || ')'), 'HB092' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'the father is made primary, and saying it twice changes nothing',
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian(' || g_dad || ',' || child || ')') || ' ' ||
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian(' || g_dad || ',' || child || ')'), 'true false' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'moving it to the mother demotes him and leaves him linked',
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian(' || g_mum || ',' || child || ')'), 'true' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'exactly one primary, and it is the mother, and he is still linked',
  (SELECT count(*) FILTER (WHERE gc.is_primary_flg)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg)
  || ' ' ||
  (SELECT string_agg(gc.guardian_id::text, ',') FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg AND gc.is_primary_flg)
  || ' ' ||
  (SELECT count(*)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg),
  '1 ' || (SELECT g_mum::text FROM ids) || ' 2';

-- The number is the index's rule, not the function's: proved by name (D-40)
-- through a direct write, which is the only way to ask the index itself.
INSERT INTO r (what, got, want)
SELECT 'and a second live primary is refused by the index, by name',
  pg_temp.try('dev_reception', 'UPDATE hbh.guardian_children SET is_primary_flg = true WHERE guardian_id = '
                  || g_dad || ' AND child_id = ' || child), '23505 uix_gc_one_primary' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'a guardian who is not linked to this child cannot be made primary',
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian(' || g_foreign || ',' || child || ')'), 'HB051' FROM ids;

-- ---------------------------------------------------------------------
-- Unlinking: soft, idempotent, and the history stays.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'unlinking the mother answers true, then false',
  pg_temp.try('dev_reception', 'SELECT hbh.unlink_guardian_from_child(' || g_mum || ',' || child || ')') || ' ' ||
  pg_temp.try('dev_reception', 'SELECT hbh.unlink_guardian_from_child(' || g_mum || ',' || child || ')'), 'true false' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'her row is still there, dated, and the father is still linked',
  (SELECT (NOT gc.active_flg AND gc.deleted_at IS NOT NULL)::text
     FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.guardian_id = (SELECT g_mum FROM ids))
  || ' ' ||
  (SELECT count(*)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg),
  'true 1';

INSERT INTO r (what, got, want)
SELECT 'relinking her revives the same row rather than making a second',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_mum || ',' || child || ', ''MOTHER'')') || ' ' ||
  (SELECT count(*)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child), 'true 2' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'a link that never existed is the same answer as one in another centre',
  pg_temp.try('dev_reception', 'SELECT hbh.unlink_guardian_from_child(' || g_foreign || ',' || child || ')'), 'HB051' FROM ids;
-- ---------------------------------------------------------------------
-- REVIVING A LINK THAT USED TO BE THE PRIMARY. Added 2026-09-19 after
-- these three found a defect the section above could not reach.
--
-- The relink two lines up happens at the one moment when NOBODY else is
-- live primary - the mother lost it to nobody, the father was demoted
-- when she took it - so a revived is_primary_flg landed on empty ground
-- and answered true. Two rows on the same side of the rule, which is the
-- CLAUDE.md lesson about the partial index tested with a centre and a
-- NULL that could never collide.
--
-- Asked from the other side, the first draft of 0164 failed both ways:
-- 23505 uix_gc_one_primary (a raw SQLSTATE -> 500 on an ordinary
-- reception action), and, where nothing collided, a link that came back
-- PRIMARY although the migration's own header says linking never moves
-- the trait.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'the revived link is not primary - linking never moves the trait',
  (SELECT gc.is_primary_flg::text FROM hbh.guardian_children gc
    JOIN ids i ON gc.child_id = i.child AND gc.guardian_id = i.g_mum), 'false';

INSERT INTO r (what, got, want)
SELECT 'she takes the primary back, then leaves again',
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian('   || g_mum || ',' || child || ')') || ' ' ||
  pg_temp.try('dev_reception', 'SELECT hbh.unlink_guardian_from_child(' || g_mum || ',' || child || ')'), 'true true' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'her ended row keeps the flag, which is the history the header wants',
  (SELECT (NOT gc.active_flg AND gc.is_primary_flg)::text FROM hbh.guardian_children gc
    JOIN ids i ON gc.child_id = i.child AND gc.guardian_id = i.g_mum), 'true';

INSERT INTO r (what, got, want)
SELECT 'the centre moves the invoice to the father',
  pg_temp.try('dev_reception', 'SELECT hbh.set_primary_guardian(' || g_dad || ',' || child || ')'), 'true' FROM ids;

-- The one the first draft answered 23505 uix_gc_one_primary.
INSERT INTO r (what, got, want)
SELECT 'and she comes back while he holds it: an answer, not a raw SQLSTATE',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_mum || ',' || child || ', ''MOTHER'')'), 'true' FROM ids;

INSERT INTO r (what, got, want)
SELECT 'and the invoice did not move behind anybody''s back',
  (SELECT string_agg(gc.guardian_id::text, ',' ORDER BY gc.guardian_id) FROM hbh.guardian_children gc
    JOIN ids i ON gc.child_id = i.child WHERE gc.active_flg AND gc.is_primary_flg),
  (SELECT g_dad::text FROM ids);

-- The other side of the same fix, and the reason it is a CASE and not a
-- plain false: with an unconditional false this one reads
-- "GUARDIAN false" - correcting a relationship code would demote the
-- primary contact as a side effect of an unrelated edit.
INSERT INTO r (what, got, want)
SELECT 'correcting a live link''s relationship does not demote the primary',
  pg_temp.try('dev_reception', 'SELECT hbh.link_guardian_to_child(' || g_dad || ',' || child || ', ''GUARDIAN'')'), 'true' FROM ids;
INSERT INTO r (what, got, want)
SELECT '...and he is still the one the invoice goes to',
  (SELECT gc.relationship_code || ' ' || gc.is_primary_flg::text FROM hbh.guardian_children gc
    JOIN ids i ON gc.child_id = i.child AND gc.guardian_id = i.g_dad), 'GUARDIAN true';


-- ---------------------------------------------------------------------
-- Grants, and down/up.
-- ---------------------------------------------------------------------
INSERT INTO r (what, got, want)
SELECT 'both functions: hbh_app yes, PUBLIC no, search_path pinned',
       string_agg(has_function_privilege('hbh_app', p.oid, 'EXECUTE')::text || ' ' ||
                  has_function_privilege('public', p.oid, 'EXECUTE')::text || ' ' ||
                  (array_to_string(p.proconfig, ',') = 'search_path=hbh, pg_catalog')::text, ' | ' ORDER BY p.proname),
       'true false true | true false true | true false true'
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'hbh' AND p.proname IN ('link_guardian_to_child', 'unlink_guardian_from_child', 'set_primary_guardian');

\i /tmp/0164_down.sql
INSERT INTO r (what, got, want)
SELECT 'down: the functions are gone and the links are not',
       (SELECT count(*) FROM pg_proc WHERE proname IN ('link_guardian_to_child', 'unlink_guardian_from_child', 'set_primary_guardian'))::text || ' ' ||
       (SELECT count(*)::text FROM hbh.guardian_children gc JOIN ids i ON gc.child_id = i.child), '0 2';
\i /tmp/0164_up.sql
INSERT INTO r (what, got, want)
SELECT 'up again', (SELECT count(*) FROM hbh.schema_migrations WHERE version = '0164')::text, '1';

SELECT n, CASE WHEN got IS NOT DISTINCT FROM want THEN 'ok  ' ELSE 'FAIL' END AS v, what, got, want FROM r ORDER BY n;
SELECT count(*) FILTER (WHERE got IS NOT DISTINCT FROM want) || ' ok, ' || count(*) FILTER (WHERE got IS DISTINCT FROM want) || ' failed' FROM r;
ROLLBACK;
