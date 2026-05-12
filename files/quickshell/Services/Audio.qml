pragma Singleton
import QtQuick
import "../Helpers/Utils.js" as Utils
import Quickshell
import Quickshell.Services.Pipewire

// Non-visual helper for centralizing PipeWire audio volume/mute state
Item {
    id: root

    // Expose the default sink and source audio objects
    property var defaultAudioSink: Pipewire.defaultAudioSink
    onDefaultAudioSinkChanged: syncFromSink()
    readonly property var _audio: (defaultAudioSink && defaultAudioSink.audio) ? defaultAudioSink.audio : null

    property var defaultAudioSource: Pipewire.defaultAudioSource
    onDefaultAudioSourceChanged: syncFromSource()
    readonly property var _micAudio: (defaultAudioSource && defaultAudioSource.audio) ? defaultAudioSource.audio : null

    // Public state
    property int volume:0          // 0..100, 0 when muted
    property bool muted: (_audio ? _audio.muted : false)

    property int micVolume: 0      // 0..100, 0 when muted
    property bool micMuted: (_micAudio ? _micAudio.muted : false)

    // Stepping/limits
    property int step: 5

    function roundToStep(v) { return Math.round(v / step) * step }

    function syncFromSink() {
        if (_audio) {
            muted = _audio.muted
            volume = _audio.muted ? 0 : Math.round((_audio.volume || 0) * 100)
        } else {
            muted = false
            volume = 0
        }
    }

    function syncFromSource() {
        if (_micAudio) {
            micMuted = _micAudio.muted
            micVolume = _micAudio.muted ? 0 : Math.round((_micAudio.volume || 0) * 100)
        } else {
            micMuted = false
            micVolume = 0
        }
    }

    // Set absolute volume in percent (0..100), quantized to `step`
    function setVolume(vol) {
        var clamped = Utils.clamp(Math.round(vol), 0, 100)
        var stepped = roundToStep(clamped)
        if (_audio) {
            _audio.volume = stepped / 100.0
            if (_audio.muted && stepped > 0) _audio.muted = false
        }
        volume = stepped
    }

    // Backward-compat alias
    function updateVolume(vol) { setVolume(vol) }

    // Relative change helper
    function changeVolume(delta) { setVolume(volume + (Number(delta) || 0)) }

    function toggleMute() { if (_audio) _audio.muted = !_audio.muted }

    function setMicVolume(vol) {
        var clamped = Utils.clamp(Math.round(vol), 0, 100)
        var stepped = roundToStep(clamped)
        if (_micAudio) {
            _micAudio.volume = stepped / 100.0
            if (_micAudio.muted && stepped > 0) _micAudio.muted = false
        }
        micVolume = stepped
    }

    function updateMicVolume(vol) { setMicVolume(vol) }

    function changeMicVolume(delta) { setMicVolume(micVolume + (Number(delta) || 0)) }

    function toggleMicMute() { if (_micAudio) _micAudio.muted = !_micAudio.muted }

    // Keep in sync with the PipeWire sink
    Connections {
        target: _audio
        function onVolumeChanged() { root.syncFromSink() }
        function onMutedChanged()  { root.syncFromSink() }
    }

    Connections {
        target: _micAudio
        function onVolumeChanged() { root.syncFromSource() }
        function onMutedChanged()  { root.syncFromSource() }
    }

    // Track sink object swap
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    Component.onCompleted: {
        syncFromSink()
        syncFromSource()
    }
}
