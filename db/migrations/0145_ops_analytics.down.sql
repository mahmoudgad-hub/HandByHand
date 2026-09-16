BEGIN;
DROP FUNCTION hbh.ops_analytics(date,date,text,text,integer);
DROP FUNCTION hbh.record_usage(text,text,text,text);
DROP TABLE hbh.usage_events;
DELETE FROM hbh.convention_exemptions WHERE table_name='usage_events';
DELETE FROM hbh.schema_migrations WHERE version='0145';
COMMIT;
