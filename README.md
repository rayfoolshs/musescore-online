# MuseScore Online

An experimental **browser build of [MuseScore Studio](https://github.com/musescore/MuseScore)**,
running entirely client-side: open MuseScore files (`.mscz`/`.mscx`), import MusicXML or MIDI,
save locally, edit and engrave, play back with a free GM SoundFont, print, and export to
MusicXML or MIDI. No server, no accounts, no cloud.

**Live demo:** https://rayfoolshs.github.io/musescore-online/viewer.html

![MuseScore Studio in a browser](https://rayfoolshs.github.io/musescore-online/preview.png)

## What works

| Feature | Notes |
|---|---|
| Editor UI | Full notation view, palettes, toolbars, properties, layout |
| Import / Open | `.mscz` (MuseScore 4) and `.mscx`, MusicXML (`.musicxml`, `.xml`, `.mxl`), MIDI (`.mid`, `.midi`, `.kar`) — Open button, drag & drop, or `muapi.loadScoreFile()` |
| New / Save / Save as | Native New Score wizard; `.mscz` download named after the score (or after the imported file) |
| Playback | Transport, playhead, scrolling, audible output (FluidR3Mono GM bank) |
| Print | Score rendered to PDF, handed to the browser print dialog |
| Export | MusicXML 4.0 (`.musicxml`) and MIDI (`.mid`) |

## This repository

GitHub's 100 MB file limit and the size of a full MuseScore checkout make a verbatim source dump
impractical. This repo therefore contains:

- `patches/` — the complete set of changes, as patches against upstream:
  - `0001-musescore-studio-web.patch` — app, web shell, JS bridge, viewer, build config
  - `0002-muse-framework.patch` — `muse` submodule (audio/RPC/settings fixes)
  - `0003-muse-deps.patch` — `muse_deps` submodule
  - `0004-web-import-musescore.patch` — score import (MIDI, MusicXML, `.mscz`, `.mscx`),
    single-window replacement and import errors (applies **after** 0001)
  - `0005-web-import-muse.patch` — MEMFS directories (needed for `.mscx`) and
    non-blocking dialogs in the web interactive layer (applies **after** 0002)
- `BUILD_PLAN.md` — the full write-up: goal, toolchain, build steps, every source repair,
  verification checklist, known issues, deployment notes.
- `scripts/build.sh` — rebuilds the app and the audio engine.
- `LICENSE.txt` — GPLv3.

The `gh-pages` branch holds the built application that the live demo serves.

### Backups

| What | Where |
|---|---|
| Changes, docs, scripts | `main` (this branch) |
| Full source tree **with score import** (current) | release **`web-build-import`** → `musescore-online-src-import-694fa6b.tar.gz` (141 MB, 15,038 files) |
| Original web-build source tree (no import) | release **`web-build`** → `musescore-online-src-cc7133f6.tar.gz` (141 MB, 15,040 files) |
| Import changes as patches | `patches/0004-web-import-musescore.patch` + `patches/0005-web-import-muse.patch` |
| Built app | `gh-pages` + the live site |

`web-build-import` is upstream `9203eb3a` + patches 0001–0005 with the submodule changes
included as working-tree files (no build outputs). Restore it with:

```bash
tar -xzf musescore-online-src-import-694fa6b.tar.gz -C MuseScore
cd MuseScore && ./scripts/build.sh
```

SHA-256: `efedd0bce3609c79ddf8fa90dc25611a9730d90708617fe928f3f22efd935d31`

The older `web-build` snapshot (local commit `cc7133f6`, patches 0001–0003 only) needs the
import patches applied by hand:

```bash
tar -xzf musescore-online-src-cc7133f6.tar.gz -C MuseScore
cd MuseScore
git apply /path/to/patches/0004-web-import-musescore.patch
git apply /path/to/patches/0005-web-import-muse.patch
./scripts/build.sh
```

SHA-256: `b5730e3cd59d49d8a02403b74a6c78f148c2658ce0bfabd3591b6e709dec3e53`

## Build it yourself

Upstream sources are public, so the patches are all you need. Everything is pinned — the
patches apply to these exact revisions (verified by rebuilding from a fresh clone):

| Component | Version / revision |
|---|---|
| `musescore/MuseScore` | `9203eb3a37f11b90e70abfaee4f66406ee25e7c8` |
| `musescore/muse_framework` (`muse/`) | `3e0eae57a9aa3dedb0a1e1d05d3ebf0cbc1b5e36` |
| `musescore/muse_deps` | `bf433c8f4f6f9d9897aa78d9fddcb2bbd02e42dc` |
| Qt | 6.11.2 — `wasm_singlethread` + host desktop |
| Emscripten | 4.0.7 |
| CMake / Ninja | 4.4.4 / 1.13.2 |

The fastest path (clones the pinned upstream, checks out the right submodule commits, applies
all patches and drops the build scripts in place):

```bash
./scripts/fetch.sh MuseScore
cd MuseScore
```

<details>
<summary>…or do it by hand</summary>

```bash
# 1. Pinned upstream + submodules
git init MuseScore && cd MuseScore
git remote add origin https://github.com/musescore/MuseScore.git
git fetch --depth 1 origin 9203eb3a37f11b90e70abfaee4f66406ee25e7c8
git checkout FETCH_HEAD
git submodule update --init --depth 1 muse muse_deps

# 2. Apply the patches, in order (0004/0005 are the import work)
git apply /path/to/patches/0001-musescore-studio-web.patch
git -C muse apply /path/to/patches/0002-muse-framework.patch
git -C muse_deps apply /path/to/patches/0003-muse-deps.patch
git apply /path/to/patches/0004-web-import-musescore.patch
git apply /path/to/patches/0005-web-import-muse.patch
```
</details>

### Toolchain

```bash
pipx install aqtinstall
# target (wasm) Qt
aqt install-qt all_os wasm 6.11.2 wasm_singlethread -m qt5compat qtshadertools qtwebsockets
# host Qt: needed for moc/rcc and for qsb — the wasm ShaderTools package requires the host tool
aqt install-qt mac desktop 6.11.2 clang_64 -m qtshadertools
# Emscripten 4.0.7
git clone --depth 1 https://github.com/emscripten-core/emsdk.git ~/emsdk
~/emsdk/emsdk install 4.0.7 && ~/emsdk/emsdk activate 4.0.7
```

### Build

`scripts/build.sh` auto-detects `~/Qt/6.11.2/wasm_singlethread`, `~/Qt/6.11.2/macos` and
`~/emsdk`; otherwise set `QT_ROOT_DIR`, `QT_HOST_PATH` and `EMSDK_PATH` (see BUILD_PLAN.md §3).
`ninja_build.sh` also sources `$HOME/build_tools/environment.sh`, so an env file there is a
handy place for those three variables.

```bash
cp -r /path/to/patches/../scripts .   # scripts/build.sh + scripts/serve.sh
./scripts/build.sh
```

Output lands in `muse/build.artifacts/` (editor + audio engine + JS glue + SoundFont), ready for
static hosting. Run `./scripts/serve.sh` from the checkout root to try it.

To redeploy the live site, publish the current build (replaces the `gh-pages` branch):

```bash
./scripts/publish.sh            # OWNER/REPO/SITE and MESSAGE are overridable
```

## Run locally

```bash
cd muse/build.artifacts
python3 -m http.server 8099 --bind 127.0.0.1
# open http://127.0.0.1:8099/viewer.html
```

Click once in the page before expecting sound — browsers only start an `AudioContext` after a
user gesture. Single-threaded WASM means **no COOP/COEP headers** are required, which is why
plain GitHub Pages hosting works.

## Notes and limitations

- The editor, save and export run in the browser; nothing is uploaded.
- The web build is single-window: importing a file replaces the open score. Unsaved changes
  are confirmed in the browser first, and a file that fails to import leaves the open score
  untouched.
- Save always downloads a copy — there is no writable local storage for the project.
- 84 MiB WebAssembly + 23 MB SoundFont on first load (cached afterwards).
- Playback uses a free GM SoundFont; Muse Sounds, VST and MuseSampler are not available.
- Experimental: this is the upstream `app-web` target, repaired and kept building.

## License

MuseScore Studio is **GPLv3**. This build is a derivative work: the corresponding source is
upstream MuseScore Studio plus the patches in `patches/`, offered here under the same license.
See `LICENSE.txt`.
