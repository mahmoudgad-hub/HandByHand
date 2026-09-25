-- Hand By Hand (new) - migration 0137 DOWN. Development only.
DELETE FROM hbh.sys_params WHERE center_id IS NULL
   AND param_code IN ('PACKAGE_DEPOSIT_PCT', 'PACKAGE_ACTIVATION_KIND');
-- find_guardian_matches and trg_completeness_guardian are left at 0137's
-- shape: reverting either would restore a defect (merging on a shared
-- phone; auditing a meaningless write on every retirement).
DELETE FROM hbh.schema_migrations WHERE version = '0137';
