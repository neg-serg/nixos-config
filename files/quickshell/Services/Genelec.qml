import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Settings
import qs.Components
import "../Helpers/Utils.js" as Utils
import "../../Helpers/Color.js" as Color

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
    property int volume: -40
    property bool muted: false
    property int preMuteVolume: -40
    property bool available: false
    property bool busy: false

    // ---- Persisted state ----
    property int _lastSetVolume: {
        if (StateCache.state && StateCache.state.genelecVolume !== undefined)
            return StateCache.state.genelecVolume;
        return -40;
    }

    function _saveState() { if (StateCache.state) StateCache.state.genelecVolume = _lastSetVolume; }

    // ---- Normalized 0..1 for slider ----
    readonly property real sliderPos: (volume - minVolume) / (maxVolume - minVolume)
    function sliderToDb(pos) { return Math.round(minVolume + pos * (maxVolume - minVolume)); }

    // ---- UI ----
    spacing: 2
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
        Layout.preferredWidth: Math.round(40 * Theme.scale(Screen))
        Layout.alignment: Qt.AlignVCenter
        onMoved: { root.pendingDb = root.sliderToDb(value); debounce.restart(); }

        background: Rectangle {
            x: volSlider.leftPadding; y: volSlider.topPadding + volSlider.availableHeight / 2 - 2
            width: volSlider.availableWidth; height: 1
            radius: 1; color: Color.withAlpha(Theme.accentPrimary, 0.15)
            Rectangle {
                width: volSlider.visualPosition * parent.width; height: parent.height
                radius: 1
                color: Color.withAlpha(Theme.accentPrimary, volSlider.hovered ? 0.6 : 0.35)
                Rectangle {
                    anchors.fill: parent; radius: 1
                    color: "transparent"
                    Rectangle { anchors.fill: parent; radius: 1; color: Color.withAlpha(Theme.accentPrimary, 0.9); opacity: 0.4; layer.enabled: true; layer.effect: FastBlur { radius: 2 } }
                }
            }
        }
        handle: Item {
            x: volSlider.leftPadding + volSlider.visualPosition * (volSlider.availableWidth - 10) - 5
            y: volSlider.topPadding + volSlider.availableHeight / 2 - 5
            implicitWidth: 10; implicitHeight: 10
            opacity: volSlider.hovered || volSlider.pressed ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150 } }
            Rectangle {
                anchors.centerIn: parent; width: 10; height: 10; radius: 5
                color: Color.withAlpha(Theme.accentPrimary, 0.15)
                border { width: 1; color: Color.withAlpha(Theme.accentPrimary, 0.5) }
                Rectangle { anchors.fill: parent; radius: 5; color: Color.withAlpha(Theme.accentPrimary, 0.8); opacity: 0.5; layer.enabled: true; layer.effect: FastBlur { radius: 3 } }
            }
        }
    }
    property real pendingDb: -40
    Timer { id: debounce; interval: 200; repeat: false; onTriggered: { if (root.pendingDb !== undefined) root.setVolume(root.pendingDb); } }
    Text {
        id: volLabel
        text: root.muted ? "MUTED" : root.volume + "dB"
        font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall * 0.95); color: Theme.textSecondary
        Layout.alignment: Qt.AlignVCenter
    }


    function clamp(v) {
        return Utils.clamp(v, minVolume, maxVolume);
    }

    function setVolume(dB) {
        var clamped = clamp(Math.round(dB));
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
    Timer {
        interval: 750; repeat: true; running: true
        onTriggered: {
            if (root.busy) return; // don't fight QML-initiated changes
            try {
                var xhr = new XMLHttpRequest();
                xhr.open("GET", "file:///tmp/genlc-volume", false);
                xhr.send();
                var v = parseInt(xhr.responseText);
                if (!isNaN(v) && v !== root.volume) root.volume = v;
            } catch(e) {}
        }
    }

    // ---- Startup ----
    Component.onCompleted: {
        volume = _lastSetVolume;
        available = true;
    }

}
