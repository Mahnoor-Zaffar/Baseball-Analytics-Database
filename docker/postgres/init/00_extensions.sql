-- Runs once on first cluster init (postgres official image convention).
-- Enables observability + analytics-grade extensions. Idempotent.

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS pg_trgm;        -- substring search on player names
CREATE EXTENSION IF NOT EXISTS btree_gin;      -- composite GIN for ad-hoc filters
CREATE EXTENSION IF NOT EXISTS pgcrypto;       -- gen_random_uuid() for run IDs

-- Workspace schemas — separation of raw, marts, and analysis layers
CREATE SCHEMA IF NOT EXISTS raw;        -- landing zone for Lahman CSV copy
CREATE SCHEMA IF NOT EXISTS analytics;  -- materialized views, generated cols
CREATE SCHEMA IF NOT EXISTS marts;      -- dbt mart targets

COMMENT ON SCHEMA raw       IS 'Untouched Lahman tables loaded via \copy';
COMMENT ON SCHEMA analytics IS 'Generated columns, materialized views, helpers';
COMMENT ON SCHEMA marts     IS 'Curated, query-ready tables (dbt + manual)';
