# HealthClaw 🏥

Sync Apple Health data to your personal server for AI-powered health insights.

## Architecture

```
┌─────────────┐        ┌──────────────┐        ┌──────────────┐
│  iOS App    │──POST──▶│  FastAPI     │──read──▶│  OpenClaw    │
│  (SwiftUI)  │        │  Server      │        │  Agent       │
│             │        │  (SQLite)    │        │  (cron)      │
└─────────────┘        └──────────────┘        └──────────────┘
```

## Components

### 1. iOS App (`ios/`)
SwiftUI app that reads from Apple HealthKit and syncs to your server.

**Data collected:**
- Activity (steps, distance, calories, exercise time, flights, VO₂ max)
- Heart (resting HR, average HR, HRV, walking HR)
- Sleep (duration, stages: deep/REM/core/awake)
- Workouts (type, duration, distance, calories, heart rate)
- Body (weight, BMI, body fat %)
- Vitals (blood pressure, SpO₂, respiratory rate, temperature)
- Mood (State of Mind, iOS 18+ — valence, labels)
- Mindfulness sessions
- Synthetic "Body Battery" score (computed from HRV + sleep + activity)

**Setup:**
1. Open `ios/` in Xcode
2. Add HealthKit capability to your target
3. Set your Team for signing
4. Run on a physical device (HealthKit doesn't work in Simulator)
5. In Settings tab, enter your server endpoint and API key

### 2. FastAPI Server (`server/`)
Receives health data and stores it in SQLite.

**Setup:**
```bash
cd server
pip install -r requirements.txt

# Set your API key
export HEALTHCLAW_API_KEY="your-secret-key"

# Run
python main.py
# → Listening on 0.0.0.0:8099
```

**Endpoints:**
| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/health/sync` | Receive health data from iOS app |
| GET | `/api/health/summary?days=7` | Daily summaries |
| GET | `/api/health/latest` | Most recent daily summary |
| GET | `/api/health/workouts?days=7` | Recent workouts |
| GET | `/api/health/mood?days=7` | Mood entries |
| GET | `/api/health/sleep?days=7` | Sleep sessions |
| GET | `/api/health/ping` | Health check (no auth) |

All endpoints except `/ping` require `X-API-Key` header.

### 3. OpenClaw Agent (TODO)
Cron job that queries the API and generates health insights.

## Network

The server runs on your Tailscale network. In the iOS app settings, enter your Tailscale IP:
```
100.x.x.x:8099
```

## License
Private — for personal use.
