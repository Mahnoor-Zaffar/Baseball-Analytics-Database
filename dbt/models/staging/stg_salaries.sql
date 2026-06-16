{{ config(materialized = 'view', tags = ['staging', 'salaries']) }}

SELECT
    year_id,
    team_id,
    lg_id,
    player_id,
    salary                              AS salary_usd
FROM {{ source('raw', 'salaries') }}
