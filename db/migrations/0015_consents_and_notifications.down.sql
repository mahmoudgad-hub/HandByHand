-- =====================================================================
-- Hand By Hand (new) - migration 0015 DOWN
-- Development convenience only. Triggers on OTHER tables go first.
-- =====================================================================

DROP TRIGGER IF EXISTS trg_appointments_notify ON hbh.appointments;
DROP TRIGGER IF EXISTS trg_invoices_notify     ON hbh.invoices;
DROP TRIGGER IF EXISTS trg_requests_notify     ON hbh.parent_requests;
DROP TRIGGER IF EXISTS trg_notes_notify        ON hbh.session_notes;
DROP TRIGGER IF EXISTS trg_reports_notify      ON hbh.progress_reports;
DROP TRIGGER IF EXISTS trg_gc_live_consent     ON hbh.guardian_children;

DROP TABLE IF EXISTS hbh.notifications;
DROP TABLE IF EXISTS hbh.consent_events;
DROP TABLE IF EXISTS hbh.consents;

DROP FUNCTION IF EXISTS hbh.trg_notify_cancelled();
DROP FUNCTION IF EXISTS hbh.trg_notify_invoice();
DROP FUNCTION IF EXISTS hbh.trg_notify_request();
DROP FUNCTION IF EXISTS hbh.trg_notify_note();
DROP FUNCTION IF EXISTS hbh.trg_notify_report();
DROP FUNCTION IF EXISTS hbh.mark_notification_read(bigint);
DROP FUNCTION IF EXISTS hbh.notify_guardians(integer, text, text, text, text, integer);
DROP FUNCTION IF EXISTS hbh.has_consent(integer, text, integer);
DROP FUNCTION IF EXISTS hbh.withdraw_consent(integer, text, integer, text);
DROP FUNCTION IF EXISTS hbh.grant_consent(integer, text, integer, text, text);
DROP FUNCTION IF EXISTS hbh.trg_live_flag_needs_consent();

DELETE FROM hbh.convention_exemptions WHERE table_name = 'consent_events';

DELETE FROM hbh.schema_migrations WHERE version = '0015';
