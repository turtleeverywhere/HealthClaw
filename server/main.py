"""HealthClaw API server."""

from contextlib import asynccontextmanager
from datetime import date as date_type
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
    get_meal_entry,
    get_meal_history,
    get_daily_nutrition_summary,
    update_meal_entry,
    delete_meal_entry,
)
from models import (
    DailyNutritionSummary,
    HealthSyncPayload,
    MealUpdateRequest,
    NutritionAnalysisRequest,
    NutritionAnalysisResponse,
    NutritionHistoryEntry,
    NutrientSummaryItem,
)
from nutrition import analyze_nutrition


@asynccontextmanager
async def lifespan(app: FastAPI):
    await init_db()
    yield


app = FastAPI(
    title="HealthClaw",
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


# ── Nutrition endpoints ───────────────────────────────────────────────

@app.post("/api/nutrition/analyze", response_model=NutritionAnalysisResponse)
async def nutrition_analyze(
    request: NutritionAnalysisRequest,
    x_api_key: str = Header(...),
):
    """Analyze food from text (and optional image) using Claude. Stores the meal."""
    verify_api_key(x_api_key)
    try:
        result = await analyze_nutrition(
            text=request.text,
            image_base64=request.image_base64,
            image_mime_type=request.image_mime_type,
        )
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Nutrition analysis failed: {e}")


@app.get("/api/nutrition/history")
async def nutrition_history(
    days: int = Query(default=7, ge=1, le=90),
    x_api_key: str = Header(...),
):
    """Return meal entries for the last N days (shaped as NutritionAnalysisResult array)."""
    verify_api_key(x_api_key)
    entries = await get_meal_history(days)
    return entries


@app.get("/api/nutrition/summary")
async def nutrition_summary(
    date: str = Query(default=None, description="Date in YYYY-MM-DD format"),
    x_api_key: str = Header(...),
):
    """Return daily nutrition summary (totals across all meals for a date)."""
    verify_api_key(x_api_key)
    if date is None:
        date = date_type.today().isoformat()
    # Validate date format
    try:
        date_type.fromisoformat(date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format, expected YYYY-MM-DD")
    summary = await get_daily_nutrition_summary(date)
    return summary


@app.get("/api/nutrition/meals/{meal_id}")
async def nutrition_meal_detail(
    meal_id: int,
    x_api_key: str = Header(...),
):
    """Get a single meal entry with full nutrient details."""
    verify_api_key(x_api_key)
    meal = await get_meal_entry(meal_id)
    if not meal:
        raise HTTPException(status_code=404, detail="Meal not found")
    return meal


@app.put("/api/nutrition/meals/{meal_id}")
async def nutrition_meal_update(
    meal_id: int,
    request: MealUpdateRequest,
    x_api_key: str = Header(...),
):
    """Update a meal's totals and food items."""
    verify_api_key(x_api_key)
    import json

    food_items_json = json.dumps([item.model_dump() for item in request.food_items])
    nutrients = []
    for item in request.food_items:
        nutrients.append({"name": "Energy", "amount": item.calories, "unit": "kcal"})
        nutrients.append({"name": "Protein", "amount": item.protein_g, "unit": "g"})
        nutrients.append({"name": "Carbohydrates", "amount": item.carbs_g, "unit": "g"})
        nutrients.append({"name": "Fat Total", "amount": item.fat_g, "unit": "g"})

    ok = await update_meal_entry(
        meal_id=meal_id,
        description=request.description,
        total_calories=request.totals.calories,
        total_protein_g=request.totals.protein_g,
        total_carbs_g=request.totals.carbs_g,
        total_fat_g=request.totals.fat_g,
        food_items_json=food_items_json,
        nutrients=nutrients,
    )
    if not ok:
        raise HTTPException(status_code=404, detail="Meal not found")
    return {"status": "ok"}


@app.delete("/api/nutrition/meals/{meal_id}")
async def nutrition_meal_delete(
    meal_id: int,
    x_api_key: str = Header(...),
):
    """Delete a meal entry."""
    verify_api_key(x_api_key)
    ok = await delete_meal_entry(meal_id)
    if not ok:
        raise HTTPException(status_code=404, detail="Meal not found")
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn
    from config import HOST, PORT
    uvicorn.run("main:app", host=HOST, port=PORT, reload=True)
