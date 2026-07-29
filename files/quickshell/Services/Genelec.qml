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
    property bool _userInputActive: false  // blocks stateReader overwrite during user interaction
    // ---- Persisted state ----
    property real _lastSetVolume: {
        if (StateCache.state && StateCache.state.genelecVolume !== undefined)
            return StateCache.state.genelecVolume;
        return -40;
    }

    function _saveState() { if (StateCache.state) { StateCache.state.genelecVolume = _lastSetVolume; try { StateCache.stateFileView.writeAdapter(); } catch(e) {} } }

    // ---- Normalized 0..1 for slider ----
    readonly property real sliderPos: (displayDb - minVolume) / (maxVolume - minVolume)
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
        onMoved: { _requestVolume(root.sliderToDb(value)); }
        background: Rectangle {
            x: volSlider.leftPadding; y: volSlider.topPadding + volSlider.availableHeight / 2 - 1
            width: volSlider.availableWidth; height: 1.5; radius: 1
            color: Color.withAlpha(Theme.accentPrimary, 0.12)
            Rectangle {
                width: volSlider.visualPosition * parent.width; height: parent.height; radius: 1
                color: Color.withAlpha(Theme.accentPrimary, volSlider.hovered ? 0.65 : 0.40)
            }
        }

    }
    // Cooldown + debounce: genlc max 1 per 3000ms, waits 2500ms after last input
    property real _lastRequestMs: 0
    property real _lastGenlcMs: 0
    Timer {
        id: commitTimer
        interval: 100; repeat: true; running: true
        onTriggered: {
            var now = Date.now();
            // Clear user-input guard after debounce window
            if (root._userInputActive && now - root._lastRequestMs >= 2500)
                root._userInputActive = false;
            if (root.busy) return;
            if (now - root._lastRequestMs < 2500) return;       // debounce
            if (now - root._lastGenlcMs < 3000) return;         // cooldown
            if (root.pendingDb === root.volume) return;
            root._lastGenlcMs = now;
            root.setVolume(root.pendingDb);
        }
    }
    Text {
        id: volLabel
        text: root.muted ? "MUTED" : "<font color='" + Theme.accentPrimary + "'>-</font>" + Math.abs(root.displayDb).toFixed(1).padStart(4,"0") + "<font color='" + Theme.accentPrimary + "'>dB</font>"
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
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "set-volume", "--volume", dB + "dB"];
        genlcProc.start();
    }
    function _sendMute() {
        if (busy) return;
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "set-mute"];
        genlcProc.start();
    }

    // ---- Unified input pipeline: slider + CLI wheel → throttle → genlc ----
    function _requestVolume(dB) {
        _userInputActive = true;
        root.displayDb = dB;
        root.pendingDb = dB;
        root._lastRequestMs = Date.now();
    }

    // CLI sync — poll state file for external volume changes
    ProcessRunner {
        id: stateReader
        onLine: function(line) {
            if (root.busy || root._userInputActive) return;
            var v = parseFloat(line);
            if (!isNaN(v) && v !== root.displayDb && !volSlider.pressed) {
                root._requestVolume(v);
            }
        }
    }
    Component.onCompleted: {
        volume = _lastSetVolume;
        available = true;
    }

}
