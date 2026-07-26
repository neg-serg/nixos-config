pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Settings
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
Singleton {
    id: root

    // ---- Configuration ----
    readonly property int minVolume: -95
    property int maxVolume: {
        if (!Settings.settings || Settings.settings.genelecMaxVolume === undefined)
            return -35;
        return Settings.settings.genelecMaxVolume;
    }
    onMaxVolumeChanged: {
        // Re-clamp current volume if cap was lowered
        if (volume > maxVolume) {
            setVolume(maxVolume);
        }
    }

    // ---- Runtime state ----
    property int volume: -40 // current dB value
    property int step: 1     // dB per scroll tick (2.5)
    readonly property real displayStep: 2.5
    readonly property int roundedVolume: Math.round(volume / displayStep) * displayStep
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

    function _saveState() {
        if (!StateCache.state) return;
        StateCache.state.genelecVolume = _lastSetVolume;
        StateCache.stateFileView.writeAdapter();
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
        proc.stderr = StderrCollector { waitForEnd: true };
        proc.stdout = StdioCollector {
            waitForEnd: true;
            onStreamFinished: {
                root.busy = false;
                root.available = true;
                root._activeProc = null;
            }
        };
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
        proc.stderr = StderrCollector { waitForEnd: true };
        proc.onFailed = function(code) {
            console.warn("[Genelec] mute failed with code:", code);
        }
        proc.running = true;
    }

    // ---- Startup ----
    Component.onCompleted: {
        volume = _lastSetVolume;
        // Probe availability
        var probe = new Process();
        probe.command = ["genlc", "--help"];
        probe.stderr = StderrCollector { waitForEnd: true };
        probe.stdout = StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.available = true;
            }
        }
        probe.onFailed = function(code) {
            root.available = false;
            console.warn("[Genelec] genlc not available, code:", code);
        }
        probe.running = true;
    }
}
