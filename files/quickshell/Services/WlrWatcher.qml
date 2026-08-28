import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.WindowManager
import Quickshell.Wayland

// Wlr backend for the shell: workspace state from ext-workspace-v1 and the
// keyboard layout from MangoWM's IPC socket (mango-<pid>.sock in XDG_RUNTIME_DIR).
Scope {
    id: root

    readonly property bool available: true
    property int activeWorkspaceId: -1
    property string activeWorkspaceName: ""
    property string currentSubmap: "" // no keymode IPC on mango yet
    property var binds: [] // no bind IPC on mango
    property var keyboardDevices: []
    property string lastKeyboardDevice: "mango-keyboard"
    property string lastKeyboardLayout: ""
    readonly property bool hideUi: false
    readonly property var hyprEnvObject: ""

    signal keyboardLayoutEvent(string deviceName, string layoutName)
    signal focusedMonitorEvent()

    // --- workspaces (ext-workspace-v1 via quickshell WindowManager) ---
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
    function refreshDevices() { root._askLayout(); }
    function refreshFullscreen() { }

    // --- keyboard layout (MangoWM IPC) ---
    property string foundSocketPath: ""
    property bool ipcConnected: false

    Socket {
        id: mangoSock
        path: root.foundSocketPath
        connected: root.ipcConnected
        parser: SplitParser {
            splitMarker: "\n"
            onRead: (line) => root._onIpcLine(line)
        }
    }

    Connections {
        target: mangoSock
        function onConnectionStateChanged() {
            if (mangoSock.connected) {
                root.ipcConnected = true;
                // Mango IPC serves one command per connection and closes it
                // after a non-watch command, so only register the persistent
                // watch here; it pushes the current layout as its first event.
                root._sendCmd("watch keyboardlayout");
            } else {
                root.ipcConnected = false;
                root.foundSocketPath = "";
            }
        }
    }

    // MangoWM's socket is mango-<pid>.sock (pid unknown), so find it by glob
    // and retry until mango is up (it starts after the panel service).
    Timer {
        id: findTimer
        interval: 2000
        repeat: true
        running: true
        onTriggered: {
            if (!root.ipcConnected) findProc.running = true;
        }
    }

    Process {
        id: findProc
        command: ["sh", "-c", "ls -1 \"$XDG_RUNTIME_DIR\"/mango-*.sock 2>/dev/null | head -1"]
        stdout: SplitParser {
            onRead: (data) => {
                const p = String(data).trim();
                if (p && p !== root.foundSocketPath) {
                    root.foundSocketPath = p;
                    root.ipcConnected = true;
                }
            }
        }
    }

    function _onIpcLine(line) {
        try {
            const obj = JSON.parse(line);
            if (obj && obj.layout) {
                const l = String(obj.layout);
                root.lastKeyboardLayout = l;
                root.keyboardDevices = [{
                    name: "mango-keyboard",
                    identifier: "mango-keyboard",
                    main: true,
                    active_keymap: l
                }];
                root.keyboardLayoutEvent("mango-keyboard", l);
            }
        } catch (e) { /* ignore non-JSON lines */ }
    }

    function _sendCmd(cmd) {
        if (root.ipcConnected) mangoSock.write(cmd + "\n");
    }

    // No-op: "get keyboardlayout" would close the persistent watch
    // connection (mango IPC is one command per connection); the watch stream
    // already delivers the current layout as its first event and on every change.
    function _askLayout() { }

    // Click-to-switch from the bar: route through mango IPC dispatch.
    function switchKeyboardLayout() {
        root._sendCmd("dispatch switch_keyboard_layout");
    }
}
