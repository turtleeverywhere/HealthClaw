"""HealthClaw server configuration."""

import os
from pathlib import Path

# API key for authenticating the iOS app
API_KEY = os.getenv("HEALTHCLAW_API_KEY", "change-me-in-production")

# SQLite database path
DB_PATH = Path(os.getenv("HEALTHCLAW_DB", "/home/lars/.openclaw/workspace-coder/HealthClaw/server/healthclaw.db"))

# Server settings
HOST = os.getenv("HEALTHCLAW_HOST", "0.0.0.0")
PORT = int(os.getenv("HEALTHCLAW_PORT", "8099"))
