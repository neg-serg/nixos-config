import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Settings
import qs.Components
import "../Helpers/Utils.js" as Utils

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
            return -35;
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

    function _saveState() { if (!StateCache.state) return; StateCache.state.genelecVolume = _lastSetVolume; StateCache.stateFileView.writeAdapter(); }

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
        Layout.preferredWidth: Math.round(80 * Theme.scale(Screen))
        Layout.alignment: Qt.AlignVCenter
        onMoved: root.setVolume(root.sliderToDb(value))
    }
    Text {
        id: volLabel
        text: root.muted ? "MUTED" : root.volume + " dB"
        font.family: Theme.fontFamily; font.pixelSize: Math.round(Theme.fontSizeSmall * 0.85); color: Theme.textSecondary
        Layout.alignment: Qt.AlignVCenter; Layout.preferredWidth: Math.round(48 * Theme.scale(Screen))
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

    property var _activeProc: null

    function _sendToHardware(dB) {
        if (busy && _activeProc) {
            _activeProc.kill();
        }
        busy = true;
        _lastSetVolume = dB;
        _saveState();

        var proc = new Process();
        _activeProc = proc;
        proc.command = ["genlc", "set-volume", "--volume=" + dB + "dB"];
        proc.stderr = null;
        proc.stdout = null;
        proc.onFailed = function(code) {
            root.busy = false;
            root.available = false;
            root._activeProc = null;
            console.warn("[Genelec] genlc failed with code:", code);
        };
        proc.running = true;
    }

    function _sendMute() {
        // Mute by setting to minimum (-95 dB effectively silent)
        var proc = new Process();
        proc.command = ["genlc", "set-volume", "--volume=-95dB"];
        proc.stderr = null;
        proc.onFailed = function(code) {
            console.warn("[Genelec] mute failed with code:", code);
        }
        proc.running = true;
    }

    // ---- Startup ----
    Component.onCompleted: {
        volume = _lastSetVolume;
        available = true;
        console.log("[Genelec] initialized, volume=" + volume + "dB, implicitWidth=" + implicitWidth + ", implicitHeight=" + implicitHeight);
    }
}
