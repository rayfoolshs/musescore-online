#!/usr/bin/env bash
# Rebuild MuseScore Online: editor (WASM) + audio engine (AudioWorklet).
# Run this from the root of the MuseScore checkout (copy the scripts/ folder there),
# after applying the patches. See README.md and BUILD_PLAN.md §3-4.
set -euo pipefail

if [[ ! -f ./ninja_build.sh || ! -d ./src/web ]]; then
    echo "error: run this from the MuseScore checkout root (copy scripts/ there first)" >&2
    exit 1
fi

: "${QT_DIR:=${HOME}/Qt/6.11.2/wasm_singlethread}"
: "${QT_ROOT_DIR:=${QT_DIR}}"
: "${QT_HOST_PATH:=${HOME}/Qt/6.11.2/macos}"
: "${EMSDK_PATH:=${HOME}/emsdk}"

export QT_DIR QT_ROOT_DIR QT_HOST_PATH
export QT_CHAINLOAD_TOOLCHAIN_FILE="${EMSDK_PATH}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
# shellcheck disable=SC1091
source "${EMSDK_PATH}/emsdk_env.sh" >/dev/null 2>&1
export CMAKE_TOOLCHAIN_FILE="${QT_ROOT_DIR}/lib/cmake/Qt6/qt.toolchain.cmake"

JOBS="${JOBS:-8}"

# --- editor ---------------------------------------------------------------
MUSE_APP_BUILD_MODE=dev \
MUSESCORE_BUILD_CONFIGURATION=app-web \
MUSESCORE_BUILD_NUMBER=12345678 \
MUSESCORE_REVISION="$(git rev-parse --short=7 HEAD)" \
MUSESCORE_DOWNLOAD_SOUNDFONT=OFF \
MUSESCORE_RUN_LRELEASE=OFF \
MUSESCORE_MODULE_UPDATE=OFF \
bash ./ninja_build.sh -t release -j "${JOBS}"

# --- audio engine ---------------------------------------------------------
mkdir -p build.audio.release
(
    cd build.audio.release
    cmake ../src/web/audioengine -GNinja -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="${CMAKE_TOOLCHAIN_FILE}"
    ninja -j 4
)

echo
echo "Built: muse/build.artifacts/"
echo "Serve: python3 -m http.server 8099 --bind 127.0.0.1 (from that folder)"
