-- =============================================================================
--  sabermetrics/war_proxy.sql — Wins Above Replacement (simplified)
--
--  Full WAR (fWAR / bWAR) requires play-by-play data, park factors, defensive
--  metrics (UZR / DRS), and league constants this dataset doesn't carry.
--  This is therefore an *honest proxy* that combines what Lahman *does* have:
--
--      Batting WAR proxy   ≈  (wRAA / runs_per_win) where wRAA derives from wOBA
--      Pitching WAR proxy  ≈  ((lg_FIP - player_FIP) * IP / 9) / runs_per_win
--
--  Constants:
--      runs_per_win = 10  (FanGraphs standard ~9.5–10.5 depending on era)
--
--  Caveats called out inline so downstream consumers know this is a proxy:
--  no defensive component, no positional adjustment, no replacement-level
--  calibration. Useful for relative ranking, not roster valuation.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

DROP VIEW IF EXISTS analytics.v_pitching_war_proxy CASCADE;
CREATE VIEW analytics.v_pitching_war_proxy AS
WITH league_fip AS (
    SELECT
        f.year_id,
        f.lg_id,
        AVG(f.fip)::numeric(6,3) AS lg_fip
    FROM analytics.v_fip f
    GROUP BY f.year_id, f.lg_id
)
SELECT
    f.player_id,
    f.year_id,
    f.team_id,
    f.lg_id,
    f.innings_pitched,
    f.era,
    f.fip,
    lf.lg_fip,
    ROUND(
        ((lf.lg_fip - f.fip) * f.innings_pitched / 9.0) / 10.0
    , 2) AS war_proxy
FROM   analytics.v_fip f
JOIN   league_fip lf ON lf.year_id = f.year_id AND lf.lg_id = f.lg_id;

DROP VIEW IF EXISTS analytics.v_batting_war_proxy CASCADE;
CREATE VIEW analytics.v_batting_war_proxy AS
WITH league_woba AS (
    SELECT
        w.year_id,
        w.lg_id,
        AVG(w.woba)::numeric(5,3) AS lg_woba,
        1.20::numeric              AS woba_scale  -- standard FanGraphs scale factor
    FROM analytics.v_woba w
    GROUP BY w.year_id, w.lg_id
)
SELECT
    w.player_id,
    w.year_id,
    w.team_id,
    w.lg_id,
    w.pa,
    w.woba,
    lw.lg_woba,
    -- wRAA = ((woba - lg_woba) / woba_scale) * PA
    ROUND(
        (((w.woba - lw.lg_woba) / lw.woba_scale) * w.pa) / 10.0
    , 2) AS war_proxy
FROM   analytics.v_woba w
JOIN   league_woba lw ON lw.year_id = w.year_id AND lw.lg_id = w.lg_id;

COMMENT ON VIEW analytics.v_pitching_war_proxy IS
    'Simplified pitching WAR (no defense / park factor). Useful for relative ranking.';
COMMENT ON VIEW analytics.v_batting_war_proxy IS
    'Simplified batting WAR (no defense / positional adj). Useful for relative ranking.';

-- Combined top-10 single-season WAR leaderboard.
\echo
\echo '──────── ALL-TIME WAR PROXY LEADERBOARD (Top 10, Batters + Pitchers) ────────'
WITH unified AS (
    SELECT pe.full_name AS player, w.year_id, w.team_id,
           'B' AS role, NULL::numeric AS ip, w.war_proxy
    FROM   analytics.v_batting_war_proxy w
    JOIN   raw.people pe ON pe.player_id = w.player_id
    UNION ALL
    SELECT pe.full_name, p.year_id, p.team_id,
           'P', p.innings_pitched, p.war_proxy
    FROM   analytics.v_pitching_war_proxy p
    JOIN   raw.people pe ON pe.player_id = p.player_id
)
SELECT *
FROM   unified
ORDER  BY war_proxy DESC NULLS LAST
LIMIT  10;
