-- =============================================================================
--  tests/test_awards.sql — pgTAP-flavored assertions on award outputs.
--
--  We don't require the pgTAP extension (one fewer dependency for CI); instead
--  we use a tiny helper function `ok(cond, message)` that raises on failure.
--  Same ergonomics, zero extension overhead.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO analytics, raw, public;

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
\echo '──────── TEST: AWARDS ASSERTIONS ────────'

-- 1. HEAVIEST HITTERS — must be a real team-year with > 5 batter appearances.
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM analytics.mv_team_physiques
    ORDER BY avg_weight_lbs DESC NULLS LAST LIMIT 1;

    PERFORM pg_temp.ok(r.team_id IS NOT NULL, 'heaviest hitters: team_id present');
    PERFORM pg_temp.ok(r.year_id BETWEEN 1871 AND 2030, 'heaviest hitters: year in range');
    PERFORM pg_temp.ok(r.batter_appearances >= 5, 'heaviest hitters: >= 5 batters');
    PERFORM pg_temp.ok(r.avg_weight_lbs BETWEEN 150 AND 280, 'heaviest hitters: realistic weight');
END$$;

-- 2. SHORTEST SLUGGERS — realistic height range, > 5 batters.
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM analytics.mv_team_physiques
    ORDER BY avg_height_in ASC NULLS LAST LIMIT 1;

    PERFORM pg_temp.ok(r.team_id IS NOT NULL, 'shortest sluggers: team_id present');
    PERFORM pg_temp.ok(r.avg_height_in BETWEEN 60 AND 80, 'shortest sluggers: realistic height');
    PERFORM pg_temp.ok(r.batter_appearances >= 5, 'shortest sluggers: >= 5 batters');
END$$;

-- 3. BIGGEST SPENDERS — payroll > $1M (sanity floor since salaries start 1985).
DO $$
DECLARE r record;
BEGIN
    SELECT * INTO r FROM analytics.mv_team_payroll
    ORDER BY total_payroll_usd DESC LIMIT 1;

    PERFORM pg_temp.ok(r.total_payroll_usd > 1000000, 'biggest spenders: > $1M payroll');
    PERFORM pg_temp.ok(r.year_id >= 1985, 'biggest spenders: from salary era');
    PERFORM pg_temp.ok(r.roster_size > 0, 'biggest spenders: roster_size > 0');
END$$;

-- 4. MOST BANG FOR THEIR BUCK 2010 — exactly one winner, year_id = 2010, wins > 0.
DO $$
DECLARE r record;
BEGIN
    SELECT t.team_id, t.year_id, t.w,
           ROUND(mp.total_payroll_usd::numeric / NULLIF(t.w,0), 2) AS cpw
    INTO   r
    FROM   analytics.mv_team_payroll mp
    JOIN   raw.teams t ON t.team_id = mp.team_id AND t.year_id = mp.year_id
    WHERE  mp.year_id = 2010 AND t.year_id = 2010 AND t.w > 0
    ORDER  BY cpw ASC
    LIMIT  1;

    PERFORM pg_temp.ok(r.year_id = 2010, 'bang for buck: year = 2010');
    PERFORM pg_temp.ok(r.w > 0, 'bang for buck: wins > 0');
    PERFORM pg_temp.ok(r.cpw > 0, 'bang for buck: cost_per_win > 0');
END$$;

-- 5. PRICIEST STARTER — gs >= 10, salary > 0.
DO $$
DECLARE r record;
BEGIN
    SELECT pi.player_id, pi.gs, s.salary,
           s.salary / NULLIF(pi.gs, 0) AS cps
    INTO   r
    FROM   raw.pitching pi
    JOIN   raw.salaries s
           ON s.player_id = pi.player_id
          AND s.year_id   = pi.year_id
          AND s.team_id   = pi.team_id
    WHERE  pi.gs >= 10
    ORDER  BY cps DESC NULLS LAST
    LIMIT  1;

    PERFORM pg_temp.ok(r.gs >= 10, 'priciest starter: gs >= 10 enforced');
    PERFORM pg_temp.ok(r.salary > 0, 'priciest starter: salary > 0');
    PERFORM pg_temp.ok(r.cps > 0, 'priciest starter: cost_per_start > 0');
END$$;

-- 6. CANADIAN ACE — team_id in (TOR, MON), era > 0, ipouts >= 162.
DO $$
DECLARE r record;
BEGIN
    SELECT pi.player_id, pi.team_id, pi.era, pi.ipouts
    INTO   r
    FROM   raw.pitching pi
    WHERE  pi.team_id IN ('TOR', 'MON')
      AND  pi.era IS NOT NULL AND pi.era > 0
      AND  pi.ipouts >= 162
    ORDER  BY pi.era ASC, pi.ipouts DESC
    LIMIT  1;

    PERFORM pg_temp.ok(r.team_id IN ('TOR', 'MON'), 'canadian ace: TOR or MON');
    PERFORM pg_temp.ok(r.era > 0, 'canadian ace: era > 0 (no zero-noise)');
    PERFORM pg_temp.ok(r.ipouts >= 162, 'canadian ace: ipouts >= 162');
END$$;

-- Sabermetric layer sanity: views exist and return rows.
DO $$
DECLARE c int;
BEGIN
    SELECT count(*) INTO c FROM analytics.v_fip;
    PERFORM pg_temp.ok(c > 0, 'sabermetrics: v_fip returns rows');

    SELECT count(*) INTO c FROM analytics.v_woba;
    PERFORM pg_temp.ok(c > 0, 'sabermetrics: v_woba returns rows');

    SELECT count(*) INTO c FROM analytics.v_era_adjusted;
    PERFORM pg_temp.ok(c > 0, 'sabermetrics: v_era_adjusted returns rows');

    SELECT count(*) INTO c FROM analytics.v_pitching_war_proxy;
    PERFORM pg_temp.ok(c > 0, 'sabermetrics: v_pitching_war_proxy returns rows');
END$$;

\echo
\echo '✓ All award assertions passed.'
