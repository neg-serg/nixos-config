import QtQuick
import Quickshell.Io

// FileView pre-wired with the reload/write echo guard shared by the persisted
// singletons (Settings, StateCache, PillTracker). Consumers set `path`, declare
// their own JsonAdapter child and may override `onLoadFailed`.
//
// The guard prevents a reload applying file changes from being written straight
// back to disk, which would trigger onFileChanged -> reload -> onAdapterUpdated
// and loop forever.
FileView {
    id: root

    watchChanges: true

    // Read the file before Component.onCompleted: the persisted singletons
    // (StateCache, Settings) are consulted from other components' startup code,
    // and without this the adapter still holds its defaults at that moment —
    // which is how the Genelec widget managed to restore -40 instead of the
    // volume actually stored in ~/.cache/quickshell/state.json.
    preload: true

    property bool _reloadPending: false
    property bool _loading: false

    onFileChanged: {
        if (!root._reloadPending) {
            root._reloadPending = true;
            Qt.callLater(function () {
                root._reloadPending = false;
                root._reload();
            });
        }
    }

    onAdapterUpdated: {
        // A reload applying file changes must not write back to the file
        // (that would trigger onFileChanged -> reload -> onAdapterUpdated loop).
        if (root._loading) {
            root._loading = false;
            return;
        }
        root.writeAdapter();
    }

    Component.onCompleted: function () {
        root._reload();
        root._onReady();
    }

    // Wrap reload() so adapter updates caused by it are not echoed back to disk.
    function _reload() {
        root._loading = true;
        root.reload();
    }

    // Subclasses may override to run extra setup after the initial reload.
    function _onReady() {}
}
