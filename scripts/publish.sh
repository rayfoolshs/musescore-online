#!/usr/bin/env bash
# Publish the current build to GitHub Pages.
#
# Run from the MuseScore checkout root after ./scripts/build.sh.
# Replaces the gh-pages branch with the contents of muse/build.artifacts
# (the JS symbol map is not published).
#
# Env: OWNER (default rayfoolshs), REPO (default musescore-online),
#      SITE  (default https://<owner>.github.io/<repo>/), MESSAGE
set -euo pipefail

OWNER="${OWNER:-rayfoolshs}"
REPO="${REPO:-musescore-online}"
SITE="${SITE:-https://${OWNER}.github.io/${REPO}/}"
MESSAGE="${MESSAGE:-Publish build $(date -u +%Y-%m-%dT%H:%M:%SZ)}"
ART="${ART:-muse/build.artifacts}"

if [[ ! -f "${ART}/MuseScoreStudio.wasm" ]]; then
    echo "error: no build found in ${ART} (run ./scripts/build.sh first)" >&2
    exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "Staging ${ART} -> ${STAGE}"
rsync -a --exclude '*.symbols' "${ART}/" "${STAGE}/"

# Keep the social preview image that lives on the live site.
curl -fsSL "${SITE}preview.png" -o "${STAGE}/preview.png" 2>/dev/null || true

touch "${STAGE}/.nojekyll"

cd "${STAGE}"
git init -q -b gh-pages
git add -A
git -c user.name="${GIT_AUTHOR_NAME:-${OWNER}}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-${OWNER}@users.noreply.github.com}" \
    commit -q -m "${MESSAGE}"

echo "Pushing to https://github.com/${OWNER}/${REPO}.git (gh-pages)"
git push --force "https://github.com/${OWNER}/${REPO}.git" gh-pages

echo
echo "Published. GitHub Pages will rebuild in about 30-60 s:"
echo "  ${SITE}viewer.html"
