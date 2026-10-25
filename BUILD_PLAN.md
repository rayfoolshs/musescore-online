# MuseScore Studio — Browser Build Plan

Turning [MuseScore Studio](https://github.com/musescore/MuseScore) back into a working **web app**
(experimental `app-web` target), running fully client-side: local file open/save, playback, no cloud,
no accounts, no collaboration.

---

## 1. Goal & scope

| In scope | Out of scope |
|---|---|
| Familiar MuseScore UI in a browser tab | Cloud saving / accounts |
| New score wizard, open & save `.mscz` locally | Real-time collaboration |
| Import MIDI, MusicXML (`.musicxml`/`.xml`/`.mxl`) and MuseScore files (`.mscz`/`.mscx`) | Other importers (GuitarPro, Capella, OVE, MNX … are compiled out) |
| Playback with a free GM SoundFont | Muse Sounds, VST, MuseSampler |
| Static hosting (no server logic) | Cloud-only features (OMR / audio→score) |

**Status: working prototype.**
The editor UI runs in the browser, the New Score wizard works, scores open and engrave,
MIDI / MusicXML / MuseScore files can be imported, **Save downloads a `.mscz` to disk**, and
the transport plays back with FluidR3Mono as the GM bank.

### Web toolbar

Six icon buttons sit between the page tabs and the playback toolbar, in this left-to-right
order: **Print, New, Open, Save, Save as ⌄, Export**.

| Button | Icon | Command | Implementation |
|---|---|---|---|
| Print | `IconCode.PRINT` | `command://web/print-score` | `IExportProjectScenario::exportScores` → PDF → hidden iframe → browser print dialog |
| New | `IconCode.NEW_FILE` | `command://project/new` | MuseScore's native "New score" wizard |
| Open | `IconCode.OPEN_FILE` | `command://web/open-score` | JS file picker (`distr/muimpl.js`) → MEMFS → `WebApi::loadFromPath` → import by suffix (`.mscz`, `.mscx`, MusicXML, MIDI) |
| Save | `IconCode.SAVE` | `command://web/score-save` | `INotationProject::save(SaveCopy)` → `saveComplited` → JS blob download, named after the score |
| Save as… | `IconCode.SMALL_ARROW_DOWN` | `command://web/score-save-as` | JS `prompt()` for a name → `saveScoreAs(name)` → same download path |
| Export | `IconCode.SHARE_FILE` | `command://web/export-musicxml`, `command://web/export-midi` | menu → `IExportProjectScenario::exportScores` to MEMFS → `onScoreExported` → JS blob download |

Save, Save as and Export all write the whole score (master notation) and name the file after
the score title (with any import suffix stripped), falling back to the name of the file the
score was opened/imported from. The web build compiles the real `iex_musicxml`, `iex_midi` and
`iex_imagesexport` (PDF) modules instead of their stubs.

---

## 2. Why this is not a "flip a flag" build

MuseScore has an `app-web` configuration (`SetupConfigure.cmake`), but upstream it is
**broken and unmaintained**: its CI workflow is `workflow_dispatch`-only and labelled
"experimental for internal use". Every web-platform file had drifted from `main`.

The work therefore falls into two buckets:

- **Toolchain / build plumbing** — getting Qt-for-WASM + Emscripten to compile and link.
- **Source repairs** — updating stale web-platform code until it links and runs.

---

## 3. Toolchain

Exact versions below are what the MuseScore CI uses, and what this build is verified against.

| Component | Version | Notes |
|---|---|---|
| Qt (target) | **6.11.2**, `wasm_singlethread` | `aqt install-qt all_os wasm 6.11.2 wasm_singlethread -m qt5compat qtshadertools qtwebsockets` |
| Qt (host) | 6.11.2, macOS desktop | Required for `QT_HOST_PATH` (moc/rcc/qtshaderc). Install `-m qtshadertools` as well: the **wasm** `Qt6ShaderTools` package needs the host `qsb` tool (`Qt6ShaderToolsTools`), otherwise configure fails with "failed to find required Qt component ShaderTools". `aqt` installs it as `Qt/6.11.2/macos` |
| Emscripten | **4.0.7** | Pinned to match Qt 6.11.2 |
| CMake | 4.x | |
| Ninja | 1.13+ | |
| Source | `musescore/MuseScore` `main` + `muse` / `muse_deps` submodules | shallow clone is fine |

Why single-threaded WASM: no `SharedArrayBuffer`, therefore **no COOP/COEP headers** —
which is what makes plain GitHub Pages hosting viable.

### Environment file

`ninja_build.sh` sources `$HOME/build_tools/environment.sh`. Minimal macOS version (paths as
`aqt` and `emsdk` create them):

```bash
export EMSDK_PATH="$HOME/emsdk"
export QT_DIR="$HOME/Qt/6.11.2/wasm_singlethread"
export QT_ROOT_DIR="$QT_DIR"
export QT_HOST_PATH="$HOME/Qt/6.11.2/macos"
export QT_CHAINLOAD_TOOLCHAIN_FILE="$EMSDK_PATH/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake"
export CMAKE_TOOLCHAIN_FILE="$QT_ROOT_DIR/lib/cmake/Qt6/qt.toolchain.cmake"
source "$EMSDK_PATH/emsdk_env.sh"
```

`scripts/build.sh` finds the same three locations on its own; the env file is only needed for
other entry points (or for non-default install paths).

---

## 4. Build

### 4.1 Main editor app (~88 MB WASM)

```bash
cd MuseScore
source $HOME/build_tools/environment.sh
export CMAKE_TOOLCHAIN_FILE=${QT_ROOT_DIR}/lib/cmake/Qt6/qt.toolchain.cmake

MUSE_APP_BUILD_MODE=dev \
MUSESCORE_BUILD_CONFIGURATION=app-web \
MUSESCORE_BUILD_NUMBER=12345678 \
MUSESCORE_REVISION=$(git rev-parse --short=7 HEAD) \
MUSESCORE_DOWNLOAD_SOUNDFONT=OFF \
MUSESCORE_RUN_LRELEASE=OFF \
bash ./ninja_build.sh -t release -j 4
```

Output lands in **`muse/build.artifacts/`**:

```
MuseScoreStudio.wasm   ~88 MB   editor (incl. MusicXML + MIDI writers)
MuseScoreStudio.js     ~265 KB  Qt loader
viewer.html / index.html
distr/                 muapi.js, muimpl.js, audiodriver.js, audio_worklet_processor.js, qtloader.js, config.js
sound/                 GM SoundFont
```

### 4.2 Audio engine (2.1 MB, runs inside an AudioWorklet)

Built as a **separate** WASM module — `MuseAudio.js` is concatenated with
`audio_worklet_processor.js` into an AudioWorklet blob at runtime.

```bash
mkdir -p build.audio.release && cd build.audio.release
cmake ../src/web/audioengine -GNinja -DCMAKE_BUILD_TYPE=Release
ninja -j 4
```

`MuseAudio.js` is written into `muse/build.artifacts/` (same folder as the editor).

### 4.3 Run locally

```bash
cd muse/build.artifacts
python3 -m http.server 8099 --bind 127.0.0.1
# open http://127.0.0.1:8099/viewer.html
```

**Click once in the page** before expecting sound — browsers require a user gesture
to start an `AudioContext` (autoplay policy). That gesture triggers
`muapi.startAudioProcessing`.

---

## 5. Source repairs applied

### 5.1 Framework (`muse/`)

| File | Problem | Fix |
|---|---|---|
| `framework/cmake/MuseSetupConfiguration.cmake` | nothing includes legacy `declare_module` macros used by `web/appshell` | include `DeclareModuleSetup` before `MuseCreateModule` |
| `audio/common/rpc/platform/web/webrpcchannel.{h,cpp}` | stale `IRpcChannel` (no `CtxId`, removed `listenAll`, wrong handler types) | rewritten against current interface |
| `interactive/internal/platform/web/webinteractive.{h,cpp}` | stale `IInteractive` (bad `override`s, missing pure virtuals) | methods moved to `IPlatformInteractive`; implemented `currentUriAboutToBeChanged`, `topWindow`, `topWindowIsWidget` |
| `audio/driver/platform/web/webaudiodriver.{h,cpp}` | stale `IAudioDriver` (removed setters, `unsigned int` vs `samples_t`) | updated signatures, added `defaultDevice()` |
| `audio/main/platform/web/websoundfontcontroller.{h,cpp}` | `ContextInject` on a **global** interface; `Method::` → `MsgCode::` | `GlobalInject`, new `MsgCode` |
| `audio/main/audiomodule.cpp` | desktop `EngineGlobalSetup` registered/resolved in the GUI process, where no engine exists on web | `#ifndef Q_OS_WASM` guards around engine setup (the engine runs in the AudioWorklet) |
| `audio/common/realtimethreadpool.h` | `setThreadPriority` absent without threads | guarded with `MUSE_THREADS_SUPPORT` |
| `audio/thirdparty/moodycamel/lightweightsemaphore.h` | POSIX `sem_timedwait` undefined in single-thread WASM | added atomic-counter semaphore for `__EMSCRIPTEN__ && !__EMSCRIPTEN_PTHREADS__` |
| `global/settings.{h,cpp}` | `QSettings`/`QString` in a Qt-free build | guarded behind `NO_QT_SUPPORT`; in-memory fallback |
| `audio/common/audiotypes.h` | `std::map<…, QString>` | `muse::String` |
| `audio/engine/internal/synthesizers/soundfontrepository.{h,cpp}` | `onResolve(this)` but class not `Asyncable` | added `async::Asyncable` |
| `audio/engine/internal/synthesizers/fluidsynth/fluidresolver.cpp` | score asks for `MS Basic.sf3`, ships a different GM bank → no synth | fallback to the single available whole-soundfont GM bank |

### 5.2 App / web layer (`src/`)

| File | Problem | Fix |
|---|---|---|
| `app/CMakeLists.txt` | `commandlineparser.cpp` only built with `MUE_ENABLE_CONSOLEAPP`, but `guiapp.cpp` always uses it | always compile it |
| `app/internal/guiapp.cpp` | `mainWindowQmlPath()` hardcodes a desktop QML path ("linux" on WASM) | `Q_OS_WASM` → `:/qml/Main.qml` |
| `app/main.cpp` | `QSslSocket` absent in Qt WASM | `MUSE_SSL_AVAILABLE` guard |
| `engraving/api/v1/util.{h,cpp}`, `qmlpluginapi.cpp` | `QProcess` absent in WASM | `QT_QPROCESS_SUPPORTED` guards |
| `web/appshell/appshellmodule.{h,cpp}` | context-scoped objects built with `globalCtx()` (id 0) → `ioc()` returns **nullptr** → null virtual calls | added `AppShellContext : IContextSetup`, mirroring desktop |
| `web/appshell/internal/appshellstate.{h,cpp}`, `iappshellstate.h` | navigator visibility lived in a **global** config but needs contextual `IUiState` | new contextual `AppShellState` |
| `web/appshell/internal/appshellconfiguration.{h,cpp}` | stale navigator methods, contextual inject in a global object | moved out |
| `web/appshell/internal/applicationuiactions.cpp` | `mu::context::*` enums removed, `useNewPercussionPanel` removed | `muse::ui::UiCtxProjectOpened`, `muse::shortcuts::CTX_*` |
| `web/appshell/view/notationpagemodel.cpp` | percussion API moved | uses `INotationSceneConfiguration`; missing includes added |
| `web/appshell/view/navigableappmenumodel.cpp` | `QApplication` (widgets) not in WASM; private Qt header path | `QGuiApplication`; Qt private include dirs derived in CMake |
| `web/appshell/internal/istartupscenario.h`, `startupscenario.{h,cpp}` | **ABI mismatch** — `runOnSplashScreen()` returned `Promise` vs desktop `void` (same interface id) | aligned to `void` |
| `web/appshell/qml/AppMenuBar.qml` | duplicated block + unbalanced brace (35/36); undefined `textMetrics` | repaired |
| `web/appshell/qml/Main.qml` | missing `import Muse.Interactive` (for `InteractiveProvider`) | added |
| `web/appjs/webapi.{h,cpp}` | `inline static` injects initialised before `globalCtx` is valid | instance members on a `Contextable`, initialised per-context |
| `web/appjs/appjsmodule.{h,cpp}` | `WebApi` needs a real context | new `AppJsContext`; `WebApi::init(ctx)` |
| `web/appjs/webapi.cpp` | no way to get bytes from JS (Qt loader doesn't export `HEAPU8`) | `loadFromPath()` reads MEMFS natively, rewrites via MuseScore IO, then `openProject()` |
| `web/appjs/install.js` | asset root pointed at `src/` instead of the repo root → **SoundFont never copied** | `ROOT=HERE+"/../../.."` |
| `web/appjs/distr/muimpl.js` | `loadScoreData` used `Module.HEAPU8` (undefined) and the dead `file-open` action | `FS.writeFile` + `ccall('loadFromPath')` |
| `project/internal/convertfiletoscore*` | `museScoreComService()` is null when the cloud module is a stub | null guard, feature disables itself |
| `engraving/engravingmodule.cpp` | scores ask for `Times New Roman`/`Arial`; missing → Qt fell back to **Bravura**, whose ASCII maps to musical symbols (`o` drawn as a notehead) | substitution table: common desktop text fonts → bundled `FreeSerif`/`FreeSans`/`DejaVu Sans Mono` |
| `web/appshell/qml/Main.qml` | no file actions in the web UI | New/Open/Save icon buttons |
| `web/appshell/view/notationpagemodel.{h,cpp}` | — | `newScore()/openScore()/saveScore()` Q_INVOKABLEs dispatching project commands |
| `web/appjs/appjsmodule.{h,cpp}` | `PROJECT_SAVE_COMMAND` has no working backend on web | `AppJsContext` registers `command://web/score-save` → `WebApi::saveScore()` |
| `web/appjs/webapi.{h,cpp}` | save bytes never reached the browser | `saveScore()` writes a copy; `onProjectSaved(name, bytes)` now passes the filename |
| `web/appjs/viewer/viewer.html`, `distr/muapi.js` | save callback only logged | Blob + anchor download with the real filename |
| `SetupConfigure.cmake` (`app-web`) | `MUE_BUILD_IMPEXP_MUSICXML_MODULE` / `_MIDI_MODULE` were `OFF`, so only stub modules were linked and no export writers existed | both set `ON` for the web build (+1.5 MB WASM) |
| `web/appjs/webapi.{h,cpp}` | no export path on web | `exportScore("musicxml"/"midi")`: `IExportProjectScenario::exportScores` into `/mu/temp`, read bytes, `onScoreExported(name, bytes)` |
| `web/appjs/appjsmodule.cpp` | no export commands | registers `command://web/export-musicxml` / `command://web/export-midi` |
| `web/appshell/view/notationpagemodel.{h,cpp}` | — | `exportMusicXml()` / `exportMidi()` Q_INVOKABLEs dispatching the export commands |
| `web/appshell/qml/Main.qml` | no export actions in the web UI | Export button + menu (MusicXML / MIDI) |
| `web/appjs/viewer/viewer.html`, `distr/muapi.js` | no export download | `onScoreExported` → Blob + anchor download, MIME by suffix |
| `SetupConfigure.cmake` (`app-web`) | `MUE_BUILD_IMPEXP_IMAGESEXPORT_MODULE` `OFF` → no PDF writer | set `ON`; backs the Print action |
| `web/appjs/webapi.{h,cpp}` | save always wrote `saved.mscz`; no naming, no save-as | `scoreBaseName()` (title, import suffix stripped → project name → `score`), `saveScoreAs(name)`, `requestSaveAs()` |
| `web/appjs/webapi.cpp` (`loadFromPath`) | every opened file was copied to `/mu/temp/current.mscz`, losing its name | writes through the io layer to the original `/mu/temp/<name>`, so title/save/export names follow the file |
| `app/webapi_export.cpp` | no save-as entry point | `EMSCRIPTEN_KEEPALIVE saveScoreAs(fileName)` |
| `web/appjs/webapi.{h,cpp}` | no print path | `printScore()` → PDF export → `onPrintReady(name, bytes)` |
| `web/appjs/viewer/viewer.html` | no save-as prompt / print | `onSaveAsRequested` → `prompt()`; `onPrintReady` → hidden iframe → `window.print()` (falls back to opening the PDF) |
| `web/appshell/iappshellconfiguration.h` | interface still declared navigator visibility methods that moved to `IAppShellState` | declarations removed |
| `web/appshell/view/mainwindowtitleprovider.h` | included the removed `context/iprojectsession.h` | `project/iprojectsession.h`, `mu::project::IProjectSession` |
| `web/appshell/view/notationstatusbarmodel.{h,cpp}` | missing includes for notation/command types | includes added |
| `web/appjs/webapi.cpp` (`loadFromPath`) | a second file could never be opened: the open scenario hands it to a new window, and the multiwindows provider is a stub on web | the file is loaded first (`IOpenProjectScenario::loadProject`) and only replaces the open score when it succeeded, so a failed import keeps the current score |
| `project/iopenprojectscenario.h`, `internal/openprojectscenario.h` | `loadProject()` was private, so "read without switching" was impossible | exposed on the interface (and the test mock) |
| `web/appjs/appjsmodule.cpp`, `web/appshell/view/notationpagemodel.cpp` | the Open button dispatched the native open command, whose dialogs the web shell lacks | `command://web/open-score` → `WebApi::requestOpenFile()` → JS picker |
| `web/appjs/distr/muimpl.js` | host callbacks were read from `Module.config`, which `qtLoad()` replaces with Qt's own config → every import error fell back to `alert()` | host callbacks kept in a module-scoped `hostConfig`; added the file picker, the "discard unsaved changes?" confirm and the import-error callback |
| `web/appjs/viewer/viewer.html` | no file input, no drag & drop, import errors invisible | hidden `<input type="file">` (created by `muimpl.js`), drag & drop overlay, dismissible error banner |
| `web/appjs/webapi.cpp` (`scoreBaseName`) | imported scores (no work title) saved as `score.mscz` | falls back to the imported file name (`grace.mid` → `grace.mscz`) |
| `muse/framework/global/io/internal/memfilesystem.cpp` | `MemFileSystem` has no directory entries, so `DirReader` (uncompressed `.mscx`) saw the container directory as missing → "File open error" | `exists()` also reports parent directories of stored files (with guards in `readFile`/`fileSize`) |
| `muse/framework/interactive/internal/platform/web/webinteractive.cpp` | dialogs forwarded to the QML provider: synchronous ones answer "Not supported!!" and **abort the app** (a malformed MusicXML killed the page), asynchronous ones open stray top-level windows that linger and leak MEMFS paths | `question`/`info`/`warning`/`error` (sync and async) log the message and answer with the default button; the web shell reports user-visible problems itself (import banner) |
| `web/appjs/distr/audiodriver.js` | a rebuilt `MuseAudio.js` could be served from the browser cache | cache-busting query on the worklet module (`MuseAudio.js?v=N`) |
| `web/appshell/qml/Main.qml`, `appshell.qrc` | upstream shipped a scratch `Dev` tab (Qt drag-and-drop demo) | tab, `DevFrame.qml` and its `.qrc` entry removed |

### 5.3 Web audio engine (`src/web/audioengine/`)

| Problem | Fix |
|---|---|
| CMake used old `src/framework` layout | layout-aware (`muse/framework` vs legacy) |
| `target_link_libraries` before `add_executable` | reordered |
| `NO_QT_SUPPORT` applied **after** `add_subdirectory` | moved before |
| missing `utfcpp` / `picojson` / `pugixml` | include paths + real `pugixml`/`utfcpp` targets |
| `MUSE_MODULE_AUDIO_WORKMODE` empty (generated header `#define`d it blank) | set as CMake variable |
| `OS_IS_WASM` undefined → compiled the desktop worker | `include(GetPlatformInfo)` |
| `EngineController::registerExports()` gone; `ModulesIoC` gone | use `EngineGlobalSetup` + `ModulesGlobalIoC` |
| **`HEAPU8` not exported** → every audio callback threw → silence | `EXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPU8` |
| **no async pump in the AudioWorklet** → `prepareToPlay` never ran → transport hung | `muse::async::processMessages()` in `WebAudioEngine::process()` |

### 5.4 Score import (MIDI / MusicXML / MuseScore files)

The web build can open **`.mscz`** (MuseScore 4 projects), **`.mscx`** (uncompressed),
**MusicXML** (`.musicxml`, `.xml`, `.mxl`) and **MIDI** (`.mid`, `.midi`, `.kar`). The readers
are the real upstream ones: the project module handles MuseScore files, `iex_musicxml` and
`iex_midi` handle the rest (the same modules that supply the export writers).

```
Open button ──▶ command://web/open-score ──▶ WebApi::requestOpenFile()
                                                        │  (module_property)
                                                        ▼
                                  muimpl.js  file picker / drag & drop
                                                        │  muapi.loadScoreFile(file)
                                                        ▼
                          MEMFS /mu/temp/<original name>  ──▶  WebApi::loadFromPath()
                                                        │
                        ┌───────────────────────────────┴────────────────────────────┐
                        ▼                                                            ▼
        no score open: IOpenProjectScenario::openProject()   score open: loadProject()
        (regular flow, opens the notation page)              → browser confirm → setProject()
```

Details worth knowing:

- **Single window.** The open scenario's "already open → open a new window" branch is a no-op
  on web (the multiwindows provider is a stub), so a second file used to do nothing. The web
  bridge loads the new file first and only then swaps it in, so a damaged file leaves the
  open score untouched.
- **Unsaved changes** are confirmed by the browser (`onConfirmDiscard`); the native
  "save changes?" dialog is not used because the web shell has no dialog surface.
- **Errors** are reported through `onImportFailed` → a dismissible banner in `viewer.html`.
  The interactive layer answers dialog calls with the default button instead of aborting
  (a malformed MusicXML used to kill the wasm runtime).
- **`.mscx`** is read through `MscReader`'s `DirReader`, which stats the containing directory;
  `MemFileSystem` has no directory entries, hence the `exists()` fix.
- **Names.** `scoreBaseName()` prefers the score title, strips any import suffix from it, and
  falls back to the imported file name — so a `.mid` opens as *grace* and saves as
  `grace.mscz` / exports as `grace.musicxml`, `grace.mid`.
- **Not supported:** MuseScore 4's *uncompressed project folder* (a directory with
  `META-INF/container.xml`) — a browser file input can only upload files, not folders.

---

## 6. SoundFont

Ships **FluidR3Mono_GM.sf3** (23 MB, MIT — FluidR3 → FluidR3Mono lineage) instead of
MuseScore's bundled `MS Basic.sf3` (49 MB). Halves the download and stays free.

- `src/web/appjs/install.js` copies `share/sound/FluidR3Mono_GM.sf3`
- `src/web/appjs/distr/muapi.js` → `DEFAULT_SOUNDFONT`
- Any SF2/SF3 GM bank works; the resolver falls back to the single available bank if a
  score names `MS Basic.sf3`.

---

## 7. Runtime flow (how the pieces talk)

```
viewer.html
 ├─ MuseScoreStudio.wasm  (Qt editor)   ──RPC via MessageChannel──┐
 └─ distr/audiodriver.js  ── AudioWorklet ── MuseAudio.js (engine) ┘
                                        └─ Web Audio → OS default sink
```

- `muapi.startAudioProcessing` needs a **user gesture**.
- RPC payloads are msgpack over `postMessage`; the SoundFont is streamed to the engine
  (≈23 MB) during driver init.

---

## 8. Verification checklist

| Check | Status |
|---|---|
| Editor UI renders in browser | ✅ (bar numbers, palettes, toolbars, theme) |
| Score opens from local bytes and engraves | ✅ "Amazing Grace" |
| Transport starts, playhead advances, score scrolls | ✅ `0:00:23:5`, pause icon, blue playhead |
| Audio callbacks run without exceptions | ✅ (after `HEAPU8` export) |
| Sound actually audible | ✅ (transport + non-silent engine output) |
| New Score wizard | ✅ instrument chooser renders and works |
| Save → browser download | ✅ `success save file: /mu/temp/saved.mscz`, 83 KB round-tripped to JS |
| Export → MusicXML download | ✅ 105 KB `Amazing_Grace.musicxml`, MusicXML 4.0 partwise, 4 parts, 68 measures |
| Export → MIDI download | ✅ 3.2 KB `.mid`, `MThd` format 1, 4 tracks |
| Save / Save as naming | ✅ save → `Amazing_Grace.mscz`; save-as (prompt "My Score") → `My_Score.mscz` |
| Print → PDF + print dialog | ✅ 35,805 B `Amazing_Grace.pdf`, `%PDF-1.4`, 2 pages, opened in the print iframe |
| Text / lyric rendering | ✅ (`Times New Roman → FreeSerif`; `how sweet the sound`, `was lost`) |
| Import MusicXML (`.musicxml`, `.xml`) | ✅ MuseScore 4.7.5 export of "Amazing Grace", 4 parts, lyrics intact |
| Import compressed MusicXML (`.mxl`) | ✅ same score from MS4's `.mxl` |
| Import MIDI (`.mid`) | ✅ 4 tracks, tempo/time signature, lyrics-as-melody, plays back |
| Import MuseScore 4 project (`.mscz`) | ✅ saved by MuseScore 4.7.5 |
| Import uncompressed `.mscx` | ✅ loaded after the `MemFileSystem` directory fix |
| Import replaces the open score | ✅ (browser confirm for unsaved changes, keeps the old score if the new file fails) |
| Unsupported / damaged file | ✅ error banner, app keeps running and keeps the open score |

---

## 9. Known issues / next steps

1. **Save still writes a copy** — Save/Save-as always produce a `SaveCopy` download; the
   in-browser project keeps living at its MEMFS path, so repeated saves don't track a
   "current file" (there is no writable local storage).
2. **Input focus** — clicking the score canvas relies on real pointer events; keyboard
   shortcuts work once the notation view has focus.
3. **Debug hooks** — `WebApi::dispatchCommand()` was added as a test hook (harmless, can be
   removed or gated behind a debug flag).
4. **Performance / memory** — 88 MB WASM + 23 MB SoundFont; consider compressing assets and
   lazy-loading the SoundFont.
5. **Print** — PDF is rendered natively and printed from a hidden iframe; if the browser
   blocks it, the PDF opens in a new tab instead.
6. **Dialogs are log-only on web** — `question`/`info`/`warning`/`error` answer with the
   default button and print the text to the browser console. Import problems reach the user
   through the viewer banner; other messages (e.g. a failing save) only appear in the console.
7. **Import is single-window** — opening a file replaces the score in the current tab. A
   directory-shaped uncompressed project (`.mscx` folder with `META-INF/container.xml`)
   cannot be uploaded, only single files.

### Fixed during development

- Lyric/text glyphs drawing as musical symbols (`Times New Roman` → Bravura fallback).
- SoundFont never being copied into the bundle (`install.js` wrong asset root).
- Every opened file renamed to `current.mscz`, so save/export were always called `saved`/`current`.
- No Save-as prompt and no naming from the score title.
- No print/PDF path on web (`imagesexport` module was disabled).
- Upstream's scratch `Dev` tab (a Qt drag-and-drop demo) shipped in the toolbar; removed along with `DevFrame.qml` and its `.qrc` entry.

---

## 10. Deployment notes

- Static hosting only: `index.html` + `viewer.html`, `*.wasm`, `*.js`, `distr/`, `sound/`.
- Single-threaded build ⇒ **no COOP/COEP headers required** ⇒ GitHub Pages works.
- MIME: ensure `.wasm` is served as `application/wasm`; `.sf3` as a binary type.
- **GPLv3**: the app is a derivative of MuseScore Studio. Publishing the built app requires
  offering the corresponding source (link to your fork) and preserving notices.

---

## 11. Repository layout of this project

This document lives in the working tree (a fork of MuseScore Studio), next to the patches it
describes:

```
MuseScore/
├─ BUILD_PLAN.md                     ← this document
├─ SetupConfigure.cmake              ← app-web config (export/print modules enabled)
├─ src/web/                          ← web app shell, JS bridge, viewer
├─ src/web/audioengine/              ← AudioWorklet engine (MuseAudio.js)
├─ muse/                             ← framework submodule (patched)
├─ muse_deps/                        ← dependencies submodule
└─ muse/build.artifacts/             ← built app (wasm, js, distr/, sound/)

../Musescore Online/                 ← patches repo (this document + screenshots)
├─ patches/                          ← 0001-0003 web build, 0004/0005 score import
└─ screenshots/
   ├─ musescore-in-browser.png       editor UI
   ├─ musescore-score-in-browser.png loaded score
   ├─ playback-running.png           transport playing
   └─ lyrics-fixed.png               correct text rendering
```
