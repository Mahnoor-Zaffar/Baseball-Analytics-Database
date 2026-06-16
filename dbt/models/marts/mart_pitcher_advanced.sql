{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['player_id', 'year_id', 'team_id'], 'unique': True},
            {'columns': ['era_plus']},
            {'columns': ['fip']}
        ],
        tags = ['marts', 'sabermetrics']
    )
}}

-- mart_pitcher_advanced: qualified pitchers (≥{{ var('qualifying_ipouts') }} ipouts)
-- with traditional + advanced metrics joined and per-league baselines applied.

WITH base AS (
    SELECT
        p.player_id,
        p.year_id,
        p.team_id,
        p.lg_id,
        p.games_started,
        p.innings_pitched,
        p.era,
        p.k_per_9,
        p.bb_per_9,
        p.hits_allowed,
        p.walks,
        p.strikeouts,
        p.home_runs_allowed,
        p.hit_batters,
        p.ipouts
    FROM {{ ref('stg_pitching') }} p
    WHERE p.ipouts >= {{ var('qualifying_ipouts') }}
      AND p.era IS NOT NULL AND p.era > 0
),
league AS (
    SELECT
        year_id, lg_id,
        AVG(era)::numeric(6,3)        AS lg_era,
        STDDEV_SAMP(era)::numeric(6,3) AS lg_era_sd,
        AVG((13 * home_runs_allowed + 3 * (walks + hit_batters) - 2 * strikeouts)::numeric
            / NULLIF(innings_pitched, 0))::numeric(6,3) AS lg_raw_fip
    FROM base
    GROUP BY year_id, lg_id
),
fip_constants AS (
    SELECT year_id, lg_id, (lg_era - lg_raw_fip) AS c_fip, lg_era, lg_era_sd
    FROM   league
)

SELECT
    b.player_id,
    b.year_id,
    b.team_id,
    b.lg_id,
    pe.full_name                                                       AS pitcher,
    b.games_started,
    b.innings_pitched,
    b.era,
    ROUND(
        ((13 * b.home_runs_allowed + 3 * (b.walks + b.hit_batters) - 2 * b.strikeouts)::numeric
            / NULLIF(b.innings_pitched, 0))
        + fc.c_fip
    , 2) AS fip,
    ROUND((b.era - fc.lg_era) / NULLIF(fc.lg_era_sd, 0), 3) AS era_z_score,
    ROUND(100.0 * fc.lg_era / NULLIF(b.era, 0), 0)::int      AS era_plus,
    b.k_per_9,
    b.bb_per_9,
    fc.lg_era                                                          AS league_era,
    fc.lg_era_sd                                                       AS league_era_stddev
FROM   base b
JOIN   fip_constants fc USING (year_id, lg_id)
JOIN   {{ ref('stg_people') }} pe USING (player_id)
