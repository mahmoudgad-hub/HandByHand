-- =====================================================================
-- 0076 - the consent the gate in 0074 was actually looking for
--
-- 0074 refuses a child's photograph unless a consent is on record, and
-- asked for consent_type = 'PHOTO'. There is no such type. The schema
-- has had 'PHOTO_USE' since consents were built, and hbh.grant_consent
-- knows it by name: it is one of the two types classed as being ABOUT A
-- CHILD, so it requires a child_id and refuses one for a child the
-- guardian has no active link to.
--
-- I INVENTED A NAME FOR SOMETHING THAT ALREADY HAD ONE, and the result
-- was a gate with no key: 'PHOTO' with a child_id is refused by
-- grant_consent ("PHOTO is a consent about the guardian and takes no
-- child"), and without a child_id it could never match the trigger's
-- WHERE. Every photograph would have been refused, and the message
-- would have told a receptionist to record a consent that no function
-- in this schema will write.
--
-- It is the same defect as ck_stm_consent_pair in 0061 - a constraint
-- naming a state nothing could produce - and the same as HB061 being
-- taken when 0052 wanted it. Both times the answer was to read what
-- exists before adding to it.
--
-- The end-to-end test is what found it. The trigger was proven to
-- refuse without consent, which looked like the gate working; it was
-- the step AFTER - recording the consent and expecting the upload to go
-- through - that showed the refusal was unconditional.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE OR REPLACE FUNCTION hbh.trg_child_photo_needs_consent()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $fn$
BEGIN
  -- Only on the way IN to being a portrait. A photograph that is
  -- already stored and is being renamed, archived or approved must not
  -- be re-checked: consent can be withdrawn, and withdrawing it has to
  -- leave the record archivable rather than frozen in place.
  IF NEW.purpose IS DISTINCT FROM 'PROFILE_PHOTO'
     OR (TG_OP = 'UPDATE' AND OLD.purpose IS NOT DISTINCT FROM 'PROFILE_PHOTO') THEN
    RETURN NEW;
  END IF;

  -- SECURITY DEFINER because the answer must be "has anybody with
  -- parental authority agreed", not "has anybody I am allowed to see
  -- agreed". A receptionist who cannot read a guardian row would
  -- otherwise get a refusal that reads as a missing consent.
  --
  -- The guardian_children join is not redundant with grant_consent's
  -- own check. That one holds at the moment the consent is recorded;
  -- this one holds at the moment the picture is stored, and a guardian
  -- whose link has since been archived is no longer the person whose
  -- agreement this is.
  IF NOT EXISTS (
    SELECT 1
    FROM   hbh.consents c
    JOIN   hbh.guardian_children gc ON gc.guardian_id = c.guardian_id
                                   AND gc.child_id    = c.child_id
    WHERE  c.child_id     = NEW.child_id
      AND  c.consent_type = 'PHOTO_USE'
      AND  c.granted_flg
      AND  c.active_flg
      AND  c.withdrawn_at IS NULL
      AND  gc.active_flg
  ) THEN
    RAISE EXCEPTION
      'a photograph of child % needs a recorded PHOTO_USE consent', NEW.child_id
      USING ERRCODE = 'HB123',
            HINT = 'record it with hbh.grant_consent(guardian_id, ''PHOTO_USE'', '
                   'child_id) from a guardian linked to this child';
  END IF;

  RETURN NEW;
END;
$fn$;

INSERT INTO hbh.schema_migrations (version) VALUES ('0076');
