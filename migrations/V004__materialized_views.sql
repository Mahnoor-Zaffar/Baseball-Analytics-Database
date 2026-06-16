-- =============================================================================
-- V004 — Materialized views
--
-- Two patterns appear in every analytical query and are worth caching:
--   1. team-season payroll  (used by Awards #3, #4 and dbt marts)
--   2. team-season roster physiques (Awards #1, #2)
--   3. league-season pitching baseline (used by era-adjusted ERA)
--
-- All views are CREATEd in `analytics.*`, refreshed CONCURRENTLY (so reads
-- never block), and indexed on their natural keys.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

-- ---------------------------------------------------------------------------
-- 1. Team-season payroll
-- ---------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS analytics.mv_team_payroll CASCADE;
CREATE MATERIALIZED VIEW analytics.mv_team_payroll AS
SELECT
    s.year_id,
    s.team_id,
    s.lg_id,
    COUNT(*)                AS roster_size,
    SUM(s.salary)::bigint   AS total_payroll_usd,
    AVG(s.salary)::numeric(12,2) AS avg_salary_usd,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY s.salary) AS median_salary_usd,
    MAX(s.salary)           AS max_salary_usd
FROM raw.salaries s
GROUP BY s.year_id, s.team_id, s.lg_id;

CREATE UNIQUE INDEX idx_mv_team_payroll_pk
    ON analytics.mv_team_payroll (year_id, team_id, lg_id);
CREATE INDEX idx_mv_team_payroll_total
    ON analytics.mv_team_payroll (total_payroll_usd DESC);

-- ---------------------------------------------------------------------------
-- 2. Team-season roster physiques
-- ---------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS analytics.mv_team_physiques CASCADE;
CREATE MATERIALIZED VIEW analytics.mv_team_physiques AS
SELECT
    b.team_id,
    b.year_id,
    COUNT(*)                                       AS batter_appearances,
    AVG(p.weight)::numeric(6,2)                    AS avg_weight_lbs,
    AVG(p.height)::numeric(6,2)                    AS avg_height_in,
    STDDEV_SAMP(p.weight)::numeric(6,2)            AS stddev_weight_lbs,
    STDDEV_SAMP(p.height)::numeric(6,2)            AS stddev_height_in
FROM   raw.batting b
JOIN   raw.people  p ON p.player_id = b.player_id
WHERE  p.weight IS NOT NULL OR p.height IS NOT NULL
GROUP  BY b.team_id, b.year_id;

CREATE UNIQUE INDEX idx_mv_team_physiques_pk
    ON analytics.mv_team_physiques (team_id, year_id);
CREATE INDEX idx_mv_team_physiques_weight
    ON analytics.mv_team_physiques (avg_weight_lbs DESC);
CREATE INDEX idx_mv_team_physiques_height
    ON analytics.mv_team_physiques (avg_height_in ASC);

-- ---------------------------------------------------------------------------
-- 3. League-season pitching baseline (used by era-adjusted ERA z-scores)
-- ---------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS analytics.mv_league_pitching_baseline CASCADE;
CREATE MATERIALIZED VIEW analytics.mv_league_pitching_baseline AS
SELECT
    pi.year_id,
    pi.lg_id,
    COUNT(*)                                      AS qualified_pitchers,
    AVG(pi.era) FILTER (WHERE pi.ipouts >= 162)::numeric(6,3) AS league_era_mean,
    STDDEV_SAMP(pi.era) FILTER (WHERE pi.ipouts >= 162)::numeric(6,3) AS league_era_stddev
FROM   raw.pitching pi
WHERE  pi.era IS NOT NULL AND pi.era > 0
GROUP  BY pi.year_id, pi.lg_id;

CREATE UNIQUE INDEX idx_mv_lpb_pk
    ON analytics.mv_league_pitching_baseline (year_id, lg_id);

-- ---------------------------------------------------------------------------
-- Refresh helper — wrap REFRESH MATERIALIZED VIEW CONCURRENTLY in a function
-- so an operator can refresh all three with a single call.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION analytics.refresh_all_mvs() RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_team_payroll;
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_team_physiques;
    REFRESH MATERIALIZED VIEW CONCURRENTLY analytics.mv_league_pitching_baseline;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION analytics.refresh_all_mvs IS
    'Refresh all analytical materialized views concurrently. Safe to call live.';

INSERT INTO analytics.schema_migrations(version, checksum)
VALUES ('V004__materialized_views', md5('V004'))
ON CONFLICT (version) DO NOTHING;
