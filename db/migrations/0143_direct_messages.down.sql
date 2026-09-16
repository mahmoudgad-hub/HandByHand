-- Existing private messages must never be dropped by a rollback.
DO $$ BEGIN RAISE EXCEPTION '0143 retains sent messages. Disable the routes to roll back the application; do not drop conversation data.'; END $$;
