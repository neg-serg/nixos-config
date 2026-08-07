pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import Quickshell.Io
import qs.Bar
import qs.Bar.Modules
import qs.Helpers
import qs.Notifications
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

    Loader {
        active: !root.disableBar
        sourceComponent: Bar { id: bar; shell: root; }
    }
    IdleInhibitor { id: idleInhibitor; }
    IPCHandlers { idleInhibitor: root.idleInhibitor; }

    // ── Notification system (quickshell — replaces dunst) ──────────────

    Loader { source: "Notifications/NotificationOverlay.qml" }
    Loader { source: "Notifications/NotificationCenter.qml" }

    // IPC semaphores for notification bindings (touch to trigger)
    readonly property string _home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/tmp";
    }

    FileView {
        id: notifCenterToggle
        path: root._home + "/.cache/quickshell/notif-center-toggle"
        watchChanges: true
        onFileChanged: {
            NotificationManager.openHistory();
            reload();
        }
    }

    FileView {
        id: notifCloseAll
        path: root._home + "/.cache/quickshell/notif-close-all"
        watchChanges: true
        onFileChanged: {
            NotificationManager.dismissAllActive();
            reload();
        }
    }

    // ── Screenshot feedback toast (watches pic-notify trigger file) ──────
    Loader {
        source: "file://" + root.quickshell.env("HOME") + "/.config/quickshell/Widgets/ScreenshotToast.qml"
    }

    Connections {
        function onReloadCompleted() { root.quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { root.quickshell.inhibitReloadPopup(); }
        target: root.quickshell
    }

}
