import QtQuick
import Quickshell.Io
import qs.Notifications


Item {
    id: root
    property IdleInhibitor idleInhibitor
    IpcHandler {
        target: "globalIPC"
        function toggleIdleInhibitor(): void { root.idleInhibitor.toggle(); }
        function toggleNotificationCenter(): void {
            NotificationManager.showTrayNotifs = !NotificationManager.showTrayNotifs;
        }
    }
}
