import MuImpl from "./muimpl.js"

const DEFAULT_SOUNDFONT = "sound/FluidR3Mono_GM.sf3"

const MuApi = {

    // Load score (mscz/mscx, MusicXML and MIDI are supported)
    loadScoreFile: MuImpl.loadScoreFile,
    loadScoreData: MuImpl.loadScoreData,

    // Open the browser's file picker for a score
    openScorePicker: () => MuImpl.openScorePicker(),

    // Save score with a user-provided file name
    saveScoreAs: MuImpl.saveScoreAs.bind(MuImpl),

    // Start audio
    startAudioProcessing: MuImpl.startAudioProcessing.bind(MuImpl),
}

async function createMuApi(config) {

    if (!config.soundFont) {
        const directoryUrl = new URL('./', window.location.href).toString();
        config.soundFont = directoryUrl + "/" + DEFAULT_SOUNDFONT
    }

    MuApi.Module = await MuImpl.loadModule(config)

    MuApi.Module.onProjectSaved = function(name, data) {
        console.log("[js muapi internal] onProjectSaved: ", name, " len: ", data.length)
        if (config.onProjectSaved) {
            config.onProjectSaved(name, data)
        }
    }

    MuApi.Module.onSaveAsRequested = function(suggestedName) {
        console.log("[js muapi internal] onSaveAsRequested: ", suggestedName)
        if (config.onSaveAsRequested) {
            config.onSaveAsRequested(suggestedName)
        }
    }

    MuApi.Module.onPrintReady = function(name, data) {
        console.log("[js muapi internal] onPrintReady: ", name, " len: ", data.length)
        if (config.onPrintReady) {
            config.onPrintReady(name, data)
        }
    }

    MuApi.Module.onScoreExported = function(name, data) {
        console.log("[js muapi internal] onScoreExported: ", name, " len: ", data.length)
        if (config.onScoreExported) {
            config.onScoreExported(name, data)
        }
    }

    return MuApi
}

export default createMuApi;

