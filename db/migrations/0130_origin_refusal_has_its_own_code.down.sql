-- Hand By Hand (new) - migration 0130 DOWN. Development only.
-- Deliberately does NOT restore HB240 on the origin trigger: that was
-- the collision this migration exists to remove. Rolling back would put
-- a business refusal back under a code the API answers with 403.
DELETE FROM hbh.schema_migrations WHERE version = '0130';
