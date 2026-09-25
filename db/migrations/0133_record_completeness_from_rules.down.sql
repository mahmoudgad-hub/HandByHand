-- Hand By Hand (new) - migration 0133 DOWN. Development only.
-- record_completeness values written while 0133 was in force are left
-- in place: they were true when written, and 0129 owns the column.
DROP TRIGGER IF EXISTS trg_pfr_completeness ON hbh.profile_field_rules;
DROP TRIGGER IF EXISTS trg_guardian_children_completeness ON hbh.guardian_children;
DROP TRIGGER IF EXISTS trg_children_completeness ON hbh.children;
DROP TRIGGER IF EXISTS trg_guardians_completeness_upd ON hbh.guardians;
DROP TRIGGER IF EXISTS trg_guardians_completeness_ins ON hbh.guardians;
DROP FUNCTION IF EXISTS hbh.trg_completeness_rule();
DROP FUNCTION IF EXISTS hbh.trg_completeness_link();
DROP FUNCTION IF EXISTS hbh.trg_completeness_child();
DROP FUNCTION IF EXISTS hbh.trg_completeness_guardian();
DROP FUNCTION IF EXISTS hbh.recompute_completeness_for_center(integer);
DROP FUNCTION IF EXISTS hbh.recompute_completeness(integer);
DROP FUNCTION IF EXISTS hbh.completeness_of(integer);
DROP TABLE IF EXISTS hbh.profile_field_rules;
DROP FUNCTION IF EXISTS hbh.trg_pfr_field_exists();
DELETE FROM hbh.schema_migrations WHERE version = '0133';
