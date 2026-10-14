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
        // Panels the bar opens by click are reachable from binds and scripts
        // too. The capsules register themselves under these names through
        // OverlayManager.registerNamed (see Components/OverlayToggleCapsule).
        function toggleCalendar(): string {
            return Services.OverlayManager.toggleNamed("calendar") ? "ok" : "not-registered";
        }
        function toggleWeather(): string {
            return Services.OverlayManager.toggleNamed("weather") ? "ok" : "not-registered";
        }
        // MPRIS transport of the current player, the same calls the bar's
        // transport buttons make.
        function mediaPlayPause(): void { Services.MusicManager.playPause(); }
        function mediaNext(): void { Services.MusicManager.next(); }
        function mediaPrev(): void { Services.MusicManager.previous(); }
        // Relative volume step (percent, e.g. +5/-5); Audio clamps and rounds.
        function volumeStep(delta: real): void { Services.Audio.changeVolume(delta); }
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
