-- =====================================================================
-- Hand By Hand (new) - migration 0019: the satisfaction question
--
-- Zero to ten, a free-text box under it, shown to a parent either every
-- so often or after a particular thing happened. The centre must be
-- able to change WHEN it is asked, and the wording, at any time and
-- without a deployment - so all of it is rows, and there is an admin
-- screen over those rows rather than a constant in the code.
--
-- Three things this migration is careful about:
--
-- 1. WHEN TO ASK IS CONFIGURATION, NOT CODE.
--    trigger_kind is PERIOD or ACTION; period_days, action_code,
--    cooldown_days and the two question texts are all columns. Changing
--    "ask after every completed session" to "ask every 90 days" is an
--    UPDATE.
--
-- 2. NOT ASKING IS AS IMPORTANT AS ASKING.
--    A dismissal is recorded, not forgotten. Without that the same
--    question reappears on every screen refresh, and a survey that
--    nags is a survey nobody answers honestly.
--
-- 3. THE SCORE IS NOT AN AVERAGE.
--    NPS is promoters minus detractors as percentages of respondents,
--    with 7 and 8 counting for neither. A mean of 0-10 is a different
--    number that looks like the same one, so the view computes the real
--    thing and the screen has nothing to get wrong.
--
-- Error classes added here:
--   HB093  the score is outside 0-10
--   HB094  this survey is not currently due for this user
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0019') THEN
    RAISE EXCEPTION 'migration 0019 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0018') THEN
    RAISE EXCEPTION 'migration 0018 must be applied first';
  END IF;
END
$guard$;

-- =====================================================================
-- THE CONFIGURATION
-- =====================================================================
CREATE TABLE hbh.nps_surveys (
  survey_id        integer     GENERATED ALWAYS AS IDENTITY,
  center_id        integer     NOT NULL,
  code             text        NOT NULL,
  name_ar          text        NOT NULL,
  question_ar      text        NOT NULL,
  followup_question_ar text    NOT NULL DEFAULT 'ما الذي يجعل تقييمك أفضل؟',
  audience         text        NOT NULL DEFAULT 'GUARDIAN',

  -- PERIOD: ask again once period_days have passed.
  -- ACTION: ask once something specific has happened since last time.
  trigger_kind     text        NOT NULL DEFAULT 'PERIOD',
  period_days      integer,
  action_code      text,

  -- After ANY answer or dismissal, stay quiet this long. This is what
  -- stops the question reappearing on every screen refresh.
  cooldown_days    integer     NOT NULL DEFAULT 30,

  starts_on        date,
  ends_on          date,
  active_flg       boolean     NOT NULL DEFAULT true,
  deleted_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at       timestamptz,
  updated_by       text,
  CONSTRAINT pk_nps_surveys PRIMARY KEY (survey_id),
  CONSTRAINT fk_nps_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT uq_nps_code UNIQUE (center_id, code),
  CONSTRAINT ck_nps_audience CHECK (audience IN ('GUARDIAN','STAFF','ALL')),
  CONSTRAINT ck_nps_trigger  CHECK (trigger_kind IN ('PERIOD','ACTION')),
  CONSTRAINT ck_nps_action   CHECK (action_code IS NULL OR action_code IN
    ('SESSION_COMPLETED','REPORT_PUBLISHED','INVOICE_PAID','FIRST_LOGIN')),
  -- The kind decides which column must be filled. A PERIOD survey with
  -- no period, or an ACTION survey with no action, would match nothing
  -- and never fire - silently, which is the worst way for a survey to
  -- be broken.
  CONSTRAINT ck_nps_shape CHECK (
    (trigger_kind = 'PERIOD' AND period_days IS NOT NULL AND action_code IS NULL)
    OR (trigger_kind = 'ACTION' AND action_code IS NOT NULL AND period_days IS NULL)),
  CONSTRAINT ck_nps_period   CHECK (period_days   IS NULL OR period_days   BETWEEN 1 AND 3650),
  CONSTRAINT ck_nps_cooldown CHECK (cooldown_days BETWEEN 0 AND 3650),
  CONSTRAINT ck_nps_window   CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on)
);

CREATE INDEX ix_nps_center ON hbh.nps_surveys (center_id);
CREATE INDEX ix_nps_live   ON hbh.nps_surveys (center_id, audience) WHERE active_flg;

-- =====================================================================
-- THE ANSWERS
--
-- A dismissal is a row too, with skipped_flg and no score. "They were
-- asked and said nothing" is information, and it is the only way to
-- know the cooldown should start.
-- =====================================================================
CREATE TABLE hbh.nps_responses (
  response_id   bigint      GENERATED ALWAYS AS IDENTITY,
  center_id     integer     NOT NULL,
  survey_id     integer     NOT NULL,
  user_id       integer     NOT NULL,
  score         smallint,
  comment_ar    text,
  skipped_flg   boolean     NOT NULL DEFAULT false,
  context_kind  text,
  context_id    integer,
  responded_at  timestamptz NOT NULL DEFAULT now(),
  client_ip     inet,
  active_flg    boolean     NOT NULL DEFAULT true,
  deleted_at    timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at    timestamptz,
  updated_by    text,
  CONSTRAINT pk_nps_responses PRIMARY KEY (response_id),
  CONSTRAINT fk_npsr_center FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_npsr_survey FOREIGN KEY (survey_id) REFERENCES hbh.nps_surveys (survey_id),
  CONSTRAINT fk_npsr_user   FOREIGN KEY (user_id)   REFERENCES hbh.users (user_id),
  CONSTRAINT ck_npsr_score CHECK (score IS NULL OR score BETWEEN 0 AND 10),
  -- Answered means a score; skipped means none. A row that is both, or
  -- neither, is a row nobody can count.
  CONSTRAINT ck_npsr_shape CHECK ((skipped_flg AND score IS NULL)
                               OR (NOT skipped_flg AND score IS NOT NULL)),
  CONSTRAINT ck_npsr_context CHECK ((context_kind IS NULL) = (context_id IS NULL))
);

CREATE INDEX ix_npsr_center  ON hbh.nps_responses (center_id, responded_at DESC);
CREATE INDEX ix_npsr_survey  ON hbh.nps_responses (survey_id, responded_at DESC);
-- The question nps_due asks on every page load.
CREATE INDEX ix_npsr_user    ON hbh.nps_responses (user_id, survey_id, responded_at DESC);
CREATE INDEX ix_npsr_scored  ON hbh.nps_responses (survey_id, score)
  WHERE NOT skipped_flg AND active_flg;
-- One answer per user per triggering event, so a session cannot be
-- rated twice.
CREATE UNIQUE INDEX uix_npsr_context
  ON hbh.nps_responses (survey_id, user_id, context_kind, context_id)
  WHERE context_id IS NOT NULL AND active_flg;

-- =====================================================================
-- IS THERE A QUESTION FOR THIS PERSON RIGHT NOW?
--
-- One call, on page load. Returns at most one survey - if two are due
-- the older configuration wins, because asking two satisfaction
-- questions at once is how you get an answer to neither.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.nps_due()
RETURNS TABLE (survey_id integer, code text, question_ar text,
               followup_question_ar text, context_kind text, context_id integer)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
BEGIN
  SELECT * INTO l_user FROM hbh.users u
  WHERE u.user_id = hbh.current_user_id();
  IF NOT FOUND THEN
    RETURN;  -- no identity, no question
  END IF;

  RETURN QUERY
  WITH candidate AS (
    SELECT s.*,
           (SELECT max(r.responded_at) FROM hbh.nps_responses r
            WHERE r.survey_id = s.survey_id AND r.user_id = l_user.user_id
              AND r.active_flg) AS last_asked
    FROM   hbh.nps_surveys s
    WHERE  s.active_flg
    AND    s.center_id = l_user.center_id
    AND    (s.starts_on IS NULL OR s.starts_on <= current_date)
    AND    (s.ends_on   IS NULL OR s.ends_on   >= current_date)
    AND    (s.audience = 'ALL'
            OR (s.audience = 'GUARDIAN' AND l_user.user_type = 'GUARDIAN')
            OR (s.audience = 'STAFF'    AND l_user.user_type IN ('STAFF','THERAPIST')))
  )
  SELECT c.survey_id, c.code, c.question_ar, c.followup_question_ar,
         CASE WHEN c.trigger_kind = 'ACTION' THEN c.action_code END,
         NULL::integer
  FROM   candidate c
  WHERE
    -- The cooldown applies to answers AND dismissals alike.
    (c.last_asked IS NULL
     OR c.last_asked <= now() - make_interval(days => c.cooldown_days))
  AND (
    CASE c.trigger_kind
      WHEN 'PERIOD' THEN
        c.last_asked IS NULL
        OR c.last_asked <= now() - make_interval(days => c.period_days)
      WHEN 'ACTION' THEN
        CASE c.action_code
          WHEN 'SESSION_COMPLETED' THEN EXISTS (
            SELECT 1 FROM hbh.therapy_sessions ts
            JOIN hbh.guardian_children gc ON gc.child_id = ts.child_id AND gc.active_flg
            JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id AND g.active_flg
            WHERE g.user_id = l_user.user_id
              AND ts.status = 'COMPLETED'
              AND ts.ended_at > coalesce(c.last_asked, '-infinity'::timestamptz))
          WHEN 'REPORT_PUBLISHED' THEN EXISTS (
            SELECT 1 FROM hbh.progress_reports pr
            JOIN hbh.guardian_children gc ON gc.child_id = pr.child_id AND gc.active_flg
            JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id AND g.active_flg
            WHERE g.user_id = l_user.user_id
              AND pr.status = 'PUBLISHED'
              AND pr.published_at > coalesce(c.last_asked, '-infinity'::timestamptz))
          WHEN 'INVOICE_PAID' THEN EXISTS (
            SELECT 1 FROM hbh.invoices i
            JOIN hbh.guardian_children gc ON gc.child_id = i.child_id AND gc.active_flg
            JOIN hbh.guardians g ON g.guardian_id = gc.guardian_id AND g.active_flg
            WHERE g.user_id = l_user.user_id
              AND i.status = 'PAID'
              AND i.updated_at > coalesce(c.last_asked, '-infinity'::timestamptz))
          WHEN 'FIRST_LOGIN' THEN c.last_asked IS NULL
          ELSE false
        END
      ELSE false
    END)
  ORDER BY c.survey_id
  LIMIT 1;
END
$$;

-- =====================================================================
-- ANSWERING, AND DECLINING TO
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.submit_nps(
  p_survey_id    integer,
  p_score        smallint,
  p_comment_ar   text    DEFAULT NULL,
  p_context_kind text    DEFAULT NULL,
  p_context_id   integer DEFAULT NULL,
  p_client_ip    inet    DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_id   bigint;
BEGIN
  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = hbh.current_user_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'an answer needs an identity' USING ERRCODE = 'HB092';
  END IF;

  IF p_score IS NULL OR p_score < 0 OR p_score > 10 THEN
    RAISE EXCEPTION 'the score must be between 0 and 10, not %', p_score
      USING ERRCODE = 'HB093';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM hbh.nps_surveys s
                 WHERE s.survey_id = p_survey_id AND s.active_flg
                   AND s.center_id = l_user.center_id) THEN
    RAISE EXCEPTION 'survey % is not available', p_survey_id USING ERRCODE = 'HB094';
  END IF;

  INSERT INTO hbh.nps_responses (center_id, survey_id, user_id, score, comment_ar,
                                 context_kind, context_id, client_ip)
  VALUES (l_user.center_id, p_survey_id, l_user.user_id, p_score, p_comment_ar,
          p_context_kind, p_context_id, p_client_ip)
  RETURNING response_id INTO l_id;

  RETURN l_id;
END
$$;

-- Recorded, not forgotten. Without this the same question reappears on
-- every screen refresh.
CREATE OR REPLACE FUNCTION hbh.skip_nps(
  p_survey_id    integer,
  p_context_kind text    DEFAULT NULL,
  p_context_id   integer DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_user hbh.users%ROWTYPE;
  l_id   bigint;
BEGIN
  SELECT * INTO l_user FROM hbh.users u WHERE u.user_id = hbh.current_user_id();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'a dismissal needs an identity' USING ERRCODE = 'HB092';
  END IF;

  INSERT INTO hbh.nps_responses (center_id, survey_id, user_id, skipped_flg,
                                 context_kind, context_id)
  VALUES (l_user.center_id, p_survey_id, l_user.user_id, true, p_context_kind, p_context_id)
  RETURNING response_id INTO l_id;

  RETURN l_id;
END
$$;

-- =====================================================================
-- THE NUMBER, COMPUTED ONCE
--
-- NPS is promoters minus detractors as PERCENTAGES of the people who
-- answered - 7 and 8 count for neither. A mean of 0-10 is a different
-- number that looks like the same one, so the screen is handed the real
-- thing and has nothing to get wrong.
-- =====================================================================
CREATE VIEW hbh.v_nps_summary
WITH (security_invoker = true)
AS
SELECT s.survey_id,
       s.center_id,
       s.code,
       s.name_ar,
       s.trigger_kind,
       s.active_flg,
       count(r.response_id) FILTER (WHERE NOT r.skipped_flg)              AS answered_cnt,
       count(r.response_id) FILTER (WHERE r.skipped_flg)                  AS skipped_cnt,
       count(r.response_id) FILTER (WHERE r.score >= 9)                   AS promoters,
       count(r.response_id) FILTER (WHERE r.score BETWEEN 7 AND 8)        AS passives,
       count(r.response_id) FILTER (WHERE r.score <= 6
                                      AND NOT r.skipped_flg)              AS detractors,
       CASE WHEN count(r.response_id) FILTER (WHERE NOT r.skipped_flg) = 0 THEN NULL
            ELSE round(
              100.0 * (count(r.response_id) FILTER (WHERE r.score >= 9)
                     - count(r.response_id) FILTER (WHERE r.score <= 6 AND NOT r.skipped_flg))
              / count(r.response_id) FILTER (WHERE NOT r.skipped_flg), 0)
       END                                                                AS nps,
       round(avg(r.score) FILTER (WHERE NOT r.skipped_flg), 2)            AS mean_score,
       max(r.responded_at)                                                AS last_response_at
FROM   hbh.nps_surveys s
LEFT   JOIN hbh.nps_responses r ON r.survey_id = s.survey_id AND r.active_flg
GROUP  BY s.survey_id, s.center_id, s.code, s.name_ar, s.trigger_kind, s.active_flg;

COMMENT ON VIEW hbh.v_nps_summary IS
  'NPS per survey: promoters minus detractors as percentages of respondents. security_invoker=true so the caller policies apply.';

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_nps_touch  BEFORE UPDATE ON hbh.nps_surveys   FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_npsr_touch BEFORE UPDATE ON hbh.nps_responses FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

-- The configuration is audited: "who changed when we ask, and when"
-- is a question somebody will have.
CREATE TRIGGER trg_nps_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.nps_surveys
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('survey_id');

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
ALTER TABLE hbh.nps_surveys   ENABLE ROW LEVEL SECURITY;
ALTER TABLE hbh.nps_responses ENABLE ROW LEVEL SECURITY;

-- Everyone in the centre may READ the survey definition - the portal
-- needs the wording to display it.
CREATE POLICY p_nps_select ON hbh.nps_surveys
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg);

-- Changing WHEN and HOW it is asked needs NPS.MANAGE. This is the admin
-- screen's write path.
CREATE POLICY p_nps_insert ON hbh.nps_surveys
  FOR INSERT TO hbh_app
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('NPS.MANAGE'));

CREATE POLICY p_nps_update ON hbh.nps_surveys
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND hbh.has_permission('NPS.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id() AND hbh.has_permission('NPS.MANAGE'));

-- A person sees their OWN answers. Somebody holding NPS.MANAGE sees the
-- centre's, because reading the free text is the point of collecting it.
CREATE POLICY p_npsr_select ON hbh.nps_responses
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND (user_id = hbh.current_user_id() OR hbh.has_permission('NPS.MANAGE')));

GRANT SELECT, INSERT, UPDATE ON hbh.nps_surveys TO hbh_app;
GRANT SELECT ON hbh.nps_responses, hbh.v_nps_summary TO hbh_app;

REVOKE ALL ON FUNCTION hbh.nps_due()                                        FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.submit_nps(integer, smallint, text, text, integer, inet) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.skip_nps(integer, text, integer)                 FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.nps_due()                                     TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.submit_nps(integer, smallint, text, text, integer, inet) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.skip_nps(integer, text, integer)              TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0019');
