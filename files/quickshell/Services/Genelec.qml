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
    property bool _sliderVisible: false     // auto-hide when idle
    property bool _sliderExpanded: false    // width collapse after opacity
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
    property real _animDb: volume    // smoothly animated display value
    Behavior on _animDb { NumberAnimation { duration: 80 } }

    // Auto-hide slider after inactivity
    Timer {
        id: hideSliderTimer
        interval: 2000
        onTriggered: { root._sliderVisible = false; _hidePhase2.start(); }
    }
    Timer {
        id: _hidePhase2
        interval: 220
        onTriggered: root._sliderExpanded = false
    }
    function _showSlider() {
        _hidePhase2.stop();
        root._sliderVisible = true;
        root._sliderExpanded = true;
        hideSliderTimer.restart();
    }
    MaterialIcon {
        id: volIcon
        icon: root.muted || root.volume <= root.minVolume ? "volume_off" : root.volume >= -20 ? "volume_up" : "volume_down"
        size: Math.round(Theme.fontSizeSmall * 1.2); color: root.available ? Theme.accentPrimary : Theme.textDisabled
        Layout.alignment: Qt.AlignVCenter
        MouseArea { anchors.fill: parent; onClicked: root.toggleMute() }
    }
    Slider {
        id: volSlider
        visible: root._sliderVisible || root._sliderExpanded
        opacity: root._sliderVisible ? 1.0 : 0.0
        Layout.preferredWidth: volSlider.implicitWidth
        from: 0; to: 1; value: root.sliderPos; stepSize: 0.01
        implicitWidth: root._sliderExpanded ? Math.round(46 * Theme.scale(Screen)) : 0
        Behavior on implicitWidth { NumberAnimation { duration: 100 } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Layout.alignment: Qt.AlignVCenter
        onMoved: { _requestVolume(root.sliderToDb(value)); }
        handle: Item {}  // remove default square handle — only scroll wheel used
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
        text: root.muted ? "MUTED" : "<font color='" + Theme.accentPrimary + "'>-</font>" + Math.abs(root._animDb).toFixed(1).padStart(4,"0") + "<font color='" + Theme.accentPrimary + "'>dB</font>"
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
        var newVol = volume + (Number(delta) || 0);
        _requestVolume(newVol);
        setVolume(newVol);
    }

    function toggleMute() {
        root._showSlider();
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
    // CLI sync — poll state file for external volume changes
    ProcessRunner {
        id: stateReader
        cmd: ["/run/current-system/sw/bin/cat", "/tmp/genlc-volume"]
        intervalMs: 150
        autoStart: true
        restartOnExit: false
        onLine: function(line) {
            if (root.busy || root._userInputActive) return;
            var v = parseFloat(line);
            if (!isNaN(v) && v !== root.displayDb && !volSlider.pressed) {
                root._showSlider();
                root.displayDb = v;
                root.pendingDb = v;
                root.volume = v;
                root._animDb = v;
            }
        }
    }
    Component.onCompleted: {
        available = true;
        var f = new XMLHttpRequest();
        f.open("GET", "file:///tmp/genlc-volume", false);
        try { f.send(); } catch (e) {}
        var v = parseFloat(f.responseText);
        volume = isNaN(v) ? _lastSetVolume : v;
        displayDb = volume;
        pendingDb = volume;
        _animDb = volume;
    }

}
