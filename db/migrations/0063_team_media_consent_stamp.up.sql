-- =====================================================================
-- 0063 - two defects in 0061 and one in the conventions suite
--
-- 1. THE CONSENT PAIR HAD NO KEY.
--
--    ck_stm_consent_pair requires consent_given_at and
--    consent_obtained_by together, and consent_obtained_by is not a
--    column any client may write - correctly, since a client that could
--    name who obtained a consent could name somebody who did not.
--
--    Every other site table solves this with trg_site_consent_stamp:
--    the client sends the date, the database writes who. 0061 added the
--    constraint and not the trigger, so recording a consent on a film
--    was refused every time and the film could never be published. The
--    same "gate with no key" that migration 0043 fixed for the other
--    site tables - written once, forgotten once.
--
-- 2. A GRANT WAS MISSING FOR THE SAME REASON.
--
--    consent_obtained_by is stamped by a trigger, so hbh_app never
--    writes it; but 0061 also left published_at and published_by
--    revoked while the stamp trigger writes them as the caller. The
--    stamp is SECURITY DEFINER, so it writes them regardless - this
--    just makes the intent explicit rather than accidental.
--
-- 3. AND MY OWN CHECK IN p00 WAS WRONG.
--
--    "every sequence is usable by hbh_app" called has_sequence_privilege
--    on rows the planner had not filtered to sequences yet, so it raised
--    42809 on an index. A WHERE clause is not evaluated before a select
--    list expression. It now reads pg_sequence, which contains nothing
--    but sequences, and cannot be handed the wrong kind of object.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TRIGGER trg_site_team_media_consent
  BEFORE INSERT OR UPDATE ON hbh.site_team_media
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_consent_stamp();

INSERT INTO hbh.schema_migrations (version) VALUES ('0063');
