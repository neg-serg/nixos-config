import QtQuick
import qs.Settings
import qs.Components
import "." as LocalMods

LocalMods.AudioEndpointTile {
    id: volumeDisplay
    settingsKey: "volume"
    iconOff: "volume_off"
    iconLow: "volume_down"
    iconHigh: "volume_up"
    labelSuffix: "%"
    levelProperty: "volume"
    mutedProperty: "muted"
    changeMethod: "changeVolume"
    toggleOnClick: false
    tooltipTitle: "Volume"
    tooltipHints: [
        "Left click for advanced settings.",
        "Scroll up/down to change volume."
    ]
    enableAdvancedToggle: true

    Item { id: ioSelector; visible: false }
    advancedSelector: ioSelector

}
