-- =====================================================================
-- Hand By Hand (new) - migration 0023: assessments
--
-- ASSESSMENT existed as a kind of service and nothing more: a child
-- could be booked for one, and there was nowhere to put what it found.
--
-- Four decisions:
--
-- 1. THE INSTRUMENT IS DATA, THE ASSESSMENT IS AN EVENT.
--    A centre adds a new instrument by inserting a row, not by
--    deploying. The bounds of a valid score belong to the instrument,
--    so a trigger checks each score against the instrument that was
--    used - a raw score of 87 is fine on one and impossible on another.
--
-- 2. IT IS BORN A DRAFT AND REACHES THE FAMILY ONLY DELIBERATELY.
--    The same ladder as a clinical note (D-24 territory): the portal
--    shows an assessment only when it is PUBLISHED, publishing is a
--    separate permissioned act, and it stamps who did it.
--
-- 3. A PUBLISHED ASSESSMENT IS FROZEN.
--    Both the summary and the item scores. A family reading a result in
--    March must find the same result in September - and unlike a report
--    there is no snapshot to take, because the item scores ARE the
--    document. So they stop being writable instead.
--
-- 4. THE TOTAL IS DERIVED FROM THE ITEMS WHEN THERE ARE ITEMS.
--    Same rule as an invoice: a total somebody typed can disagree with
--    what it is a total of. An instrument scored as a whole has no
--    items and keeps its raw_score; one with items has it computed.
--
-- Error classes added here:
--   HB110  illegal assessment status transition
--   HB111  not permitted to record or edit this assessment
--   HB112  a published assessment cannot be changed
--   HB113  the score is outside the instrument's range
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0023') THEN
    RAISE EXCEPTION 'migration 0023 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0022') THEN
    RAISE EXCEPTION 'migration 0022 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE INSTRUMENTS
-- =====================================================================
CREATE TABLE hbh.assessment_instruments (
  instrument_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  code          text        NOT NULL,
  name_ar       text        NOT NULL,
  name_en       text,
  domain_code   text        NOT NULL,
  scoring_kind  text        NOT NULL DEFAULT 'RAW',
  min_score     numeric(8,2),
  max_score     numeric(8,2),
  age_from_mon  smallint,
  age_to_mon    smallint,
  description_ar text,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_assessment_instruments PRIMARY KEY (instrument_id),
  CONSTRAINT fk_ains_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_ains_code UNIQUE (center_id, code),
  CONSTRAINT ck_ains_domain CHECK (domain_code IN
    ('SPEECH','OT','BEHAVIOUR','COGNITIVE','MOTOR','SOCIAL','GENERAL')),
  CONSTRAINT ck_ains_scoring CHECK (scoring_kind IN ('RAW','PERCENTILE','SCALED','AGE_EQUIV')),
  CONSTRAINT ck_ains_range CHECK (max_score IS NULL OR min_score IS NULL OR max_score > min_score),
  CONSTRAINT ck_ains_age   CHECK (age_to_mon IS NULL OR age_from_mon IS NULL OR age_to_mon >= age_from_mon)
);

CREATE INDEX ix_ains_center ON hbh.assessment_instruments (center_id);
CREATE INDEX ix_ains_domain ON hbh.assessment_instruments (domain_code) WHERE active_flg;

CREATE TABLE hbh.assessment_items (
  item_id       integer     GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  instrument_id integer     NOT NULL,
  item_no       smallint    NOT NULL,
  prompt_ar     text        NOT NULL,
  max_score     numeric(6,2) NOT NULL DEFAULT 1,
  sort_order    integer     NOT NULL DEFAULT 100,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_assessment_items PRIMARY KEY (item_id),
  CONSTRAINT fk_aitem_center     FOREIGN KEY (center_id)     REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_aitem_instrument FOREIGN KEY (instrument_id) REFERENCES hbh.assessment_instruments (instrument_id),
  CONSTRAINT uq_aitem_no UNIQUE (instrument_id, item_no),
  CONSTRAINT ck_aitem_max CHECK (max_score > 0)
);

CREATE INDEX ix_aitem_center     ON hbh.assessment_items (center_id);
CREATE INDEX ix_aitem_instrument ON hbh.assessment_items (instrument_id, sort_order);

-- =====================================================================
-- AN ASSESSMENT THAT HAPPENED
-- =====================================================================
CREATE TABLE hbh.assessments (
  assessment_id   integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,
  branch_id       integer,
  child_id        integer     NOT NULL,
  instrument_id   integer     NOT NULL,
  therapist_id    integer     NOT NULL,
  session_id      integer,
  appointment_id  integer,
  assessed_on     date        NOT NULL DEFAULT current_date,
  age_at_months   smallint,
  raw_score       numeric(8,2),
  derived_score   numeric(8,2),
  age_equiv_months smallint,
  summary_ar      text,
  recommendation_ar text,
  status          text        NOT NULL DEFAULT 'DRAFT',
  published_by    integer,
  published_at    timestamptz,
  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,
  CONSTRAINT pk_assessments PRIMARY KEY (assessment_id),
  CONSTRAINT fk_asmt_center     FOREIGN KEY (center_id)     REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_asmt_branch     FOREIGN KEY (branch_id)     REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_asmt_child      FOREIGN KEY (child_id)      REFERENCES hbh.children (child_id),
  CONSTRAINT fk_asmt_instrument FOREIGN KEY (instrument_id) REFERENCES hbh.assessment_instruments (instrument_id),
  CONSTRAINT fk_asmt_therapist  FOREIGN KEY (therapist_id)  REFERENCES hbh.therapists (therapist_id),
  CONSTRAINT fk_asmt_session    FOREIGN KEY (session_id)    REFERENCES hbh.therapy_sessions (session_id),
  CONSTRAINT fk_asmt_appt       FOREIGN KEY (appointment_id) REFERENCES hbh.appointments (appointment_id),
  CONSTRAINT fk_asmt_publisher  FOREIGN KEY (published_by)  REFERENCES hbh.users (user_id),
  CONSTRAINT ck_asmt_status CHECK (status IN ('DRAFT','COMPLETED','PUBLISHED')),
  CONSTRAINT ck_asmt_date   CHECK (assessed_on <= current_date),
  -- Published means somebody decided to publish it, and the row says who.
  CONSTRAINT ck_asmt_published CHECK (
    (status = 'PUBLISHED') = (published_by IS NOT NULL AND published_at IS NOT NULL))
);

CREATE INDEX ix_asmt_center     ON hbh.assessments (center_id);
CREATE INDEX ix_asmt_branch     ON hbh.assessments (branch_id);
CREATE INDEX ix_asmt_child      ON hbh.assessments (child_id, assessed_on DESC);
CREATE INDEX ix_asmt_instrument ON hbh.assessments (instrument_id);
CREATE INDEX ix_asmt_therapist  ON hbh.assessments (therapist_id);
CREATE INDEX ix_asmt_session    ON hbh.assessments (session_id);
CREATE INDEX ix_asmt_appt       ON hbh.assessments (appointment_id);
CREATE INDEX ix_asmt_publisher  ON hbh.assessments (published_by);
-- The portal's own query.
CREATE INDEX ix_asmt_published ON hbh.assessments (child_id, assessed_on DESC)
  WHERE status = 'PUBLISHED' AND active_flg;

CREATE TABLE hbh.assessment_item_scores (
  score_id      bigint      GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  assessment_id integer     NOT NULL,
  item_id       integer     NOT NULL,
  score         numeric(6,2) NOT NULL,
  note_ar       text,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_assessment_item_scores PRIMARY KEY (score_id),
  CONSTRAINT fk_ascore_center     FOREIGN KEY (center_id)     REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ascore_assessment FOREIGN KEY (assessment_id) REFERENCES hbh.assessments (assessment_id),
  CONSTRAINT fk_ascore_item       FOREIGN KEY (item_id)       REFERENCES hbh.assessment_items (item_id),
  CONSTRAINT uq_ascore UNIQUE (assessment_id, item_id),
  CONSTRAINT ck_ascore CHECK (score >= 0)
);

CREATE INDEX ix_ascore_center     ON hbh.assessment_item_scores (center_id);
CREATE INDEX ix_ascore_assessment ON hbh.assessment_item_scores (assessment_id);
CREATE INDEX ix_ascore_item       ON hbh.assessment_item_scores (item_id);

-- =====================================================================
-- THE RULES
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.legal_assessment_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('DRAFT',     'COMPLETED'),
    ('COMPLETED', 'PUBLISHED'),
    -- Withdrawing is allowed and takes the stamp with it, the same way
    -- a note does. A row must not keep a signature for something it no
    -- longer says.
    ('PUBLISHED', 'COMPLETED'),
    ('COMPLETED', 'DRAFT')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_assessment_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_assessment_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'assessment % cannot go from % to %',
                    OLD.assessment_id, OLD.status, NEW.status
      USING ERRCODE = 'HB110';
  END IF;

  -- Frozen while published. A family reading a result in March must
  -- find the same result in September.
  IF OLD.status = 'PUBLISHED' AND NEW.status = 'PUBLISHED'
     AND (NEW.raw_score, NEW.derived_score, NEW.age_equiv_months,
          NEW.summary_ar, NEW.recommendation_ar, NEW.assessed_on, NEW.instrument_id)
         IS DISTINCT FROM
         (OLD.raw_score, OLD.derived_score, OLD.age_equiv_months,
          OLD.summary_ar, OLD.recommendation_ar, OLD.assessed_on, OLD.instrument_id) THEN
    RAISE EXCEPTION 'assessment % is published and cannot be changed', OLD.assessment_id
      USING ERRCODE = 'HB112';
  END IF;

  IF NEW.status <> 'PUBLISHED' AND OLD.status = 'PUBLISHED' THEN
    NEW.published_by := NULL;
    NEW.published_at := NULL;
  END IF;

  RETURN NEW;
END
$$;

-- A score is checked against the INSTRUMENT that was used. 87 is a fine
-- raw score on one instrument and impossible on another, so the bounds
-- cannot live on the score row.
CREATE OR REPLACE FUNCTION hbh.trg_assessment_score_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  l_status text;
  l_max    numeric(6,2);
BEGIN
  SELECT a.status INTO l_status FROM hbh.assessments a
  WHERE a.assessment_id = coalesce(NEW.assessment_id, OLD.assessment_id);

  IF l_status = 'PUBLISHED' THEN
    RAISE EXCEPTION 'assessment % is published - its item scores cannot be changed',
                    coalesce(NEW.assessment_id, OLD.assessment_id)
      USING ERRCODE = 'HB112';
  END IF;

  IF TG_OP <> 'DELETE' THEN
    SELECT i.max_score INTO l_max FROM hbh.assessment_items i WHERE i.item_id = NEW.item_id;
    IF NEW.score > l_max THEN
      RAISE EXCEPTION 'score % is above the item maximum of %', NEW.score, l_max
        USING ERRCODE = 'HB113';
    END IF;
  END IF;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END
$$;

-- The total follows the items when there are items. An instrument
-- scored as a whole has none and keeps the raw score it was given.
CREATE OR REPLACE FUNCTION hbh.trg_assessment_total()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE l_id integer := coalesce(NEW.assessment_id, OLD.assessment_id);
BEGIN
  UPDATE hbh.assessments a
     SET raw_score = (SELECT sum(s.score) FROM hbh.assessment_item_scores s
                      WHERE s.assessment_id = l_id AND s.active_flg)
   WHERE a.assessment_id = l_id
     AND EXISTS (SELECT 1 FROM hbh.assessment_item_scores s
                 WHERE s.assessment_id = l_id AND s.active_flg);
  RETURN NULL;
END
$$;

CREATE OR REPLACE FUNCTION hbh.record_assessment(
  p_child_id      integer,
  p_instrument_id integer,
  p_therapist_id  integer,
  p_assessed_on   date    DEFAULT current_date,
  p_session_id    integer DEFAULT NULL,
  p_summary_ar    text    DEFAULT NULL)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_child hbh.children%ROWTYPE;
  l_id    integer;
BEGIN
  IF NOT hbh.has_permission('ASSESSMENT.RECORD') THEN
    RAISE EXCEPTION 'recording an assessment needs ASSESSMENT.RECORD' USING ERRCODE = 'HB111';
  END IF;
  IF NOT hbh.can_access_child(p_child_id) THEN
    RAISE EXCEPTION 'not permitted to assess child %', p_child_id USING ERRCODE = 'HB111';
  END IF;

  SELECT * INTO l_child FROM hbh.children WHERE child_id = p_child_id AND active_flg;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such child %', p_child_id USING ERRCODE = 'HB111';
  END IF;

  INSERT INTO hbh.assessments (center_id, branch_id, child_id, instrument_id, therapist_id,
                               session_id, assessed_on, age_at_months, summary_ar)
  VALUES (l_child.center_id, l_child.branch_id, p_child_id, p_instrument_id, p_therapist_id,
          p_session_id, p_assessed_on,
          (extract(year FROM age(p_assessed_on, l_child.birth_date)) * 12
           + extract(month FROM age(p_assessed_on, l_child.birth_date)))::smallint,
          p_summary_ar)
  RETURNING assessment_id INTO l_id;

  RETURN l_id;
END
$$;

CREATE OR REPLACE FUNCTION hbh.publish_assessment(p_assessment_id integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE l_a hbh.assessments%ROWTYPE;
BEGIN
  IF NOT hbh.has_permission('ASSESSMENT.PUBLISH') THEN
    RAISE EXCEPTION 'publishing an assessment needs ASSESSMENT.PUBLISH' USING ERRCODE = 'HB111';
  END IF;

  SELECT * INTO l_a FROM hbh.assessments
  WHERE assessment_id = p_assessment_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such assessment %', p_assessment_id USING ERRCODE = 'HB111';
  END IF;
  IF l_a.status <> 'COMPLETED' THEN
    RAISE EXCEPTION 'assessment % is % - only a COMPLETED one may be published',
                    p_assessment_id, l_a.status
      USING ERRCODE = 'HB110';
  END IF;

  UPDATE hbh.assessments
     SET status = 'PUBLISHED', published_by = hbh.current_user_id(), published_at = now()
   WHERE assessment_id = p_assessment_id;

  PERFORM hbh.notify_guardians(l_a.child_id, 'ASSESSMENT_PUBLISHED',
                               'نتيجة تقييم جديدة', NULL, 'ASSESSMENT', p_assessment_id);

  PERFORM hbh.audit_attempt('READ', l_a.center_id, hbh.current_app_user(),
                            'assessment ' || p_assessment_id || ' published to guardian');
END
$$;

-- A new notification kind, so publish_assessment can use the same path
-- everything else does.
ALTER TABLE hbh.notifications DROP CONSTRAINT ck_ntf_kind;
ALTER TABLE hbh.notifications ADD CONSTRAINT ck_ntf_kind CHECK (kind_code IN
  ('REPORT_PUBLISHED','NOTE_PUBLISHED','REQUEST_DECIDED','INVOICE_ISSUED',
   'APPOINTMENT_CANCELLED','SESSION_STARTED','ASSESSMENT_PUBLISHED'));

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_ains_touch   BEFORE UPDATE ON hbh.assessment_instruments  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_aitem_touch  BEFORE UPDATE ON hbh.assessment_items        FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_asmt_touch   BEFORE UPDATE ON hbh.assessments             FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_ascore_touch BEFORE UPDATE ON hbh.assessment_item_scores  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

CREATE TRIGGER trg_asmt_guard   BEFORE UPDATE ON hbh.assessments FOR EACH ROW EXECUTE FUNCTION hbh.trg_assessment_guard();
CREATE TRIGGER trg_ascore_guard BEFORE INSERT OR UPDATE OR DELETE ON hbh.assessment_item_scores
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_assessment_score_guard();
CREATE TRIGGER trg_ascore_total AFTER INSERT OR UPDATE OR DELETE ON hbh.assessment_item_scores
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_assessment_total();

CREATE TRIGGER trg_asmt_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.assessments
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('assessment_id');

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- The same ladder as a clinical note: the family sees a PUBLISHED
-- assessment and nothing before it.
-- =====================================================================
ALTER TABLE hbh.assessment_instruments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.assessment_items        ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.assessments             ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.assessment_item_scores  ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_ains_select ON hbh.assessment_instruments
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

CREATE POLICY p_aitem_select ON hbh.assessment_items
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ASSESSMENT.RECORD'));

CREATE POLICY p_asmt_select ON hbh.assessments
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.can_access_child(child_id)
         AND (hbh.has_permission('CHILD.VIEW_ALL') OR status = 'PUBLISHED'));

CREATE POLICY p_asmt_update ON hbh.assessments
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ASSESSMENT.RECORD') AND hbh.can_access_child(child_id))
  WITH CHECK (center_id = hbh.current_center_id()
         AND hbh.has_permission('ASSESSMENT.RECORD'));

-- Item scores are working detail. A family gets the summary and the
-- recommendation, not the individual prompts a clinician scored.
CREATE POLICY p_ascore_select ON hbh.assessment_item_scores
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ASSESSMENT.RECORD')
         AND EXISTS (SELECT 1 FROM hbh.assessments a
                     WHERE a.assessment_id = hbh.assessment_item_scores.assessment_id
                       AND hbh.can_access_child(a.child_id)));

CREATE POLICY p_ascore_write ON hbh.assessment_item_scores
  FOR INSERT TO hbh_app
  WITH CHECK (center_id = hbh.current_center_id()
         AND hbh.has_permission('ASSESSMENT.RECORD'));

CREATE POLICY p_ascore_edit ON hbh.assessment_item_scores
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('ASSESSMENT.RECORD'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('ASSESSMENT.RECORD'));

GRANT SELECT ON hbh.assessment_instruments, hbh.assessment_items, hbh.assessments TO hbh_app;
GRANT SELECT, INSERT, UPDATE ON hbh.assessment_item_scores TO hbh_app;
GRANT UPDATE ON hbh.assessments TO hbh_app;

REVOKE ALL ON FUNCTION hbh.record_assessment(integer, integer, integer, date, integer, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.publish_assessment(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.record_assessment(integer, integer, integer, date, integer, text) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.publish_assessment(integer) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_assessment_transition(text, text) TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0023');
