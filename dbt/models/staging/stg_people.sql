{{
    config(
        materialized = 'view',
        tags        = ['staging', 'people']
    )
}}

-- Staging layer = renamed, typed, cleaned. No business logic.
SELECT
    player_id,
    full_name,
    name_first,
    name_last,
    name_given,
    weight                              AS weight_lbs,
    height                              AS height_in,
    bats,
    throws,
    debut                               AS debut_date,
    final_game                          AS final_game_date,
    birth_year,
    birth_country,
    death_year IS NOT NULL              AS is_deceased
FROM {{ source('raw', 'people') }}
