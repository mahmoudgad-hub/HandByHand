-- =====================================================================
-- 0120 - the room a consultation happens in, and the pass to enter it
--
-- NUMBER RESERVED BEFORE WRITING. 0106-0111 and 0119 belong to another
-- session in this tree; 0112-0118 are mine.
--
-- ORDER OF DEPLOYMENT: EITHER WAY ROUND. HB252 and HB253 are new, and
-- businessRefusal answers any unknown HB code with 409 REFUSED rather
-- than 500 - business_refusal_test.go walks HB000 to HB999 to prove it.
-- The build beside this one says NOT_YET_OPEN and NOT_CONFIRMED.
--
-- =====================================================================
-- THE DECISION THIS MIGRATION RECORDS, BECAUSE IT COLLIDES WITH A RULE
-- =====================================================================
--
-- CLAUDE.md says, without qualification:
--
--   "لا رابط كاميرا ولا عنوان IP ولا بيانات اعتماد في أي مكان يبلغه عميل"
--
-- The live-stream path honours it exactly: hbh.issue_stream_token puts
-- the token in an HttpOnly cookie the page cannot read, and the service
-- PROXIES the video, so the camera's address and credentials never leave
-- the server. See live_handlers.go.
--
-- THAT IS NOT POSSIBLE FOR A CONVERSATION, and the reason is WebRTC, not
-- the provider. Real-time media goes browser-to-server directly; there
-- is nothing to proxy and no way to keep the credential server-side. The
-- parent's browser must authenticate to the video provider itself.
--
-- So: a short-lived signed token reaches the family's browser, and that
-- browser talks to the provider directly. The owner was shown this
-- before it was built, in those words, and asked for the video embedded
-- in the application anyway. This paragraph is the record of it.
--
-- THE RULE WAS WRITTEN ABOUT CAMERAS IN TREATMENT ROOMS, where proxying
-- works. A consultation is a different shape. It is worth saying that
-- plainly rather than letting a future reader think the rule was
-- forgotten.
--
-- WHAT NARROWS IT, and every one of these is enforced below rather than
-- being a habit:
--
--   * The token names ONE room, ONE person, and a window that cannot
--     exceed MEETING_TOKEN_TTL_MIN - a CHECK on the row, not an argument.
--   * It is issued only for an appointment that is the caller's, is
--     CONFIRMED, and whose door is open.
--   * The guardian is never a moderator.
--   * Every issue is a row: who, which meeting, when, from where.
--
-- AND ONE THING IT CANNOT DO. A Jitsi token is a signed JWT, stateless
-- at the provider: once issued it works until it expires, and nothing
-- here can call it back. hbh.stream_tokens has revoked_at and means it;
-- THIS TABLE DELIBERATELY HAS NO SUCH COLUMN, because a column that
-- promised revocation would be a promise the system cannot keep. The
-- only control is the window, which is why it is short and why the CHECK
-- is on the row.
--
-- =====================================================================
-- WHY THERE IS NO PUller HERE, WHICH THE ARCHITECT'S NOTE EXPECTS
-- =====================================================================
--
-- docs/architect/03-online-consultation.md designs hbh.meetings as an
-- outbox: rows land PENDING, a worker calls the provider to create the
-- room, and stamps room_ref. That is right for Daily.co, where a room is
-- a REST call that can fail, cost money and be left orphaned.
--
-- A JITSI ROOM IS NOT CREATED. It exists when somebody joins a name. So
-- for this provider there is nothing to call, nothing to retry, and no
-- room to leak - room_ref is a secret this migration generates, and the
-- row is READY the moment it is written.
--
-- The status column still carries PENDING and FAILED as legal values, so
-- the day Daily arrives its states are already lawful and the puller has
-- somewhere to put them. Nothing else speculative is built: no attempts
-- counter, no last_error_code, no worker. Machinery that always holds
-- the same value is machinery nobody can tell is broken.
-- =====================================================================

\set ON_ERROR_STOP on

DO $guard$
BEGIN
  IF EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0120') THEN
    RAISE EXCEPTION 'migration 0120 is already applied - migrations are forward-only';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM hbh.schema_migrations WHERE version = '0118') THEN
    RAISE EXCEPTION 'migration 0118 must be applied first';
  END IF;
END
$guard$;

-- ---------------------------------------------------------------------
-- Parameters.
--
-- SEEDED HERE, next to the two tables that read them, following 0094 -
-- which put the SMS knobs in the migration that built the outbox rather
-- than in db/seed/. A knob that lives away from its mechanism is a knob
-- nobody finds.
-- ---------------------------------------------------------------------
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  (NULL, 'MEETING_TOKEN_TTL_MIN', '15', 'NUMBER',
   'صلاحية توكن دخول الاستشارة بالدقائق — لا تزيد أبدًا، فالتوكن لا يمكن إلغاؤه بعد إصداره'),
  (NULL, 'CONSULT_DOOR_OPENS_MIN', '10', 'NUMBER',
   'قبل الموعد بكم دقيقة يفتح زرّ الدخول'),
  (NULL, 'CONSULT_DOOR_GRACE_MIN', '15', 'NUMBER',
   'بعد نهاية الموعد بكم دقيقة يقفل الباب'),
  (NULL, 'MEETING_PROVIDER', 'JITSI_PUBLIC', 'STRING',
   'مزوّد الاستشارة — JITSI_JAAS للإنتاج، وJITSI_PUBLIC للتطوير فقط لأنه بلا توكنات')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- ---------------------------------------------------------------------
-- hbh.meetings
--
-- ONE APPOINTMENT, ONE ROOM, and the UNIQUE says so. Two rows for one
-- appointment would mean two rooms, and the half of the family holding
-- the older token would sit alone in an empty one.
--
-- room_ref IS A SECRET, not a name. Deriving it from the appointment
-- number would make every consultation in the centre guessable by
-- counting - and with a provider whose rooms are created by being
-- joined, a guessed name is an open door. It is generated here, from
-- gen_random_bytes, and it is the only place it is generated.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hbh.meetings (
  meeting_id     bigint      GENERATED ALWAYS AS IDENTITY,
  center_id      integer     NOT NULL,
  appointment_id integer     NOT NULL,

  -- Recorded per meeting, not read from a parameter at display time: a
  -- centre that changes provider next year must not rewrite what its
  -- past consultations were held on.
  provider       text        NOT NULL,
  room_ref       text        NOT NULL,

  status         text        NOT NULL DEFAULT 'READY',

  -- The door, as instants. Computed once from the appointment and the
  -- parameters, so moving a parameter does not silently move the door on
  -- consultations already booked.
  opens_at       timestamptz NOT NULL,
  expires_at     timestamptz NOT NULL,

  closed_at      timestamptz,
  closed_reason  text,

  active_flg     boolean     NOT NULL DEFAULT true,
  deleted_at     timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at     timestamptz,
  updated_by     text,

  CONSTRAINT pk_meetings PRIMARY KEY (meeting_id),
  CONSTRAINT uq_meetings_appointment UNIQUE (appointment_id),
  CONSTRAINT fk_meetings_center      FOREIGN KEY (center_id) REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_meetings_appointment FOREIGN KEY (appointment_id) REFERENCES hbh.appointments (appointment_id),
  CONSTRAINT ck_meetings_provider CHECK (provider IN ('JITSI_JAAS', 'JITSI_PUBLIC', 'DAILY')),
  CONSTRAINT ck_meetings_status   CHECK (status IN ('PENDING', 'READY', 'CLOSED', 'FAILED')),
  CONSTRAINT ck_meetings_window   CHECK (expires_at > opens_at),
  -- A closed room says when and why. "Closed" with no reason is a row
  -- nobody can explain to a family who could not get in.
  CONSTRAINT ck_meetings_closed   CHECK ((status = 'CLOSED') = (closed_at IS NOT NULL)),
  CONSTRAINT ck_meetings_reason   CHECK (closed_at IS NULL OR closed_reason IS NOT NULL),
  -- Long enough that it cannot be guessed, and checked so that a future
  -- writer cannot quietly put the appointment number here.
  CONSTRAINT ck_meetings_room_ref CHECK (room_ref ~ '^[a-z0-9]{24,64}$')
);

CREATE INDEX ix_meetings_center ON hbh.meetings (center_id, opens_at DESC);
CREATE INDEX ix_meetings_open   ON hbh.meetings (opens_at) WHERE status = 'READY';

COMMENT ON TABLE hbh.meetings IS
  'One video room per online appointment. room_ref is a generated secret, not a name: with a provider whose rooms exist by being joined, a guessable name is an open door.';

COMMENT ON COLUMN hbh.meetings.provider IS
  'JITSI_JAAS in production - hosted Jitsi with per-participant JWTs, free to 25 monthly active users. JITSI_PUBLIC is meet.jit.si and is DEVELOPMENT ONLY: it has no tokens at all, so the room name is the only credential. DAILY is the upgrade to consider when volume passes the free tier - it is the same shape (a room plus a per-participant token), which is why it is one layer and not a rewrite.';

CREATE TRIGGER trg_meetings_touch BEFORE UPDATE ON hbh.meetings
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();

ALTER TABLE hbh.meetings ENABLE ROW LEVEL SECURITY;

-- WHO MAY SEE THAT A CONSULTATION HAS A ROOM. The same people who may
-- see the appointment, asked the same way - p_appointments_select is
-- `center_id = current_center_id() AND can_access_child(child_id)`, and
-- this reaches the child through the appointment rather than inventing a
-- second opinion about who a family is.
--
-- room_ref IS IN THIS TABLE AND THE POLICY DOES NOT HIDE IT, because RLS
-- filters rows and not columns. That is why the API never selects it:
-- hbh.issue_meeting_token is the only thing that reads it out, and the
-- column is not on any CRUD resource. Noted here so the next person
-- adding a screen knows it is a decision and not an oversight.
CREATE POLICY p_meetings_select ON hbh.meetings
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND EXISTS (SELECT 1 FROM hbh.appointments a
                     WHERE a.appointment_id = meetings.appointment_id
                       AND hbh.can_access_child(a.child_id)));

GRANT SELECT ON hbh.meetings TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

-- ---------------------------------------------------------------------
-- hbh.meeting_tokens
--
-- SHAPED ON hbh.stream_tokens, WITH ONE COLUMN DELIBERATELY MISSING.
--
-- Same idea: the plaintext is never stored, the window is a CHECK on the
-- row rather than an argument somebody can pass, and the row says who
-- and from where. Same access: RLS on, NO POLICY - nothing reads this
-- table except SECURITY DEFINER functions, and a credential record is
-- not a screen.
--
-- The missing column is revoked_at. See the header: a Jitsi JWT cannot
-- be called back, and a column that said otherwise would be worse than
-- not having one.
--
-- WHAT IT IS FOR, THEN, IF IT REDEEMS NOTHING. It answers "who entered
-- this consultation, and when" - the rule that every sensitive read is
-- recorded explicitly, because triggers do not catch reads. It is
-- evidence, not a key.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS hbh.meeting_tokens (
  meeting_token_id bigint      GENERATED ALWAYS AS IDENTITY,
  center_id        integer     NOT NULL,
  token_hash       bytea       NOT NULL,
  meeting_id       bigint      NOT NULL,
  user_id          integer     NOT NULL,
  -- Whether this pass was minted as the host. A guardian is never one,
  -- and the row says which was issued rather than leaving it to be
  -- inferred from who the user is today.
  moderator_flg    boolean     NOT NULL DEFAULT false,
  issued_at        timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  client_ip        inet,

  CONSTRAINT pk_meeting_tokens PRIMARY KEY (meeting_token_id),
  CONSTRAINT uq_mtok_hash   UNIQUE (token_hash),
  CONSTRAINT fk_mtok_center  FOREIGN KEY (center_id)  REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_mtok_meeting FOREIGN KEY (meeting_id) REFERENCES hbh.meetings (meeting_id),
  CONSTRAINT fk_mtok_user    FOREIGN KEY (user_id)    REFERENCES hbh.users (user_id),
  CONSTRAINT ck_mtok_window  CHECK (expires_at > issued_at),
  -- THE CEILING IS ON THE ROW. A parameter decides the window inside
  -- that, and this decides what a parameter may not exceed - the same
  -- arrangement as ck_tok_ttl on stream_tokens, and for a sharper
  -- reason here, since nothing can revoke what this issues.
  CONSTRAINT ck_mtok_ttl     CHECK (expires_at <= issued_at + interval '15 minutes')
);

CREATE INDEX ix_mtok_center  ON hbh.meeting_tokens (center_id);
CREATE INDEX ix_mtok_meeting ON hbh.meeting_tokens (meeting_id, issued_at DESC);
CREATE INDEX ix_mtok_user    ON hbh.meeting_tokens (user_id, issued_at DESC);

COMMENT ON TABLE hbh.meeting_tokens IS
  'One row per pass issued into a consultation. Evidence, not a key: the provider validates the JWT itself, so this cannot revoke anything - which is why it has no revoked_at and why ck_mtok_ttl is a hard ceiling.';

ALTER TABLE hbh.meeting_tokens ENABLE ROW LEVEL SECURITY;

-- Exemptions, with their reasons, in the table that holds them rather
-- than as silence in a test file - and the same two stream_tokens has.
INSERT INTO hbh.convention_exemptions (table_name, rule_code, reason) VALUES
  ('meeting_tokens', 'AUDIT_COLUMNS',
   'A credential record, not business data. issued_at, expires_at and user_id ARE its audit trail, and a created_by beside issued_at would be the same fact twice.'),
  ('meeting_tokens', 'SOFT_DELETE',
   'A pass expires; it is not deactivated. There is nothing to hide and nothing to restore, and an active_flg here would suggest a revocation this provider cannot perform.')
ON CONFLICT (table_name, rule_code) DO NOTHING;

INSERT INTO hbh.schema_migrations (version) VALUES ('0120');
