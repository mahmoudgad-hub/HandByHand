-- =====================================================================
-- 0047 - the site's services, attached to the catalogue rather than
--        beside it
--
-- THE NUMBERS THAT DECIDED THE SHAPE. site/index.html advertises eight
-- services:
--
--   تخاطب وتنمية لغة · علاج وظيفي · تحليل سلوك تطبيقي (ABA) · مهارات
--   تقييم · علاج بالموسيقى · تكامل حسّي · أكاديمي وصعوبات تعلّم
--
-- hbh.services holds three active rows, two of which are both speech:
--
--   جلسة تخاطب · علاج وظيفي · تخاطب
--
-- So SIX of the eight things this centre advertises cannot be booked by
-- the system that runs it. Whichever way that gap is closed, a second
-- independent list of services would hide it: the site would go on
-- promising six services no appointment can be made for, and nothing
-- would ever say so.
--
-- Hence the shape here. This table carries MARKETING TEXT FOR A ROW OF
-- hbh.services and nothing else. There is no title of its own - the name
-- comes from the catalogue - and service_id is NOT NULL, so a service
-- cannot be advertised into existence. Adding one to the site means
-- adding it to the catalogue first, which is the honest order: the
-- centre decides it offers a thing, and then says so.
--
-- WHAT THIS COSTS TODAY, stated plainly rather than discovered later:
-- exporting now would put two services on a page that shows eight. The
-- fix is to fill the catalogue - the centre really does offer ABA and
-- sensory integration - not to loosen this table.
-- =====================================================================

\set ON_ERROR_STOP on

CREATE TABLE hbh.site_services (
  site_service_id integer     GENERATED ALWAYS AS IDENTITY,
  center_id       integer     NOT NULL,

  -- The service being described. NOT NULL and a foreign key: this is the
  -- whole point of the table.
  service_id      integer     NOT NULL,

  -- Marketing copy only. The NAME is not here - it is the catalogue's,
  -- so the page and the booking screen can never disagree about what a
  -- service is called.
  blurb_ar        text        NOT NULL,
  blurb_en        text,

  -- One of the icons already drawn into index.html. Free text renders
  -- nothing at all, so the screen offers a list.
  icon_key        text,

  sort_order      integer     NOT NULL DEFAULT 0,

  status          text        NOT NULL DEFAULT 'DRAFT',
  published_at    timestamptz,
  published_by    integer,

  active_flg      boolean     NOT NULL DEFAULT true,
  deleted_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  created_by      text        NOT NULL DEFAULT hbh.current_app_user(),
  updated_at      timestamptz,
  updated_by      text,

  CONSTRAINT pk_site_services PRIMARY KEY (site_service_id),
  CONSTRAINT fk_ssv_center    FOREIGN KEY (center_id)    REFERENCES hbh.centers (center_id),
  CONSTRAINT fk_ssv_service   FOREIGN KEY (service_id)   REFERENCES hbh.services (service_id),
  CONSTRAINT fk_ssv_publisher FOREIGN KEY (published_by) REFERENCES hbh.users (user_id),
  -- One description per service. Two would be two answers to the same
  -- question, and whichever sorted first would win silently.
  CONSTRAINT uq_site_services UNIQUE (service_id),
  CONSTRAINT ck_ssv_status    CHECK (status IN ('DRAFT', 'PUBLISHED')),
  CONSTRAINT ck_ssv_published CHECK (
    status = 'DRAFT' OR (published_at IS NOT NULL AND published_by IS NOT NULL)
  ),
  CONSTRAINT ck_ssv_blurb     CHECK (length(btrim(blurb_ar)) BETWEEN 1 AND 200)
);

CREATE INDEX ix_site_services_order ON hbh.site_services (center_id, sort_order)
  WHERE active_flg;
CREATE INDEX ix_site_services_service ON hbh.site_services (service_id);

CREATE TRIGGER trg_site_services_touch BEFORE UPDATE ON hbh.site_services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_touch();
CREATE TRIGGER trg_site_services_audit AFTER INSERT OR UPDATE OR DELETE ON hbh.site_services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_audit('site_service_id');
CREATE TRIGGER trg_site_services_publish BEFORE INSERT OR UPDATE ON hbh.site_services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_guard();
CREATE TRIGGER trg_site_services_stamp BEFORE INSERT OR UPDATE ON hbh.site_services
  FOR EACH ROW EXECUTE FUNCTION hbh.trg_site_publish_stamp();

ALTER TABLE hbh.site_services ENABLE ROW LEVEL SECURITY;

CREATE POLICY p_site_services_select ON hbh.site_services
  FOR SELECT TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND active_flg
         AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_services_insert ON hbh.site_services
  FOR INSERT TO hbh_app
  WITH CHECK (hbh.current_center_id() IS NOT NULL
              AND center_id = hbh.current_center_id()
              AND hbh.has_permission('SITE.EDIT'));

CREATE POLICY p_site_services_update ON hbh.site_services
  FOR UPDATE TO hbh_app
  USING (hbh.current_center_id() IS NOT NULL
         AND center_id = hbh.current_center_id()
         AND hbh.has_permission('SITE.EDIT'))
  WITH CHECK (center_id = hbh.current_center_id());

GRANT SELECT, INSERT, UPDATE ON hbh.site_services TO hbh_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA hbh TO hbh_app;

INSERT INTO hbh.schema_migrations (version) VALUES ('0047');
