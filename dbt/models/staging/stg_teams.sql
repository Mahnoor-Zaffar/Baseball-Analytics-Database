{{ config(materialized = 'view', tags = ['staging', 'teams']) }}

SELECT
    year_id,
    team_id,
    lg_id,
    franch_id,
    div_id,
    name                                AS team_name,
    park                                AS park_name,
    g                                   AS games,
    w                                   AS wins,
    l                                   AS losses,
    ROUND(w::numeric / NULLIF(g, 0), 3) AS win_pct,
    r                                   AS runs_scored,
    ra                                  AS runs_allowed,
    era                                 AS team_era,
    attendance,
    CASE team_id WHEN 'TOR' THEN true
                 WHEN 'MON' THEN true
                 ELSE false END         AS is_canadian
FROM {{ source('raw', 'teams') }}
