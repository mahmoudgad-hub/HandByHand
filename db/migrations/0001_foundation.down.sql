-- =====================================================================
-- Hand By Hand (new) - migration 0001 DOWN
--
-- Development convenience only. This is never run against an
-- environment that holds real data: it drops the schema and everything
-- in it. Production corrections are new forward migrations.
-- =====================================================================

DROP SCHEMA IF EXISTS hbh CASCADE;

-- The role is cluster-wide, so its grants must go before it can be
-- dropped. Nothing outside this schema was ever granted to it.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'hbh_app') THEN
    EXECUTE 'DROP OWNED BY hbh_app';
    EXECUTE 'DROP ROLE hbh_app';
  END IF;
END
$$;
