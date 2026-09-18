pragma Singleton
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
    property bool busy: false
    // Host GLM path: genlc can reach the GLM adapter on the host (dockur VM off).
    property bool adapterOnHost: true
    // VM GLM path: the adapter is inside the dockur VM, so control goes over
    // the MIDI bridge (glm-midi -> relay :9004 -> VM bridge -> loopMIDI -> GLM).
    readonly property bool midiMode: !adapterOnHost
    // Anchor CC20 once when the MIDI path becomes active (quickshell start
    // with the VM running, or the VM starting later). No periodic re-anchor.
    onMidiModeChanged: { if (midiMode) root._anchorVolume(); }
    // Last result of the host genlc path. available = usable via either path.
    property bool genlcOk: true
    property bool available: adapterOnHost ? genlcOk : true
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
    function sliderToDb(pos) { return Math.round(minVolume + pos * (maxVolume - minVolume)); }

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
        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.toggleMute() }
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
        text: root.muted ? "MUTED" : "<font color='" + Theme.accentPrimary + "'>-</font>" + Math.abs(root.volume).toFixed(0).padStart(3,"0") + "<font color='" + Theme.accentPrimary + "'>dB</font>"
        font { family: Theme.fontFamily; pixelSize: Math.round(Theme.fontSizeSmall * 1.05); weight: Font.DemiBold; italic: true }
        color: Theme.textSecondary
        Layout.alignment: Qt.AlignVCenter
    }


    // Whole dB only: GLM CC20 is integer (dB = value - 127), so clamp rounds.
    function clamp(v) { var c = v < minVolume ? minVolume : v > maxVolume ? maxVolume : v; return Math.round(c); }

    // ---- Hardware send coalescing ----
    // GLM's MIDI input drops or delays messages that arrive in quick
    // succession. Wheel/slider changes update the display instantly but
    // commit the final absolute target once input settles, with
    // >= _minSendGapMs between sends.
    property bool _wheelPending: false
    property real _lastSendMs: 0
    readonly property int _minSendGapMs: 400
    // No relative C21/C22 steps: volume is set only by absolute CC20
    // (anchored once on MIDI activation, then 400 ms after each change).
    Timer {
        id: wheelCommitTimer
        interval: 150
        repeat: false
        onTriggered: {
            if (!root._wheelPending) return;
            if (root.busy) { wheelCommitTimer.start(); return; }
            var wait = root._lastSendMs + root._minSendGapMs - Date.now();
            if (wait > 0) {
                wheelCommitTimer.interval = Math.max(50, wait);
                wheelCommitTimer.start();
                return;
            }
            wheelCommitTimer.interval = 150;
            root._wheelPending = false;
            root._commitAndSend(root.pendingDb);
        }
    }
    // One-shot CC20 anchor: when the MIDI path becomes active, set the
    // absolute target in GLM once. Whole dB only — CC20 is integer.
    // No periodic re-sync: idle volume must not move on its own.
    function _anchorVolume() {
        if (busy || !midiMode) return;
        _sendMidi(["/home/neg/.local/bin/glm-midi", "volume", volume + "dB"]);
    }
    // Self-heal: 400 ms after the last widget commit, re-anchor CC20 once so
    // a dropped relative step is corrected. Not periodic — the timer is only
    // re-armed by a new commit, so idle GLM receives nothing.
    Timer {
        id: selfHealTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (root.busy) { root.selfHealTimer.restart(); return; }
            root._anchorVolume();
        }
    }
    // Confirmation: 2 s after the last commit, send CC20 once more. GLM
    // applies MIDI with a delay, so the repeat guarantees the target lands
    // even if the first anchor was dropped. Re-armed by every commit, never
    // periodic.
    Timer {
        id: confirmTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.busy) { root.confirmTimer.restart(); return; }
            root._anchorVolume();
        }
    }
    // Late confirmation: 8 s after the last commit, send CC20 one final
    // time. Catches slow GLM applies / restarts after the 2 s repeat.
    // One-shot, re-armed by every commit — still never periodic.
    Timer {
        id: lateConfirmTimer
        interval: 8000
        repeat: false
        onTriggered: {
            if (root.busy) { root.lateConfirmTimer.restart(); return; }
            root._anchorVolume();
        }
    }
    function _queueCommit(dB) {
        var target = clamp(Number(dB));
        root.displayDb = target;
        root.pendingDb = target;
        root.volume = target;
        root._wheelPending = true;
        root._userInputActive = true;
        root._lastRequestMs = Date.now();
        wheelCommitTimer.start();
    }
    // The state file genlc, glm-vol, genlc-media, glm-sync and glm-adapter share.
    // It is per-session state, so it belongs in XDG_RUNTIME_DIR (0700, wiped on
    // logout) and not in the fixed, world-writable /tmp path it used to be.
    // XDG_RUNTIME_DIR is always set in a user session; the fallback mirrors what
    // the shell scripts do (`${XDG_RUNTIME_DIR:-/run/user/$(id -u)}`).
    readonly property string _runtimeDir: {
        var dir = Quickshell.env("XDG_RUNTIME_DIR");
        return (dir && dir !== "") ? dir : "/run/user/" + Quickshell.env("UID");
    }
    readonly property string statePath: _runtimeDir + "/genlc-volume"

    function _commitAndSend(dB) {
        var clamped = clamp(Number(dB));
        volume = clamped;
        displayDb = clamped; // keep the slider in sync in midiMode too
        muted = false;
        _lastSendMs = Date.now();
        _sendToHardware(clamped);
        // Persist the target so the state file is never stale after wheel
        // scrolling (the wheel path bypasses genlc-media, the only other
        // writer). The FileView above watches this file; the value equals
        // displayDb, so the reload is a display no-op.
        if (midiMode) {
            // glm-vol owns the state file (path, validation, clamping), so the
            // widget asks it instead of writing the file itself — one definition
            // of where the volume lives, and no shell in the path at all.
            Quickshell.execDetached(["glm-vol", String(clamped)]);
            // Re-arm all one-shot anchors after every commit: CC20 lands
            // 400 ms after input settles (self-heal), again 2 s later
            // (confirmation), and one last time at 8 s (late confirmation).
            // Never periodic.
            selfHealTimer.restart();
            confirmTimer.restart();
            lateConfirmTimer.restart();
        }
    }
    function setVolume(dB) {
        var clamped = clamp(Number(dB));
        if (clamped === volume && !busy) return;
        _commitAndSend(clamped);
    }

    function setVolumeDb(dB) {
        if (midiMode) { _queueCommit(dB); return; }
        setVolume(dB);
    }

    function changeVolume(delta) {
        var d = Number(delta) || 0;
        if (midiMode) {
            // VM-side GLM: update the display immediately per wheel notch,
            // defer the hardware send to wheelCommitTimer so a fast scroll
            // reaches GLM as one final absolute message instead of a burst.
            _queueCommit(volume + d);
            return;
        }
        var newVol = volume + d;
        _requestVolume(newVol);
        setVolume(newVol);
    }

    function _requestVolume(dB) {
        _userInputActive = true;
        root.displayDb = dB;
        root.pendingDb = dB;
        root._lastRequestMs = Date.now();
    }

    function toggleMute() {
        root._showSlider();
        if (midiMode) {
            _sendMidi(["/home/neg/.local/bin/glm-midi", "mute"]);
            muted = !muted;
            return;
        }
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
            root.genlcOk = code === 0;
        }
    }

    function _sendToHardware(dB) {
        if (busy) return;
        if (midiMode) {
            // CC20 only: the one-shot selfHealTimer sends the absolute target
            // 400 ms after the last commit; nothing is sent here directly.
            return;
        }
        busy = true;
        _lastSetVolume = dB;
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "set-volume", "--volume", dB + "dB"];
        genlcProc.start();
    }

    // MIDI bridge path (dockur VM running): one-shot glm-midi invocations.
    ProcessRunner {
        id: midiProc
        autoStart: false
        restartOnExit: false
        onExited: function(code, status) { root.busy = false; }
    }
    function _sendMidi(args) {
        if (busy) return;
        busy = true;
        midiProc.cmd = args;
        midiProc.start();
    }

    // Adapter placement probe: genlc discover succeeds only when the adapter
    // is on the host (VM off). Poll to follow VM start/stop. The interval is
    // deliberately slow: genlc spawn costs ~30 ms of process setup and the
    // VM/adapter state changes on human timescales, not every few seconds.
    ProcessRunner {
        id: probeProc
        autoStart: false
        restartOnExit: false
        onExited: function(code, status) { root.adapterOnHost = code === 0; }
    }
    Timer {
        id: adapterProbeTimer
        interval: 30000
        repeat: true
        running: true
        onTriggered: {
            if (!probeProc.running) {
                probeProc.cmd = ["/run/current-system/sw/bin/genlc", "discover"];
                probeProc.start();
            }
        }
    }

    function _sendMute() {
        if (busy) return;
        if (midiMode) { _sendMidi(["/home/neg/.local/bin/glm-midi", "mute"]); return; }
        busy = true;
        genlcProc.cmd = ["/run/current-system/sw/bin/genlc", "mute"];
        genlcProc.start();
    }
    // CLI sync — watch the state file for external volume changes.
    // genlc rewrites the file in place, so the watcher fires on each write
    // without per-interval subprocesses.
    FileView {
        id: stateReader
        path: root.statePath
        watchChanges: true
        preload: true
        printErrors: false
        property bool _reloadPending: false
        onFileChanged: {
            if (stateReader._reloadPending) return;
            stateReader._reloadPending = true;
            Qt.callLater(function() {
                stateReader._reloadPending = false;
                stateReader.reload();
            });
        }
        onLoaded: function() {
            root._onGenlcFileChanged();
        }
    }
    function _onGenlcFileChanged() {
        // Block only while a wheel debounce is in flight (_wheelPending) — a
        // busy send must NOT drop the keyboard's update: apply the display
        // always and send when free.
        if (root._wheelPending) return;
        var line = stateReader.text() || "";
        var v = parseFloat(line);
        if (!isNaN(v) && v !== root.displayDb && !volSlider.pressed) {
            root._showSlider();
            root.displayDb = v;
            root.pendingDb = v;
            root.volume = v;
            root._animDb = v;
            // Same send path as the wheel: relative C21/C22.
            // genlc-media only writes the target, so keyboard and wheel
            // share one code path through quickshell.
            if (!root.busy) root._commitAndSend(v);
        }
    }
    Component.onCompleted: {
        genlcOk = true;
        // Ensure the state file exists so FileView can watch it (genlc rewrites it in place).
        Quickshell.execDetached(["touch", root.statePath]);
        // Initial adapter probe (the Timer handles the follow-ups).
        probeProc.cmd = ["/run/current-system/sw/bin/genlc", "discover"];
        probeProc.start();
    }

}
