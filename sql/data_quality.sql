-- =============================================================================
--  data_quality.sql — Data quality report over the raw Lahman tables.
--
--  Outputs a single result set with one row per check + status. Status values:
--      PASS — invariant holds
--      WARN — non-fatal anomaly (e.g., expected historical NULL ratio)
--      FAIL — referential/structural failure (exits non-zero in CI)
--
--  Categories of checks:
--    1. Row counts vs. expected order of magnitude (smoke test).
--    2. PK uniqueness (defensive — load script enforces, but post-migration?).
--    3. NULL ratios on critical columns (height/weight, era, salary).
--    4. Referential integrity (orphan player_id / team_id / year_id).
--    5. Range sanity (salary > 0, weight 100-400, height 50-90, gs >= 0).
--    6. Mid-season trade integrity (stint sequencing).
--
--  Run via: `make dq` (results to stdout). The trailing assertion raises if
--  any check is FAIL — used by CI.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO raw, public;

DROP TABLE IF EXISTS pg_temp.dq_results;
CREATE TEMP TABLE pg_temp.dq_results (
    category    text,
    check_name  text,
    status      text,
    observed    text,
    expected    text,
    note        text
);

-- ── 1. Row counts ────────────────────────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'rowcount', 'people',   CASE WHEN c > 18000 THEN 'PASS' ELSE 'FAIL' END,
       c::text, '> 18000', 'Lahman 2023 carries ~20k people'
FROM (SELECT count(*) c FROM raw.people) q
UNION ALL
SELECT 'rowcount', 'teams',    CASE WHEN c > 2800  THEN 'PASS' ELSE 'FAIL' END,
       c::text, '> 2800', 'One row per team-year since 1871'
FROM (SELECT count(*) c FROM raw.teams) q
UNION ALL
SELECT 'rowcount', 'batting',  CASE WHEN c > 100000 THEN 'PASS' ELSE 'FAIL' END,
       c::text, '> 100000', NULL
FROM (SELECT count(*) c FROM raw.batting) q
UNION ALL
SELECT 'rowcount', 'pitching', CASE WHEN c > 47000  THEN 'PASS' ELSE 'FAIL' END,
       c::text, '> 47000', NULL
FROM (SELECT count(*) c FROM raw.pitching) q
UNION ALL
SELECT 'rowcount', 'salaries', CASE WHEN c > 26000  THEN 'PASS' ELSE 'FAIL' END,
       c::text, '> 26000', 'Salaries only from 1985 onward'
FROM (SELECT count(*) c FROM raw.salaries) q;

-- ── 2. Primary key uniqueness ───────────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'uniqueness', 'people.player_id', CASE WHEN n = c THEN 'PASS' ELSE 'FAIL' END,
       n::text || ' / ' || c::text, 'equal', NULL
FROM (SELECT count(DISTINCT player_id) n, count(*) c FROM raw.people) q;

-- ── 3. NULL ratios ──────────────────────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'nullratio', 'people.weight',
       CASE WHEN pct < 5.0 THEN 'PASS' WHEN pct < 25.0 THEN 'WARN' ELSE 'FAIL' END,
       round(pct, 2)::text || '%', '< 5%', 'Pre-1900 records often missing'
FROM (
    SELECT 100.0 * count(*) FILTER (WHERE weight IS NULL) / count(*)::numeric AS pct
    FROM raw.people
) q
UNION ALL
SELECT 'nullratio', 'people.height',
       CASE WHEN pct < 5.0 THEN 'PASS' WHEN pct < 25.0 THEN 'WARN' ELSE 'FAIL' END,
       round(pct, 2)::text || '%', '< 5%', NULL
FROM (
    SELECT 100.0 * count(*) FILTER (WHERE height IS NULL) / count(*)::numeric AS pct
    FROM raw.people
) q
UNION ALL
SELECT 'nullratio', 'pitching.era',
       CASE WHEN pct < 10.0 THEN 'PASS' ELSE 'WARN' END,
       round(pct, 2)::text || '%', '< 10%', 'NULL when no batters faced'
FROM (
    SELECT 100.0 * count(*) FILTER (WHERE era IS NULL) / count(*)::numeric AS pct
    FROM raw.pitching
) q
UNION ALL
SELECT 'nullratio', 'salaries.salary',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n::text, '0', 'Salaries must be present'
FROM (SELECT count(*) n FROM raw.salaries WHERE salary IS NULL) q;

-- ── 4. Referential integrity ────────────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'refintegrity', 'batting.player_id → people',
       CASE WHEN orphans = 0 THEN 'PASS' ELSE 'FAIL' END,
       orphans::text, '0', NULL
FROM (
    SELECT count(*) AS orphans
    FROM raw.batting b LEFT JOIN raw.people p USING (player_id)
    WHERE p.player_id IS NULL
) q
UNION ALL
SELECT 'refintegrity', 'pitching.player_id → people',
       CASE WHEN orphans = 0 THEN 'PASS' ELSE 'FAIL' END,
       orphans::text, '0', NULL
FROM (
    SELECT count(*) AS orphans
    FROM raw.pitching pi LEFT JOIN raw.people p USING (player_id)
    WHERE p.player_id IS NULL
) q
UNION ALL
SELECT 'refintegrity', 'salaries.(team_id,year_id) → teams',
       CASE WHEN orphans = 0 THEN 'PASS' WHEN orphans < 50 THEN 'WARN' ELSE 'FAIL' END,
       orphans::text, '0', 'Some lg_id mismatches are historical (e.g., 1994 strike year)'
FROM (
    SELECT count(*) AS orphans
    FROM raw.salaries s
    LEFT JOIN raw.teams t ON t.team_id = s.team_id AND t.year_id = s.year_id
    WHERE t.team_id IS NULL
) q;

-- ── 5. Range sanity ─────────────────────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'range', 'people.weight ∈ [100, 400]',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'WARN' END,
       n::text, '0', NULL
FROM (SELECT count(*) n FROM raw.people WHERE weight NOT BETWEEN 100 AND 400) q
UNION ALL
SELECT 'range', 'people.height ∈ [50, 90]',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'WARN' END,
       n::text, '0', NULL
FROM (SELECT count(*) n FROM raw.people WHERE height NOT BETWEEN 50 AND 90) q
UNION ALL
SELECT 'range', 'salaries.salary > 0',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n::text, '0', NULL
FROM (SELECT count(*) n FROM raw.salaries WHERE salary <= 0) q
UNION ALL
SELECT 'range', 'pitching.gs >= 0',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n::text, '0', NULL
FROM (SELECT count(*) n FROM raw.pitching WHERE gs < 0) q;

-- ── 6. Mid-season trade integrity ───────────────────────────────────────────
INSERT INTO pg_temp.dq_results
SELECT 'logic', 'batting stint sequencing',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'WARN' END,
       n::text, '0', 'Stints should be dense 1..N per player-year'
FROM (
    SELECT count(*) n FROM (
        SELECT player_id, year_id,
               max(stint) AS max_s,
               count(*)   AS c
        FROM   raw.batting
        GROUP  BY player_id, year_id
        HAVING max(stint) <> count(*)
    ) bad
) q;

-- ── Emit final report ───────────────────────────────────────────────────────
\echo
\echo '──────── DATA QUALITY REPORT ────────'
SELECT category, check_name, status, observed, expected, note
FROM   pg_temp.dq_results
ORDER  BY CASE status WHEN 'FAIL' THEN 0 WHEN 'WARN' THEN 1 ELSE 2 END,
          category, check_name;

\echo
\echo '──────── SUMMARY ────────'
SELECT status, count(*) AS checks
FROM   pg_temp.dq_results
GROUP  BY status
ORDER  BY status;

-- Fail loudly if anything is FAIL (used by CI).
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM pg_temp.dq_results WHERE status = 'FAIL';
    IF n > 0 THEN
        RAISE EXCEPTION 'Data-quality FAILures: %', n;
    END IF;
END$$;
