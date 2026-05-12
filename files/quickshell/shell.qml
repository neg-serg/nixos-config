pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick
import QtCore
import qs.Bar
import qs.Bar.Modules
import qs.Helpers
import qs.Services

Scope {
    id: root
    readonly property var quickshell: Quickshell
    readonly property alias idleInhibitor: idleInhibitor

    // Env toggles to triage perf issues
    readonly property bool disableBar: ((root.quickshell.env("QS_DISABLE_BAR") || "") === "1")
                                     || ((root.quickshell.env("QS_MINIMAL_UI") || "") === "1")

    Component.onCompleted: {
        root.quickshell.shell = root;
    }

    // Overview {}
    Loader {
        active: !root.disableBar
        sourceComponent: Bar { id: bar; shell: root; }
    }

    IdleInhibitor { id: idleInhibitor; }
    IPCHandlers { idleInhibitor: root.idleInhibitor; }

    Connections {
        function onReloadCompleted() { root.quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { root.quickshell.inhibitReloadPopup(); }
        target: root.quickshell
    }

    Timer {
        id: reloadTimer
        interval: 500
        repeat: false
        onTriggered: root.quickshell.reload(true)
    }
}
