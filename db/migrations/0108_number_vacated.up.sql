-- =====================================================================
-- Hand By Hand (new) - migration 0108: this number was vacated, and
-- this file exists to say so.
--
-- IT CHANGES NOTHING. There is no DDL below, no data, no grant. Its
-- whole purpose is to occupy 0108 so the ledger has no hole in it.
--
-- WHY THERE WAS A HOLE. Three migrations were written as 0106, 0107 and
-- 0108 - the outbox template variables, the enrolment assessment
-- message, and the WhatsApp consent. Before any of them was applied,
-- `db.sh migrate` refused to run at all: another session was claiming
-- 0106 and 0107 for its own work at the same moment, and the duplicate
-- guard stops everything before it runs anything. That guard did exactly
-- what it was added for.
--
-- So these three were renumbered to 0109, 0110 and 0111, and the other
-- session's three settled at 0112, 0113 and 0114. Nobody took 0108, and
-- nothing was ever applied under it.
--
-- WHY A GAP IS NOT ALLOWED TO JUST SIT THERE, in the words of the check
-- that caught this (tests/db/p00_verify.sql): a migration applied
-- without recording its number leaves a gap where its number should be,
-- so a gap is the symptom that check exists to find. A number reserved
-- and never used produces the identical symptom, and the next person to
-- read the ledger has no way to tell the two apart - "a lost migration"
-- and "a number somebody skipped" look the same from here. The check
-- cannot distinguish them either, which is why it refuses both and says
-- the honest fix is a migration that takes the number and explains
-- itself.
--
-- WHAT THIS IS NOT. It is not a placeholder to be filled in later. If
-- 0108 is ever edited to do real work, it will be skipped in silence on
-- every database that already recorded it - which is the trap in the
-- header of the duplicate-number rule, reached by a different road. A
-- new change takes a new number.
--
-- AND THE RULE THIS PAID FOR, already written in CLAUDE.md and now
-- demonstrated: when more than one person is working on the schema,
-- RESERVE THE NUMBER BEFORE WRITING THE FILE. Renumbering after the fact
-- is cheap for the files and leaves this behind.
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0108') THEN
    RAISE EXCEPTION 'migration 0108 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0107') THEN
    RAISE EXCEPTION 'migration 0107 must be applied first';
  END IF;
END
$guard$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0108');
