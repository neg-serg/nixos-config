pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// StateCache: Runtime state that should NOT be committed to git.
// Persists to ~/.cache/quickshell/state.json
Singleton {
    property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/quickshell/"
    property string stateFile: (cacheDir + "state.json")
    property var state: stateAdapter

    Item {
        Component.onCompleted: {
            Quickshell.execDetached(["mkdir", "-p", cacheDir]);
        }
    }

    FileView {
        id: stateFileView
        path: stateFile
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: function() {
            reload()
        }
        onLoadFailed: function(error) {
            stateAdapter = {}
            writeAdapter()
        }
        JsonAdapter {
            id: stateAdapter
            // Runtime state that changes frequently and should not be in git

            // Last active music players (LIFO stack)
            property var lastActivePlayers: []
        }
    }
}
