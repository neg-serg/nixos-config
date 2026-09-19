import QtQuick
import Quickshell.Io
import qs.Notifications
import qs.Services as Services


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
        // Same path the workspace capsule click uses; handy for binds, scripts
        // and anything else that should not re-implement the hyprctl incantation.
        function toggleOverview(): void { Services.Expo.toggle(); }
        // Per-window glass overrides, same functions the Glass panel's buttons
        // call. spec is a JSON object: {"class":"music","enabled":true,
        // "blurStrength":16,"glassOpacity":0.9,"adaptiveDim":0,"tint":"000000cc"}.
        // Fields left out inherit the global values; tint is RRGGBBAA or "".
        function setGlassWindowOverride(spec: string): string {
            if (!root.glassPanel) return "panel-not-loaded";
            try {
                var parsed = JSON.parse(spec);
                return root.glassPanel.upsertWindowOverride(parsed) ? "ok" : "bad-spec";
            } catch (e) {
                return "bad-json";
            }
        }
        function removeGlassWindowOverride(cls: string): string {
            if (!root.glassPanel) return "panel-not-loaded";
            var list = root.glassPanel.windowOverrides();
            for (var i = 0; i < list.length; i++) {
                if (list[i].class === cls) {
                    root.glassPanel.removeWindowOverride(i);
                    return "ok";
                }
            }
            return "not-found";
        }
        function listGlassWindowOverrides(): string {
            if (!root.glassPanel) return "[]";
            return JSON.stringify(root.glassPanel.windowOverrides());
        }
    }
}
