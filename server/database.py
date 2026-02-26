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
                created_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE INDEX IF NOT EXISTS idx_daily_summary_date ON daily_summary(date);
            CREATE INDEX IF NOT EXISTS idx_workouts_date ON workouts(date);
            CREATE INDEX IF NOT EXISTS idx_mood_date ON mood_entries(date);
            CREATE INDEX IF NOT EXISTS idx_sleep_date ON sleep_sessions(date);
        """)
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

        # Calculate sleep totals
        sleep_total = sum(s.total_duration_min for s in payload.sleep)
        deep_total = sum(
            st.duration_min for s in payload.sleep for st in s.stages if st.stage == "deep"
        )
        rem_total = sum(
            st.duration_min for s in payload.sleep for st in s.stages if st.stage == "rem"
        )
        core_total = sum(
            st.duration_min for s in payload.sleep for st in s.stages if st.stage == "core"
        )
        awake_total = sum(
            st.duration_min for s in payload.sleep for st in s.stages if st.stage == "awake"
        )

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

        # Store sleep sessions
        for s in payload.sleep:
            s_date = s.start.strftime("%Y-%m-%d")
            await db.execute(
                """INSERT INTO sleep_sessions (date, start_time, end_time, total_duration_min,
                   in_bed_duration_min, stages_json) VALUES (?, ?, ?, ?, ?, ?)""",
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
