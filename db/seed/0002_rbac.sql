-- =====================================================================
-- Hand By Hand (new) - roles, permissions and number series
--
-- Reference data. Idempotent. No test data here.
-- =====================================================================

INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('PORTAL.VIEW',        'دخول البوابة',              'Access the portal'),
  ('CHILD.VIEW_ALL',     'عرض كل الأطفال',            'View every child'),
  ('CHILD.CREATE',       'تسجيل طفل',                 'Register a child'),
  ('CHILD.EDIT',         'تعديل بيانات طفل',          'Edit a child'),
  ('GUARDIAN.MANAGE',    'إدارة أولياء الأمور',       'Manage guardians'),
  ('APPOINTMENT.BOOK',   'حجز موعد',                  'Book an appointment'),
  ('APPOINTMENT.CANCEL', 'إلغاء موعد',                'Cancel an appointment'),
  ('SESSION.START',      'بدء جلسة',                  'Start a session'),
  ('SESSION.COMPLETE',   'إنهاء جلسة',                'Close a session'),
  ('SESSION.NOTES.EDIT', 'كتابة ملاحظات الجلسة',      'Author session notes'),
  ('REPORT.VIEW',        'عرض التقارير',              'View reports'),
  ('REPORT.PUBLISH',     'نشر تقرير لولي الأمر',      'Publish a report to a guardian'),
  ('LIVE.VIEW',          'مشاهدة البث المباشر',       'Watch the live stream'),
  ('BILLING.VIEW',       'عرض الفواتير',              'View invoices'),
  ('BILLING.MANAGE',     'إدارة الفواتير والدفعات',   'Manage invoices and payments'),
  ('REQUEST.SUBMIT',     'إرسال طلب',                 'Submit a request'),
  ('REQUEST.MANAGE',     'اعتماد الطلبات',            'Approve requests')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.roles (center_id, code, name_ar, name_en, is_system_flg)
SELECT c.center_id, r.code, r.name_ar, r.name_en, true
FROM   hbh.centers c
CROSS  JOIN (VALUES
        ('CENTER_ADMIN', 'مدير المركز',  'Centre administrator'),
        ('RECEPTION',    'استقبال',      'Reception'),
        ('THERAPIST',    'أخصائي',       'Therapist'),
        ('GUARDIAN',     'وليّ أمر',     'Guardian')
      ) AS r(code, name_ar, name_en)
WHERE  c.code = 'HBH'
ON CONFLICT (center_id, code) DO NOTHING;

-- ---------------------------------------------------------------------
-- Role to permission
--
-- Note what CENTER_ADMIN does NOT get: SESSION.NOTES.EDIT. A clinical
-- note is authored by the clinician who was in the room, and no
-- administrator writes one on their behalf. This is deliberate.
--
-- It is also the withholding that caused a real defect in the Oracle
-- system: a single gate demanded CHILD.VIEW_ALL *and* SESSION.NOTES.EDIT
-- to close a session, so reception could start a session that only the
-- assigned therapist could ever end - and the screen refused a user
-- holding the very permission the action was named after. When two
-- rights have separate codes they need separate gates. Closing a
-- session asks SESSION.COMPLETE; authoring a note asks
-- SESSION.NOTES.EDIT. Never one gate for both.
-- ---------------------------------------------------------------------
INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN   hbh.centers c ON c.center_id = r.center_id AND c.code = 'HBH'
JOIN  (VALUES
        ('CENTER_ADMIN', 'PORTAL.VIEW'),
        ('CENTER_ADMIN', 'CHILD.VIEW_ALL'),
        ('CENTER_ADMIN', 'CHILD.CREATE'),
        ('CENTER_ADMIN', 'CHILD.EDIT'),
        ('CENTER_ADMIN', 'GUARDIAN.MANAGE'),
        ('CENTER_ADMIN', 'APPOINTMENT.BOOK'),
        ('CENTER_ADMIN', 'APPOINTMENT.CANCEL'),
        ('CENTER_ADMIN', 'SESSION.START'),
        ('CENTER_ADMIN', 'SESSION.COMPLETE'),
        ('CENTER_ADMIN', 'REPORT.VIEW'),
        ('CENTER_ADMIN', 'REPORT.PUBLISH'),
        ('CENTER_ADMIN', 'LIVE.VIEW'),
        ('CENTER_ADMIN', 'BILLING.VIEW'),
        ('CENTER_ADMIN', 'BILLING.MANAGE'),
        ('CENTER_ADMIN', 'REQUEST.MANAGE'),

        ('RECEPTION', 'PORTAL.VIEW'),
        ('RECEPTION', 'CHILD.VIEW_ALL'),
        ('RECEPTION', 'CHILD.CREATE'),
        ('RECEPTION', 'CHILD.EDIT'),
        ('RECEPTION', 'GUARDIAN.MANAGE'),
        ('RECEPTION', 'APPOINTMENT.BOOK'),
        ('RECEPTION', 'APPOINTMENT.CANCEL'),
        ('RECEPTION', 'BILLING.VIEW'),
        ('RECEPTION', 'REQUEST.MANAGE'),

        ('THERAPIST', 'PORTAL.VIEW'),
        ('THERAPIST', 'CHILD.VIEW_ALL'),
        ('THERAPIST', 'SESSION.START'),
        ('THERAPIST', 'SESSION.COMPLETE'),
        ('THERAPIST', 'SESSION.NOTES.EDIT'),
        ('THERAPIST', 'REPORT.VIEW'),
        ('THERAPIST', 'REPORT.PUBLISH'),
        ('THERAPIST', 'LIVE.VIEW'),

        -- A guardian holds almost nothing. Everything they can reach is
        -- decided by the link in guardian_children, not by a permission.
        ('GUARDIAN', 'PORTAL.VIEW'),
        ('GUARDIAN', 'REPORT.VIEW'),
        ('GUARDIAN', 'REQUEST.SUBMIT')
      ) AS m(role_code, perm_code)
  ON  m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO hbh.user_roles (user_id, role_id)
SELECT u.user_id, r.role_id
FROM   hbh.users u
JOIN   hbh.roles r ON r.center_id = u.center_id AND r.code = 'CENTER_ADMIN'
WHERE  lower(u.username) = 'admin'
ON CONFLICT (user_id, role_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Number series
-- ---------------------------------------------------------------------
INSERT INTO hbh.number_series (center_id, code, prefix, include_year_flg, width)
SELECT c.center_id, s.code, s.prefix, s.include_year_flg, s.width
FROM   hbh.centers c
CROSS  JOIN (VALUES
        ('CHILD',   'CH-',  false, 5),
        ('INVOICE', 'INV-', true,  5),
        ('APPT',    'APT-', true,  5),
        ('REQUEST', 'REQ-', true,  5)
      ) AS s(code, prefix, include_year_flg, width)
WHERE  c.code = 'HBH'
ON CONFLICT (center_id, code) DO NOTHING;

-- =====================================================================
-- Phase 4: plans, measurements and note publication
--
-- These live here and not in migration 0006 for an ordering reason that
-- cost a full acceptance run: scripts/db.sh applies every migration
-- first and the seed files afterwards, so at migration time hbh.roles
-- and hbh.centers are empty on a rebuilt database. An INSERT that reads
-- either of them matches nothing, inserts nothing, and reports success.
--
-- A migration creates STRUCTURE. Anything that reads a table the seed
-- populates belongs in the seed.
-- =====================================================================
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('PLAN.MANAGE',  'إدارة الخطط العلاجية',   'Manage treatment plans'),
  ('GOAL.MEASURE', 'تسجيل قياسات التقدّم',    'Record progress measurements'),
  ('NOTE.PUBLISH', 'نشر ملاحظة لولي الأمر',  'Publish a note to a guardian')
ON CONFLICT (code) DO NOTHING;

-- NOTE.PUBLISH goes to the clinician, not to the administrator. The
-- person who wrote a clinical note is the one who decides a family
-- should see it; an administrator publishes formal reports, not
-- somebody else's notes.
INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('CENTER_ADMIN', 'PLAN.MANAGE'),
        ('THERAPIST',    'PLAN.MANAGE'),
        ('THERAPIST',    'GOAL.MEASURE'),
        ('THERAPIST',    'NOTE.PUBLISH')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO hbh.number_series (center_id, code, prefix, include_year_flg, width)
SELECT c.center_id, 'REPORT', 'RPT-', true, 5 FROM hbh.centers c
ON CONFLICT (center_id, code) DO NOTHING;

-- Staff sign-in (migration 0011). In the seed, not the migration: at
-- migration time hbh.roles is empty on a rebuilt database.
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('USER.MANAGE', 'إدارة الحسابات وكلمات المرور', 'Manage accounts and passwords')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN   hbh.permissions p ON p.code = 'USER.MANAGE'
WHERE  r.code = 'CENTER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- Write access (migration 0012). In the seed for the same reason as the
-- rows above: at migration time hbh.roles is empty on a rebuilt
-- database, and an INSERT that reads it matches nothing, inserts
-- nothing, and reports success.
--
-- Two codes, not one, and the split is the point. CATALOG.MANAGE is the
-- price list and the rooms; STAFF.MANAGE is who works here and when.
-- Whoever maintains the catalogue does not thereby get to add a
-- therapist, and the policies on hbh.cameras demand CATALOG.MANAGE AND
-- LIVE.VIEW together - so a catalogue editor still cannot repoint a
-- camera at a different room.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('CATALOG.MANAGE', 'إدارة الخدمات والغرف والأنشطة والباقات', 'Manage the service catalogue'),
  ('STAFF.MANAGE',   'إدارة الأخصائيين وساعات عملهم',          'Manage therapists and their hours')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('CENTER_ADMIN', 'CATALOG.MANAGE'),
        ('CENTER_ADMIN', 'STAFF.MANAGE')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- =====================================================================
-- Enrolment, satisfaction and operations (migrations 0018-0020)
--
-- In the seed, not the migrations: at migration time hbh.roles and
-- hbh.centers are empty on a rebuilt database.
-- =====================================================================
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('ENROLMENT.MANAGE', 'إدارة طلبات الالتحاق',      'Manage enrolment applications'),
  ('NPS.MANAGE',       'إدارة استبيان الرضا',        'Manage the satisfaction survey'),
  ('OPS.VIEW',         'عرض سجلّ التشغيل والأداء',   'View the operations and performance log')
ON CONFLICT (code) DO NOTHING;

-- OPS.VIEW goes to the administrator alone. The log names every user
-- and every path they touched; reception has no operational role and a
-- therapist certainly does not.
INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('CENTER_ADMIN', 'ENROLMENT.MANAGE'),
        ('RECEPTION',    'ENROLMENT.MANAGE'),
        ('CENTER_ADMIN', 'NPS.MANAGE'),
        ('CENTER_ADMIN', 'OPS.VIEW')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- The enrolment number series.
INSERT INTO hbh.number_series (center_id, code, prefix, include_year_flg, width)
SELECT c.center_id, 'ENROL', 'ENR-', true, 5 FROM hbh.centers c
ON CONFLICT (center_id, code) DO NOTHING;

-- One survey to start with, and it is only a starting point: the centre
-- changes the wording, the trigger and the cooldown from the admin
-- screen without a deployment.
INSERT INTO hbh.nps_surveys (center_id, code, name_ar, question_ar, followup_question_ar,
                             audience, trigger_kind, action_code, cooldown_days)
SELECT c.center_id, 'PARENT_SESSION', 'رضا وليّ الأمر بعد الجلسة',
       'ما مدى احتمال أن ترشّح مركزنا لصديق أو قريب؟',
       'ما الذي يجعل تجربتك أفضل؟',
       'GUARDIAN', 'ACTION', 'SESSION_COMPLETED', 30
FROM   hbh.centers c WHERE c.code = 'HBH'
ON CONFLICT (center_id, code) DO NOTHING;

-- =====================================================================
-- Assessments (migration 0023). In the seed for the usual reason: at
-- migration time hbh.roles and hbh.centers are empty on a rebuild.
-- =====================================================================
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('ASSESSMENT.RECORD',  'تسجيل التقييمات',        'Record assessments'),
  ('ASSESSMENT.PUBLISH', 'نشر نتيجة تقييم لولي الأمر', 'Publish an assessment to a guardian')
ON CONFLICT (code) DO NOTHING;

-- The clinician who administered the instrument is the one who decides
-- a family should see the result, the same way a note works.
INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('THERAPIST',    'ASSESSMENT.RECORD'),
        ('THERAPIST',    'ASSESSMENT.PUBLISH'),
        ('CENTER_ADMIN', 'ASSESSMENT.RECORD')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- Attachments (migration 0024).
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('ATTACHMENT.UPLOAD',  'رفع المرفقات',              'Upload attachments'),
  ('ATTACHMENT.PUBLISH', 'نشر مرفق لولي الأمر',       'Publish an attachment to a guardian')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('THERAPIST',    'ATTACHMENT.UPLOAD'),
        ('THERAPIST',    'ATTACHMENT.PUBLISH'),
        ('RECEPTION',    'ATTACHMENT.UPLOAD'),
        ('CENTER_ADMIN', 'ATTACHMENT.UPLOAD'),
        ('CENTER_ADMIN', 'ATTACHMENT.PUBLISH')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- The public site's content (migration 0040). In the seed, like every
-- grant above it: at migration time hbh.roles is empty on a rebuilt
-- database, so an INSERT that reads it matches nothing, inserts nothing,
-- and reports success.
--
-- TWO CODES, NOT ONE, and the split is deliberate rather than tidy.
-- Writing a testimonial and putting it on the open internet are
-- different acts with different consequences, and the natural
-- arrangement is that a member of staff drafts and a manager publishes.
-- A single code serving both would decide, silently, which of the two
-- decisions nobody is being asked to make - the same defect this project
-- already found between SESSION.COMPLETE and SESSION.NOTES.EDIT.
--
-- Both go to CENTER_ADMIN today, because the owner asked for screens
-- only the manager can see. The split costs nothing now and is the
-- difference between a policy change and a migration later.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('SITE.EDIT',    'تحرير محتوى الموقع',  'Edit website content'),
  ('SITE.PUBLISH', 'نشر محتوى الموقع',    'Publish website content')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN  (VALUES
        ('CENTER_ADMIN', 'SITE.EDIT'),
        ('CENTER_ADMIN', 'SITE.PUBLISH')
      ) AS m(role_code, perm_code) ON m.role_code = r.code
JOIN   hbh.permissions p ON p.code = m.perm_code
ON CONFLICT (role_id, permission_id) DO NOTHING;

-- ---------------------------------------------------------------------
-- The centre's own parameters (migration 0051).
--
-- CENTER_ADMIN alone. This is not a screen where a wrong entry is a
-- wrong row: the weekend decides which days can be booked across every
-- screen, and the currency labels every amount the system has ever
-- stored. Reception can read the values on the settings screen and
-- cannot write them.
--
-- The permission covers the row; it does not decide which COLUMNS move.
-- That is a column-level grant in 0051, and `code` is left out of it
-- entirely, so no permission reaches it.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('SETTINGS.MANAGE', 'تعديل بارامترات المركز', 'Edit centre parameters')
ON CONFLICT (code) DO NOTHING;

-- ---------------------------------------------------------------------
-- A member of staff's personal record (migration 0067): identity
-- number, date of birth, home address, scanned documents.
--
-- ITS OWN CODE, AND NOT USER.MANAGE. USER.MANAGE is the authority to
-- decide who may open which screen; reading where a colleague lives and
-- what their identity number is answers a different question entirely.
-- Folding the second into the first would mean that everybody who can
-- grant a role can also read every employee's papers - and nobody would
-- have chosen that, they would have inherited it.
--
-- CENTER_ADMIN and nobody else. Reception administers appointments, not
-- personnel files.
--
-- It is not needed to read YOUR OWN record: the policy admits the owner
-- directly, which is what stops this code from having to be handed out
-- to everybody who might want to check their own date of birth.
-- ---------------------------------------------------------------------
INSERT INTO hbh.permissions (code, name_ar, name_en) VALUES
  ('STAFF.PII', 'الاطّلاع على بيانات الموظفين الشخصية', 'Read staff personal data')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN   hbh.permissions p ON p.code = 'STAFF.PII'
WHERE  r.code = 'CENTER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;

INSERT INTO hbh.role_permissions (role_id, permission_id)
SELECT r.role_id, p.permission_id
FROM   hbh.roles r
JOIN   hbh.permissions p ON p.code = 'SETTINGS.MANAGE'
WHERE  r.code = 'CENTER_ADMIN'
ON CONFLICT (role_id, permission_id) DO NOTHING;
