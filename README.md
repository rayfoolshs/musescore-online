# MuseScore Online

An experimental **browser build of [MuseScore Studio](https://github.com/musescore/MuseScore)**,
running entirely client-side: open and save `.mscz` locally, edit and engrave, play back with a
free GM SoundFont, print, and export to MusicXML or MIDI. No server, no accounts, no cloud.

**Live demo:** https://rayfoolshs.github.io/musescore-online/viewer.html

![MuseScore Studio in a browser](https://rayfoolshs.github.io/musescore-online/preview.png)

## What works

| Feature | Notes |
|---|---|
| Editor UI | Full notation view, palettes, toolbars, properties, layout |
| New / Open / Save / Save as | Native New Score wizard; local file open; `.mscz` download named after the score |
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
- `BUILD_PLAN.md` — the full write-up: goal, toolchain, build steps, every source repair,
  verification checklist, known issues, deployment notes.
- `scripts/build.sh` — rebuilds the app and the audio engine.
- `LICENSE.txt` — GPLv3.

The `gh-pages` branch holds the built application that the live demo serves.

### Backups

| What | Where |
|---|---|
| Changes, docs, scripts | `main` (this branch) |
| Full patched source tree | release **`web-build`** → `musescore-online-src-cc7133f6.tar.gz` (141 MB, 15,040 files) |
| Built app | `gh-pages` + the live site |

The `web-build` snapshot is the local commit `cc7133f6` (upstream `9203eb3a` + the three
patches, with the submodule changes included as working-tree files). Restore it with:

```bash
tar -xzf musescore-online-src-cc7133f6.tar.gz -C MuseScore
cd MuseScore && ./scripts/build.sh
```

SHA-256: `6d651cc73cc6d3a93728e80e48b6be9fab8ea328d52339088c58e9761bed4541`

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

# 2. Apply the patches
git apply /path/to/patches/0001-musescore-studio-web.patch
git -C muse apply /path/to/patches/0002-muse-framework.patch
git -C muse_deps apply /path/to/patches/0003-muse-deps.patch
```
</details>

# 3. Toolchain (versions used and verified)
#    Qt 6.11.2 wasm_singlethread + host Qt 6.11.2 (macOS), Emscripten 4.0.7
aqt install-qt all_os wasm 6.11.2 wasm_singlethread -m qt5compat qtshadertools qtwebsockets

# 4. Build (see BUILD_PLAN.md §3–4 for the environment file)
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
- Save always downloads a copy — there is no writable local storage for the project.
- 84 MiB WebAssembly + 23 MB SoundFont on first load (cached afterwards).
- Playback uses a free GM SoundFont; Muse Sounds, VST and MuseSampler are not available.
- Experimental: this is the upstream `app-web` target, repaired and kept building.

## License

MuseScore Studio is **GPLv3**. This build is a derivative work: the corresponding source is
upstream MuseScore Studio plus the patches in `patches/`, offered here under the same license.
See `LICENSE.txt`.
