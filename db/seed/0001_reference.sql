-- =====================================================================
-- Hand By Hand (new) - reference seed for migration 0001
--
-- Reference data only: the centre, its branch, system parameters and
-- lookup values. Idempotent - safe to re-run.
--
-- This file carries NO test data. Fixtures for the acceptance suite
-- live in tests/fixtures and are created and torn down by the suite.
-- =====================================================================

-- ---------------------------------------------------------------------
-- The centre
--
-- Country, currency, timezone and weekend are data. Egypt is the first
-- tenant, not a hardcoded assumption.
-- ---------------------------------------------------------------------
INSERT INTO hbh.centers (code, name_ar, name_en, country_code, currency_code, time_zone, weekend_days)
VALUES ('HBH', 'مركز هاند باي هاند للمهارات', 'Hand By Hand Skills Center', 'EG', 'EGP', 'Africa/Cairo', '{5,6}')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.branches (center_id, code, name_ar, name_en)
SELECT c.center_id, 'MAIN', 'الفرع الرئيسي', 'Main Branch'
FROM   hbh.centers c
WHERE  c.code = 'HBH'
ON CONFLICT (center_id, code) DO NOTHING;

-- ---------------------------------------------------------------------
-- System parameters
--
-- center_id NULL = a global default that applies to every tenant.
-- A centre overrides one by inserting its own row with the same code.
-- ---------------------------------------------------------------------
INSERT INTO hbh.sys_params (center_id, param_code, param_value, data_type, description_ar) VALUES
  -- WHAT A PERSON MAY TYPE, and only that. The API checks it at the edge
  -- before the database is called at all, so it has to accept the
  -- national form an Egyptian parent has typed for a year AND the
  -- international form a family in Riyadh types. What may be STORED is
  -- E.164, decided by the triggers and checks 0112 added - not here.
  --
  -- THIS VALUE AND THE UPDATE IN 0113 HAVE TO AGREE - 0113, because it is
  -- the LAST migration to write this parameter and the last one wins.
  -- This insert is ON CONFLICT DO NOTHING, so on an existing database
  -- only the migrations' UPDATEs land; on a rebuilt one they UPDATE a row
  -- that does not exist yet - matching nothing, silently - and this line
  -- is the only thing that decides. That is 0058's defect exactly, and
  -- the comment further down this file describes it.
  -- It is a SIEVE, not a specification. It sees the value a person typed,
  -- separators and all - guard_identity_format fires before the
  -- canonicaliser, by trigger name order - so a pattern without spaces in
  -- it refuses "+966 50 123 4567" and 0113 exists because that is what
  -- happened. hbh.canonical_mobile is what decides.
  (NULL, 'MOBILE_PATTERN',        '^\+?[0-9٠-٩][0-9٠-٩\s().-]{5,24}$',
                                                  'STRING',
   'ما يجوز كتابته كرقم جوّال — يقبل المسافات والشرطات والأرقام العربية. شكل التخزين E.164 وتفرضه القاعدة'),
  -- Which country a number with a leading 0 and no country code belongs
  -- to. Sign-in reads it because that path runs before there is an
  -- identity and therefore before there is a centre to ask; everywhere
  -- else hbh.centers.country_code answers instead, per centre.
  (NULL, 'DEFAULT_COUNTRY',       'EG',           'STRING',  'الدولة التي يُقرأ بها رقم محلي بلا كود دولي'),
  (NULL, 'NATIONAL_ID_LENGTH',    '14',           'NUMBER',  'طول الرقم القومي'),
  (NULL, 'OTP_LENGTH',            '6',            'NUMBER',  'عدد أرقام رمز التحقّق'),
  (NULL, 'OTP_TTL_MINUTES',       '15',           'NUMBER',  'صلاحية رمز التحقّق بالدقائق'),
  (NULL, 'OTP_MAX_ATTEMPTS',      '5',            'NUMBER',  'عدد المحاولات قبل قفل الحساب'),
  (NULL, 'OTP_RESEND_SECONDS',    '60',           'NUMBER',  'أقل مدة بين طلبَي رمز'),
  (NULL, 'SESSION_TTL_MINUTES',   '480',          'NUMBER',  'صلاحية جلسة الدخول'),
  (NULL, 'STREAM_TOKEN_TTL_MIN',  '15',           'NUMBER',  'صلاحية توكن البث — لا تزيد أبدًا'),
  (NULL, 'MAX_ATTACHMENT_MB',     '5',            'NUMBER',  'أقصى حجم مرفق'),
  (NULL, 'DEFAULT_TAX_RATE',      '0',            'NUMBER',  'نسبة الضريبة حتى يؤكّدها المحاسب'),
  (NULL, 'DATE_DISPLAY_FORMAT',   'DD/MM/YYYY',   'STRING',  'صيغة عرض التاريخ'),
  (NULL, 'RECORDING_ENABLED',     'false',        'BOOLEAN', 'التسجيل ممنوع دائمًا — القيمة هنا للتوثيق ولا تُغيَّر'),
  -- How long a password setup code stays usable. A day by default:
  -- long enough to hand over in person on the next shift, short enough
  -- that one written on a note stops working before the week is out.
  (NULL, 'PASSWORD_SETUP_TTL_MINUTES', '1440',    'NUMBER',
   'صلاحية رمز ضبط كلمة المرور بالدقائق'),
  -- The path prefix written into the database for an uploaded photograph
  -- or film, and the one the public page puts in a src attribute.
  --
  -- It does NOT decide which directory the service may write to. That is
  -- the mounted media directory and it is a deployment fact, not a row:
  -- a filesystem path taken from a table would let anyone who can edit
  -- this row aim the service's writes at somewhere else on the disk.
  -- What this changes is the path the SITE looks under, so it has to
  -- match the folder the web server publishes that directory as.
  (NULL, 'SITE_MEDIA_PREFIX',     'assets',       'STRING',
   'مسار الصور والفيديوهات كما يقرأه الموقع — لا يحدّد مكان الكتابة على القرص'),
  -- How far apart the free windows the booking screen offers are. Fifteen
  -- minutes, so a forty-five minute session can start at 10:00 or 10:15
  -- rather than only on the hour.
  --
  -- It changes what is OFFERED, never what is allowed: a time between two
  -- offers is still a legal booking, and the manual fields still take one.
  -- hbh.validate_slot decides either way.
  (NULL, 'SLOT_GRANULARITY_MIN',  '15',           'NUMBER',
   'المسافة بين الفتحات المعروضة في شاشة الحجز بالدقائق')
ON CONFLICT (center_id, param_code) DO NOTHING;

-- ---------------------------------------------------------------------
-- Which of them the settings screen may change.
--
-- IT IS HERE AND NOT IN THE MIGRATION THAT ADDED THE COLUMN, and that is
-- the whole point. 0058 added `editable_flg` and set it with an UPDATE
-- in the same file - and on a REBUILT database that UPDATE runs while
-- this table is still empty, because db.sh applies every migration
-- first and the seeds afterwards. It matched five of the eight rows
-- (the ones other migrations happen to insert) and silently missed
-- three: DEFAULT_TAX_RATE, MAX_ATTACHMENT_MB and DATE_DISPLAY_FORMAT
-- exist only here. Nothing failed. The screen just showed three fewer
-- editable parameters than it should, on a fresh install only.
--
-- The rule is written in CLAUDE.md and this is exactly it: a statement
-- that READS a table the seeds fill belongs in the seed file.
--
-- Nothing is set back to false. `false` is the column default, so a
-- parameter this list does not name is locked already - and one somebody
-- deliberately opened later stays open rather than being closed again by
-- the next migrate. Same instinct as the DO NOTHING above: the seed
-- guarantees a floor, it does not overwrite a decision.
--
-- WHAT IS ABSENT IS ABSENT ON PURPOSE. The security limits (OTP_*,
-- LOGIN_*, MIN_PASSWORD_LENGTH, SESSION_TTL_MINUTES,
-- PASSWORD_SETUP_TTL_MINUTES), the anti-abuse ceilings
-- (ENROLMENT_MAX_PER_*), the country rules (MOBILE_PATTERN,
-- NATIONAL_ID_LENGTH), the retention of evidence
-- (AUDIT_ARCHIVE_AFTER_DAYS, REQUEST_LOG_RETENTION_DAYS), the media
-- gateway, and RECORDING_ENABLED - whose own description here says it is
-- never changed - are not settings a screen moves.
-- ---------------------------------------------------------------------
UPDATE hbh.sys_params
   SET editable_flg = true
 WHERE center_id IS NULL
   AND NOT editable_flg
   AND param_code IN (
     'ALLOW_BACKDATED_BOOKING_DAYS',
     'INVOICE_DUE_DAYS',
     'DEFAULT_TAX_RATE',
     'WAITLIST_OFFER_HOURS',
     'MAX_ATTACHMENT_MB',
     'BACKUP_MAX_AGE_HOURS',
     'MAINTENANCE_MAX_AGE_MIN',
     'DATE_DISPLAY_FORMAT',
     -- Editable: it decides how a screen offers times, not what may be
     -- booked. A centre that works on the half hour says so here instead
     -- of asking somebody to read PL/pgSQL.
     'SLOT_GRANULARITY_MIN'
   );

-- ---------------------------------------------------------------------
-- Lookup types and values
-- ---------------------------------------------------------------------
INSERT INTO hbh.lookup_types (code, name_ar, name_en) VALUES
  ('SERVICE_KIND',   'نوع الخدمة',        'Service kind'),
  ('RELATIONSHIP',   'صلة القرابة',        'Relationship'),
  ('REQUEST_KIND',   'نوع الطلب',          'Request kind'),
  ('REQUEST_STATUS', 'حالة الطلب',         'Request status')
ON CONFLICT (code) DO NOTHING;

INSERT INTO hbh.lookup_values (lookup_type_id, center_id, code, name_ar, name_en, sort_order)
SELECT t.lookup_type_id, NULL, v.code, v.name_ar, v.name_en, v.sort_order
FROM   hbh.lookup_types t
JOIN  (VALUES
        ('SERVICE_KIND', 'SPEECH',     'تخاطب وتنمية لغة',      'Speech therapy',        10),
        ('SERVICE_KIND', 'OT',         'علاج وظيفي',            'Occupational therapy',  20),
        ('SERVICE_KIND', 'ABA',        'تحليل سلوك تطبيقي',      'ABA',                   30),
        ('SERVICE_KIND', 'SKILLS',     'مهارات',                'Skills',                40),
        ('SERVICE_KIND', 'ASSESSMENT', 'تقييم',                 'Assessment',            50),
        -- Named by the owner as services the centre actually runs today.
        -- Source: docs/06-owner-brief-whatsapp-2026-09-03.md
        ('SERVICE_KIND', 'MUSIC',      'علاج بالموسيقى',        'Music therapy',         60),
        ('SERVICE_KIND', 'SENSORY',    'تكامل حسي',             'Sensory integration',   70),
        ('SERVICE_KIND', 'ACADEMIC',   'أكاديمي وصعوبات تعلّم',  'Academic support',      80),

        ('RELATIONSHIP', 'FATHER',     'الأب',                  'Father',                10),
        ('RELATIONSHIP', 'MOTHER',     'الأم',                  'Mother',                20),
        ('RELATIONSHIP', 'GUARDIAN',   'وليّ أمر',              'Legal guardian',        30),

        ('REQUEST_KIND', 'RESCHEDULE', 'تغيير موعد',            'Reschedule',            10),
        ('REQUEST_KIND', 'CANCEL',     'إلغاء موعد',            'Cancel',                20),
        ('REQUEST_KIND', 'CALLBACK',   'مكالمة من الأخصائي',    'Callback',              30),

        ('REQUEST_STATUS', 'NEW',      'قيد المراجعة',          'Under review',          10),
        ('REQUEST_STATUS', 'ACCEPTED', 'مقبول',                 'Accepted',              20),
        ('REQUEST_STATUS', 'REJECTED', 'مرفوض',                 'Rejected',              30)
      ) AS v(type_code, code, name_ar, name_en, sort_order)
  ON  v.type_code = t.code
ON CONFLICT (lookup_type_id, center_id, code) DO NOTHING;

-- ---------------------------------------------------------------------
-- The first administrator
--
-- No password and no login capability yet - authentication arrives in
-- 0002. This row exists so that identity resolves to a centre and the
-- policies can be exercised end to end today.
-- ---------------------------------------------------------------------
INSERT INTO hbh.users (center_id, branch_id, username, full_name_ar, user_type, status)
SELECT c.center_id, b.branch_id, 'admin', 'مدير النظام', 'STAFF', 'ACTIVE'
FROM   hbh.centers c
JOIN   hbh.branches b ON b.center_id = c.center_id AND b.code = 'MAIN'
WHERE  c.code = 'HBH'
AND NOT EXISTS (SELECT 1 FROM hbh.users u WHERE lower(u.username) = 'admin');
