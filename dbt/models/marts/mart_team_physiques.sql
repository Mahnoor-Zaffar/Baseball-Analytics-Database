{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['team_id', 'year_id'], 'unique': True},
            {'columns': ['avg_weight_lbs']},
            {'columns': ['avg_height_in']}
        ],
        tags = ['marts', 'physical']
    )
}}

-- mart_team_physiques: average roster physique per team-season. Drives the
-- Heaviest Hitters and Shortest Sluggers awards.
SELECT
    b.team_id,
    b.year_id,
    COUNT(*)                                       AS batter_appearances,
    AVG(p.weight_lbs)::numeric(6,2)                AS avg_weight_lbs,
    AVG(p.height_in)::numeric(6,2)                 AS avg_height_in,
    STDDEV_SAMP(p.weight_lbs)::numeric(6,2)        AS stddev_weight_lbs,
    STDDEV_SAMP(p.height_in)::numeric(6,2)         AS stddev_height_in,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.weight_lbs) AS median_weight_lbs,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY p.height_in) AS median_height_in
FROM {{ ref('stg_batting') }} b
JOIN {{ ref('stg_people') }}  p USING (player_id)
WHERE p.weight_lbs IS NOT NULL OR p.height_in IS NOT NULL
GROUP BY b.team_id, b.year_id
