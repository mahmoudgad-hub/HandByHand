-- =====================================================================
-- 0113 down - back to the separator-free pattern 0112 wrote
--
-- This puts back a value that refuses "+966 50 123 4567", which is how a
-- Gulf number is written. Going down past this migration means going
-- down past 0112 as well, and 0112's own down is where that is handled.
-- =====================================================================

\set ON_ERROR_STOP on

UPDATE hbh.sys_params
   SET param_value    = '^(\+[1-9][0-9]{7,14}|00[1-9][0-9]{7,14}|0[0-9]{6,14})$',
       description_ar = 'نمط رقم الجوّال كما يُكتَب — محلي أو دولي. شكل التخزين E.164 ويُفرَض في القاعدة',
       updated_at     = now(),
       updated_by     = hbh.current_app_user()
 WHERE param_code = 'MOBILE_PATTERN';

DELETE FROM hbh.schema_migrations WHERE version = '0113';
