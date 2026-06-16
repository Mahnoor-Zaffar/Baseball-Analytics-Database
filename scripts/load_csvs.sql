-- =============================================================================
-- load_csvs.sql
-- Schema definition + COPY-based load for the Lahman CSV bundle.
-- Run inside the Postgres container so /workspace/data/raw is reachable.
--
-- Engineering notes:
--   * Uses `raw.*` schema as the landing zone (no PII, no business logic).
--   * UNLOGGED tables during initial load → 3-5x faster COPY throughput; we
--     promote to LOGGED via ALTER TABLE after population in migrations/V001.
--   * Composite primary keys mirror Lahman documentation.
--   * Column names normalized to snake_case for downstream consistency.
-- =============================================================================
\set ON_ERROR_STOP on
\timing on

SET search_path = raw, public;

-- ---------------------------------------------------------------------------
-- PEOPLE
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS raw.people CASCADE;
CREATE UNLOGGED TABLE raw.people (
    player_id       text PRIMARY KEY,
    birth_year      int,
    birth_month     int,
    birth_day       int,
    birth_country   text,
    birth_state     text,
    birth_city      text,
    death_year      int,
    death_month     int,
    death_day       int,
    death_country   text,
    death_state     text,
    death_city      text,
    name_first      text,
    name_last       text,
    name_given      text,
    weight          int,
    height          int,
    bats            text,
    throws          text,
    debut           date,
    final_game      date,
    retro_id        text,
    bbref_id        text
);
\copy raw.people FROM '/workspace/data/raw/People.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- TEAMS
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS raw.teams CASCADE;
CREATE UNLOGGED TABLE raw.teams (
    year_id         int,
    lg_id           text,
    team_id         text,
    franch_id       text,
    div_id          text,
    team_rank       int,
    g               int,
    ghome           int,
    w               int,
    l               int,
    div_win         text,
    wc_win          text,
    lg_win          text,
    ws_win          text,
    r               int,
    ab              int,
    h               int,
    "2b"            int,
    "3b"            int,
    hr              int,
    bb              int,
    so              int,
    sb              int,
    cs              int,
    hbp             int,
    sf              int,
    ra              int,
    er              int,
    era             numeric(5,2),
    cg              int,
    sho             int,
    sv              int,
    ipouts          int,
    ha              int,
    hra             int,
    bba             int,
    soa             int,
    e               int,
    dp              int,
    fp              numeric(5,3),
    name            text,
    park            text,
    attendance      int,
    bpf             int,
    ppf             int,
    team_id_br      text,
    team_id_lahman45 text,
    team_id_retro   text,
    PRIMARY KEY (year_id, team_id)
);
\copy raw.teams FROM '/workspace/data/raw/Teams.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- BATTING
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS raw.batting CASCADE;
CREATE UNLOGGED TABLE raw.batting (
    player_id       text,
    year_id         int,
    stint           int,
    team_id         text,
    lg_id           text,
    g               int,
    ab              int,
    r               int,
    h               int,
    "2b"            int,
    "3b"            int,
    hr              int,
    rbi             int,
    sb              int,
    cs              int,
    bb              int,
    so              int,
    ibb             int,
    hbp             int,
    sh              int,
    sf              int,
    gidp            int,
    PRIMARY KEY (player_id, year_id, stint)
);
\copy raw.batting FROM '/workspace/data/raw/Batting.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- PITCHING
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS raw.pitching CASCADE;
CREATE UNLOGGED TABLE raw.pitching (
    player_id       text,
    year_id         int,
    stint           int,
    team_id         text,
    lg_id           text,
    w               int,
    l               int,
    g               int,
    gs              int,
    cg              int,
    sho             int,
    sv              int,
    ipouts          int,
    h               int,
    er              int,
    hr              int,
    bb              int,
    so              int,
    baopp           numeric(5,3),
    era             numeric(6,2),
    ibb             int,
    wp              int,
    hbp             int,
    bk              int,
    bfp             int,
    gf              int,
    r               int,
    sh              int,
    sf              int,
    gidp            int,
    PRIMARY KEY (player_id, year_id, stint)
);
\copy raw.pitching FROM '/workspace/data/raw/Pitching.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- SALARIES
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS raw.salaries CASCADE;
CREATE UNLOGGED TABLE raw.salaries (
    year_id         int,
    team_id         text,
    lg_id           text,
    player_id       text,
    salary          numeric(12,2),
    PRIMARY KEY (year_id, team_id, lg_id, player_id)
);
\copy raw.salaries FROM '/workspace/data/raw/Salaries.csv' WITH (FORMAT csv, HEADER true, NULL '');

-- ---------------------------------------------------------------------------
-- ALL OTHER LAHMAN TABLES (fielding, awards, schools, etc.)
-- Loaded into raw.* automatically by generic loader script if present.
-- ---------------------------------------------------------------------------
-- Skipping for brevity in v1; add as needed in raw.* using same pattern.

-- ---------------------------------------------------------------------------
-- Promote to LOGGED tables so they survive a crash, then analyze for planner.
-- ---------------------------------------------------------------------------
ALTER TABLE raw.people   SET LOGGED;
ALTER TABLE raw.teams    SET LOGGED;
ALTER TABLE raw.batting  SET LOGGED;
ALTER TABLE raw.pitching SET LOGGED;
ALTER TABLE raw.salaries SET LOGGED;

ANALYZE raw.people;
ANALYZE raw.teams;
ANALYZE raw.batting;
ANALYZE raw.pitching;
ANALYZE raw.salaries;

-- Expose unqualified table names to all downstream queries.
ALTER DATABASE :"DBNAME" SET search_path TO raw, analytics, marts, public;

\echo ''
\echo '✓ Load complete. Row counts:'
SELECT 'people'   AS table_name, count(*) AS rows FROM raw.people
UNION ALL SELECT 'teams',    count(*) FROM raw.teams
UNION ALL SELECT 'batting',  count(*) FROM raw.batting
UNION ALL SELECT 'pitching', count(*) FROM raw.pitching
UNION ALL SELECT 'salaries', count(*) FROM raw.salaries
ORDER BY 1;
