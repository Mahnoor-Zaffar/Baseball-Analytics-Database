-- =============================================================================
-- V001 — Base schema is created by `scripts/load_csvs.sql` (run via `make load`).
-- This migration is a sentinel + post-load housekeeping step.
-- =============================================================================
\set ON_ERROR_STOP on

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'raw' AND tablename IN ('people','teams','batting','pitching','salaries')
        GROUP BY 1
        HAVING count(*) = 5
    ) THEN
        RAISE EXCEPTION USING
            ERRCODE = 'undefined_table',
            MESSAGE = 'Base schema not loaded. Run `make load` first.';
    END IF;
END$$;

-- Record applied migration in a small ledger table (poor man's flyway_schema_history)
CREATE TABLE IF NOT EXISTS analytics.schema_migrations (
    version     text PRIMARY KEY,
    applied_at  timestamptz NOT NULL DEFAULT now(),
    checksum    text
);

INSERT INTO analytics.schema_migrations(version, checksum)
VALUES ('V001__base_schema_notes', md5('V001'))
ON CONFLICT (version) DO NOTHING;

VACUUM (ANALYZE) raw.people;
VACUUM (ANALYZE) raw.teams;
VACUUM (ANALYZE) raw.batting;
VACUUM (ANALYZE) raw.pitching;
VACUUM (ANALYZE) raw.salaries;
