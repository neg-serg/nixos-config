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
    property bool _expanded: false

    // Click toggles embedded slider visibility
    onClicked: { _expanded = !_expanded; }

    // Expanded slider — inline below the capsule content
    Rectangle {
        id: expandedSlider
        anchors.bottom: parent.top
        anchors.topMargin: -Math.round(Theme.panelMenuItemHeight * 3)
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.round(200 * Theme.scale(Screen))
        height: _expanded ? Math.round(Theme.panelMenuItemHeight * 2.5) : 0
        clip: true
        color: Theme.background
        border.color: Color.withAlpha(Theme.accentPrimary, 0.3)
        border.width: _expanded ? Theme.uiBorderWidth : 0
        radius: 4
        Behavior on height { NumberAnimation { duration: 150 } }

        RowLayout {
            anchors.fill: parent
            anchors.margins: _expanded ? 6 : 0
            spacing: 6
            opacity: _expanded ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 100 } }

            MaterialIcon {
                icon: Services.Genelec.muted ? "volume_off" : "volume_up"
                size: Math.round(Theme.fontSizeSmall * 1.2)
                color: Theme.accentPrimary
            }
            Slider {
                from: 0; to: 1
                value: (Services.Genelec.volume - Services.Genelec.minVolume) / (Services.Genelec.maxVolume - Services.Genelec.minVolume)
                stepSize: 0.01
                Layout.preferredWidth: Math.round(100 * Theme.scale(Screen))
                onMoved: { Services.Genelec.setVolumeDb(Services.Genelec.minVolume + value * (Services.Genelec.maxVolume - Services.Genelec.minVolume)); }
            }
            Text {
                text: Math.abs(Services.Genelec.volume).toFixed(1) + "dB"
                color: Theme.textSecondary
                font.pixelSize: Math.round(Theme.fontSizeSmall * 0.9)
            }
        }
    }

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


    Component.onCompleted: refreshFromService()

    onAtCapChanged: {
        if (atCap) {
            pill.textColor = Theme.panelVolumeHighColor;
        } else {
            pill.textColor = Theme.textPrimary;
        }
    }
}
