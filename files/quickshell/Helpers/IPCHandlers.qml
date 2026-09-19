import QtQuick
import Quickshell.Io
import qs.Notifications


Item {
    id: root
    property IdleInhibitor idleInhibitor
    // The glass panel is created by a Loader in shell.qml; the binding is lazy, so
    // an IPC call made before the shell finished loading simply does nothing.
    property var glassPanel
    IpcHandler {
        target: "globalIPC"
        function toggleIdleInhibitor(): void { root.idleInhibitor.toggle(); }
        function toggleGlassPanel(): void { if (root.glassPanel) root.glassPanel.toggle(); }
        function toggleNotificationCenter(): void {
            NotificationManager.showTrayNotifs = !NotificationManager.showTrayNotifs;
        }
    }
}
