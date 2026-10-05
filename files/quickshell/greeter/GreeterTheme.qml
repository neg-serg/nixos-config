pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads Theme/.theme.json from the user's config directory to synchronize
// greeter colors and timings with the main shell's Theme system.
// Falls back to hardcoded defaults if the file is missing or unreadable.
Singleton {
    id: root

    readonly property bool isLoaded: _data !== null

    // Path to shared theme file
    readonly property string _themePath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME");
        var home = Quickshell.env("HOME");
        var base = xdg ? xdg : (home + "/.config");
        return base + "/quickshell/Theme/.theme.json";
    }

    property var _data: null

    FileView {
        id: themeFileView
        path: root._themePath
        watchChanges: true
        onFileChanged: reload()
        Component.onCompleted: reload()
        onLoadFailed: function() { root._data = null; }
        onAdapterUpdated: {
            try {
                root._data = themeAdapter;
            } catch (e) {
                root._data = null;
            }
        }
        JsonAdapter {
            id: themeAdapter
            property var greeter: ({})
        }
    }

    // Helper to resolve a dotted path from the loaded theme data
    function _val(path, fallback) {
        if (!_data) return fallback;
        try {
            var parts = path.split('.');
            var obj = _data;
            for (var i = 0; i < parts.length; i++) {
                if (obj === undefined || obj === null) return fallback;
                obj = obj[parts[i]];
            }
            return (obj !== undefined && obj !== null) ? obj : fallback;
        } catch (e) {
            return fallback;
        }
    }

    // Color tokens (synced with Theme/greeter.jsonc defaults)
    readonly property color barColor: _val('greeter.barColor', "#30c0ffff")
    readonly property color barOutline: _val('greeter.barOutline', "#50ffffff")
    readonly property color widgetColor: _val('greeter.widgetColor', "#25ceffff")
    readonly property color widgetActiveColor: _val('greeter.widgetActiveColor', "#80ceffff")
    readonly property color widgetOutline: _val('greeter.widgetOutline', "#40ffffff")
    readonly property color widgetOutlineSeparate: _val('greeter.widgetOutlineSeparate', "#20ffffff")
    readonly property color separatorColor: _val('greeter.separatorColor', "#60ffffff")

    // Login card tokens (lock/LockContent.qml)
    readonly property color cardColor: _val('greeter.cardColor', "#8c0f141c")
    readonly property color cardOutline: _val('greeter.cardOutline', "#3dffffff")
    readonly property color accentColor: _val('greeter.accentColor', "#7fd6ff")
    readonly property color dangerColor: _val('greeter.dangerColor', "#ff9b9b")
    readonly property color textColor: _val('greeter.textColor', "#f2f6fa")
    readonly property color textMutedColor: _val('greeter.textMutedColor', "#9db0c2")
    readonly property color avatarColor: _val('greeter.avatarColor', "#3d7fd6ff")

    // Timing tokens
    readonly property int lockAnimationMs: _val('greeter.lockAnimationMs', 500)
    readonly property int slideshowDurationMs: _val('greeter.slideshowDurationMs', 3000)
    readonly property int contextTimerMs: _val('greeter.contextTimerMs', 300)
    readonly property int animFastMs: _val('greeter.animFastMs', 150)
    readonly property int animMediumMs: _val('greeter.animMediumMs', 250)
    readonly property int animSlowMs: _val('greeter.animSlowMs', 500)
    readonly property int appearMs: _val('greeter.appearMs', 420)
}
