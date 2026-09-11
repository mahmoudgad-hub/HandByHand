-- =====================================================================
-- Hand By Hand (new) - API phase 4 fixture teardown
--
-- Runs BEFORE the fixture as well as after it.
--
-- Nothing here needs an append-only trigger disabled: this fixture
-- creates no history rows. The catalogue rows the suite creates are
-- named A4-, and they are removed by name rather than by "everything
-- created recently" - a teardown that guesses eventually removes
-- somebody else's row.
-- =====================================================================

\set ON_ERROR_STOP on

-- The therapist the mask group needs. Removed by the exact mobile this
-- fixture writes and not by a name or a prefix: a therapist is a person, and
-- a LIKE over people is how a cleanup reaches into somebody else's row. The
-- caseload and services rows that could point at them go first.
DELETE FROM hbh.caseload           WHERE therapist_id IN
  (SELECT therapist_id FROM hbh.therapists WHERE mobile = '+201500000049');
DELETE FROM hbh.therapist_services WHERE therapist_id IN
  (SELECT therapist_id FROM hbh.therapists WHERE mobile = '+201500000049');
DELETE FROM hbh.therapists          WHERE mobile = '+201500000049';

DELETE FROM hbh.cameras          WHERE code LIKE 'A4-%';
DELETE FROM hbh.service_packages WHERE code LIKE 'A4-%';
DELETE FROM hbh.activity_library WHERE code LIKE 'A4-%';
DELETE FROM hbh.rooms            WHERE code LIKE 'A4-%';
DELETE FROM hbh.services         WHERE code LIKE 'A4-%';

DELETE FROM hbh.guardian_children gc
 USING hbh.children c WHERE c.child_id = gc.child_id AND c.child_no LIKE 'A4-%';
DELETE FROM hbh.children WHERE child_no LIKE 'A4-%';

DELETE FROM hbh.guardians g
 USING hbh.users u WHERE u.user_id = g.user_id AND u.username LIKE 'a4\_%';
-- Consents and notifications (migration 0015). The consent trigger
-- creates rows here as a side effect of the fixture, and notifications
-- hold a foreign key to the user - so both must go before the user does.
ALTER TABLE hbh.consent_events DISABLE TRIGGER ALL;
DELETE FROM hbh.consent_events ce
 USING hbh.consents cn, hbh.guardians g, hbh.users u
 WHERE cn.consent_id = ce.consent_id AND g.guardian_id = cn.guardian_id
   AND u.user_id = g.user_id AND u.username LIKE 'a4_%';
ALTER TABLE hbh.consent_events ENABLE TRIGGER ALL;

DELETE FROM hbh.consents cn
 USING hbh.guardians g, hbh.users u
 WHERE g.guardian_id = cn.guardian_id AND u.user_id = g.user_id
   AND u.username LIKE 'a4_%';

DELETE FROM hbh.notifications n
 USING hbh.users u WHERE u.user_id = n.user_id AND u.username LIKE 'a4_%';

DELETE FROM hbh.user_roles ur
 USING hbh.users u WHERE u.user_id = ur.user_id AND u.username LIKE 'a4\_%';
DELETE FROM hbh.auth_sessions s
 USING hbh.users u WHERE u.user_id = s.user_id AND u.username LIKE 'a4\_%';
DELETE FROM hbh.otp_codes o
 USING hbh.users u WHERE u.user_id = o.user_id AND u.username LIKE 'a4\_%';
DELETE FROM hbh.users WHERE username LIKE 'a4\_%';
