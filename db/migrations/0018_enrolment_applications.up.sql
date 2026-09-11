-- =====================================================================
-- Hand By Hand (new) - migration 0018: enrolment applications
--
-- A family that has never been to the centre fills a form from the
-- parent LOGIN screen, before any account exists. Their own details and
-- their child's, and reception takes it from there.
--
-- This is the first ANONYMOUS write in the schema, and that is the
-- whole of its difficulty. Four rules follow from it:
--
-- 1. AN APPLICATION IS NOT A CHILD.
--    Submitting creates a row in ONE table and nothing else. It cannot
--    create a guardian, a child, a link or an account - if it could,
--    anybody on the internet could put a child into the clinical
--    record. Turning an application into real records is a separate,
--    permissioned act by a member of staff.
--
-- 2. THE SUBMITTER GETS NOTHING BACK BUT A REFERENCE.
--    submit_enrolment returns the application number and nothing else.
--    There is no read path for an anonymous caller, so the endpoint
--    cannot be used to discover whether a mobile number is already
--    known to the centre.
--
-- 3. IT IS RATE LIMITED, AND THE LIMIT IS DATA.
--    Per mobile per day and per IP per hour, both from sys_params. An
--    unauthenticated endpoint with no ceiling is a way to fill the
--    receptionist's morning with rubbish.
--
-- 4. STAFF ONLY, AND NOT EVERY MEMBER OF STAFF.
--    Reading applications needs ENROLMENT.MANAGE. A guardian never
--    sees one - not even their own, because "their own" cannot be
--    established before the account exists.
--
-- Error classes added here:
--   HB090  illegal enrolment status transition
--   HB091  the application cannot be converted in its current state
--   HB092  not permitted
-- =====================================================================

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0018') THEN
    RAISE EXCEPTION 'migration 0018 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0017') THEN
    RAISE EXCEPTION 'migration 0017 must be applied first';
  END IF;
END
$guard$;

CREATE TABLE hbh.enrolment_applications (
  application_id   integer     GENERATED ALWAYS AS IDENTITY,
  center_id        integer     NOT NULL,
  branch_id        integer,
  application_no   text        NOT NULL,

  -- the parent, as they typed it
  parent_name_ar   text        NOT NULL,
  parent_mobile    text        NOT NULL,
  parent_email     text,
  parent_national_id text,
  relationship_code text       NOT NULL DEFAULT 'FATHER',
  address_ar       text,
  preferred_contact_time text,

  -- the child, as they typed it. Nothing here is a foreign key: this is
  -- an application, not a record.
  child_name_ar    text        NOT NULL,
  child_birth_date date        NOT NULL,
  child_gender     char(1)     NOT NULL,
  child_national_id text,
  main_concern_ar  text,
  previous_therapy_ar text,
  preferred_service_id integer,

  source_code      text        NOT NULL DEFAULT 'WEB',
  status           text        NOT NULL DEFAULT 'NEW',

  assigned_to      integer,
  contacted_at     timestamptz,
  contact_note_ar  text,
  decided_by       integer,
  decided_at       timestamptz,
  decision_note_ar text,

  -- Filled ONLY by convert_enrolment, and the proof that a real record
  -- came from this application rather than the other way round.
  converted_guardian_id integer,
  converted_child_id    integer,

  client_ip        inet,
  submitted_at     timestamptz NOT NULL DEFAULT now(),
  active_flg       boolean     NOT NULL DEFAULT true,
  deleted_at       timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at       timestamptz,
  updated_by       text,
  CONSTRAINT pk_enrolment_applications PRIMARY KEY (application_id),
  CONSTRAINT fk_enr_center   FOREIGN KEY (center_id)            REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_enr_branch   FOREIGN KEY (branch_id)            REFERENCES hbh.branches (branch_id),
  CONSTRAINT fk_enr_service  FOREIGN KEY (preferred_service_id) REFERENCES hbh.services (service_id),
  CONSTRAINT fk_enr_assignee FOREIGN KEY (assigned_to)          REFERENCES hbh.users (user_id),
  CONSTRAINT fk_enr_decider  FOREIGN KEY (decided_by)           REFERENCES hbh.users (user_id),
  CONSTRAINT fk_enr_guardian FOREIGN KEY (converted_guardian_id) REFERENCES hbh.guardians (guardian_id),
  CONSTRAINT fk_enr_child    FOREIGN KEY (converted_child_id)    REFERENCES hbh.children (child_id),
  CONSTRAINT uq_enr_no UNIQUE (center_id, application_no),
  CONSTRAINT ck_enr_status CHECK (status IN
    ('NEW','CONTACTED','ASSESSMENT_BOOKED','ENROLLED','REJECTED','DUPLICATE')),
  CONSTRAINT ck_enr_source CHECK (source_code IN ('WEB','PHONE','WALK_IN','REFERRAL')),
  CONSTRAINT ck_enr_gender CHECK (child_gender IN ('M','F')),
  CONSTRAINT ck_enr_birth  CHECK (child_birth_date <= current_date),
  -- The mobile is how reception calls them back, so it is checked to be
  -- a plausible number without assuming a country - the Egyptian
  -- pattern is a sys_params value the API applies.
  CONSTRAINT ck_enr_mobile CHECK (parent_mobile ~ '^[0-9+]{6,20}$'),
  CONSTRAINT ck_enr_email  CHECK (parent_email IS NULL OR parent_email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[A-Za-z]{2,}$'),
  -- ENROLLED is the only state in which a real record may be named, and
  -- in that state both must be.
  CONSTRAINT ck_enr_converted CHECK (
    (status = 'ENROLLED') = (converted_guardian_id IS NOT NULL AND converted_child_id IS NOT NULL)),
  CONSTRAINT ck_enr_decided CHECK ((decided_by IS NULL) = (decided_at IS NULL))
);

CREATE INDEX ix_enr_center   ON hbh.enrolment_applications (center_id, submitted_at DESC);
CREATE INDEX ix_enr_branch   ON hbh.enrolment_applications (branch_id);
CREATE INDEX ix_enr_service  ON hbh.enrolment_applications (preferred_service_id);
CREATE INDEX ix_enr_assignee ON hbh.enrolment_applications (assigned_to);
CREATE INDEX ix_enr_decider  ON hbh.enrolment_applications (decided_by);
CREATE INDEX ix_enr_guardian ON hbh.enrolment_applications (converted_guardian_id);
CREATE INDEX ix_enr_child    ON hbh.enrolment_applications (converted_child_id);
CREATE INDEX ix_enr_mobile   ON hbh.enrolment_applications (parent_mobile, submitted_at DESC);
-- The receptionist's own queue.
CREATE INDEX ix_enr_open     ON hbh.enrolment_applications (center_id, submitted_at)
  WHERE status IN ('NEW','CONTACTED','ASSESSMENT_BOOKED') AND active_flg;

-- =====================================================================
-- THE STATE MACHINE
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.legal_enrolment_transition(p_from text, p_to text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_from IS DISTINCT FROM p_to AND (p_from, p_to) IN (
    ('NEW',               'CONTACTED'),
    ('NEW',               'REJECTED'),
    ('NEW',               'DUPLICATE'),
    ('CONTACTED',         'ASSESSMENT_BOOKED'),
    ('CONTACTED',         'ENROLLED'),
    ('CONTACTED',         'REJECTED'),
    ('CONTACTED',         'DUPLICATE'),
    ('ASSESSMENT_BOOKED', 'ENROLLED'),
    ('ASSESSMENT_BOOKED', 'REJECTED')
  )
$$;

CREATE OR REPLACE FUNCTION hbh.trg_enrolment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status
     AND NOT hbh.legal_enrolment_transition(OLD.status, NEW.status) THEN
    RAISE EXCEPTION 'application % cannot go from % to %',
                    OLD.application_id, OLD.status, NEW.status
      USING ERRCODE = 'HB090';
  END IF;
  RETURN NEW;
END
$$;

-- =====================================================================
-- SUBMITTING - THE ANONYMOUS PATH
--
-- Callable with NO identity set, which makes it the only function in
-- the schema that does not begin by asking who is calling. Everything
-- it is allowed to touch is one row in one table.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.submit_enrolment(
  p_center_code       text,
  p_parent_name_ar    text,
  p_parent_mobile     text,
  p_child_name_ar     text,
  p_child_birth_date  date,
  p_child_gender      char(1),
  p_parent_email      text    DEFAULT NULL,
  p_relationship_code text    DEFAULT 'FATHER',
  p_main_concern_ar   text    DEFAULT NULL,
  p_preferred_service_id integer DEFAULT NULL,
  p_address_ar        text    DEFAULT NULL,
  p_preferred_contact_time text DEFAULT NULL,
  p_previous_therapy_ar text  DEFAULT NULL,
  p_source_code       text    DEFAULT 'WEB',
  p_client_ip         inet    DEFAULT NULL)
RETURNS TABLE (ok boolean, reason text, application_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_center   hbh.centers%ROWTYPE;
  l_per_mob  integer;
  l_per_ip   integer;
  l_no       text;
BEGIN
  SELECT * INTO l_center FROM hbh.centers c
  WHERE c.code = p_center_code AND c.active_flg;
  IF NOT FOUND THEN
    -- Deliberately vague. A caller with no identity learns nothing
    -- about which centre codes exist.
    RETURN QUERY SELECT false, 'REJECTED', NULL::text; RETURN;
  END IF;

  l_per_mob := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_MOBILE_DAY', '3')::integer;
  l_per_ip  := hbh.param(l_center.center_id, 'ENROLMENT_MAX_PER_IP_HOUR',   '10')::integer;

  IF (SELECT count(*) FROM hbh.enrolment_applications a
      WHERE a.parent_mobile = p_parent_mobile
        AND a.submitted_at > now() - interval '1 day') >= l_per_mob THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_MOBILE', NULL::text; RETURN;
  END IF;

  IF p_client_ip IS NOT NULL
     AND (SELECT count(*) FROM hbh.enrolment_applications a
          WHERE a.client_ip = p_client_ip
            AND a.submitted_at > now() - interval '1 hour') >= l_per_ip THEN
    RETURN QUERY SELECT false, 'TOO_MANY_FOR_IP', NULL::text; RETURN;
  END IF;

  l_no := hbh.next_number(l_center.center_id, 'ENROL');

  INSERT INTO hbh.enrolment_applications (
    center_id, application_no, parent_name_ar, parent_mobile, parent_email,
    relationship_code, address_ar, preferred_contact_time,
    child_name_ar, child_birth_date, child_gender, main_concern_ar,
    previous_therapy_ar, preferred_service_id, source_code, client_ip)
  VALUES (
    l_center.center_id, l_no, p_parent_name_ar, p_parent_mobile, p_parent_email,
    p_relationship_code, p_address_ar, p_preferred_contact_time,
    p_child_name_ar, p_child_birth_date, p_child_gender, p_main_concern_ar,
    p_previous_therapy_ar, p_preferred_service_id, p_source_code, p_client_ip);

  -- Written outside the transaction, so a submission that later rolls
  -- back still leaves a trace of having been attempted.
  PERFORM hbh.audit_attempt('READ', l_center.center_id, 'anonymous',
                            'enrolment application ' || l_no || ' submitted', p_client_ip);

  RETURN QUERY SELECT true, 'OK', l_no;
END
$$;

-- =====================================================================
-- CONVERTING - THE PERMISSIONED PATH
--
-- This is where an application becomes a family. It is the only route,
-- it needs ENROLMENT.MANAGE, and it records on the application which
-- records it produced.
-- =====================================================================
CREATE OR REPLACE FUNCTION hbh.convert_enrolment(
  p_application_id integer,
  p_note_ar        text DEFAULT NULL)
RETURNS TABLE (guardian_id integer, child_id integer, child_no text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = hbh, pg_catalog
AS $$
DECLARE
  l_app hbh.enrolment_applications%ROWTYPE;
  l_g   integer;
  l_c   integer;
  l_no  text;
BEGIN
  IF NOT hbh.has_permission('ENROLMENT.MANAGE') THEN
    RAISE EXCEPTION 'converting an application needs ENROLMENT.MANAGE' USING ERRCODE = 'HB092';
  END IF;

  SELECT * INTO l_app FROM hbh.enrolment_applications
  WHERE application_id = p_application_id AND active_flg
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no such application %', p_application_id USING ERRCODE = 'HB091';
  END IF;

  -- Converting twice would produce a second child for one family.
  IF l_app.status = 'ENROLLED' THEN
    RAISE EXCEPTION 'application % is already enrolled as child %',
                    p_application_id, l_app.converted_child_id
      USING ERRCODE = 'HB091';
  END IF;

  IF l_app.status NOT IN ('CONTACTED','ASSESSMENT_BOOKED') THEN
    RAISE EXCEPTION 'application % is % - contact the family before enrolling them',
                    p_application_id, l_app.status
      USING ERRCODE = 'HB091';
  END IF;

  l_no := hbh.next_number(l_app.center_id, 'CHILD');

  INSERT INTO hbh.children (center_id, branch_id, child_no, full_name_ar,
                            birth_date, gender, national_id)
  VALUES (l_app.center_id, l_app.branch_id, l_no, l_app.child_name_ar,
          l_app.child_birth_date, l_app.child_gender, l_app.child_national_id)
  RETURNING hbh.children.child_id INTO l_c;

  -- One guardian record per mobile in a centre: a second child for the
  -- same family must attach to the parent who is already known, not
  -- create a duplicate of them.
  SELECT g.guardian_id INTO l_g FROM hbh.guardians g
  WHERE g.center_id = l_app.center_id AND g.mobile = l_app.parent_mobile AND g.active_flg
  LIMIT 1;

  IF l_g IS NULL THEN
    INSERT INTO hbh.guardians (center_id, branch_id, full_name_ar, mobile, national_id)
    VALUES (l_app.center_id, l_app.branch_id, l_app.parent_name_ar,
            l_app.parent_mobile, l_app.parent_national_id)
    RETURNING hbh.guardians.guardian_id INTO l_g;
  END IF;

  -- can_view_live_flg is NOT set here. Watching a child in therapy needs
  -- a recorded consent (D-24), and an enrolment form is not one.
  INSERT INTO hbh.guardian_children (guardian_id, child_id, relationship_code, is_primary_flg)
  VALUES (l_g, l_c, l_app.relationship_code, true);

  UPDATE hbh.enrolment_applications
     SET status = 'ENROLLED',
         converted_guardian_id = l_g,
         converted_child_id    = l_c,
         decided_by = hbh.current_user_id(),
         decided_at = now(),
         decision_note_ar = coalesce(p_note_ar, decision_note_ar)
   WHERE application_id = p_application_id;

  RETURN QUERY SELECT l_g, l_c, l_no;
END
$$;

-- =====================================================================
-- TRIGGERS
-- =====================================================================
CREATE TRIGGER trg_enr_touch  BEFORE UPDATE ON hbh.enrolment_applications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_enr_status BEFORE UPDATE ON hbh.enrolment_applications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_enrolment_status();
CREATE TRIGGER trg_enr_audit  AFTER INSERT OR UPDATE OR DELETE ON hbh.enrolment_applications
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('application_id');

-- =====================================================================
-- ROW LEVEL SECURITY
--
-- Staff with ENROLMENT.MANAGE, and nobody else. A guardian never sees
-- an application - not even the one that created their own account,
-- because "their own" cannot be established at the moment it is
-- submitted, and afterwards it is a working document of the centre.
-- =====================================================================
ALTER TABLE hbh.enrolment_applications ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_enr_select ON hbh.enrolment_applications
  FOR SELECT TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ENROLMENT.MANAGE'));

CREATE POLICY p_enr_update ON hbh.enrolment_applications
  FOR UPDATE TO hbh_app
  USING (center_id = hbh.current_center_id() AND active_flg
         AND hbh.has_permission('ENROLMENT.MANAGE'))
  WITH CHECK (center_id = hbh.current_center_id()
         AND hbh.has_permission('ENROLMENT.MANAGE'));

-- No INSERT policy and no INSERT grant. The only way a row appears is
-- submit_enrolment, which is SECURITY DEFINER.
GRANT SELECT, UPDATE ON hbh.enrolment_applications TO hbh_app;

REVOKE ALL ON FUNCTION hbh.submit_enrolment(text, text, text, text, date, char, text, text, text, integer, text, text, text, text, inet) FROM PUBLIC;
REVOKE ALL ON FUNCTION hbh.convert_enrolment(integer, text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION hbh.submit_enrolment(text, text, text, text, date, char, text, text, text, integer, text, text, text, text, inet) TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.convert_enrolment(integer, text)          TO hbh_app;
GRANT EXECUTE ON FUNCTION hbh.legal_enrolment_transition(text, text)    TO hbh_app;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'ENROLMENT_MAX_PER_MOBILE_DAY', '3',  'NUMBER', 'أقصى عدد طلبات التحاق من نفس الجوّال في اليوم'),
  (NULL, 'ENROLMENT_MAX_PER_IP_HOUR',    '10', 'NUMBER', 'أقصى عدد طلبات التحاق من نفس العنوان في الساعة')
ON CONFLICT (center_id, param_code) DO NOTHING;

INSERT INTO hbh.schema_migrations (version) VALUES ('0018');
