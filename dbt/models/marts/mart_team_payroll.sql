{{
    config(
        materialized = 'table',
        indexes = [
            {'columns': ['year_id', 'team_id'], 'unique': True},
            {'columns': ['total_payroll_usd']}
        ],
        tags = ['marts', 'finance']
    )
}}

-- mart_team_payroll: one row per (year, team) with payroll + record + efficiency.
-- Drives the API endpoints /awards/biggest-spenders and /awards/bang-for-buck.

WITH payroll AS (
    SELECT
        year_id, team_id, lg_id,
        COUNT(*)                              AS roster_size,
        SUM(salary_usd)::bigint               AS total_payroll_usd,
        AVG(salary_usd)::numeric(12,2)        AS avg_salary_usd,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY salary_usd) AS median_salary_usd
    FROM {{ ref('stg_salaries') }}
    GROUP BY year_id, team_id, lg_id
),
record AS (
    SELECT year_id, team_id, team_name, wins, losses, win_pct
    FROM   {{ ref('stg_teams') }}
)

SELECT
    p.year_id,
    p.team_id,
    p.lg_id,
    r.team_name,
    p.roster_size,
    p.total_payroll_usd,
    p.avg_salary_usd,
    p.median_salary_usd,
    r.wins,
    r.losses,
    r.win_pct,
    ROUND(p.total_payroll_usd::numeric / NULLIF(r.wins, 0), 2)
        AS cost_per_win_usd,
    ROUND(p.total_payroll_usd::numeric / NULLIF(r.wins + r.losses, 0), 2)
        AS cost_per_game_usd
FROM   payroll p
LEFT   JOIN record  r USING (year_id, team_id)
