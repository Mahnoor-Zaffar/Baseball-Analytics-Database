-- =============================================================================
--  sabermetrics/era_adjusted.sql — Era-adjusted ERA via z-score normalization
--
--  Problem the PRD explicitly calls out (Open Question #1, "structural shift
--  variations"): raw ERA is incomparable across eras.
--    • 1968 ("Year of the Pitcher"): MLB-wide ERA ≈ 2.98
--    • 2000 (peak steroid era):       MLB-wide ERA ≈ 4.77
--  A 3.00 ERA in 1968 is *average*; the same ERA in 2000 is elite.
--
--  Solution: z-score each pitcher's ERA against the league-season mean and
--  standard deviation (already materialized in analytics.mv_league_pitching_baseline).
--  Negative z = better-than-average (lower ERA), so we invert sign for sorting.
--
--  Bonus: ERA+ is the classic Baseball-Reference adjustment
--      ERA+ = 100 * (lg_ERA / player_ERA)
--  We surface both for cross-checking.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

DROP VIEW IF EXISTS analytics.v_era_adjusted CASCADE;
CREATE VIEW analytics.v_era_adjusted AS
SELECT
    pi.player_id,
    pi.year_id,
    pi.team_id,
    pi.lg_id,
    pi.innings_pitched,
    pi.era,
    lb.league_era_mean,
    lb.league_era_stddev,
    ROUND(
        ((pi.era - lb.league_era_mean) / NULLIF(lb.league_era_stddev, 0))
    , 3) AS era_z_score,                  -- negative = better
    ROUND(
        100.0 * lb.league_era_mean / NULLIF(pi.era, 0)
    , 0)::int AS era_plus,                -- 100 = league average, 200 = twice as good
    NTILE(100) OVER (PARTITION BY pi.year_id, pi.lg_id ORDER BY pi.era ASC) AS era_percentile
FROM   raw.pitching pi
JOIN   analytics.mv_league_pitching_baseline lb
       ON  lb.year_id = pi.year_id
      AND  lb.lg_id   = pi.lg_id
WHERE  pi.ipouts >= 162
  AND  pi.era IS NOT NULL
  AND  pi.era > 0;

COMMENT ON VIEW analytics.v_era_adjusted IS
    'Era-adjusted ERA via z-score and ERA+. Negative z = elite, ERA+ > 100 = better than avg.';

-- Top-10 ERA+ seasons of all time (the historically dominant pitching seasons).
\echo
\echo '──────── ALL-TIME ERA+ LEADERBOARD (Top 10) ────────'
SELECT
    pe.full_name AS pitcher,
    ea.year_id,
    ea.team_id,
    ea.innings_pitched,
    ea.era,
    ea.league_era_mean,
    ea.era_z_score,
    ea.era_plus
FROM   analytics.v_era_adjusted ea
JOIN   raw.people pe ON pe.player_id = ea.player_id
ORDER  BY ea.era_plus DESC NULLS LAST
LIMIT  10;
