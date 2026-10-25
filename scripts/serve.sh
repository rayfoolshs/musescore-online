#!/usr/bin/env bash
# Serve the built app locally (static files only).
# Run this from the root of the MuseScore checkout.
set -euo pipefail

if [[ ! -d ./muse/build.artifacts ]]; then
    echo "error: run this from the MuseScore checkout root after building" >&2
    exit 1
fi

cd muse/build.artifacts
PORT="${PORT:-8099}"
echo "http://127.0.0.1:${PORT}/viewer.html"
exec python3 -m http.server "${PORT}" --bind 127.0.0.1
