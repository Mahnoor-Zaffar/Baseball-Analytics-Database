-- =============================================================================
--  sabermetrics/woba.sql — Weighted On-Base Average
--
--  wOBA weighs each offensive event by its run-expectancy value. It's strictly
--  superior to BA / OBP / SLG for measuring batter contribution.
--
--  Industry coefficients (post-2010 standard, FanGraphs):
--      uBB = 0.69   HBP = 0.722   1B = 0.888   2B = 1.271   3B = 1.616   HR = 2.101
--
--  These are pinned constants (rounded to 3 decimals to match published wOBA).
--  For a fully rigorous pipeline we'd recompute them per-year from a run
--  expectancy matrix — left as a TODO under `sabermetrics/woba_calibrated.sql`.
--
--  Qualification: PA >= 502 (the official MLB qualifying threshold).
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

DROP VIEW IF EXISTS analytics.v_woba CASCADE;
CREATE VIEW analytics.v_woba AS
SELECT
    b.player_id,
    b.year_id,
    b.team_id,
    b.lg_id,
    b.pa,
    b.ab,
    b.obp,
    b.slg,
    b.ops,
    ROUND(
        (
              0.690 * (b.bb - COALESCE(b.ibb,0))                       -- unintentional BB
            + 0.722 * COALESCE(b.hbp,0)
            + 0.888 * (b.h - COALESCE(b."2b",0) - COALESCE(b."3b",0) - COALESCE(b.hr,0))
            + 1.271 * COALESCE(b."2b",0)
            + 1.616 * COALESCE(b."3b",0)
            + 2.101 * COALESCE(b.hr,0)
        )::numeric
        / NULLIF(b.ab + b.bb - COALESCE(b.ibb,0) + COALESCE(b.sf,0) + COALESCE(b.hbp,0), 0)
    , 3) AS woba
FROM   raw.batting b
WHERE  b.pa >= 502;

COMMENT ON VIEW analytics.v_woba IS
    'Weighted On-Base Average (post-2010 FanGraphs coefficients), qualified hitters (PA ≥ 502).';

-- Top-10 wOBA seasons of all time.
\echo
\echo '──────── ALL-TIME wOBA LEADERBOARD (Top 10) ────────'
SELECT
    pe.full_name AS batter,
    w.year_id,
    w.team_id,
    w.pa,
    w.obp,
    w.slg,
    w.ops,
    w.woba
FROM   analytics.v_woba w
JOIN   raw.people pe ON pe.player_id = w.player_id
ORDER  BY w.woba DESC NULLS LAST
LIMIT  10;
