pragma Singleton
import QtQuick
import Quickshell
import qs.Services

// Hyprland keyboard/workspace watcher facade (Hyprland is the desktop).
Scope {
    id: root

    HyprlandWatcherImpl {
        id: watcher
    }

    readonly property var backend: watcher
    readonly property bool available: backend ? backend.available : false
    readonly property int activeWorkspaceId: backend ? backend.activeWorkspaceId : -1
    readonly property string activeWorkspaceName: backend ? backend.activeWorkspaceName : ""
    readonly property string currentSubmap: backend ? backend.currentSubmap : ""
    readonly property var binds: backend ? backend.binds : []
    readonly property var keyboardDevices: backend ? backend.keyboardDevices : []
    readonly property string lastKeyboardDevice: backend ? backend.lastKeyboardDevice : ""
    readonly property string lastKeyboardLayout: backend ? backend.lastKeyboardLayout : ""
    readonly property var hyprEnvObject: backend ? backend.hyprEnvObject : ""

    signal keyboardLayoutEvent(string deviceName, string layoutName)
    signal focusedMonitorEvent()

    Connections {
        target: root.backend
        function onKeyboardLayoutEvent(deviceName, layoutName) { root.keyboardLayoutEvent(deviceName, layoutName); }
        function onFocusedMonitorEvent() { root.focusedMonitorEvent(); }
    }

    function switchKeyboardLayout() { if (backend) backend.switchKeyboardLayout(); }
    function refreshWorkspace() { if (backend) backend.refreshWorkspace(); }
    function refreshBinds() { if (backend) backend.refreshBinds(); }
    function refreshDevices() { if (backend) backend.refreshDevices(); }
}
