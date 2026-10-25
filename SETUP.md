# Recreate this build from scratch

Everything needed to go from an empty folder to the running web build is in this repo:
pinned upstream revisions, five patches, and the build scripts. This file is the short version;
`BUILD_PLAN.md` has the full write-up (every source repair, verification checklist, deployment).

## Quick start

```bash
git clone https://github.com/rayfoolshs/musescore-online.git
cd musescore-online
./scripts/fetch.sh MuseScore      # pinned upstream + all 5 patches
cd MuseScore && ./scripts/build.sh
```

Result: `MuseScore/muse/build.artifacts/` — `MuseScoreStudio.wasm` (~84 MiB), `MuseScoreStudio.js`,
`MuseAudio.js`, `distr/`, `sound/FluidR3Mono_GM.sf3`, `viewer.html`.

## 1. Prerequisites

| Tool | Version | Notes |
|---|---|---|
| Qt (target) | 6.11.2 `wasm_singlethread` | + `qt5compat`, `qtshadertools`, `qtwebsockets` |
| Qt (host) | 6.11.2 desktop | + `qtshadertools` — see the gotcha below |
| Emscripten | 4.0.7 | pinned to match Qt 6.11.2 |
| CMake / Ninja | 4.4.4 / 1.13.2 | CMake 4.x, Ninja 1.13+ |
| Node, Python 3 | any recent | used by the asset-copy step and `serve.sh` |

```bash
pipx install aqtinstall

# target (wasm) Qt
aqt install-qt all_os wasm 6.11.2 wasm_singlethread -m qt5compat qtshadertools qtwebsockets

# host Qt — needed for moc/rcc AND for qsb
aqt install-qt mac desktop 6.11.2 clang_64 -m qtshadertools

# Emscripten
git clone --depth 1 https://github.com/emscripten-core/emsdk.git ~/emsdk
~/emsdk/emsdk install 4.0.7 && ~/emsdk/emsdk activate 4.0.7
```

**Gotcha:** the *wasm* `Qt6ShaderTools` package requires the host tool `qsb`
(`Qt6ShaderToolsTools`). Installing the host Qt without `-m qtshadertools` makes configure fail
with `Failed to find required Qt component "ShaderTools"`.

`scripts/build.sh` auto-detects `~/Qt/6.11.2/wasm_singlethread`, `~/Qt/6.11.2/macos` and
`~/emsdk`. For other locations, set `QT_ROOT_DIR`, `QT_HOST_PATH`, `EMSDK_PATH`
(`ninja_build.sh` also sources `$HOME/build_tools/environment.sh`, a convenient place for them).

## 2. Fetch the pinned sources

`scripts/fetch.sh [target-dir]` (default `MuseScore`) does:

1. shallow clone of `musescore/MuseScore` at **`9203eb3a37f11b90e70abfaee4f66406ee25e7c8`**
2. submodules: `muse` at `3e0eae57a9aa3dedb0a1e1d05d3ebf0cbc1b5e36`,
   `muse_deps` at `bf433c8f4f6f9d9897aa78d9fddcb2bbd02e42dc`
3. applies the patches **in order**:

| Patch | Contents |
|---|---|
| `0001-musescore-studio-web.patch` | app, web shell, JS bridge, viewer, `app-web` build config |
| `0002-muse-framework.patch` | `muse` (audio engine, RPC, settings, web interactive, MEMFS) |
| `0003-muse-deps.patch` | `muse_deps` |
| `0004-web-import-musescore.patch` | score import (MIDI, MusicXML, `.mscz`, `.mscx`), single-window replace, import errors |
| `0005-web-import-muse.patch` | MEMFS directories (needed for `.mscx`) + non-blocking dialogs |

4. copies `BUILD_PLAN.md` and `scripts/{build,serve,publish}.sh` into the checkout

Or by hand: see the "…or do it by hand" block in `README.md`.

## 3. Build

```bash
cd MuseScore
./scripts/build.sh          # JOBS=16 to use more cores; default 8
```

It builds two things:

* the editor with `MUSESCORE_BUILD_CONFIGURATION=app-web` → `MuseScoreStudio.wasm`
* the AudioWorklet engine (`src/web/audioengine`) → `MuseAudio.js`

Both land in `muse/build.artifacts/`. A clean build takes ~5 minutes on 16 cores plus the
one-time CMake configure and third-party dependency download.

## 4. Run it

```bash
cd muse/build.artifacts
python3 -m http.server 8099 --bind 127.0.0.1
# open http://127.0.0.1:8099/viewer.html
```

Click once in the page before expecting sound (autoplay policy). The build is single-threaded
WASM, so **no COOP/COEP headers** are needed — plain static hosting works.

## 5. Publish

```bash
cd MuseScore
./scripts/publish.sh        # force-replaces the gh-pages branch with muse/build.artifacts
```

`OWNER`, `REPO`, `SITE` and `MESSAGE` are overridable. The script excludes `*.symbols`, keeps the
social `preview.png`, and adds `.nojekyll`. GitHub Pages then serves
https://rayfoolshs.github.io/musescore-online/viewer.html (allow 30–60 s).

## 6. Verify

| Check | Expectation |
|---|---|
| Editor UI | notation view, palettes, toolbars render |
| Open `.mscz` (MuseScore 4) | score engraves |
| Open `.musicxml`, `.xml`, `.mxl` | MusicXML import, parts + lyrics intact |
| Open `.mid`, `.midi`, `.kar` | MIDI import, tracks/tempo imported, plays back |
| Open a second file | browser asks before discarding unsaved changes; new score replaces the old one |
| Open a damaged/unsupported file | error banner, app keeps running and keeps the open score |
| Save / Save as | downloads `<name>.mscz` (imported scores keep their file name) |
| Export | `MusicXML 4.0` and `MIDI` downloads |
| Print | PDF handed to the browser print dialog |

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| configure: `Failed to find required Qt component "ShaderTools"` | host Qt lacks `qtshadertools` (no `qsb`) — install it |
| `ninja: error: loading 'build.ninja'` | configure failed earlier; read the CMake error above it |
| Blank score area after opening a file | check the browser console for `WebApi::loadFromPath` / import errors |
| No sound | click once in the page first; playback needs an `AudioContext` after a user gesture |
| `.mscx` fails with "File open error" | the MEMFS directory fix (patch 0005) is missing |
| App exits on a bad file | patch 0005 (non-blocking web dialogs) is missing |
| Push rejected: file over 100 MB | the wasm grew past GitHub's hard limit; use Git LFS or split the assets |

## 8. If you would rather not build

- built app: `gh-pages` branch (and the live site)
- full source tree, patches already applied: release **`web-build-import`** →
  `musescore-online-src-import-694fa6b.tar.gz`
  (SHA-256 `efedd0bce3609c79ddf8fa90dc25611a9730d90708617fe928f3f22efd935d31`)

  ```bash
  tar -xzf musescore-online-src-import-694fa6b.tar.gz -C MuseScore
  cd MuseScore && ./scripts/build.sh
  ```

- older tree without the import work: release `web-build` → `musescore-online-src-cc7133f6.tar.gz`
  (SHA-256 `b5730e3cd59d49d8a02403b74a6c78f148c2658ce0bfabd3591b6e709dec3e53`); apply
  `0004`/`0005` by hand afterwards.
