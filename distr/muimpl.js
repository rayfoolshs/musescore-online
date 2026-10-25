import config from "./config.js";
import qtLoad from "./qtloader.js";
import AudioDriver from "./audiodriver.js";

const SCORE_FILETYPES = [
    ".mscz", ".mscx",                     // MuseScore Studio projects (MuseScore 4 and older)
    ".musicxml", ".xml", ".mxl",          // MusicXML (plain and compressed)
    ".mid", ".midi", ".kar",              // MIDI
];

// Callbacks of the host page (viewer.html). Kept here because after qtLoad() the
// Module's own `config` property is Qt's config, not the object passed in by the page.
let hostConfig = {};

function hostCallback(name) {
    return typeof hostConfig[name] === "function" ? hostConfig[name] : null;
}

function setupInternalCallbacks(Module) {

    // Opening a score: the native side asks, the browser owns the file picker.
    Module.onOpenScoreRequested = function() {
        const onRequested = hostCallback("onOpenScoreRequested");
        if (onRequested) {
            onRequested();
            return;
        }
        MuImpl.openScorePicker();
    };

    // The web build is single-window: importing replaces the open score. Native dialogs
    // are not available, so ask here before the score (and its changes) are dropped.
    Module.onConfirmDiscard = function(displayName) {
        return window.confirm(
            "“" + displayName + "” has unsaved changes.\n\n" +
            "Discard them and open the selected file?");
    };

    Module.onImportFailed = function(fileName, message) {
        console.error("[js] import failed: ", fileName, ", ", message);
        const onImportFailed = hostCallback("onImportFailed");
        if (onImportFailed) {
            onImportFailed(fileName, message);
        } else {
            window.alert("Could not import “" + fileName + "”.\n\n" + message);
        }
    };

    // Interactive
    Module.openFileDialog = function(callback) {
        console.log("[js] openFileDialog")
        const input = document.createElement('input');
        input.type = 'file';
        input.onchange = (e) => {
            const file = e.target.files[0];
            const fileName = file.name
            const reader = new FileReader();
            reader.onload = (e) => {
                const contents = e.target.result;
                const uint8View = new Uint8Array(contents);
                console.log("[js] openFileDialog fileName: ", fileName, ", contents: ", uint8View.length, ", [0]=", uint8View[0])
                callback(fileName, uint8View);
            };
            reader.readAsArrayBuffer(file); 
        };
        input.click();
    }
}

function setupRpc(Module)
{
    // Main <=> Worker 
    // port1 - main
    // port2 - worker
    Module.main_worker_rpcChannel = new MessageChannel();

    Module.main_worker_rpcSend = function(data) {
        Module.main_worker_rpcChannel.port1.postMessage(data)
    }

    Module.main_worker_rpcListen = function(data) {} // will be overridden

    Module.main_worker_rpcChannel.port1.onmessage = function(event) {
        Module.main_worker_rpcListen(event.data)
    };

    // Worker <=> Driver (processor)
    // port1 - driver
    // port2 - worker
    Module.driver_worker_rpcChannel = new MessageChannel();
}

async function setupDriver(Module) 
{
    Module.driver = AudioDriver;

    AudioDriver.onInited = function() {
        console.log("driver on inited add sound font")

        if (Module.isNeedStartAudio) {
            Module._startAudioProcessing()
        }

        Module.ccall('addSoundFont', '', ['string'], [Module.soundFont]);
    }

    if (config.MUSE_MODULE_AUDIO_WORKER == "ON") {
        await AudioDriver.setup(Module.config, Module.driver_worker_rpcChannel.port1);
    } else {
        await AudioDriver.setup(Module.config, Module.main_worker_rpcChannel.port2);
    }

}

async function setupWorker(Module)
{
    // Initialize the worker.
    Module.worker = new Worker("distr/audioworker.js")

    var museAudioUrl = new URL("MuseAudio.js", window.location) + "";

    Module.worker.onmessage = function(event) {
        if (event.data.type == "WORKER_INITED") {
            Module.ccall('addSoundFont', '', ['string'], [Module.soundFont]);
        }
    }

    Module.worker.postMessage({
    type: 'INITIALIZE_WORKER',
    mainPort: Module.main_worker_rpcChannel.port2,
    driverPort: Module.driver_worker_rpcChannel.port2,
    options: {
        museAudioUrl: museAudioUrl
    }
    }, [Module.main_worker_rpcChannel.port2, Module.driver_worker_rpcChannel.port2]);
}

const MuImpl = {

    Module: {},

    loadModule: async function(opt) {

        console.info("STEP 0: Begin load main module")

        hostConfig = opt || {};

        this.Module = {
            config: config, // static configuration

            qt: {
                onLoaded: opt.onLoaded,
                onExit: opt.onExit,
                entryFunction: window.MuseScoreStudio_entry, // from MuseScoreStudio.js
                containerElements: [opt.screen],
            },

            soundFont: opt.soundFont,

            // called from cpp
            onStartApp: this._onStartApp.bind(this)
        }

        setupRpc(this.Module);
        console.info("STEP 0.1: End setupRpc")
        setupInternalCallbacks(this.Module);
        console.info("STEP 0.2: End setupInternalCallbacks")

        this.Module = await qtLoad(this.Module);
        console.info("STEP 0.3: End load main module")

        return this.Module;
    },

    _onStartApp: async function() {
        console.info("STEP 1: Begin on onStartApp")
        await setupDriver(this.Module);
        console.info("STEP 1.1: End setupDriver")

        if (config.MUSE_MODULE_AUDIO_WORKER == "ON") {
            await setupWorker(this.Module);
            console.info("STEP 1.2: End setupWorker")
        }
    },

    // Browser file picker for "Open score" (called from the native side).
    openScorePicker: function() {
        const input = document.createElement("input");
        input.type = "file";
        input.accept = SCORE_FILETYPES.join(",");
        input.style.display = "none";

        input.onchange = () => {
            const file = input.files && input.files[0];
            input.remove();

            if (file) {
                MuImpl.loadScoreFile(file);
            }
        };

        document.body.appendChild(input);
        input.click();
    },

    loadScoreFile: async function(file) {
        if (!file) {
            return
        }

        const lowerName = String(file.name || "").toLowerCase();
        const supported = SCORE_FILETYPES.some(suffix => lowerName.endsWith(suffix));
        if (!supported) {
            const message = "Unsupported file type. Use .mscz, .musicxml, .xml, .mxl, .mid, .midi or .kar.";
            console.error("[js] unsupported file: ", file.name);
            const onImportFailed = hostCallback("onImportFailed");
            if (onImportFailed) {
                onImportFailed(file.name, message);
            } else {
                window.alert("Could not import “" + file.name + "”.\n\n" + message);
            }
            return
        }

        const buffer = await file.arrayBuffer();
        this.loadScoreData(new Uint8Array(buffer), file.name)
    },

    loadScoreData: function(data, fileName) {
        const M = this.Module;
        // Keep the original file name: the score title (and therefore the save/export
        // file names) is derived from the project path.
        const safeName = String(fileName || "current.mscz").replace(/[\\/]/g, "_");
        const path = "/mu/temp/" + safeName;

        // Write the file into Emscripten's virtual filesystem. Qt's loader does
        // not expose HEAPU8, so we cannot copy the bytes into wasm memory directly.
        try {
            M.FS.mkdirTree("/mu/temp");
        } catch (e) { /* already exists */ }
        M.FS.writeFile(path, data);

        M.ccall("loadFromPath", null, ["string"], [path]);
    },

    saveScoreAs: function(fileName) {
        this.Module.ccall("saveScoreAs", null, ["string"], [fileName || ""]);
    },

    startAudioProcessing: async function() {
        if (this.Module.driver.inited) {
            this.Module._startAudioProcessing()
        } else {
            console.log("driver not inited, start audio will be later")
            this.Module.isNeedStartAudio = true;
        }
    }
}

export default MuImpl;
