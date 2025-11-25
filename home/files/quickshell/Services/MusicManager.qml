pragma Singleton
import QtQuick
import Quickshell.Services.Mpris
import qs.Services
import qs.Settings
import qs.Components
import "../Helpers/MusicIds.js" as MusicIds
// Settings are schema-validated; avoid runtime clamps

Item {
    id: manager

    // Identify whether a player is MPD-like (mpd/mpdris/mopidy)
    function isPlayerMpd(player) {
        return MusicIds.isPlayerMpd(player || currentPlayer);
    }

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
    property string coverUrl: currentPlayer ? (currentPlayer.trackArtUrl || "") : ""
    property real trackLength:currentPlayer ? currentPlayer.length : 0  // raw from backend
    property bool canPlay:currentPlayer ? currentPlayer.canPlay : false
    property bool canPause:currentPlayer ? currentPlayer.canPause : false
    property bool canGoNext:currentPlayer ? currentPlayer.canGoNext : false
    property bool canGoPrevious:currentPlayer ? currentPlayer.canGoPrevious : false
    property bool canSeek:currentPlayer ? currentPlayer.canSeek : false
    property bool hasPlayer:players.hasPlayer

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
    Cava {
        id: cava
        count: (
            Settings.settings.visualizerProfiles
            && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile]
            && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].cavaBars !== undefined
        ) ? Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].cavaBars
          : Settings.settings.cavaBars
    }
    property alias cavaValues: cava.values
}
