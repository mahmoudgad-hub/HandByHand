-- Hand By Hand (new) - migration 0138 DOWN. Development only.
-- Deliberately does NOT restore the two parameters: OD-33 cancelled
-- them, and putting them back recreates the second source of truth
-- this migration removed.
DELETE FROM hbh.schema_migrations WHERE version = '0138';
