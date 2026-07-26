import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Settings
import qs.Components
import "../Helpers/Utils.js" as Utils
import "../Helpers/Color.js" as Color

/*!
 * Genelec — hardware volume control for Genelec SAM monitors via GLM adapter.
 *
 * Key behaviour:
 *  - Volume is dB (negative values, -95 to maxVolume).
 *  - maxVolume defaults to -35 dB. Any attempt to set above is silently clamped.
 *  - To raise the cap: change genelecMaxVolume in Settings.json.
 *  - State (last-set volume) is persisted via StateCache.
 */
RowLayout {
    id: root

    // ---- Configuration ----
    readonly property int minVolume: -95
    property int maxVolume: {
        if (!Settings.settings || Settings.settings.genelecMaxVolume === undefined)
            return -30;
        return Settings.settings.genelecMaxVolume;
    }
    onMaxVolumeChanged: { if (volume > maxVolume) setVolume(maxVolume); }

    // ---- Runtime state ----
    property real volume: -40
    property bool muted: false
    property real preMuteVolume: -40
    property bool available: false
    property bool busy: false

    // ---- Persisted state ----
    property real _lastSetVolume: {
        if (StateCache.state && StateCache.state.genelecVolume !== undefined)
            return StateCache.state.genelecVolume;
        return -40;
    }

    function _saveState() { if (StateCache.state) StateCache.state.genelecVolume = _lastSetVolume; }

    // ---- Normalized 0..1 for slider ----
    readonly property real sliderPos: (volume - minVolume) / (maxVolume - minVolume)
    function sliderToDb(pos) { return +(minVolume + pos * (maxVolume - minVolume)).toFixed(1); }

    // ---- UI ----
    property real pendingDb: -40
    property real displayDb: volume  // instant visual, no debounce
    MaterialIcon {
        id: volIcon
        icon: root.muted || root.volume <= root.minVolume ? "volume_off" : root.volume >= -20 ? "volume_up" : "volume_down"
        size: Math.round(Theme.fontSizeSmall * 1.2); color: root.available ? Theme.accentPrimary : Theme.textDisabled
        Layout.alignment: Qt.AlignVCenter
        MouseArea { anchors.fill: parent; onClicked: root.toggleMute() }
    }
    Slider {
        id: volSlider
        from: 0; to: 1; value: root.sliderPos; stepSize: 0.01
        Layout.preferredWidth: Math.round(46 * Theme.scale(Screen))
        Layout.alignment: Qt.AlignVCenter
        onMoved: { root.pendingDb = root.sliderToDb(value); root.displayDb = root.pendingDb; sliderDebounce.restart(); }
        background: Rectangle {
            x: volSlider.leftPadding; y: volSlider.topPadding + volSlider.availableHeight / 2 - 1
            width: volSlider.availableWidth; height: 1.5; radius: 1
            color: Color.withAlpha(Theme.accentPrimary, 0.12)
            Rectangle {
                width: volSlider.visualPosition * parent.width; height: parent.height; radius: 1
                color: Color.withAlpha(Theme.accentPrimary, volSlider.hovered ? 0.65 : 0.40)
            }
        }
        handle: Item {
            x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - 8) - 4
            y: volSlider.topPadding + volSlider.availableHeight / 2 - 4
            implicitWidth: 8; implicitHeight: 8
            opacity: volSlider.hovered || volSlider.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Rectangle {
                anchors.fill: parent; radius: 4
                color: "#00000000"; border { width: 1; color: Color.withAlpha(Theme.accentPrimary, 0.7) }
            }
            Rectangle {
                anchors.centerIn: parent; width: 5; height: 5; radius: 2.5
                color: Color.withAlpha(Theme.accentPrimary, 0.8)
            }
        }
    }
    Timer { id: sliderDebounce; interval: 2000; repeat: false; onTriggered: { if (root.pendingDb !== undefined && root.pendingDb !== root.volume) root.setVolume(root.pendingDb); } }
    Text {
        id: volLabel
        text: root.muted ? "MUTED" : "<font color='" + Theme.accentPrimary + "'>-</font>" + (Math.abs(root.displayDb) < 10 ? "0" : "") + Math.abs(root.displayDb).toFixed(1).replace(/\.0$/,'') + "<font color='" + Theme.accentPrimary + "'>dB</font>"
        font { family: Theme.fontFamily; pixelSize: Math.round(Theme.fontSizeSmall * 1.05); weight: Font.DemiBold; italic: true }
        color: Theme.textSecondary
        Layout.alignment: Qt.AlignVCenter
    }


    function clamp(v) { return v < minVolume ? minVolume : v > maxVolume ? maxVolume : v; }
    function setVolume(dB) {
        var clamped = clamp(Number(dB));
        if (clamped === volume && !busy) return;
        volume = clamped;
        muted = false;
        _sendToHardware(clamped);
    }

    function setVolumeDb(dB) {
        setVolume(dB);
    }

    function changeVolume(delta) {
        setVolume(volume + (Number(delta) || 0));
    }

    function toggleMute() {
        if (muted) {
            setVolume(preMuteVolume);
            muted = false;
        } else {
            preMuteVolume = volume;
            muted = true;
            _sendMute();
        }
    }

    // ---- Hardware communication ----

    ProcessRunner {
        id: genlcProc
        autoStart: false
        restartOnExit: false
        onStarted: {}
        onExited: function(code, status) {
            root.busy = false;
            root.available = code === 0;
        }
    }

    function _sendToHardware(dB) {
        if (busy) return;
        busy = true;
        _lastSetVolume = dB;
        _saveState();
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "set-volume", "--volume=" + dB + "dB"];
        genlcProc.start();
    }

    function _sendMute() {
        if (busy) return;
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "set-mute"];
        genlcProc.start();
    }

    // ---- Sync with CLI (genlc-media.sh writes /tmp/genlc-volume) ----
    property real _syncedVolume: -40
    property real _cliPendingDb: volume
    Timer {
        id: cliSync
        interval: 10; repeat: true; running: true
        onTriggered: {
            if (root.busy) return;
            try {
                var xhr = new XMLHttpRequest();
                xhr.open("GET", "file:///tmp/genlc-volume", false);
                xhr.send();
                var v = parseFloat(xhr.responseText);
                if (!isNaN(v) && v !== root._syncedVolume) {
                    root._syncedVolume = v;
                    root.displayDb = v;
                    root._cliPendingDb = v;
                    cliDebounce.restart();
                }
            } catch(e) {}
        }
    }
    Timer {
        id: cliDebounce
        interval: 2000; repeat: false
        onTriggered: { if (root._cliPendingDb !== root.volume && !root.busy) root.setVolume(root._cliPendingDb); }
    }

    Component.onCompleted: {
        volume = _lastSetVolume;
        available = true;
    }

}
