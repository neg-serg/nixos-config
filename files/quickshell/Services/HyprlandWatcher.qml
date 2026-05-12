pragma Singleton
import QtQuick
import Quickshell
import qs.Components
import qs.Settings

Item {
    id: root

    readonly property string hyprSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ("/run/user/" + (Quickshell.env("UID") || ""))
    readonly property string socketPath: (hyprSignature && runtimeDir)
        ? (runtimeDir + "/hypr/" + hyprSignature + "/.socket2.sock")
        : ""
    readonly property bool available: socketPath.length > 0
    readonly property var hyprEnvObject: hyprSignature
        ? ({ "HYPRLAND_INSTANCE_SIGNATURE": hyprSignature })
        : ({})

    property int activeWorkspaceId: -1
    property string activeWorkspaceName: ""
    property string currentSubmap: ""
    property var binds: []
    property var keyboardDevices: []
    property string lastKeyboardDevice: ""
    property string lastKeyboardLayout: ""
    readonly property int restartBackoffMs: (typeof Theme !== "undefined" && Theme.networkRestartBackoffMs !== undefined)
        ? Theme.networkRestartBackoffMs
        : 1500
    readonly property int workspaceDebounceMs: (typeof Theme !== "undefined" && Theme.wsRefreshDebounceMs !== undefined)
        ? Theme.wsRefreshDebounceMs
        : 120

    signal hyprEvent(string eventName, string payload)
    signal keyboardLayoutEvent(string deviceName, string layoutName)
    signal focusedMonitorEvent()

    ProcessRunner {
        id: socketFeed
        cmd: root.available ? ["socat", "-u", "UNIX-CONNECT:" + root.socketPath, "-"] : ["true"]
        autoStart: root.available
        restartMode: "always"
        backoffMs: root.restartBackoffMs
        onLine: line => root._handleSocketLine(line)
    }

    ProcessRunner {
        id: workspaceProbe
        cmd: ["hyprctl", "-j", "activeworkspace"]
        env: root.hyprEnvObject
        parseJson: true
        autoStart: false
        restartMode: "never"
        onJson: obj => {
            try {
                if (typeof obj.id === "number") root.activeWorkspaceId = obj.id;
                if (obj.name !== undefined) root.activeWorkspaceName = obj.name || "";
            } catch (e) { }
        }
    }

    ProcessRunner {
        id: bindsProbe
        cmd: ["hyprctl", "-j", "binds"]
        env: root.hyprEnvObject
        parseJson: true
        autoStart: false
        restartMode: "never"
        onJson: arr => {
            try {
                root.binds = Array.isArray(arr) ? arr : [];
            } catch (e) { }
        }
    }

    ProcessRunner {
        id: devicesProbe
        cmd: ["hyprctl", "-j", "devices"]
        env: root.hyprEnvObject
        parseJson: true
        autoStart: false
        restartMode: "never"
        onJson: obj => {
            try {
                const list = Array.isArray(obj?.keyboards) ? obj.keyboards : [];
                root.keyboardDevices = list;
            } catch (e) { }
        }
    }

    Timer {
        id: workspaceDebounce
        interval: root.workspaceDebounceMs
        repeat: false
        onTriggered: root.refreshWorkspace()
    }

    function refreshWorkspace() {
        if (!root.available) return;
        if (!workspaceProbe.running) workspaceProbe.start();
    }

    function refreshBinds() {
        if (!root.available) return;
        if (!bindsProbe.running) bindsProbe.start();
    }

    function refreshDevices() {
        if (!root.available) return;
        if (!devicesProbe.running) devicesProbe.start();
    }

    function _handleSocketLine(lineRaw) {
        const line = String(lineRaw || "").trim();
        if (!line) return;
        const sep = line.indexOf(">>");
        if (sep <= 0) return;
        const eventName = line.substring(0, sep);
        const payload = line.substring(sep + 2);
        root.hyprEvent(eventName, payload);
        const key = eventName.toLowerCase();
        if (key === "workspacev2") {
            const parts = payload.split(",", 2);
            const idVal = parseInt(parts[0]);
            let name = (parts[1] || "").trim();
            if (name.startsWith("name:")) name = name.substring(5);
            if (!isNaN(idVal)) root.activeWorkspaceId = idVal;
            root.activeWorkspaceName = name || "";
            return;
        }
        if (key === "workspace") {
            const id = parseInt(payload.trim());
            if (!isNaN(id)) root.activeWorkspaceId = id;
            return;
        }
        if (key === "submap" || key === "submapv2") {
            root._updateSubmap(payload.trim());
            return;
        }
        if (key === "focusedmon" || key === "focusedmonv2") {
            root.focusedMonitorEvent();
            workspaceDebounce.restart();
            return;
        }
        if (key === "keyboard-layout"
                || key === "keyboard_layout"
                || key === "activelayout"
                || key === "activelayoutv2") {
            root._handleKeyboardLayout(payload);
            return;
        }
    }

    function _updateSubmap(raw) {
        const name = (!raw || raw === "default" || raw === "reset") ? "" : raw;
        root.currentSubmap = name;
    }

    function _handleKeyboardLayout(payload) {
        const text = String(payload || "");
        const idx = text.indexOf(",");
        if (idx < 0) return;
        const device = text.substring(0, idx);
        const layout = text.substring(idx + 1);
        root.lastKeyboardDevice = device;
        root.lastKeyboardLayout = layout;
        root.keyboardLayoutEvent(device, layout);
    }

    Component.onCompleted: {
        if (root.available) {
            refreshWorkspace();
            refreshBinds();
            refreshDevices();
        }
    }
}
