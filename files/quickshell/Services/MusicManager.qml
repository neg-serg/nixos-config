pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import qs.Services
import qs.Settings
import qs.Components
import "../Helpers/MusicIds.js" as MusicIds
// Settings are schema-validated; avoid runtime clamps

Item {
    id: manager

    function isCurrentMpdPlayer() { return MusicIds.isPlayerMpd(currentPlayer); }
    MusicPlayers { id: players }
    MusicPosition { id: position; currentPlayer: players.currentPlayer }
    property alias currentPlayer: players.currentPlayer
    property alias selectedPlayerIndex: players.selectedPlayerIndex
    property alias currentPosition: position.currentPosition

    // Playback state helpers
    property bool isPlaying:currentPlayer ? currentPlayer.isPlaying : false
    property bool isPaused:currentPlayer ? (currentPlayer.playbackState === MprisPlaybackState.Paused) : false
    property bool isStopped:currentPlayer ? (currentPlayer.playbackState === MprisPlaybackState.Stopped) : true
    property string trackTitle: currentPlayer ? (currentPlayer.trackTitle  || "") : ""
    property string trackArtist: currentPlayer ? (currentPlayer.trackArtist || "") : ""
    property string trackAlbum: currentPlayer ? (currentPlayer.trackAlbum  || "") : ""
    property string coverUrl: coverResolver.resolvedCoverUrl || ""
    property real trackLength:currentPlayer ? currentPlayer.length : 0  // raw from backend
    property bool canPlay:currentPlayer ? currentPlayer.canPlay : false
    property bool canPause:currentPlayer ? currentPlayer.canPause : false
    property bool canGoNext:currentPlayer ? currentPlayer.canGoNext : false
    property bool canGoPrevious:currentPlayer ? currentPlayer.canGoPrevious : false
    property bool canSeek:currentPlayer ? currentPlayer.canSeek : false
    property bool hasPlayer:players.hasPlayer

    CoverResolver {
        id: coverResolver
        rawArtUrl: currentPlayer ? (currentPlayer.trackArtUrl || "") : ""
        trackTitle: currentPlayer ? (currentPlayer.trackTitle || "") : ""
        trackArtist: currentPlayer ? (currentPlayer.trackArtist || "") : ""
        currentPlayer: players.currentPlayer
    }
    MusicMeta { id: meta; currentPlayer: players.currentPlayer }
    property alias trackGenre: meta.trackGenre
    property alias trackLabel: meta.trackLabel
    property alias trackYear: meta.trackYear
    property alias trackBitrateStr: meta.trackBitrateStr
    property alias trackSampleRateStr: meta.trackSampleRateStr
    property alias trackDsdRateStr: meta.trackDsdRateStr
    property alias trackCodec: meta.trackCodec
    property alias trackCodecDetail: meta.trackCodecDetail
    property alias trackChannelsStr: meta.trackChannelsStr
    property alias trackBitDepthStr: meta.trackBitDepthStr
    property alias trackNumberStr: meta.trackNumberStr
    property alias trackDiscNumberStr: meta.trackDiscNumberStr
    property alias trackAlbumArtist: meta.trackAlbumArtist
    property alias trackComposer: meta.trackComposer
    property alias trackUrlStr: meta.trackUrlStr
    property alias trackDateStr: meta.trackDateStr
    property alias trackContainer: meta.trackContainer
    property alias trackFileSizeStr: meta.trackFileSizeStr
    property alias trackChannelLayout: meta.trackChannelLayout
    property alias trackQualitySummary: meta.trackQualitySummary
    

    Item { Component.onCompleted: players.updateCurrentPlayer() }
    function getAvailablePlayers() { return players.getAvailablePlayers(); }
    function updateCurrentPlayer() { return players.updateCurrentPlayer(); }

    function playPause() {
        if (!currentPlayer) return;
        if (currentPlayer.isPlaying) currentPlayer.pause(); else currentPlayer.play();
    }
    function play()     { if (currentPlayer && currentPlayer.canPlay)       currentPlayer.play(); }
    function pause()    { if (currentPlayer && currentPlayer.canPause)      currentPlayer.pause(); }
    function stop()     { if (currentPlayer && typeof currentPlayer.stop === "function") currentPlayer.stop(); }
    function next()     { if (currentPlayer && currentPlayer.canGoNext)     currentPlayer.next(); }
    function previous() { if (currentPlayer && currentPlayer.canGoPrevious) currentPlayer.previous(); }

    function seek(posMs) { position.seek(posMs); }

    // Audio spectrum bars (prefer active profile, then settings)
    readonly property bool visualizerAllowed: ((Quickshell.env("QS_DISABLE_VISUALIZER") || "") !== "1")
    Loader {
        id: cavaLoader
        active: manager.visualizerAllowed
        sourceComponent: Cava {
            id: cava
            count: (
                Settings.settings.visualizerProfiles
                && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile]
                && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].cavaBars !== undefined
            ) ? Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].cavaBars
              : Settings.settings.cavaBars
        }
    }
    property var cavaValues: cavaLoader.active && cavaLoader.item ? cavaLoader.item.values : []

    // ── Accent color (shared state, sampled by first consumer in a window) ──
    property color accentColor: Theme.accentPrimary
    property bool accentReady: false
    property string _lastSampledUrl: ""
    property var _accentCache: ({})

    // Called by consumers before sampling — returns true if sampling is needed
    function accentNeedsSample() {
        var url = coverUrl || "";
        if (url === manager._lastSampledUrl) return false;
        // Invalidate stale cache entry when only the cache-buster changed (same base path)
        var oldBase = String(manager._lastSampledUrl || "").replace(/\?t=\d+$/, "");
        var newBase = String(url).replace(/\?t=\d+$/, "");
        if (oldBase && oldBase === newBase && manager._accentCache) {
            delete manager._accentCache[manager._lastSampledUrl];
        }
        manager._lastSampledUrl = url;
        if (!url) {
            manager.accentColor = Theme.accentPrimary;
            manager.accentReady = false;
            return false;
        }
        if (manager._accentCache && manager._accentCache[url]) {
            manager.accentColor = manager._accentCache[url];
            manager.accentReady = true;
            return false;
        }
        manager.accentReady = false;
        return true;
    }

    // Called by the consumer's Canvas after sampling
    function accentSetResult(url, rgb) {
        if (rgb) {
            var col = Qt.rgba(rgb.r / 255.0, rgb.g / 255.0, rgb.b / 255.0, 1);
            manager.accentColor = col;
            manager.accentReady = true;
            if (manager._accentCache) manager._accentCache[url] = col;
        } else {
            var cached = manager._accentCache && manager._accentCache[url];
            var fallback = cached || Theme.accentPrimary;
            manager.accentColor = fallback;
            manager.accentReady = !!cached;
            if (manager._accentCache && !cached) manager._accentCache[url] = fallback;
        }
    }
}
