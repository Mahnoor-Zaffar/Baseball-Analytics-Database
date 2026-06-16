-- =============================================================================
--  tests/test_data_quality.sql — structural invariants
--
--  These tests run *after* migrations and *before* awards in CI. If any FAIL,
--  CI bails out before producing potentially wrong analytical results.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO raw, analytics, public;

CREATE OR REPLACE FUNCTION pg_temp.ok(cond boolean, msg text) RETURNS void AS $$
BEGIN
    IF cond THEN
        RAISE NOTICE '  ✓ %', msg;
    ELSE
        RAISE EXCEPTION '  ✗ % (FAILED)', msg;
    END IF;
END;
$$ LANGUAGE plpgsql;

\echo
\echo '──────── TEST: DATA QUALITY INVARIANTS ────────'

-- All five core raw tables exist.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM pg_tables
    WHERE schemaname = 'raw'
      AND tablename IN ('people','teams','batting','pitching','salaries');
    PERFORM pg_temp.ok(n = 5, 'all 5 raw.* tables exist');
END$$;

-- Required indexes are in place.
DO $$
DECLARE needed text[] := ARRAY[
    'idx_batting_team_year',
    'idx_pitching_team_year',
    'idx_pitching_era_qualified',
    'idx_salaries_year_team',
    'idx_salaries_2010'
];
    missing text;
BEGIN
    FOREACH missing IN ARRAY needed LOOP
        PERFORM pg_temp.ok(
            EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = missing),
            'index present: ' || missing
        );
    END LOOP;
END$$;

-- Materialized views are populated.
DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM analytics.mv_team_payroll;
    PERFORM pg_temp.ok(n > 0, 'mv_team_payroll has rows: ' || n);

    SELECT count(*) INTO n FROM analytics.mv_team_physiques;
    PERFORM pg_temp.ok(n > 0, 'mv_team_physiques has rows: ' || n);

    SELECT count(*) INTO n FROM analytics.mv_league_pitching_baseline;
    PERFORM pg_temp.ok(n > 0, 'mv_league_pitching_baseline has rows: ' || n);
END$$;

-- Generated columns return correct values for a known row.
DO $$
DECLARE pi_val numeric;
BEGIN
    SELECT innings_pitched INTO pi_val FROM raw.pitching WHERE ipouts = 300 LIMIT 1;
    PERFORM pg_temp.ok(pi_val = 100.0, 'generated col: ipouts=300 → IP=100.0');
END$$;

-- Referential integrity: no orphan pitchers/batters.
DO $$
DECLARE orphans int;
BEGIN
    SELECT count(*) INTO orphans
    FROM   raw.batting b LEFT JOIN raw.people p USING (player_id)
    WHERE  p.player_id IS NULL;
    PERFORM pg_temp.ok(orphans = 0, 'no orphan batting.player_id (' || orphans || ')');
END$$;

-- Salary sanity: no negative or zero salaries.
DO $$
DECLARE bad int;
BEGIN
    SELECT count(*) INTO bad FROM raw.salaries WHERE salary <= 0;
    PERFORM pg_temp.ok(bad = 0, 'no non-positive salaries (' || bad || ')');
END$$;

\echo
\echo '✓ All data-quality invariants hold.'
