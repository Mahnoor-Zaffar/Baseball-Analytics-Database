-- =============================================================================
-- V002 — Performance indexes
--
-- The Lahman PKs are great for transactional lookups but not for the analytical
-- access patterns we care about. Specifically:
--   * Awards #1/#2: group-by (team_id, year_id) → need leading (team_id, year_id)
--   * Award #4    : year_id = 2010 filter + dual-key join to teams
--   * Award #5    : triple-key join (player_id, year_id, team_id) on pitching
--   * Award #6    : filtered scan on (team_id IN (...), era IS NOT NULL)
--
-- Every index is created with IF NOT EXISTS so the migration is re-runnable.
-- CONCURRENTLY is intentionally NOT used here — it cannot run inside a
-- transaction block and we want the whole migration to be atomic on first run.
-- For production hot-patching, peel these out and run CONCURRENTLY manually.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO raw, analytics, public;

-- BATTING ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_batting_team_year
    ON raw.batting (team_id, year_id);
CREATE INDEX IF NOT EXISTS idx_batting_player_year
    ON raw.batting (player_id, year_id);
CREATE INDEX IF NOT EXISTS idx_batting_year
    ON raw.batting (year_id);

-- PITCHING --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pitching_team_year
    ON raw.pitching (team_id, year_id);
CREATE INDEX IF NOT EXISTS idx_pitching_player_year_team
    ON raw.pitching (player_id, year_id, team_id);
-- Partial index: only the rows that actually qualify for ERA leaderboards.
-- Drastically smaller than a full index → fits in shared_buffers.
CREATE INDEX IF NOT EXISTS idx_pitching_era_qualified
    ON raw.pitching (era)
    WHERE era IS NOT NULL AND ipouts >= 162;
-- Covering index for the "priciest starter" qualifying filter.
CREATE INDEX IF NOT EXISTS idx_pitching_gs_threshold
    ON raw.pitching (gs)
    INCLUDE (player_id, year_id, team_id)
    WHERE gs >= 10;

-- SALARIES --------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_salaries_year_team
    ON raw.salaries (year_id, team_id);
CREATE INDEX IF NOT EXISTS idx_salaries_player_year_team
    ON raw.salaries (player_id, year_id, team_id);
-- A 2010-only partial index: ~1 KB, used by Award #4 cold.
CREATE INDEX IF NOT EXISTS idx_salaries_2010
    ON raw.salaries (team_id)
    WHERE year_id = 2010;

-- PEOPLE ----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_people_weight_notnull
    ON raw.people (player_id)
    WHERE weight IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_people_height_notnull
    ON raw.people (player_id)
    WHERE height IS NOT NULL;
-- Trigram index supports ILIKE name searches from the API layer.
CREATE INDEX IF NOT EXISTS idx_people_name_trgm
    ON raw.people USING gin ((name_first || ' ' || name_last) gin_trgm_ops);

-- TEAMS -----------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_teams_year
    ON raw.teams (year_id);

-- Refresh statistics for the planner after creating new indexes.
ANALYZE raw.batting;
ANALYZE raw.pitching;
ANALYZE raw.salaries;
ANALYZE raw.people;
ANALYZE raw.teams;

INSERT INTO analytics.schema_migrations(version, checksum)
VALUES ('V002__performance_indexes', md5('V002'))
ON CONFLICT (version) DO NOTHING;
