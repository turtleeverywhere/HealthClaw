"""SQLite database layer for HealthClaw."""

from __future__ import annotations

import aiosqlite
import json
from datetime import datetime
from pathlib import Path

from config import DB_PATH
from models import HealthSyncPayload


async def init_db() -> None:
    """Create tables if they don't exist."""
    async with aiosqlite.connect(DB_PATH) as db:
        await db.executescript("""
            CREATE TABLE IF NOT EXISTS sync_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                device_id TEXT NOT NULL,
                synced_at TEXT NOT NULL,
                period_from TEXT NOT NULL,
                period_to TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS daily_summary (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL UNIQUE,
                steps INTEGER,
                distance_km REAL,
                active_calories REAL,
                exercise_minutes REAL,
                stand_hours INTEGER,
                flights_climbed INTEGER,
                resting_hr REAL,
                avg_hr REAL,
                hrv_sdnn REAL,
                sleep_duration_min REAL,
                deep_sleep_min REAL,
                rem_sleep_min REAL,
                core_sleep_min REAL,
                awake_min REAL,
                weight_kg REAL,
                body_fat_pct REAL,
                body_battery INTEGER,
                mood_avg_valence REAL,
                workout_count INTEGER,
                workout_minutes REAL,
                workout_calories REAL,
                mindfulness_minutes REAL,
                blood_oxygen_pct REAL,
                respiratory_rate REAL,
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS workouts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                workout_type TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                duration_min REAL,
                distance_km REAL,
                active_calories REAL,
                avg_hr REAL,
                max_hr REAL,
                elevation_gain_m REAL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS mood_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                kind TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                valence REAL NOT NULL,
                labels TEXT,
                associations TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS sleep_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                start_time TEXT NOT NULL,
                end_time TEXT NOT NULL,
                total_duration_min REAL,
                in_bed_duration_min REAL,
                stages_json TEXT,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                UNIQUE(date, start_time)
            );

            CREATE TABLE IF NOT EXISTS meal_entries (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                date TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                description TEXT NOT NULL,
                image_path TEXT,
                analysis_json TEXT NOT NULL,
                total_calories REAL,
                total_protein_g REAL,
                total_carbs_g REAL,
                total_fat_g REAL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS meal_nutrients (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                meal_entry_id INTEGER NOT NULL REFERENCES meal_entries(id),
                nutrient_name TEXT NOT NULL,
                amount REAL NOT NULL,
                unit TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_daily_summary_date ON daily_summary(date);
            CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts(date);
            CREATE INDEX IF NOT EXISTS idx_mood_date ON mood_entries(date);
            CREATE INDEX IF NOT EXISTS idx_sleep_date ON sleep_sessions(date);
            CREATE INDEX IF NOT EXISTS idx_meal_entries_date ON meal_entries(date);
            CREATE INDEX IF NOT EXISTS idx_meal_nutrients_entry ON meal_nutrients(meal_entry_id);
        """)
        # Migration: add food_items_json column if missing
        try:
            await db.execute("ALTER TABLE meal_entries ADD COLUMN food_items_json TEXT")
        except Exception:
            pass  # column already exists

        # Migration: deduplicate sleep_sessions and add unique constraint
        try:
            await db.execute("""
                DELETE FROM sleep_sessions WHERE id NOT IN (
                    SELECT MIN(id) FROM sleep_sessions GROUP BY date, start_time
                )
            """)
            await db.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_sleep_unique ON sleep_sessions(date, start_time)"
            )
        except Exception:
            pass  # already migrated

        await db.commit()


async def store_sync(payload: HealthSyncPayload) -> int:
    """Store a sync payload and update derived tables. Returns sync_log id."""
    async with aiosqlite.connect(DB_PATH) as db:
        # Store raw payload
        cursor = await db.execute(
            "INSERT INTO sync_log (device_id, synced_at, period_from, period_to, payload_json) VALUES (?, ?, ?, ?, ?)",
            (
                payload.device_id,
                payload.synced_at.isoformat(),
                payload.period_from.isoformat(),
                payload.period_to.isoformat(),
                payload.model_dump_json(),
            ),
        )
        sync_id = cursor.lastrowid

        # Upsert daily summary
        date_str = payload.period_to.strftime("%Y-%m-%d")
        activity = payload.activity
        heart = payload.heart
        body = payload.body
        vitals = payload.vitals

        # Calculate sleep totals — use the longest session whose wake-up (end)
        # falls on the summary date, to avoid double-counting overlapping
        # Apple Health sources (iPhone + Watch) and to attribute overnight
        # sleep to the correct day
        date_sleeps = [s for s in payload.sleep if s.end.strftime("%Y-%m-%d") == date_str]
        if date_sleeps:
            longest_sleep = max(date_sleeps, key=lambda s: s.total_duration_min)
            sleep_total = longest_sleep.total_duration_min
            deep_total = sum(st.duration_min for st in longest_sleep.stages if st.stage == "deep")
            rem_total = sum(st.duration_min for st in longest_sleep.stages if st.stage == "rem")
            core_total = sum(st.duration_min for st in longest_sleep.stages if st.stage == "core")
            awake_total = sum(st.duration_min for st in longest_sleep.stages if st.stage == "awake")
        else:
            sleep_total = deep_total = rem_total = core_total = awake_total = 0

        # Calculate mood average
        mood_avg = None
        if payload.mood:
            mood_avg = sum(m.valence for m in payload.mood) / len(payload.mood)

        # Calculate workout totals
        workout_count = len(payload.workouts)
        workout_minutes = sum(w.duration_min for w in payload.workouts)
        workout_calories = sum(w.active_calories or 0 for w in payload.workouts)

        mindfulness_min = sum(m.duration_min for m in payload.mindfulness)

        await db.execute(
            """INSERT INTO daily_summary (
                date, steps, distance_km, active_calories, exercise_minutes, stand_hours,
                flights_climbed, resting_hr, avg_hr, hrv_sdnn, sleep_duration_min,
                deep_sleep_min, rem_sleep_min, core_sleep_min, awake_min,
                weight_kg, body_fat_pct, body_battery, mood_avg_valence,
                workout_count, workout_minutes, workout_calories, mindfulness_minutes,
                blood_oxygen_pct, respiratory_rate, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'))
            ON CONFLICT(date) DO UPDATE SET
                steps = COALESCE(excluded.steps, steps),
                distance_km = COALESCE(excluded.distance_km, distance_km),
                active_calories = COALESCE(excluded.active_calories, active_calories),
                exercise_minutes = COALESCE(excluded.exercise_minutes, exercise_minutes),
                stand_hours = COALESCE(excluded.stand_hours, stand_hours),
                flights_climbed = COALESCE(excluded.flights_climbed, flights_climbed),
                resting_hr = COALESCE(excluded.resting_hr, resting_hr),
                avg_hr = COALESCE(excluded.avg_hr, avg_hr),
                hrv_sdnn = COALESCE(excluded.hrv_sdnn, hrv_sdnn),
                sleep_duration_min = COALESCE(excluded.sleep_duration_min, sleep_duration_min),
                deep_sleep_min = COALESCE(excluded.deep_sleep_min, deep_sleep_min),
                rem_sleep_min = COALESCE(excluded.rem_sleep_min, rem_sleep_min),
                core_sleep_min = COALESCE(excluded.core_sleep_min, core_sleep_min),
                awake_min = COALESCE(excluded.awake_min, awake_min),
                weight_kg = COALESCE(excluded.weight_kg, weight_kg),
                body_fat_pct = COALESCE(excluded.body_fat_pct, body_fat_pct),
                body_battery = COALESCE(excluded.body_battery, body_battery),
                mood_avg_valence = COALESCE(excluded.mood_avg_valence, mood_avg_valence),
                workout_count = COALESCE(excluded.workout_count, workout_count),
                workout_minutes = COALESCE(excluded.workout_minutes, workout_minutes),
                workout_calories = COALESCE(excluded.workout_calories, workout_calories),
                mindfulness_minutes = COALESCE(excluded.mindfulness_minutes, mindfulness_minutes),
                blood_oxygen_pct = COALESCE(excluded.blood_oxygen_pct, blood_oxygen_pct),
                respiratory_rate = COALESCE(excluded.respiratory_rate, respiratory_rate),
                updated_at = datetime('now')
            """,
            (
                date_str,
                activity.steps if activity else None,
                activity.distance_km if activity else None,
                activity.active_calories if activity else None,
                activity.exercise_minutes if activity else None,
                activity.stand_hours if activity else None,
                activity.flights_climbed if activity else None,
                heart.resting_hr if heart else None,
                heart.avg_hr if heart else None,
                heart.hrv_sdnn if heart else None,
                sleep_total or None,
                deep_total or None,
                rem_total or None,
                core_total or None,
                awake_total or None,
                body.weight_kg if body else None,
                body.body_fat_pct if body else None,
                payload.body_battery,
                mood_avg,
                workout_count or None,
                workout_minutes or None,
                workout_calories or None,
                mindfulness_min or None,
                vitals.blood_oxygen_pct if vitals else None,
                vitals.respiratory_rate if vitals else None,
            ),
        )

        # Store individual workouts
        for w in payload.workouts:
            w_date = w.start.strftime("%Y-%m-%d")
            await db.execute(
                """INSERT INTO workouts (date, workout_type, start_time, end_time, duration_min,
                   distance_km, active_calories, avg_hr, max_hr, elevation_gain_m)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (w_date, w.workout_type, w.start.isoformat(), w.end.isoformat(),
                 w.duration_min, w.distance_km, w.active_calories, w.avg_hr, w.max_hr, w.elevation_gain_m),
            )

        # Store mood entries
        for m in payload.mood:
            m_date = m.timestamp.strftime("%Y-%m-%d")
            await db.execute(
                "INSERT INTO mood_entries (date, kind, timestamp, valence, labels, associations) VALUES (?, ?, ?, ?, ?, ?)",
                (m_date, m.kind, m.timestamp.isoformat(), m.valence,
                 json.dumps(m.labels), json.dumps(m.associations)),
            )

        # Store sleep sessions (deduplicate by date + start_time)
        # Attribute sleep to the wake-up date (end), since overnight sleep
        # starting before midnight belongs to the next day
        for s in payload.sleep:
            s_date = s.end.strftime("%Y-%m-%d")
            await db.execute(
                """INSERT INTO sleep_sessions (date, start_time, end_time, total_duration_min,
                   in_bed_duration_min, stages_json) VALUES (?, ?, ?, ?, ?, ?)
                   ON CONFLICT(date, start_time) DO UPDATE SET
                     end_time = excluded.end_time,
                     total_duration_min = excluded.total_duration_min,
                     in_bed_duration_min = excluded.in_bed_duration_min,
                     stages_json = excluded.stages_json""",
                (s_date, s.start.isoformat(), s.end.isoformat(), s.total_duration_min,
                 s.in_bed_duration_min, json.dumps([st.model_dump(mode="json") for st in s.stages])),
            )

        await db.commit()
        return sync_id


async def get_daily_summaries(days: int = 7) -> list[dict]:
    """Get the last N days of daily summaries."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM daily_summary ORDER BY date DESC LIMIT ?", (days,)
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]


async def get_latest_summary() -> dict | None:
    """Get the most recent daily summary."""
    rows = await get_daily_summaries(1)
    return rows[0] if rows else None


async def get_workouts(days: int = 7) -> list[dict]:
    """Get workouts from the last N days."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM workouts WHERE date >= date('now', ?) ORDER BY start_time DESC",
            (f"-{days} days",),
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]


async def get_mood_entries(days: int = 7) -> list[dict]:
    """Get mood entries from the last N days."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM mood_entries WHERE date >= date('now', ?) ORDER BY timestamp DESC",
            (f"-{days} days",),
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]


async def get_sleep_sessions(days: int = 7) -> list[dict]:
    """Get sleep sessions from the last N days."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM sleep_sessions WHERE date >= date('now', ?) ORDER BY start_time DESC",
            (f"-{days} days",),
        )
        rows = await cursor.fetchall()
        return [dict(row) for row in rows]


# ── Nutrition ────────────────────────────────────────────────────────

async def store_meal_entry(
    date: str,
    timestamp: str,
    description: str,
    analysis_json: str,
    total_calories: float | None,
    total_protein_g: float | None,
    total_carbs_g: float | None,
    total_fat_g: float | None,
    nutrients: list[dict],
    image_path: str | None = None,
    food_items_json: str | None = None,
) -> int:
    """Store a meal entry and its nutrients. Returns the meal entry id."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute(
            """INSERT INTO meal_entries
               (date, timestamp, description, image_path, analysis_json,
                total_calories, total_protein_g, total_carbs_g, total_fat_g,
                food_items_json)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (date, timestamp, description, image_path, analysis_json,
             total_calories, total_protein_g, total_carbs_g, total_fat_g,
             food_items_json),
        )
        meal_id = cursor.lastrowid

        for n in nutrients:
            await db.execute(
                "INSERT INTO meal_nutrients (meal_entry_id, nutrient_name, amount, unit) VALUES (?, ?, ?, ?)",
                (meal_id, n["name"], n["amount"], n["unit"]),
            )

        await db.commit()
        return meal_id


async def update_meal_entry(
    meal_id: int,
    description: str | None,
    total_calories: float,
    total_protein_g: float,
    total_carbs_g: float,
    total_fat_g: float,
    food_items_json: str | None = None,
    nutrients: list[dict] | None = None,
) -> bool:
    """Update a meal entry's totals and optionally its food items/nutrients."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT id FROM meal_entries WHERE id = ?", (meal_id,))
        if not await cursor.fetchone():
            return False

        await db.execute(
            """UPDATE meal_entries
               SET total_calories = ?, total_protein_g = ?, total_carbs_g = ?, total_fat_g = ?,
                   description = COALESCE(?, description),
                   food_items_json = COALESCE(?, food_items_json)
               WHERE id = ?""",
            (total_calories, total_protein_g, total_carbs_g, total_fat_g,
             description, food_items_json, meal_id),
        )

        if nutrients is not None:
            await db.execute("DELETE FROM meal_nutrients WHERE meal_entry_id = ?", (meal_id,))
            for n in nutrients:
                await db.execute(
                    "INSERT INTO meal_nutrients (meal_entry_id, nutrient_name, amount, unit) VALUES (?, ?, ?, ?)",
                    (meal_id, n["name"], n["amount"], n["unit"]),
                )

        await db.commit()
        return True


async def delete_meal_entry(meal_id: int) -> bool:
    """Delete a meal entry and its nutrients."""
    async with aiosqlite.connect(DB_PATH) as db:
        cursor = await db.execute("SELECT id FROM meal_entries WHERE id = ?", (meal_id,))
        if not await cursor.fetchone():
            return False
        await db.execute("DELETE FROM meal_nutrients WHERE meal_entry_id = ?", (meal_id,))
        await db.execute("DELETE FROM meal_entries WHERE id = ?", (meal_id,))
        await db.commit()
        return True


async def get_meal_entry(meal_id: int) -> dict | None:
    """Get a single meal entry with its nutrients."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM meal_entries WHERE id = ?", (meal_id,)
        )
        row = await cursor.fetchone()
        if not row:
            return None
        meal = dict(row)

        cursor2 = await db.execute(
            "SELECT nutrient_name, amount, unit FROM meal_nutrients WHERE meal_entry_id = ?",
            (meal_id,),
        )
        nutrients = await cursor2.fetchall()
        meal["nutrients"] = [dict(n) for n in nutrients]
        return meal


async def get_meal_history(days: int = 7) -> list[dict]:
    """Get meal entries shaped as NutritionAnalysisResult for iOS."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            """SELECT id, date, timestamp, description, total_calories,
                      total_protein_g, total_carbs_g, total_fat_g,
                      food_items_json, analysis_json
               FROM meal_entries
               WHERE date >= date('now', ?)
               ORDER BY timestamp DESC""",
            (f"-{days} days",),
        )
        rows = await cursor.fetchall()

        results = []
        for row in rows:
            r = dict(row)
            # Parse food items from stored JSON or fall back to analysis_json
            food_items = []
            if r.get("food_items_json"):
                try:
                    food_items = json.loads(r["food_items_json"])
                except (json.JSONDecodeError, TypeError):
                    pass
            elif r.get("analysis_json"):
                try:
                    analysis = json.loads(r["analysis_json"])
                    food_items = analysis.get("food_items", [])
                except (json.JSONDecodeError, TypeError):
                    pass

            results.append({
                "meal_id": r["id"],
                "timestamp": r["timestamp"],
                "description": r["description"],
                "food_items": food_items,
                "totals": {
                    "calories": r["total_calories"] or 0,
                    "protein_g": r["total_protein_g"] or 0,
                    "carbs_g": r["total_carbs_g"] or 0,
                    "fat_g": r["total_fat_g"] or 0,
                },
                "healthkit_samples": [],
            })
        return results


async def get_daily_nutrition_summary(date: str) -> dict:
    """Get aggregated nutrition totals for a specific date."""
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            """SELECT
                 COUNT(*) AS meal_count,
                 COALESCE(SUM(total_calories), 0) AS total_calories,
                 COALESCE(SUM(total_protein_g), 0) AS total_protein_g,
                 COALESCE(SUM(total_carbs_g), 0) AS total_carbs_g,
                 COALESCE(SUM(total_fat_g), 0) AS total_fat_g
               FROM meal_entries
               WHERE date = ?""",
            (date,),
        )
        row = await cursor.fetchone()
        summary = dict(row) if row else {}

        # Also get per-nutrient totals
        cursor2 = await db.execute(
            """SELECT mn.nutrient_name, SUM(mn.amount) AS total_amount, mn.unit
               FROM meal_nutrients mn
               JOIN meal_entries me ON mn.meal_entry_id = me.id
               WHERE me.date = ?
               GROUP BY mn.nutrient_name, mn.unit""",
            (date,),
        )
        nutrient_rows = await cursor2.fetchall()
        summary["nutrients"] = [dict(n) for n in nutrient_rows]
        summary["date"] = date
        return summary
