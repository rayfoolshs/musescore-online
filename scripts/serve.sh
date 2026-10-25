#!/usr/bin/env bash
# Serve the built app locally (static files only).
set -euo pipefail
cd "$(dirname "$0")/../muse/build.artifacts"
PORT="${PORT:-8099}"
echo "http://127.0.0.1:${PORT}/viewer.html"
exec python3 -m http.server "${PORT}" --bind 127.0.0.1
