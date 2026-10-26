import QtQuick
import Quickshell.Io
import qs.Notifications
import qs.Services as Services


Item {
    id: root
    property IdleInhibitor idleInhibitor
    IpcHandler {
        target: "globalIPC"
        function toggleIdleInhibitor(): void { root.idleInhibitor.toggle(); }
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
    }
}
