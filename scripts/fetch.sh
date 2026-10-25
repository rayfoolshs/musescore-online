#!/usr/bin/env bash
# Recreate the exact source tree from scratch, pinned to the versions this project
# was built and verified against.
#
# Run this from the patches repository (not from the MuseScore checkout):
#   ./scripts/fetch.sh [target-dir]
set -euo pipefail

BASE_COMMIT=9203eb3a37f11b90e70abfaee4f66406ee25e7c8   # musescore/MuseScore
MUSE_COMMIT=3e0eae57a9aa3dedb0a1e1d05d3ebf0cbc1b5e36   # musescore/muse_framework
DEPS_COMMIT=bf433c8f4f6f9d9897aa78d9fddcb2bbd02e42dc   # musescore/muse_deps

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "${HERE}/.." && pwd)"
DEST="${1:-MuseScore}"

if [[ -e "${DEST}" ]]; then
    echo "error: ${DEST} already exists" >&2
    exit 1
fi

echo "Cloning MuseScore @ ${BASE_COMMIT:0:7}"
git init -q "${DEST}"
cd "${DEST}"
git remote add origin https://github.com/musescore/MuseScore.git
git fetch -q --depth 1 origin "${BASE_COMMIT}"
git checkout -q FETCH_HEAD

echo "Fetching submodules"
git submodule update --init --depth 1 muse muse_deps
git -C muse fetch -q --depth 1 origin "${MUSE_COMMIT}" 2>/dev/null || true
git -C muse checkout -q "${MUSE_COMMIT}"
git -C muse_deps fetch -q --depth 1 origin "${DEPS_COMMIT}" 2>/dev/null || true
git -C muse_deps checkout -q "${DEPS_COMMIT}"

echo "Applying patches"
git apply "${REPO}/patches/0001-musescore-studio-web.patch"
git -C muse apply "${REPO}/patches/0002-muse-framework.patch"
git -C muse_deps apply "${REPO}/patches/0003-muse-deps.patch"

cp "${REPO}/BUILD_PLAN.md" .
mkdir -p scripts
cp "${REPO}/scripts/build.sh" "${REPO}/scripts/serve.sh" "${REPO}/scripts/publish.sh" scripts/

echo
echo "Ready: $(pwd)"
echo "  muse: $(git -C muse rev-parse --short HEAD)  muse_deps: $(git -C muse_deps rev-parse --short HEAD)"
echo "Next: ./scripts/build.sh"
