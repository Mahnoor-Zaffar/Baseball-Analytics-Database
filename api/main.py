"""FastAPI read-only service exposing the 6 baseball awards + sabermetrics views.

Engineering notes:
    * Read-only — no INSERT/UPDATE/DELETE paths, ever. The DB user can be a
      `pg_read_all_data` role in production.
    * Connection pool via psycopg's built-in ConnectionPool — sized for the
      typical FastAPI workload (4 workers × 5 conns).
    * Endpoints accept a `year` query param where it makes sense; the SQL
      uses parameter binding (no f-strings) so it's injection-safe.
    * Every endpoint returns the same envelope shape: `{award, winner, metric, context}`.
"""
from __future__ import annotations

import os
from contextlib import asynccontextmanager
from typing import Any, Optional

from fastapi import FastAPI, HTTPException, Query
from psycopg_pool import ConnectionPool
from psycopg.rows import dict_row
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
PG_DSN = (
    f"host={os.getenv('POSTGRES_HOST', 'postgres')} "
    f"port={os.getenv('POSTGRES_PORT', '5432')} "
    f"dbname={os.getenv('POSTGRES_DB', 'baseball')} "
    f"user={os.getenv('POSTGRES_USER', 'baseball')} "
    f"password={os.getenv('POSTGRES_PASSWORD', 'baseball')}"
)

pool: Optional[ConnectionPool] = None


@asynccontextmanager
async def lifespan(_: FastAPI):
    global pool
    pool = ConnectionPool(conninfo=PG_DSN, min_size=2, max_size=10, open=True)
    yield
    pool.close()


app = FastAPI(
    title="Baseball Analytics API",
    description="Read-only access to the 6 historical awards and the sabermetrics layer.",
    version="1.0.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------
class AwardEnvelope(BaseModel):
    award: str
    winner: dict[str, Any]
    metric: dict[str, Any]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def fetch_one(sql: str, params: tuple = ()) -> dict[str, Any]:
    assert pool is not None, "Connection pool not initialized"
    with pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params)
        row = cur.fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="No row matched.")
        return row


def fetch_many(sql: str, params: tuple = (), limit: int = 10) -> list[dict[str, Any]]:
    assert pool is not None
    with pool.connection() as conn, conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params + (limit,))
        return list(cur.fetchall())


# ---------------------------------------------------------------------------
# Endpoints — awards
# ---------------------------------------------------------------------------
@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/awards/heaviest-hitters", response_model=AwardEnvelope)
def heaviest_hitters():
    row = fetch_one("""
        SELECT p.team_id, p.year_id, t.name AS team_name,
               p.avg_weight_lbs, p.batter_appearances
        FROM   analytics.mv_team_physiques p
        LEFT   JOIN raw.teams t USING (team_id, year_id)
        ORDER  BY p.avg_weight_lbs DESC NULLS LAST
        LIMIT  1
    """)
    return AwardEnvelope(
        award="Heaviest Hitters",
        winner={"team_id": row["team_id"], "year_id": row["year_id"], "team_name": row["team_name"]},
        metric={"avg_weight_lbs": float(row["avg_weight_lbs"]),
                "batter_appearances": row["batter_appearances"]},
    )


@app.get("/awards/shortest-sluggers", response_model=AwardEnvelope)
def shortest_sluggers():
    row = fetch_one("""
        SELECT p.team_id, p.year_id, t.name AS team_name,
               p.avg_height_in, p.batter_appearances
        FROM   analytics.mv_team_physiques p
        LEFT   JOIN raw.teams t USING (team_id, year_id)
        ORDER  BY p.avg_height_in ASC NULLS LAST
        LIMIT  1
    """)
    return AwardEnvelope(
        award="Shortest Sluggers",
        winner={"team_id": row["team_id"], "year_id": row["year_id"], "team_name": row["team_name"]},
        metric={"avg_height_in": float(row["avg_height_in"]),
                "batter_appearances": row["batter_appearances"]},
    )


@app.get("/awards/biggest-spenders", response_model=AwardEnvelope)
def biggest_spenders(year: Optional[int] = Query(None, description="Restrict to one year")):
    if year is None:
        sql = """
            SELECT mp.year_id, mp.team_id, t.name AS team_name, mp.total_payroll_usd
            FROM   analytics.mv_team_payroll mp
            LEFT   JOIN raw.teams t USING (team_id, year_id)
            ORDER  BY mp.total_payroll_usd DESC LIMIT 1
        """
        row = fetch_one(sql)
    else:
        sql = """
            SELECT mp.year_id, mp.team_id, t.name AS team_name, mp.total_payroll_usd
            FROM   analytics.mv_team_payroll mp
            LEFT   JOIN raw.teams t USING (team_id, year_id)
            WHERE  mp.year_id = %s
            ORDER  BY mp.total_payroll_usd DESC LIMIT 1
        """
        row = fetch_one(sql, (year,))
    return AwardEnvelope(
        award="Biggest Spenders" + (f" ({year})" if year else ""),
        winner={"team_id": row["team_id"], "year_id": row["year_id"], "team_name": row["team_name"]},
        metric={"total_payroll_usd": int(row["total_payroll_usd"])},
    )


@app.get("/awards/bang-for-buck", response_model=AwardEnvelope)
def bang_for_buck(year: int = Query(2010)):
    row = fetch_one("""
        SELECT t.team_id, t.year_id, t.name AS team_name, t.w AS wins,
               mp.total_payroll_usd,
               ROUND(mp.total_payroll_usd::numeric / NULLIF(t.w, 0), 2) AS cost_per_win_usd
        FROM   analytics.mv_team_payroll mp
        JOIN   raw.teams t USING (team_id, year_id)
        WHERE  mp.year_id = %s AND t.year_id = %s AND t.w > 0
        ORDER  BY cost_per_win_usd ASC LIMIT 1
    """, (year, year))
    return AwardEnvelope(
        award=f"Most Bang for the Buck ({year})",
        winner={"team_id": row["team_id"], "team_name": row["team_name"], "year_id": year},
        metric={"wins": row["wins"], "total_payroll_usd": int(row["total_payroll_usd"]),
                "cost_per_win_usd": float(row["cost_per_win_usd"])},
    )


@app.get("/awards/priciest-starter", response_model=AwardEnvelope)
def priciest_starter(year: Optional[int] = Query(None)):
    base_sql = """
        SELECT pe.full_name AS pitcher, pi.player_id, pi.year_id, pi.team_id,
               pi.gs AS games_started, s.salary AS salary_usd,
               ROUND(s.salary::numeric / NULLIF(pi.gs, 0), 2) AS cost_per_start_usd
        FROM   raw.pitching pi
        JOIN   raw.salaries s
               ON s.player_id = pi.player_id
              AND s.year_id   = pi.year_id
              AND s.team_id   = pi.team_id
        JOIN   raw.people pe ON pe.player_id = pi.player_id
        WHERE  pi.gs >= 10
    """
    if year is not None:
        sql = base_sql + " AND pi.year_id = %s ORDER BY cost_per_start_usd DESC NULLS LAST LIMIT 1"
        row = fetch_one(sql, (year,))
    else:
        sql = base_sql + " ORDER BY cost_per_start_usd DESC NULLS LAST LIMIT 1"
        row = fetch_one(sql)
    return AwardEnvelope(
        award="Priciest Starter" + (f" ({year})" if year else ""),
        winner={"player_id": row["player_id"], "pitcher": row["pitcher"],
                "team_id": row["team_id"], "year_id": row["year_id"]},
        metric={"games_started": row["games_started"], "salary_usd": float(row["salary_usd"]),
                "cost_per_start_usd": float(row["cost_per_start_usd"])},
    )


@app.get("/awards/canadian-ace", response_model=AwardEnvelope)
def canadian_ace(min_ipouts: int = Query(162, ge=1)):
    row = fetch_one("""
        WITH qual AS (
            SELECT pi.player_id, pi.team_id, pi.year_id, pi.era, pi.innings_pitched,
                   pi.k_per_9, pi.bb_per_9,
                   RANK() OVER (ORDER BY pi.era ASC, pi.ipouts DESC) AS rk
            FROM   raw.pitching pi
            WHERE  pi.team_id IN ('TOR', 'MON')
              AND  pi.era IS NOT NULL AND pi.era > 0
              AND  pi.ipouts >= %s
        )
        SELECT pe.full_name AS pitcher, q.*
        FROM   qual q JOIN raw.people pe USING (player_id)
        WHERE  q.rk = 1 LIMIT 1
    """, (min_ipouts,))
    return AwardEnvelope(
        award="Canadian Ace",
        winner={"player_id": row["player_id"], "pitcher": row["pitcher"],
                "team_id": row["team_id"], "year_id": row["year_id"]},
        metric={"era": float(row["era"]), "innings_pitched": float(row["innings_pitched"]),
                "k_per_9": float(row["k_per_9"]) if row["k_per_9"] else None,
                "bb_per_9": float(row["bb_per_9"]) if row["bb_per_9"] else None},
    )


# ---------------------------------------------------------------------------
# Sabermetrics leaderboards
# ---------------------------------------------------------------------------
@app.get("/leaderboards/fip")
def fip_top(limit: int = Query(10, ge=1, le=100)):
    rows = fetch_many("""
        SELECT pe.full_name AS pitcher, f.year_id, f.team_id,
               f.innings_pitched, f.era, f.fip
        FROM   analytics.v_fip f
        JOIN   raw.people pe USING (player_id)
        ORDER  BY f.fip ASC LIMIT %s
    """, (), limit)
    return {"leaderboard": "FIP (lower is better)", "rows": rows}


@app.get("/leaderboards/woba")
def woba_top(limit: int = Query(10, ge=1, le=100)):
    rows = fetch_many("""
        SELECT pe.full_name AS batter, w.year_id, w.team_id,
               w.pa, w.obp, w.slg, w.woba
        FROM   analytics.v_woba w
        JOIN   raw.people pe USING (player_id)
        ORDER  BY w.woba DESC NULLS LAST LIMIT %s
    """, (), limit)
    return {"leaderboard": "wOBA (higher is better)", "rows": rows}


@app.get("/leaderboards/era-plus")
def era_plus_top(limit: int = Query(10, ge=1, le=100)):
    rows = fetch_many("""
        SELECT pe.full_name AS pitcher, ea.year_id, ea.team_id,
               ea.innings_pitched, ea.era, ea.era_plus
        FROM   analytics.v_era_adjusted ea
        JOIN   raw.people pe USING (player_id)
        ORDER  BY ea.era_plus DESC NULLS LAST LIMIT %s
    """, (), limit)
    return {"leaderboard": "ERA+ (era-adjusted, 100 = league average)", "rows": rows}
