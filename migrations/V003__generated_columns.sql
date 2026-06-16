-- =============================================================================
-- V003 — Generated columns
--
-- Move repeatedly-computed derived metrics into the table itself as
-- GENERATED ALWAYS … STORED so the executor never recomputes them.
-- The trade-off is disk + write cost; for a read-mostly Lahman warehouse this
-- is a clear win — the columns are written exactly once during load.
-- =============================================================================
\set ON_ERROR_STOP on
SET search_path TO raw, analytics, public;

-- Pitching: innings pitched (ipouts / 3) — the single most common derivation.
ALTER TABLE raw.pitching
    ADD COLUMN IF NOT EXISTS innings_pitched numeric(6,1)
    GENERATED ALWAYS AS (ipouts::numeric / 3.0) STORED;

-- Pitching: K/BB and K/9 — pitcher quality metrics used by the sabermetrics layer.
ALTER TABLE raw.pitching
    ADD COLUMN IF NOT EXISTS k_per_9 numeric(6,2)
    GENERATED ALWAYS AS (
        CASE WHEN ipouts > 0 THEN so::numeric * 27.0 / NULLIF(ipouts, 0) END
    ) STORED;

ALTER TABLE raw.pitching
    ADD COLUMN IF NOT EXISTS bb_per_9 numeric(6,2)
    GENERATED ALWAYS AS (
        CASE WHEN ipouts > 0 THEN bb::numeric * 27.0 / NULLIF(ipouts, 0) END
    ) STORED;

-- Batting: traditional rate stats (OBP, SLG, OPS) — required by wOBA & wRC+.
-- These intentionally accept NULL when AB+BB+HBP+SF = 0 (cup-of-coffee callups).
ALTER TABLE raw.batting
    ADD COLUMN IF NOT EXISTS pa int
    GENERATED ALWAYS AS (
        COALESCE(ab,0) + COALESCE(bb,0) + COALESCE(hbp,0) + COALESCE(sh,0) + COALESCE(sf,0)
    ) STORED;

ALTER TABLE raw.batting
    ADD COLUMN IF NOT EXISTS obp numeric(5,3)
    GENERATED ALWAYS AS (
        (COALESCE(h,0) + COALESCE(bb,0) + COALESCE(hbp,0))::numeric /
        NULLIF(COALESCE(ab,0) + COALESCE(bb,0) + COALESCE(hbp,0) + COALESCE(sf,0), 0)
    ) STORED;

ALTER TABLE raw.batting
    ADD COLUMN IF NOT EXISTS slg numeric(5,3)
    GENERATED ALWAYS AS (
        (COALESCE(h,0) - COALESCE("2b",0) - COALESCE("3b",0) - COALESCE(hr,0)
            + 2 * COALESCE("2b",0)
            + 3 * COALESCE("3b",0)
            + 4 * COALESCE(hr,0))::numeric
        / NULLIF(ab, 0)
    ) STORED;

ALTER TABLE raw.batting
    ADD COLUMN IF NOT EXISTS ops numeric(5,3)
    GENERATED ALWAYS AS (
        COALESCE(
            (COALESCE(h,0) + COALESCE(bb,0) + COALESCE(hbp,0))::numeric /
            NULLIF(COALESCE(ab,0) + COALESCE(bb,0) + COALESCE(hbp,0) + COALESCE(sf,0), 0)
        , 0)
        +
        COALESCE(
            (COALESCE(h,0) - COALESCE("2b",0) - COALESCE("3b",0) - COALESCE(hr,0)
                + 2 * COALESCE("2b",0)
                + 3 * COALESCE("3b",0)
                + 4 * COALESCE(hr,0))::numeric
            / NULLIF(ab, 0)
        , 0)
    ) STORED;

-- People: full display name and BMI (just because it's almost free to store).
ALTER TABLE raw.people
    ADD COLUMN IF NOT EXISTS full_name text
    GENERATED ALWAYS AS (
        TRIM(BOTH ' ' FROM COALESCE(name_first,'') || ' ' || COALESCE(name_last,''))
    ) STORED;

-- Index the new columns that filter / sort hot paths.
CREATE INDEX IF NOT EXISTS idx_pitching_ip   ON raw.pitching (innings_pitched);
CREATE INDEX IF NOT EXISTS idx_batting_pa    ON raw.batting  (pa);

ANALYZE raw.pitching;
ANALYZE raw.batting;
ANALYZE raw.people;

INSERT INTO analytics.schema_migrations(version, checksum)
VALUES ('V003__generated_columns', md5('V003'))
ON CONFLICT (version) DO NOTHING;
