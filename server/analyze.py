#!/usr/bin/env python3
"""
HealthClaw Analyzer — queries the API and outputs a health summary for the agent.
Run daily via OpenClaw cron. Outputs markdown to stdout.
"""

import json
import os
import sys
import urllib.request
from datetime import datetime

BASE_URL = os.getenv("HEALTHCLAW_URL", "http://localhost:8099")
API_KEY = os.getenv("HEALTHCLAW_API_KEY", "hb-lars-2026")


def api_get(path: str, params: dict | None = None) -> dict:
    url = f"{BASE_URL}{path}"
    if params:
        qs = "&".join(f"{k}={v}" for k, v in params.items())
        url += f"?{qs}"
    req = urllib.request.Request(url, headers={"X-API-Key": API_KEY})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def fmt(val, unit="", decimals=0):
    if val is None:
        return "—"
    if decimals == 0:
        return f"{int(val)}{unit}"
    return f"{val:.{decimals}f}{unit}"


def trend_emoji(current, previous):
    if current is None or previous is None:
        return ""
    if current > previous * 1.05:
        return " ↑"
    if current < previous * 0.95:
        return " ↓"
    return " →"


def analyze():
    # Get last 7 days of summaries
    data = api_get("/api/health/summary", {"days": 7})
    summaries = data.get("summaries", [])

    if not summaries:
        print("No health data available yet. Waiting for first sync from iOS app.")
        return

    today = summaries[0] if summaries else {}
    yesterday = summaries[1] if len(summaries) > 1 else {}

    # Get recent workouts
    workouts_data = api_get("/api/health/workouts", {"days": 7})
    workouts = workouts_data.get("workouts", [])

    # Get sleep
    sleep_data = api_get("/api/health/sleep", {"days": 7})
    sleeps = sleep_data.get("sleep", [])

    # Get mood
    mood_data = api_get("/api/health/mood", {"days": 7})
    moods = mood_data.get("mood", [])

    # Build report
    date = today.get("date", datetime.now().strftime("%Y-%m-%d"))
    print(f"# Health Report — {date}\n")

    # Body Battery
    bb = today.get("body_battery")
    if bb is not None:
        emoji = "🟢" if bb >= 70 else "🟡" if bb >= 40 else "🔴"
        print(f"## {emoji} Body Battery: {bb}/100\n")

    # Activity
    print("## 🏃 Activity")
    steps = today.get("steps")
    prev_steps = yesterday.get("steps")
    print(f"- Steps: **{fmt(steps)}**{trend_emoji(steps, prev_steps)}")
    print(f"- Distance: {fmt(today.get('distance_km'), ' km', 1)}")
    print(f"- Active Calories: {fmt(today.get('active_calories'), ' kcal')}")
    print(f"- Exercise: {fmt(today.get('exercise_minutes'), ' min')}")
    print(f"- Flights Climbed: {fmt(today.get('flights_climbed'))}")
    print()

    # Heart
    print("## ❤️ Heart")
    rhr = today.get("resting_hr")
    prev_rhr = yesterday.get("resting_hr")
    print(f"- Resting HR: **{fmt(rhr, ' bpm')}**{trend_emoji(rhr, prev_rhr)}")
    print(f"- Average HR: {fmt(today.get('avg_hr'), ' bpm')}")
    hrv = today.get("hrv_sdnn")
    prev_hrv = yesterday.get("hrv_sdnn")
    print(f"- HRV (SDNN): **{fmt(hrv, ' ms')}**{trend_emoji(hrv, prev_hrv)}")
    print()

    # Sleep
    print("## 😴 Sleep")
    sleep_dur = today.get("sleep_duration_min")
    if sleep_dur:
        hours = sleep_dur / 60
        quality = "🟢 Good" if hours >= 7 else "🟡 Fair" if hours >= 6 else "🔴 Low"
        print(f"- Duration: **{hours:.1f}h** ({quality})")
        print(f"- Deep: {fmt(today.get('deep_sleep_min'), ' min')}")
        print(f"- REM: {fmt(today.get('rem_sleep_min'), ' min')}")
        print(f"- Core: {fmt(today.get('core_sleep_min'), ' min')}")
        print(f"- Awake: {fmt(today.get('awake_min'), ' min')}")
    else:
        print("- No sleep data for today")
    print()

    # Workouts
    print("## 💪 Workouts (last 7 days)")
    if workouts:
        total_min = sum(w.get("duration_min", 0) or 0 for w in workouts)
        total_cal = sum(w.get("active_calories", 0) or 0 for w in workouts)
        print(f"- Count: **{len(workouts)}** sessions")
        print(f"- Total time: {fmt(total_min, ' min')}")
        print(f"- Total calories: {fmt(total_cal, ' kcal')}")
        print(f"\nRecent:")
        for w in workouts[:5]:
            dist = f", {w['distance_km']:.1f} km" if w.get("distance_km") else ""
            print(f"  - {w['workout_type']}: {fmt(w.get('duration_min'), ' min')}{dist} ({w['date']})")
    else:
        print("- No workouts recorded")
    print()

    # Body
    weight = today.get("weight_kg")
    if weight:
        print("## ⚖️ Body")
        print(f"- Weight: {fmt(weight, ' kg', 1)}")
        bf = today.get("body_fat_pct")
        if bf:
            print(f"- Body Fat: {fmt(bf, '%', 1)}")
        print()

    # Mood
    if moods:
        print("## 🧠 Mood")
        avg_valence = today.get("mood_avg_valence")
        if avg_valence is not None:
            emoji = "😊" if avg_valence > 0.3 else "😐" if avg_valence > -0.3 else "😔"
            print(f"- Today's mood: {emoji} (valence: {avg_valence:.2f})")
        print()

    # Vitals
    spo2 = today.get("blood_oxygen_pct")
    rr = today.get("respiratory_rate")
    if spo2 or rr:
        print("## 🩺 Vitals")
        if spo2:
            print(f"- SpO₂: {fmt(spo2, '%', 1)}")
        if rr:
            print(f"- Respiratory Rate: {fmt(rr, ' breaths/min', 1)}")
        print()

    # Alerts
    alerts = []
    if rhr and rhr > 80:
        alerts.append("⚠️ Resting HR elevated (>80 bpm)")
    if rhr and rhr < 40:
        alerts.append("⚠️ Resting HR unusually low (<40 bpm)")
    if hrv and hrv < 20:
        alerts.append("⚠️ HRV very low (<20 ms) — possible stress/fatigue")
    if sleep_dur and sleep_dur < 300:
        alerts.append("⚠️ Sleep under 5 hours")
    if bb is not None and bb < 30:
        alerts.append("⚠️ Body battery critically low")
    if steps and steps < 3000:
        alerts.append("💡 Low step count — try to move more today")

    if alerts:
        print("## 🚨 Alerts")
        for a in alerts:
            print(f"- {a}")
        print()

    # 7-day trends
    if len(summaries) >= 3:
        print("## 📊 7-Day Trends")
        step_vals = [s.get("steps") for s in summaries if s.get("steps")]
        if step_vals:
            print(f"- Avg steps: {fmt(sum(step_vals) / len(step_vals))}")
        sleep_vals = [s.get("sleep_duration_min") for s in summaries if s.get("sleep_duration_min")]
        if sleep_vals:
            avg_sleep_h = sum(sleep_vals) / len(sleep_vals) / 60
            print(f"- Avg sleep: {avg_sleep_h:.1f}h")
        rhr_vals = [s.get("resting_hr") for s in summaries if s.get("resting_hr")]
        if rhr_vals:
            print(f"- Avg resting HR: {fmt(sum(rhr_vals) / len(rhr_vals), ' bpm')}")
        workout_counts = [s.get("workout_count", 0) or 0 for s in summaries]
        print(f"- Total workouts: {sum(workout_counts)}")


if __name__ == "__main__":
    try:
        analyze()
    except Exception as e:
        print(f"Error fetching health data: {e}", file=sys.stderr)
        sys.exit(1)
