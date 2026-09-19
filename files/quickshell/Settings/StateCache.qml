pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Helpers

// StateCache: Runtime state that should NOT be committed to git.
// Persists to ~/.cache/quickshell/state.json
Singleton {
    property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/"
    property string stateFile: (cacheDir + "state.json")
    property var state: stateAdapter

    // True once state.json has been read (or its absence handled), so consumers can
    // tell the stored values from the -40 defaults the adapter carries before the
    // load lands. The Genelec widget gates its startup restore on this; reading the
    // adapter during Component.onCompleted saw the defaults and pushed -40 dB to the
    // monitors on every restart.
    //
    // Driven by the adapter's own change signal rather than by FileView.loaded or
    // onAdapterUpdated: a preloaded adapter can be `loaded` before it is populated
    // and does not emit onAdapterUpdated at all (measured with a headless probe),
    // while the property change is exactly the moment the stored value becomes
    // readable.
    readonly property bool ready: stateFileView.adapterTouched

    Connections {
        target: stateAdapter
        function onGenelecVolumeChanged() { stateFileView.adapterTouched = true; }
    }

    Item {
        Component.onCompleted: {
            Quickshell.execDetached(["mkdir", "-p", cacheDir]);
        }
    }

    GuardedFileView {
        id: stateFileView
        path: stateFile
        // Flipped by the adapter change signal above (qualified by the id: a
        // singleton cannot reach its own root by name).
        property bool adapterTouched: false
        onLoadFailed: function (error) {
            console.warn("[StateCache] load failed:", error, "— resetting to defaults");
            stateAdapter.lastActivePlayers = [];
            stateAdapter.audioOffReminderLastShownAt = 0;
            stateAdapter.genelecVolume = -40;
            stateAdapter.genelecPreMuteVolume = -40;
            writeAdapter();
        }
        JsonAdapter {
            id: stateAdapter
            // Runtime state that changes frequently and should not be in git

            // Last active music players (LIFO stack)
            property var lastActivePlayers: []
            property double audioOffReminderLastShownAt: 0
            property int genelecVolume: -40 // Last-set Genelec SAM hardware volume (dB)
            // Volume that was active when the widget got muted: without it a
            // restart makes unmute jump back to the hardcoded -40.
            property int genelecPreMuteVolume: -40
        }
    }
}
