#!/usr/bin/env bash
# Rebuild MuseScore Online: editor (WASM) + audio engine (AudioWorklet).
# Run this from the root of the MuseScore checkout (copy the scripts/ folder there),
# after applying the patches. See README.md and BUILD_PLAN.md §3-4.
#
# Toolchain locations are auto-detected; override with QT_DIR, QT_ROOT_DIR,
# QT_HOST_PATH and EMSDK_PATH if yours live elsewhere.
set -euo pipefail

if [[ ! -f ./ninja_build.sh || ! -d ./src/web ]]; then
    echo "error: run this from the MuseScore checkout root (copy scripts/ there first)" >&2
    exit 1
fi

find_dir() {
    local candidate
    for candidate in "$@"; do
        [[ -n "${candidate}" && -d "${candidate}" ]] && { printf '%s' "${candidate}"; return 0; }
    done
    return 1
}

EMSDK_PATH="${EMSDK_PATH:-$(find_dir "$HOME/emsdk" "$HOME/Downloads/emsdk" "/opt/emsdk" || true)}"
if [[ -z "${EMSDK_PATH}" || ! -f "${EMSDK_PATH}/emsdk_env.sh" ]]; then
    echo "error: emsdk not found; set EMSDK_PATH (expected 4.0.7)" >&2
    exit 1
fi

QT_ROOT_DIR="${QT_ROOT_DIR:-${QT_DIR:-$(find_dir \
    "$HOME/Qt/6.11.2/wasm_singlethread" \
    "$HOME/Downloads/Qt/6.11.2/wasm_singlethread" \
    "/opt/Qt/6.11.2/wasm_singlethread" || true)}}"
QT_HOST_PATH="${QT_HOST_PATH:-$(find_dir \
    "$HOME/Qt/6.11.2/macos" \
    "$HOME/Downloads/Qt/6.11.2/macos" \
    "/opt/Qt/6.11.2/macos" || true)}"
QT_DIR="${QT_DIR:-${QT_ROOT_DIR}}"

if [[ -z "${QT_ROOT_DIR}" || -z "${QT_HOST_PATH}" ]]; then
    echo "error: Qt 6.11.2 (wasm_singlethread + host) not found; set QT_ROOT_DIR/QT_HOST_PATH" >&2
    exit 1
fi

export QT_DIR QT_ROOT_DIR QT_HOST_PATH
export QT_CHAINLOAD_TOOLCHAIN_FILE="${EMSDK_PATH}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
# shellcheck disable=SC1091
source "${EMSDK_PATH}/emsdk_env.sh" >/dev/null 2>&1
export CMAKE_TOOLCHAIN_FILE="${QT_ROOT_DIR}/lib/cmake/Qt6/qt.toolchain.cmake"

echo "Qt (wasm): ${QT_ROOT_DIR}"
echo "Qt (host): ${QT_HOST_PATH}"
echo "emsdk:     ${EMSDK_PATH}"

JOBS="${JOBS:-8}"

# A source snapshot extracted from an archive has no git metadata; the build only
# uses the revision for the About/version string.
REVISION="${MUSESCORE_REVISION:-$(git rev-parse --short=7 HEAD 2>/dev/null || echo 0000000)}"

# --- editor ---------------------------------------------------------------
MUSE_APP_BUILD_MODE=dev \
MUSESCORE_BUILD_CONFIGURATION=app-web \
MUSESCORE_BUILD_NUMBER=12345678 \
MUSESCORE_REVISION="${REVISION}" \
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
