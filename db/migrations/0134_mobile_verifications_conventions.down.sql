-- Hand By Hand (new) - migration 0134 DOWN. Development only.
REVOKE USAGE, SELECT ON SEQUENCE hbh.mobile_verifications_verification_id_seq FROM hbh_app;
DROP TRIGGER IF EXISTS trg_mver_mobile_canon ON hbh.mobile_verifications;
DELETE FROM hbh.schema_migrations WHERE version = '0134';
