import QtQuick
import qs.Settings
import qs.Components
import "." as LocalMods

LocalMods.AudioEndpointTile {
    id: micDisplay
    settingsKey: "microphone"
    iconOff: "mic_off"
    iconLow: "mic_none"
    iconHigh: "mic"
    levelProperty: "micVolume"
    mutedProperty: "micMuted"
    changeMethod: "changeMicVolume"
    toggleMethod: "toggleMicMute"
    toggleOnClick: true
    tooltipTitle: "Microphone"
    tooltipHints: [
        "Left click to toggle mute.",
        "Scroll up/down to change level."
    ]
}
