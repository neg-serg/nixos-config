pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Settings

Item {
    id: root

    enabled: Settings.settings.wallpaperAccent !== false
    property string currentWallpaperPath: ""
    property bool hasAccent: false

    readonly property string _cachePath: (Quickshell.env("XDG_CACHE_HOME")
        || (Quickshell.env("HOME") + "/.cache")) + "/quickshell-wallpaper-path"

    FileView {
        id: pathFile
        path: root._cachePath
        watchChanges: true
        blockLoading: false
        onLoaded: root._onPathLoaded(text())
        onFileChanged: reload()
        onLoadFailed: root.hasAccent = false
    }

    function _onPathLoaded(raw) {
        if (!root.enabled) return;
        var p = raw.trim();
        if (p.length === 0) { root.hasAccent = false; return; }
        root.currentWallpaperPath = p;
    }
}
