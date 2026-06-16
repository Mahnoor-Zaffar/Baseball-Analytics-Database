-- =============================================================================
--  benchmarks.sql — cold-cache + warm-cache benchmark harness
--
--  Strategy:
--    1. RESET / pg_stat_statements_reset() so we start clean.
--    2. Cold pass: DISCARD ALL + clear OS cache is impossible from psql, so
--       we approximate "cold" by querying objects we haven't touched yet.
--    3. Warm pass: re-execute the same statements; the planner now has the
--       relations + indexes in shared_buffers.
--    4. Report mean / max / total time + shared block hits/reads from
--       pg_stat_statements.
--
--  Used by:
--    * `make bench`               (interactive)
--    * CI's benchmark step        (regression detection)
-- =============================================================================
\set ON_ERROR_STOP on
\timing on
SET search_path TO raw, analytics, public;

SELECT pg_stat_statements_reset();

-- ── Cold pass (planner sees fresh statistics) ───────────────────────────────
\echo
\echo '──────── COLD PASS ────────'
DISCARD PLANS;
SELECT count(*) FROM raw.batting;
SELECT count(*) FROM raw.pitching;
SELECT count(*) FROM raw.salaries;
SELECT count(*) FROM analytics.mv_team_payroll;
SELECT count(*) FROM analytics.mv_team_physiques;

-- The 6 awards in sequence.
\i /workspace/sql/baseball_awards.sql

-- ── Warm pass (identical queries, expect shared block hits = ~100%) ─────────
\echo
\echo '──────── WARM PASS ────────'
\i /workspace/sql/baseball_awards.sql

-- ── pg_stat_statements report ───────────────────────────────────────────────
\echo
\echo '──────── pg_stat_statements (top 15 by mean exec time) ────────'
SELECT
    LEFT(regexp_replace(query, '\s+', ' ', 'g'), 90)              AS query,
    calls,
    round(mean_exec_time::numeric, 2)                             AS mean_ms,
    round(stddev_exec_time::numeric, 2)                           AS stddev_ms,
    round((total_exec_time / 1000.0)::numeric, 2)                 AS total_s,
    shared_blks_hit                                               AS blk_hit,
    shared_blks_read                                              AS blk_read,
    round(100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0), 1)
                                                                  AS cache_hit_pct
FROM   pg_stat_statements
WHERE  query NOT ILIKE '%pg_stat_statements%'
ORDER  BY mean_exec_time DESC
LIMIT  15;
