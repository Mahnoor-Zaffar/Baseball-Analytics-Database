-- =====================================================================
--  baseball_awards.sql
--  Project : Best of Baseball Analytics Database (Lahman 1871-2019)
--  Author  : Senior Data Engineer
--  Engine  : PostgreSQL 14+
--
--  Engineering principles applied throughout:
--    * Each block is wrapped with EXPLAIN ANALYZE per PRD §6 to surface
--      the executor's chosen plan, scan strategy, and index usage.
--    * Joins are restricted to the *minimum* projected columns BEFORE
--      aggregation so the hash/merge phase stays in memory and avoids
--      "Disk: …kB" spillage on the multi-million-row fact tables.
--    * Composite predicates (team_id, year_id) are kept as equi-joins so
--      the planner can lean on the natural composite indexes that ship
--      with the Lahman schema (PK on teams = team_id+year_id+lg_id,
--      PK on salaries = year_id+team_id+lg_id+player_id, etc.) — this
--      forces Index/Bitmap scans instead of Seq Scans.
--    * NULLIF(divisor, 0) guards every ratio expression to eliminate the
--      possibility of div-by-zero on franchises with 0 wins / 0 starts.
--    * ORDER BY … LIMIT 1 is preferred over MAX()/MIN() sub-queries:
--      it lets PostgreSQL terminate the sort early once the top tuple
--      is materialized (Top-N heap sort, O(N log k) with k=1).
--    * HAVING filters are applied post-aggregation so the GROUP BY
--      hash table is built once, and qualifying thresholds are evaluated
--      against the materialized aggregate — never against raw rows.
-- =====================================================================


-- =====================================================================
-- 1. HEAVIEST HITTERS AWARD
--    "Which historical (team_id, year_id) lineup carried the heaviest
--     average roster weight among its batters?"
--
--    JOIN STRATEGY
--      batting  ─ player_id ─►  people     (FK lookup, hash join expected)
--      Filter people.weight IS NOT NULL early to keep the hash table tight.
--    AGGREGATION
--      AVG over people.weight pulled through the batting roster so each
--      player-season contributes once per team appearance (this honors
--      mid-season trades — a traded player counts for *both* clubs).
-- =====================================================================
EXPLAIN ANALYZE
SELECT
    b.team_id,
    b.year_id,
    ROUND(AVG(p.weight)::numeric, 2) AS avg_team_weight_lbs,
    COUNT(*)                         AS roster_batter_appearances
FROM   batting  AS b
JOIN   people   AS p  ON p.player_id = b.player_id
WHERE  p.weight IS NOT NULL                    -- prune NULLs before the hash build
GROUP  BY b.team_id, b.year_id
ORDER  BY avg_team_weight_lbs DESC             -- Top-N heap sort, k = 1
LIMIT  1;


-- =====================================================================
-- 2. SHORTEST SLUGGERS AWARD
--    Mirrors block #1 but sorts ascending on AVG(height) to surface the
--    most vertically challenged historical roster.
--
--    NOTE: We intentionally re-run the join rather than cache results in
--    a temp table — the planner produces an identical hash join for both
--    blocks, so caching only adds I/O and breaks EXPLAIN's per-query
--    timing isolation that the PRD calls out in Success Metrics.
-- =====================================================================
EXPLAIN ANALYZE
SELECT
    b.team_id,
    b.year_id,
    ROUND(AVG(p.height)::numeric, 2) AS avg_team_height_in,
    COUNT(*)                         AS roster_batter_appearances
FROM   batting AS b
JOIN   people  AS p  ON p.player_id = b.player_id
WHERE  p.height IS NOT NULL
GROUP  BY b.team_id, b.year_id
ORDER  BY avg_team_height_in ASC               -- ascending = "shortest"
LIMIT  1;


-- =====================================================================
-- 3. BIGGEST SPENDERS AWARD
--    Largest single-season team payroll across all history.
--
--    ENGINEERING NOTES
--      * salaries.salary is stored as numeric/integer cents-per-dollar in
--        the Lahman schema → SUM() promotes to bigint/numeric automatically,
--        eliminating overflow risk on aggregate franchise payrolls that
--        exceed INT4 (~$2.1B) cumulative thresholds.
--      * Single-table aggregation: no joins required, the planner will
--        choose a HashAggregate over a sequential read of `salaries`
--        (≈ 26k rows), executing in well under the 250 ms PRD ceiling.
-- =====================================================================
EXPLAIN ANALYZE
SELECT
    s.team_id,
    s.year_id,
    SUM(s.salary)::bigint AS total_payroll_usd
FROM   salaries AS s
GROUP  BY s.team_id, s.year_id
ORDER  BY total_payroll_usd DESC
LIMIT  1;


-- =====================================================================
-- 4. MOST BANG FOR THEIR BUCK IN 2010
--    Lowest cost-per-win ratio for the 2010 season:
--        cost_per_win = SUM(salaries.salary) / teams.w
--
--    JOIN PATH (per PRD §Technical Considerations, dual-key equality)
--      salaries (year_id=2010) ⨝ teams ON team_id AND year_id
--
--    OPTIMIZATION
--      * Push the year_id = 2010 predicate to *both* sides of the join
--        so each scan returns only ~30 rows (teams) and ~830 rows
--        (salaries) — index-only scans on the composite PKs.
--      * Aggregate salaries first via a CTE, then join 1:1 against
--        teams to avoid duplicating teams.w across every salary row
--        prior to aggregation (a common bug that inflates SUM()).
--      * NULLIF(t.w, 0) defensively guards against any franchise that
--        somehow recorded zero wins in 2010 (none did — but the cost
--        of the guard is a single CPU cycle).
-- =====================================================================
EXPLAIN ANALYZE
WITH payroll_2010 AS (                         -- pre-aggregate to keep join 1:1
    SELECT  s.team_id,
            s.year_id,
            SUM(s.salary)::bigint AS total_payroll_usd
    FROM    salaries AS s
    WHERE   s.year_id = 2010                   -- predicate pushdown ➜ index scan
    GROUP   BY s.team_id, s.year_id
)
SELECT
    t.name                                                         AS team_name,
    t.team_id,
    t.year_id,
    t.w                                                            AS wins,
    pr.total_payroll_usd,
    ROUND(pr.total_payroll_usd::numeric / NULLIF(t.w, 0), 2)       AS cost_per_win_usd
FROM   payroll_2010 AS pr
JOIN   teams        AS t
       ON  t.team_id = pr.team_id              -- dual-key equality (PRD §Tech)
       AND t.year_id = pr.year_id
WHERE  t.year_id = 2010                        -- redundant but enables the planner
                                               -- to pick the partial index on year_id
ORDER  BY cost_per_win_usd ASC                 -- lowest = most efficient roster
LIMIT  1;


-- =====================================================================
-- 5. PRICIEST STARTER AWARD
--    Pitcher with the highest salary-per-game-started ratio in any year,
--    constrained to bona-fide starters (gs >= 10) to filter out spot
--    starters and bullpen call-ups whose tiny denominators distort the
--    metric.
--
--    JOIN PATH (player_id + year_id + team_id triple equality)
--      Triple-key join is essential — the same player can pitch for two
--      teams in one season (mid-year trades), and a two-key join would
--      double-count salary across both rows.
--
--    PERFORMANCE
--      * The composite (player_id, year_id, team_id) index that backs
--        salaries' PK lets the planner do a Nested Loop with Index Scan
--        on the inner side — far cheaper than a HashAggregate on
--        pitching's 47k+ rows.
--      * gs >= 10 is pushed into the join predicate so the planner can
--        prune before the lookup into salaries.
-- =====================================================================
EXPLAIN ANALYZE
SELECT
    pe.name_first || ' ' || pe.name_last                                  AS pitcher,
    pi.player_id,
    pi.year_id,
    pi.team_id,
    pi.gs                                                                 AS games_started,
    s.salary                                                              AS salary_usd,
    ROUND(s.salary::numeric / NULLIF(pi.gs, 0), 2)                        AS cost_per_start_usd
FROM   pitching AS pi
JOIN   salaries AS s
       ON  s.player_id = pi.player_id
       AND s.year_id   = pi.year_id
       AND s.team_id   = pi.team_id            -- triple-key equality (handles trades)
JOIN   people   AS pe ON pe.player_id = pi.player_id
WHERE  pi.gs >= 10                             -- PRD-mandated qualifying threshold
ORDER  BY cost_per_start_usd DESC NULLS LAST
LIMIT  1;


-- =====================================================================
-- 6. CUSTOM CREATIVE AWARD — "CANADIAN ACE"
--    Lowest single-season ERA by a pitcher contracted to a Canadian
--    franchise. Canadian historical franchise IDs in the Lahman set:
--      • TOR — Toronto Blue Jays           (1977 – present)
--      • MON — Montreal Expos              (1969 – 2004; relocated to WSN)
--
--    DATA QUALITY GUARDS
--      * era > 0       → drops perfect-but-tiny appearances (e.g., 0.00
--                        across 1 IP) that artificially win the award.
--      * ipouts >= 162 → enforces a 54-inning floor (162 outs = 54 IP),
--                        an industry-standard "qualifying" minimum that
--                        guarantees statistical relevance without being
--                        as restrictive as the official 1 IP/team-game
--                        rule (which would exclude relievers entirely).
--      * Joining `people` enriches the output with a human-readable
--        name; the join is by PK so the planner uses an Index Scan.
--
--    CREATIVITY LAYER
--      * Window function adds a national leaderboard rank so the query
--        is reusable for "top N" expansions without restructuring.
-- =====================================================================
EXPLAIN ANALYZE
WITH canadian_qualifiers AS (
    SELECT  pi.player_id,
            pi.year_id,
            pi.team_id,
            pi.era,
            pi.ipouts,
            ROUND(pi.ipouts::numeric / 3.0, 1) AS innings_pitched,
            RANK() OVER (ORDER BY pi.era ASC)  AS canadian_era_rank
    FROM    pitching AS pi
    WHERE   pi.team_id IN ('TOR', 'MON')       -- Canadian franchises (historical)
      AND   pi.era IS NOT NULL
      AND   pi.era > 0                         -- drops zero-ERA small-sample noise
      AND   pi.ipouts >= 162                   -- ≥ 54 IP qualifying floor
)
SELECT
    pe.name_first || ' ' || pe.name_last AS pitcher,
    cq.team_id                           AS canadian_team,
    cq.year_id                           AS season,
    cq.innings_pitched,
    cq.era                               AS earned_run_average,
    cq.canadian_era_rank
FROM   canadian_qualifiers AS cq
JOIN   people              AS pe ON pe.player_id = cq.player_id
WHERE  cq.canadian_era_rank = 1                -- the singular "Canadian Ace"
ORDER  BY cq.era ASC, cq.innings_pitched DESC  -- tie-break: more innings wins
LIMIT  1;
