-- =============================================================================
--  sql/baseball_awards.sql
--  Project : Baseball Analytics Database (Lahman 1871–2019)
--  Engine  : PostgreSQL 16
--
--  This is the canonical 6-award analytical script. Every block is wrapped
--  with EXPLAIN (ANALYZE, BUFFERS, VERBOSE, FORMAT TEXT) so plan regressions
--  show up in the CI diff of `plans/awards_*.log`.
--
--  Engineering principles applied throughout:
--    * Top-N (`ORDER BY … LIMIT 1`) instead of MAX subqueries — lets the
--      planner terminate the sort as soon as the leader is known.
--    * Composite (team_id, year_id) joins lean on V002 indexes.
--    * Materialized views (V004) absorb the heavy grouping work for awards
--      that reappear in dbt and the API.
--    * NULLIF(divisor, 0) guards every ratio.
--    * `\timing on` surfaces wall-clock for each statement; the planner
--      cost estimates are validated against actual runtime in BUFFERS.
-- =============================================================================
\set ON_ERROR_STOP on
\timing on
SET search_path TO raw, analytics, marts, public;
SET work_mem = '128MB';     -- generous for the hash aggregates below


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. HEAVIEST HITTERS AWARD
--    Historical (team_id, year_id) with the highest avg batter weight.
--    Reads from analytics.mv_team_physiques (pre-aggregated, indexed DESC).
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 1. HEAVIEST HITTERS ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    p.team_id,
    p.year_id,
    t.name                                 AS team_name,
    p.avg_weight_lbs,
    p.stddev_weight_lbs,
    p.batter_appearances
FROM   analytics.mv_team_physiques p
LEFT   JOIN raw.teams t
       ON t.team_id = p.team_id AND t.year_id = p.year_id
ORDER  BY p.avg_weight_lbs DESC NULLS LAST
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. SHORTEST SLUGGERS AWARD
--    Same materialized view, sorted ascending on height.
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 2. SHORTEST SLUGGERS ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    p.team_id,
    p.year_id,
    t.name                                 AS team_name,
    p.avg_height_in,
    p.stddev_height_in,
    p.batter_appearances
FROM   analytics.mv_team_physiques p
LEFT   JOIN raw.teams t
       ON t.team_id = p.team_id AND t.year_id = p.year_id
ORDER  BY p.avg_height_in ASC NULLS LAST
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. BIGGEST SPENDERS AWARD
--    Largest single-season payroll ever recorded. Single index seek on
--    idx_mv_team_payroll_total — O(log N).
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 3. BIGGEST SPENDERS ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    mp.year_id,
    mp.team_id,
    t.name                                 AS team_name,
    mp.total_payroll_usd,
    mp.roster_size,
    mp.median_salary_usd,
    mp.max_salary_usd
FROM   analytics.mv_team_payroll mp
LEFT   JOIN raw.teams t
       ON t.team_id = mp.team_id AND t.year_id = mp.year_id
ORDER  BY mp.total_payroll_usd DESC
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. MOST BANG FOR THEIR BUCK IN 2010
--    Lowest cost-per-win using SUM(salary) / teams.w.
--    Two predicates, both year_id = 2010, push the cardinality to ~30 rows
--    each side → Nested Loop with Index Scan is the optimal plan.
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 4. MOST BANG FOR THEIR BUCK (2010) ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    t.team_id,
    t.year_id,
    t.name                                            AS team_name,
    t.w                                               AS wins,
    mp.total_payroll_usd,
    ROUND(mp.total_payroll_usd::numeric / NULLIF(t.w, 0), 2) AS cost_per_win_usd
FROM   analytics.mv_team_payroll mp
JOIN   raw.teams t
       ON t.team_id = mp.team_id
      AND t.year_id = mp.year_id
WHERE  mp.year_id = 2010
  AND  t.year_id  = 2010                            -- predicate echo enables
                                                    -- partial index hit on both sides
  AND  t.w > 0                                      -- defensive; planner prunes IS NOT NULL
ORDER  BY cost_per_win_usd ASC
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. PRICIEST STARTER AWARD
--    Salary / games-started for any pitcher with gs >= 10.
--    Triple-key join (player_id, year_id, team_id) handles mid-season trades.
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 5. PRICIEST STARTER ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
SELECT
    pe.full_name                                                  AS pitcher,
    pi.player_id,
    pi.year_id,
    pi.team_id,
    pi.gs                                                         AS games_started,
    pi.innings_pitched,
    s.salary                                                      AS salary_usd,
    ROUND(s.salary::numeric / NULLIF(pi.gs, 0), 2)                AS cost_per_start_usd
FROM   raw.pitching pi
JOIN   raw.salaries s
       ON s.player_id = pi.player_id
      AND s.year_id   = pi.year_id
      AND s.team_id   = pi.team_id
JOIN   raw.people pe ON pe.player_id = pi.player_id
WHERE  pi.gs >= 10
ORDER  BY cost_per_start_usd DESC NULLS LAST
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CUSTOM CREATIVE AWARD — "CANADIAN ACE"
--    Lowest single-season ERA for a pitcher on a Canadian franchise.
--    Canadian historical team_ids:
--        TOR — Toronto Blue Jays   (1977 – present)
--        MON — Montreal Expos      (1969 – 2004; relocated to WSN)
--    Filters:
--        era > 0           (drops 0.00 ERA small-sample noise)
--        ipouts >= 162     (≥ 54 IP qualifying floor)
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── 6. CANADIAN ACE ────────'
EXPLAIN (ANALYZE, BUFFERS, VERBOSE)
WITH canadian_qualifiers AS (
    SELECT  pi.player_id,
            pi.year_id,
            pi.team_id,
            pi.era,
            pi.innings_pitched,
            pi.k_per_9,
            pi.bb_per_9,
            RANK() OVER (ORDER BY pi.era ASC, pi.ipouts DESC) AS canadian_era_rank
    FROM    raw.pitching pi
    WHERE   pi.team_id IN ('TOR', 'MON')
      AND   pi.era IS NOT NULL
      AND   pi.era > 0
      AND   pi.ipouts >= 162
)
SELECT
    pe.full_name                            AS pitcher,
    cq.team_id                              AS canadian_team,
    cq.year_id                              AS season,
    cq.innings_pitched,
    cq.era                                  AS earned_run_average,
    cq.k_per_9,
    cq.bb_per_9,
    cq.canadian_era_rank
FROM   canadian_qualifiers cq
JOIN   raw.people pe ON pe.player_id = cq.player_id
WHERE  cq.canadian_era_rank = 1
LIMIT  1;


-- ─────────────────────────────────────────────────────────────────────────────
-- Plan-archive trailer: emit the JSON plan of the most contentious query
-- (Award #4) so CI can diff it against the previous run.
-- ─────────────────────────────────────────────────────────────────────────────
\echo
\echo '──────── Award #4 plan (JSON, archivable) ────────'
EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)
SELECT t.team_id,
       ROUND(mp.total_payroll_usd::numeric / NULLIF(t.w, 0), 2) AS cost_per_win_usd
FROM   analytics.mv_team_payroll mp
JOIN   raw.teams t ON t.team_id = mp.team_id AND t.year_id = mp.year_id
WHERE  mp.year_id = 2010 AND t.year_id = 2010 AND t.w > 0
ORDER  BY cost_per_win_usd ASC
LIMIT  1;
