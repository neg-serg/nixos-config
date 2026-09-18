pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import Quickshell.Io
import qs.Bar
import qs.Helpers
import qs.Notifications

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

    // Now-playing media popup — loaded top-level so its PanelWindow actually
    // maps as an OS surface (a PanelWindow nested inside Bar.qml does not map).
    // Relative path like the working Notifications loaders (absolute file://
    // URLs to Widgets/SidePanel can fail with "No such file or directory").
    Loader {
        id: musicPopupLoader
        source: "Widgets/SidePanel/MusicPopup.qml"
    }
    // Public access for Bar.qml (QML ids don't leak into parent scope, so
    // expose the loaded popup item via an explicit property).
    readonly property var musicPopup: musicPopupLoader ? musicPopupLoader.item : null

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
        source: "file://" + root.quickshell.env("HOME") + "/.config/quickshell/Widgets/ScreenshotToast.qml"
    }

    Connections {
        function onReloadCompleted() { root.quickshell.inhibitReloadPopup(); }
        function onReloadFailed() { root.quickshell.inhibitReloadPopup(); }
        target: root.quickshell
    }

}
