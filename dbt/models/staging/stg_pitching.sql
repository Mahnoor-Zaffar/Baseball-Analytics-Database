{{ config(materialized = 'view', tags = ['staging', 'pitching']) }}

SELECT
    player_id,
    year_id,
    stint,
    team_id,
    lg_id,
    w                                   AS wins,
    l                                   AS losses,
    g                                   AS games,
    gs                                  AS games_started,
    cg                                  AS complete_games,
    sho                                 AS shutouts,
    sv                                  AS saves,
    ipouts,
    innings_pitched,
    h                                   AS hits_allowed,
    er                                  AS earned_runs,
    hr                                  AS home_runs_allowed,
    bb                                  AS walks,
    so                                  AS strikeouts,
    baopp                               AS opponent_batting_avg,
    era,
    k_per_9,
    bb_per_9,
    hbp                                 AS hit_batters
FROM {{ source('raw', 'pitching') }}
