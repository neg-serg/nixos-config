pragma Singleton
import QtQuick
import Quickshell
import qs.Services

// Session-aware facade over HyprlandWatcherImpl / WlrWatcher.
// The panel keeps using Services.HyprlandWatcher; the backend is chosen by
// QS_SESSION (set to "mango" by start-mango / the mango quickshell service).
Scope {
    id: root

    readonly property bool isMango: Quickshell.env("QS_SESSION") === "mango"

    Component { id: hyprBackend; HyprlandWatcherImpl { } }
    Component { id: wlrBackend; WlrWatcher { } }

    Loader {
        id: backendLoader
        sourceComponent: root.isMango ? wlrBackend : hyprBackend
    }

    readonly property var backend: backendLoader.item
    readonly property bool available: backend ? backend.available : false
    readonly property int activeWorkspaceId: backend ? backend.activeWorkspaceId : -1
    readonly property string activeWorkspaceName: backend ? backend.activeWorkspaceName : ""
    readonly property string currentSubmap: backend ? backend.currentSubmap : ""
    readonly property var binds: backend ? backend.binds : []
    readonly property var keyboardDevices: backend ? backend.keyboardDevices : []
    readonly property string lastKeyboardDevice: backend ? backend.lastKeyboardDevice : ""
    readonly property string lastKeyboardLayout: backend ? backend.lastKeyboardLayout : ""
    readonly property bool hideUi: backend ? backend.hideUi : false
    readonly property var hyprEnvObject: backend ? backend.hyprEnvObject : ""

    signal keyboardLayoutEvent(string deviceName, string layoutName)
    signal focusedMonitorEvent()

    Connections {
        target: root.backend
        function onKeyboardLayoutEvent(deviceName, layoutName) { root.keyboardLayoutEvent(deviceName, layoutName); }
        function onFocusedMonitorEvent() { root.focusedMonitorEvent(); }
    }

    function refreshWorkspace() { if (backend) backend.refreshWorkspace(); }
    function refreshBinds() { if (backend) backend.refreshBinds(); }
    function refreshDevices() { if (backend) backend.refreshDevices(); }
    function refreshFullscreen() { if (backend) backend.refreshFullscreen(); }
}
