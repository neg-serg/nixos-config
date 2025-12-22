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
    // Env toggles to triage perf issues
    readonly property bool disableBar: ((Quickshell.env("QS_DISABLE_BAR") || "") === "1")
                                     || ((Quickshell.env("QS_MINIMAL_UI") || "") === "1")

    Component.onCompleted: {
        Quickshell.shell = root;
    }

    // Overview {}
    Loader {
        active: !root.disableBar
        sourceComponent: Bar { id: bar; shell: root; }
    }

    IdleInhibitor { id: idleInhibitor; }
    IPCHandlers { idleInhibitor: idleInhibitor; }

    Connections {
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { Quickshell.inhibitReloadPopup(); }
        target: Quickshell
    }

    Timer {
        id: reloadTimer
        interval: 500
        repeat: false
        onTriggered: Quickshell.reload(true)
    }

    // Volume/mute updates are handled inside Services/Audio

}
