-- =============================================================================
--  sabermetrics/fip.sql — Fielding-Independent Pitching
--
--  FIP isolates what a pitcher controls (K, BB, HBP, HR) from defense / luck.
--  Industry formula:
--
--      FIP = ((13*HR) + (3*(BB + HBP)) - (2*K)) / IP   +  cFIP
--
--  cFIP is a per-season constant that pins league-average FIP to league-average
--  ERA. We compute cFIP_year from the data itself for full reproducibility.
--
--  Engineering choices:
--    * Two-pass CTE: first compute per-year league constants, then apply them.
--    * Qualified pitchers only (ipouts >= 162 → 54 IP) — same threshold as
--      the Canadian Ace filter, for consistency across the sabermetrics layer.
--    * The output is a *view* in `analytics.*` so dbt and the API can SELECT
--      from it without re-computing.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

DROP VIEW IF EXISTS analytics.v_fip CASCADE;
CREATE VIEW analytics.v_fip AS
WITH league_constants AS (
    SELECT
        pi.year_id,
        pi.lg_id,
        AVG(pi.era)::numeric                                    AS lg_era,
        SUM(13 * pi.hr + 3 * (pi.bb + COALESCE(pi.hbp,0)) - 2 * pi.so)::numeric
            / NULLIF(SUM(pi.ipouts) / 3.0, 0)                   AS lg_raw_fip
    FROM raw.pitching pi
    WHERE pi.ipouts >= 162 AND pi.era IS NOT NULL
    GROUP BY pi.year_id, pi.lg_id
),
fip_constant AS (
    SELECT year_id, lg_id, (lg_era - lg_raw_fip) AS c_fip
    FROM   league_constants
)
SELECT
    pi.player_id,
    pi.year_id,
    pi.team_id,
    pi.lg_id,
    pi.innings_pitched,
    pi.era,
    ROUND(
        ((13 * pi.hr + 3 * (pi.bb + COALESCE(pi.hbp,0)) - 2 * pi.so)::numeric
            / NULLIF(pi.ipouts / 3.0, 0))
        + fc.c_fip
    , 2) AS fip,
    fc.c_fip
FROM   raw.pitching pi
JOIN   fip_constant fc
       ON fc.year_id = pi.year_id AND fc.lg_id = pi.lg_id
WHERE  pi.ipouts >= 162;

COMMENT ON VIEW analytics.v_fip IS
    'Fielding-Independent Pitching, qualified pitchers (≥54 IP), with per-year cFIP.';

-- Surface the top FIP leaderboard.
\echo
\echo '──────── ALL-TIME FIP LEADERBOARD (Top 10) ────────'
SELECT
    pe.full_name      AS pitcher,
    f.year_id,
    f.team_id,
    f.innings_pitched,
    f.era,
    f.fip
FROM   analytics.v_fip f
JOIN   raw.people pe ON pe.player_id = f.player_id
ORDER  BY f.fip ASC
LIMIT  10;
