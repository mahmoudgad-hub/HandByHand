-- Hand By Hand (new) - migration 0022 DOWN. Development only.
DROP TABLE    IF EXISTS hbh.waiting_list;
DROP FUNCTION IF EXISTS hbh.release_expired_offers();
DROP FUNCTION IF EXISTS hbh.accept_offer(integer);
DROP FUNCTION IF EXISTS hbh.offer_slot(integer, integer, integer);
DROP FUNCTION IF EXISTS hbh.add_to_waiting_list(integer, integer, integer, smallint, date, date, smallint[], time, time, text);
DROP FUNCTION IF EXISTS hbh.waiting_candidates(integer, integer, timestamptz, timestamptz, integer, integer);
DROP FUNCTION IF EXISTS hbh.trg_wait_status();
DROP FUNCTION IF EXISTS hbh.legal_wait_transition(text, text);
DROP FUNCTION IF EXISTS hbh.cancel_recurrence(bigint, timestamptz, text);
DROP FUNCTION IF EXISTS hbh.book_recurring(integer, integer, integer, integer, integer, integer, timestamptz, timestamptz, smallint, smallint, text);
DROP INDEX    IF EXISTS hbh.ix_appointments_recurrence;
ALTER TABLE hbh.appointments DROP CONSTRAINT IF EXISTS ck_appointments_recurrence;
ALTER TABLE hbh.appointments DROP COLUMN IF EXISTS recurrence_index, DROP COLUMN IF EXISTS recurrence_group_id;
DROP SEQUENCE IF EXISTS hbh.seq_recurrence_group;
DELETE FROM hbh.sys_params WHERE param_code = 'WAITLIST_OFFER_HOURS';
DELETE FROM hbh.schema_migrations WHERE version = '0022';
