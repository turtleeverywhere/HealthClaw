"""HealthBridge server configuration."""

import os
from pathlib import Path

# API key for authenticating the iOS app
API_KEY = os.getenv("HEALTHBRIDGE_API_KEY", "change-me-in-production")

# SQLite database path
DB_PATH = Path(os.getenv("HEALTHBRIDGE_DB", "/home/lars/.openclaw/workspace-coder/HealthBridge/server/healthbridge.db"))

# Server settings
HOST = os.getenv("HEALTHBRIDGE_HOST", "0.0.0.0")
PORT = int(os.getenv("HEALTHBRIDGE_PORT", "8099"))
