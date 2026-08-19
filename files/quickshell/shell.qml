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

    // Hide the whole shell UI (bar, notifications, toasts) while a fullscreen
    // window (e.g. a game) is active on the focused workspace, so qs never
    // overlaps the game.
    readonly property bool gameFullscreen: HyprlandWatcher.focusedFullscreen

    Component.onCompleted: {
        root.quickshell.shell = root;
    }

    Loader {
        active: !root.disableBar
        sourceComponent: Bar { id: bar; shell: root; visible: !root.gameFullscreen; }
    }
    IdleInhibitor { id: idleInhibitor; }
    IPCHandlers { idleInhibitor: root.idleInhibitor; }

    // ── Notification system (quickshell — replaces dunst) ──────────────

    Loader { source: "Notifications/NotificationOverlay.qml"; visible: !root.gameFullscreen }
    Loader { source: "Notifications/NotificationCenter.qml"; visible: !root.gameFullscreen }

    // IPC semaphores for notification bindings (touch to trigger)
    readonly property string _home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/tmp";
    }


    FileView {
        id: notifCloseAll
        path: root._home + "/.cache/quickshell/notif-close-all"
        watchChanges: true
        onFileChanged: {
            // M4+space: dismiss floating overlays — toasts, screenshot toast,
            // and the notification center.
            NotificationManager.dismissAllActive();
            NotificationManager.showTrayNotifs = false;
            if (screenshotToast.item) screenshotToast.item.hideRequested = true;
            reload();
        }
    }

    // ── Screenshot feedback toast (watches pic-notify trigger file) ──────
    Loader {
        id: screenshotToast
        visible: !root.gameFullscreen
        source: "file://" + root.quickshell.env("HOME") + "/.config/quickshell/Widgets/ScreenshotToast.qml"
    }

    Connections {
        function onReloadCompleted() { root.quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { root.quickshell.inhibitReloadPopup(); }
        target: root.quickshell
    }

}
