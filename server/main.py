"""HealthBridge API server."""

from contextlib import asynccontextmanager
from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import JSONResponse

from config import API_KEY
from database import (
    init_db,
    store_sync,
    get_daily_summaries,
    get_latest_summary,
    get_workouts,
    get_mood_entries,
    get_sleep_sessions,
)
from models import HealthSyncPayload


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="HealthBridge",
    description="API for receiving and querying Apple Health data",
    version="0.1.0",
    lifespan=lifespan,
)


def verify_api_key(x_api_key: str = Header(...)):
    if x_api_key != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


# ── Sync endpoint (iOS app pushes here) ──────────────────────────────

@app.post("/api/health/sync")
async def sync_health_data(
    payload: HealthSyncPayload,
    x_api_key: str = Header(...),
):
    verify_api_key(x_api_key)
    sync_id = await store_sync(payload)
    return {"status": "ok", "sync_id": sync_id}


# ── Query endpoints (agent reads from here) ──────────────────────────

@app.get("/api/health/summary")
async def get_summary(
    days: int = Query(default=7, ge=1, le=90),
    x_api_key: str = Header(...),
):
    verify_api_key(x_api_key)
    summaries = await get_daily_summaries(days)
    return {"days": days, "summaries": summaries}


@app.get("/api/health/latest")
async def get_latest(x_api_key: str = Header(...)):
    verify_api_key(x_api_key)
    summary = await get_latest_summary()
    if not summary:
        return {"status": "no_data"}
    return summary


@app.get("/api/health/workouts")
async def list_workouts(
    days: int = Query(default=7, ge=1, le=90),
    x_api_key: str = Header(...),
):
    verify_api_key(x_api_key)
    workouts = await get_workouts(days)
    return {"days": days, "workouts": workouts}


@app.get("/api/health/mood")
async def list_mood(
    days: int = Query(default=7, ge=1, le=90),
    x_api_key: str = Header(...),
):
    verify_api_key(x_api_key)
    entries = await get_mood_entries(days)
    return {"days": days, "mood": entries}


@app.get("/api/health/sleep")
async def list_sleep(
    days: int = Query(default=7, ge=1, le=90),
    x_api_key: str = Header(...),
):
    verify_api_key(x_api_key)
    sessions = await get_sleep_sessions(days)
    return {"days": days, "sleep": sessions}


@app.get("/api/health/ping")
async def ping():
    """Health check — no auth required."""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    from config import HOST, PORT
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
