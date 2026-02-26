"""Pydantic models for the HealthClaw API."""

from __future__ import annotations
from datetime import datetime
from typing import Any, Optional
from pydantic import BaseModel


class ActivityData(BaseModel):
    steps: Optional[int] = None
    distance_km: Optional[float] = None
    active_calories: Optional[float] = None
    basal_calories: Optional[float] = None
    exercise_minutes: Optional[float] = None
    stand_hours: Optional[int] = None
    flights_climbed: Optional[int] = None
    vo2_max: Optional[float] = None
    walking_speed_kmh: Optional[float] = None
    walking_steadiness: Optional[float] = None


class HeartData(BaseModel):
    resting_hr: Optional[float] = None
    avg_hr: Optional[float] = None
    min_hr: Optional[float] = None
    max_hr: Optional[float] = None
    hrv_sdnn: Optional[float] = None
    walking_hr_avg: Optional[float] = None


class SleepStage(BaseModel):
    stage: str  # awake, rem, core, deep
    start: datetime
    end: datetime
    duration_min: float


class SleepSession(BaseModel):
    start: datetime
    end: datetime
    total_duration_min: float
    stages: list[SleepStage] = []
    in_bed_duration_min: Optional[float] = None


class WorkoutSession(BaseModel):
    workout_type: str
    start: datetime
    end: datetime
    duration_min: float
    distance_km: Optional[float] = None
    active_calories: Optional[float] = None
    avg_hr: Optional[float] = None
    max_hr: Optional[float] = None
    elevation_gain_m: Optional[float] = None


class MoodEntry(BaseModel):
    kind: str  # momentary_emotion or daily_mood
    timestamp: datetime
    valence: float  # -1.0 to 1.0
    labels: list[str] = []
    associations: list[str] = []


class BodyData(BaseModel):
    weight_kg: Optional[float] = None
    bmi: Optional[float] = None
    body_fat_pct: Optional[float] = None
    height_cm: Optional[float] = None


class VitalsData(BaseModel):
    blood_pressure_systolic: Optional[float] = None
    blood_pressure_diastolic: Optional[float] = None
    blood_oxygen_pct: Optional[float] = None
    respiratory_rate: Optional[float] = None
    body_temperature_c: Optional[float] = None


class MindfulnessSession(BaseModel):
    start: datetime
    end: datetime
    duration_min: float


class HealthSyncPayload(BaseModel):
    device_id: str
    synced_at: datetime
    period_from: datetime
    period_to: datetime
    activity: Optional[ActivityData] = None
    heart: Optional[HeartData] = None
    sleep: list[SleepSession] = []
    workouts: list[WorkoutSession] = []
    mood: list[MoodEntry] = []
    body: Optional[BodyData] = None
    vitals: Optional[VitalsData] = None
    mindfulness: list[MindfulnessSession] = []
    # Synthetic body battery (0-100), computed client-side from HRV + sleep + activity
    body_battery: Optional[int] = None


# ── Nutrition models ─────────────────────────────────────────────────

class NutritionAnalysisRequest(BaseModel):
    text: str
    image_base64: Optional[str] = None
    image_mime_type: Optional[str] = None  # e.g. "image/jpeg"


class NutrientDetail(BaseModel):
    name: str
    amount: float
    unit: str
    daily_value_pct: Optional[float] = None


class FoodItem(BaseModel):
    name: str
    portion: str
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0
    nutrients: list[NutrientDetail] = []


class NutritionTotals(BaseModel):
    calories: float
    protein_g: float
    carbs_g: float
    fat_g: float
    fiber_g: float = 0.0
    sugar_g: float = 0.0
    sodium_mg: float = 0.0


class NutritionAnalysisResponse(BaseModel):
    meal_id: int
    timestamp: datetime
    description: str
    food_items: list[FoodItem]
    totals: NutritionTotals
    healthkit_samples: list[dict[str, Any]]


class NutritionHistoryEntry(BaseModel):
    id: int
    date: str
    timestamp: str
    description: str
    total_calories: Optional[float] = None
    total_protein_g: Optional[float] = None
    total_carbs_g: Optional[float] = None
    total_fat_g: Optional[float] = None
    created_at: str


class NutrientSummaryItem(BaseModel):
    nutrient_name: str
    total_amount: float
    unit: str


class DailyNutritionSummary(BaseModel):
    date: str
    meal_count: int
    total_calories: float
    total_protein_g: float
    total_carbs_g: float
    total_fat_g: float
    nutrients: list[NutrientSummaryItem] = []
