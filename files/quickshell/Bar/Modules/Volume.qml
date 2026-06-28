import QtQuick
import qs.Settings
import qs.Components
import qs.Services as Services
import "." as LocalMods

LocalMods.AudioEndpointTile {
    id: volumeDisplay
    settingsKey: "volume"
    iconOff: "volume_off"
    iconLow: "volume_down"
    iconHigh: (Services.Audio && Services.Audio.currentRoute === "phones") ? "headphones" : "volume_up"
    labelSuffix: "%"
    labelText: (Services.Audio && Services.Audio.isProAudioSink) ? (Services.Audio.routeShortLabel || "?") : ""
    levelProperty: "volume"
    mutedProperty: "muted"
    changeMethod: "changeVolume"
    wheelEnabled: !(Services.Audio && Services.Audio.isProAudioSink)
    offReminderStateKey: "audioOffReminderLastShownAt"
    toggleOnClick: false
    tooltipTitle: "Output"
    tooltipValue: (Services.Audio && Services.Audio.isProAudioSink) ? (Services.Audio.routeShortLabel || "?") : ""
    tooltipHints: [
        "Mirror: " + (Services.Audio ? Services.Audio.routeDisplayName : "?"),
        "Left click to toggle AES / Analog.",
        "Scroll changes volume only on non-pro outputs."
    ]
    enableAdvancedToggle: false
    autoHideWhenMuted: true

    Item { id: ioSelector; visible: false }
    advancedSelector: ioSelector

    onClicked: {
        if (Services.Audio) Services.Audio.toggleRoute();
    }
}
