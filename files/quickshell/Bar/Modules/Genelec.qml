import QtQuick
import qs.Settings
import qs.Components
import qs.Services as Services
import "." as LocalMods

/*!
 * Genelec hardware volume widget — controls Genelec SAM monitors via GLM adapter.
 *
 * Displays current dB value. Scroll wheel adjusts by ±displayStep (2.5 dB).
 * Volume is capped at genelecMaxVolume (default -35 dB).
 */
LocalMods.AudioEndpointTile {
    id: root
    settingsKey: "genelec"
    iconOff: "volume_off"
    iconLow: "volume_down"
    iconHigh: "speaker" // Use speaker icon for hardware monitors
    labelSuffix: "dB"
    labelText: ""
    levelProperty: "volume"
    mutedProperty: "muted"
    changeMethod: "changeVolume"
    wheelEnabled: Services.Genelec ? Services.Genelec.available : false
    offReminderStateKey: ""
    toggleOnClick: false
    tooltipTitle: "Genelec SAM"
    tooltipValue: (function() {
        if (!Services.Genelec) return "N/A";
        var v = Services.Genelec.volume;
        return v + " dB" + (Services.Genelec.maxVolume >= -30 ? "" : " (cap " + Services.Genelec.maxVolume + " dB)");
    })()
    tooltipHints: [
        "Hardware volume via GLM adapter.",
        "Cap: " + (Services.Genelec ? Services.Genelec.maxVolume + " dB" : "N/A"),
        "Raise cap: set genelecMaxVolume in Settings.json",
        "Scroll: ±2.5 dB"
    ]
    enableAdvancedToggle: false
    autoHideWhenMuted: false

    // Override level display to show dB instead of percentage
    function refreshFromService() {
        if (!Services.Genelec) return;
        const srv = Services.Genelec;
        // Map dB range to 0-100 for the capsule display
        var normalized = ((srv.volume - srv.minVolume) / (srv.maxVolume - srv.minVolume)) * 100;
        root.updateFrom(Math.max(0, normalized), srv.muted);
        // Update the label to show actual dB
        pill.text = srv.volume + " dB";
    }

    function _serviceStep() {
        // Override: Genelec uses dB steps, not percentage
        // Convert our scroll direction to dB delta
        return 2.5;
    }

    function invokeChange(direction) {
        if (!Services.Genelec || !Services.Genelec.available) return;
        Services.Genelec.changeVolume(direction > 0 ? _serviceStep() : -_serviceStep());
    }

    function _maybeHandle(prop) {
        if (prop === "volume" || prop === "muted" || prop === "maxVolume" || prop === "available") {
            refreshFromService();
        }
    }

    // Show cap indicator on the label
    readonly property bool atCap: Services.Genelec ? Services.Genelec.volume >= Services.Genelec.maxVolume : false

    Connections {
        target: Services.Genelec
        function onVolumeChanged() { root._maybeHandle("volume"); }
        function onMutedChanged() { root._maybeHandle("muted"); }
        function onMaxVolumeChanged() { root._maybeHandle("maxVolume"); }
        function onAvailableChanged() { root._maybeHandle("available"); }
    }

    Connections {
        target: root
        function onWheelStep(direction) { root.invokeChange(direction); }
    }

    Component.onCompleted: refreshFromService()

    onAtCapChanged: {
        if (atCap) {
            pill.textColor = Theme.panelVolumeHighColor;
        } else {
            pill.textColor = Theme.textPrimary;
        }
    }
}
