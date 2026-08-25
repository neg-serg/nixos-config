import QtQuick
import Quickshell
import Quickshell.WindowManager
import Quickshell.Wayland.Toplevel

// Wlr backend for the shell: reads workspace state from ext-workspace-v1
// (mango implements it) and exposes the same interface as HyprlandWatcher.
Scope {
    id: root

    readonly property bool available: true
    property int activeWorkspaceId: -1
    property string activeWorkspaceName: ""
    property string currentSubmap: "" // no keymode IPC on mango yet
    property var binds: [] // no bind IPC on mango
    property var keyboardDevices: []
    property string lastKeyboardDevice: ""
    property string lastKeyboardLayout: ""
    readonly property bool hideUi: false
    readonly property var hyprEnvObject: ""

    signal keyboardLayoutEvent(string deviceName, string layoutName)
    signal focusedMonitorEvent()

    // ext-workspace-v1: workspaces push updates; WindowManager is the
    // quickshell singleton wrapping the protocol.
    function _sync() {
        const ws = WindowManager.windowsets.find(w => w.active === true);
        activeWorkspaceId = ws ? parseInt(ws.id, 10) : -1;
        activeWorkspaceName = ws ? (ws.name || ws.id || "") : "";
        if (ws) root.focusedMonitorEvent();
    }

    Connections {
        target: WindowManager
        function onWindowsetsChanged() { root._sync(); }
    }

    Component.onCompleted: _sync()

    function refreshWorkspace() { _sync(); }
    function refreshBinds() { }
    function refreshDevices() { }
    function refreshFullscreen() { }
}
