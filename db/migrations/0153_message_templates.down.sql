-- =====================================================================
-- 0153 down - the templates leave the database.
--
-- UNLIKE MOST REVERSALS HERE, THE ROWS GO. A template row is not a record
-- that something happened to a family - message_template_events is the
-- nearest thing to that, and it goes with its table because it cannot
-- outlive the rows it references. Anything a family was actually sent is
-- still in hbh.sms_outbox, which this does not touch.
--
-- An API already built to read ContentSids from here must be rolled back
-- first: its worker calls hbh.sms_template_sid, and after this that
-- function does not exist.
--
-- Functions before tables that nothing depends on, and the events table
-- before the templates it references.
-- =====================================================================

DROP FUNCTION IF EXISTS hbh.set_message_template_status(integer, text, text, text);
DROP FUNCTION IF EXISTS hbh.edit_message_template(integer, text, text, text, text);
DROP FUNCTION IF EXISTS hbh.centres_without_template_sid(text);
DROP FUNCTION IF EXISTS hbh.sms_template_sid(bigint);
DROP FUNCTION IF EXISTS hbh.message_template_sid(integer, text);
DROP FUNCTION IF EXISTS hbh.message_template_key(text);

DROP TABLE IF EXISTS hbh.message_template_events;
DROP TABLE IF EXISTS hbh.message_templates;

DROP FUNCTION IF EXISTS hbh.trg_message_template_event();
DROP FUNCTION IF EXISTS hbh.trg_message_template_rules();
DROP FUNCTION IF EXISTS hbh.legal_message_template_transition(text, text);
DROP FUNCTION IF EXISTS hbh.template_placeholders_ok(text, integer);

DELETE FROM hbh.convention_exemptions WHERE table_name = 'message_template_events';

DELETE FROM hbh.schema_migrations WHERE version = '0153';
