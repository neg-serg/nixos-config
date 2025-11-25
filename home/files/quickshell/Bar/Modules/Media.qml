import QtQuick
import "../../Helpers/Utils.js" as Utils
import QtQuick.Controls
import QtQuick.Layouts
// Quickshell.Widgets not needed
import QtQuick.Effects
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/Time.js" as Time
import "../../Helpers/Color.js" as Color
import qs.Settings
import qs.Services
import qs.Components

Item {
    id: mediaControl
    property var sidePanelPopup: null
    readonly property real capsuleScale: capsule.capsuleScale
    readonly property var capsuleMetrics: capsule.capsuleMetrics
    property int baseHeight: Math.max(capsule.capsuleHeight, Math.round(Theme.panelHeight * capsule.capsuleScale))
    readonly property int capsuleInnerSize: capsule.capsuleInner
    property real albumActionIconScale: 0.6
    property string iconLayoutMode: {
        var mode = (Settings.settings.mediaIconStretchMode || Theme.mediaIconMode || "compact");
        return typeof mode === 'string' ? mode : "compact";
    }
    readonly property bool stretchMode: iconLayoutMode === "stretch"
    readonly property bool panelMode: iconLayoutMode === "panel"
    property real iconStretchShare: {
        var settingShare = Number(Settings.settings.mediaIconStretchShare);
        if (isFinite(settingShare) && settingShare >= 0 && settingShare <= 1) return settingShare;
        var themeShare = Number(Theme.mediaIconStretchShare);
        if (isFinite(themeShare) && themeShare >= 0 && themeShare <= 1) return themeShare;
        return 1.0;
    }
    readonly property real iconPreferredWidth: _resolveIconPx(Settings.settings.mediaIconPreferredWidthPx, Theme.mediaIconPreferredWidthPx, mediaControl.baseHeight)
    readonly property real iconMinWidth: Math.min(iconPreferredWidth, _resolveIconPx(Settings.settings.mediaIconMinWidthPx, Theme.mediaIconMinWidthPx, mediaControl.baseHeight))
    readonly property real iconMaxWidth: {
        var v = _resolveIconPx(Settings.settings.mediaIconMaxWidthPx, Theme.mediaIconMaxWidthPx, 0);
        return (v > 0) ? Math.max(v, iconPreferredWidth) : Number.MAX_VALUE;
    }
    readonly property real iconOverlayPadding: Math.max(0, _resolveIconPx(Settings.settings.mediaIconOverlayPaddingPx, Theme.mediaIconOverlayPaddingPx, 0))
    readonly property real panelOverlayPadding: Math.max(0, _resolveIconPx(Settings.settings.mediaIconPanelOverlayPaddingPx, Theme.mediaIconPanelOverlayPaddingPx, iconOverlayPadding))
    readonly property real panelOverlayContentPadding: Math.max(2, Math.round(Theme.panelWidgetSpacing * mediaControl.capsuleScale * 0.4))
    readonly property real panelOverlayWidthShare: (function(){
        var s = Number(Settings.settings.mediaIconPanelOverlayWidthShare);
        if (isFinite(s) && s > 0 && s <= 1) return s;
        var t = Number(Theme.mediaIconPanelOverlayWidthShare);
        if (isFinite(t) && t > 0 && t <= 1) return t;
        return 0.45;
    })()
    readonly property real panelOverlayMaxWidth: Math.max(mediaControl.baseHeight, (layoutHost.width || mediaControl.baseHeight) * mediaControl.panelOverlayWidthShare)
    readonly property real panelOverlayBgOpacity: (function(){
        var s = Number(Settings.settings.mediaIconPanelOverlayBgOpacity);
        if (isFinite(s) && s >= 0 && s <= 1) return s;
        var t = Number(Theme.mediaIconPanelOverlayBgOpacity);
        if (isFinite(t) && t >= 0 && t <= 1) return t;
        return 0.6;
    })()
    readonly property color panelOverlayBgColor: Color.withAlpha(Theme.surface, mediaControl.panelOverlayBgOpacity)
    readonly property real mediaRowSpacing: Math.max(4, Math.round(Theme.panelWidgetSpacing * mediaControl.capsuleScale * 0.6))
    readonly property real stretchTrackHeightHint: Math.max(mediaControl.musicTextPx * 1.6, Math.round(mediaControl.baseHeight * Math.max(0, Math.min(1, 1 - mediaControl.iconStretchShare))))
    readonly property real compactContentWidth: mediaRow
        ? Math.max(mediaRow.implicitWidth, mediaControl.iconPreferredWidth + mediaControl.mediaRowSpacing + Math.max(trackContainer.implicitWidth, 1))
        : (mediaControl.iconPreferredWidth + Math.max(trackContainer.implicitWidth, 1))
    readonly property real stretchContentWidth: Math.max(trackContainer.implicitWidth + iconOverlayPadding * 2, baseHeight)
    implicitWidth: mediaControl.panelMode
        ? (capsule.horizontalPadding * 2 + mediaControl.baseHeight)
        : ((mediaControl.stretchMode ? mediaControl.stretchContentWidth : mediaControl.compactContentWidth)
            + capsule.horizontalPadding * 2)
    height: baseHeight
    implicitHeight: baseHeight
    visible: Settings.settings.showMediaInBar
             && MusicManager.currentPlayer
             && !MusicManager.isStopped
             && (MusicManager.isPlaying
                 || MusicManager.isPaused
                 || (MusicManager.trackTitle && MusicManager.trackTitle.length > 0))

    property int musicTextPx: Math.round(Theme.fontSizeSmall * capsuleScale)
    // Accent derived from current cover art (dominant color)
    property color mediaAccent: Theme.accentPrimary
    property string mediaAccentCss: Format.colorCss(mediaAccent, 1)
    // Cache of computed accents keyed by cover URL to avoid flicker on track changes
    property var _accentCache: ({})
    // Use the same accent for minus and brackets (simplified)
    // Version bump to force RichText recompute on accent changes
    property int accentVersion: 0
    // Accent readiness: hold accent color until palette is ready
    property bool accentReady: false
    readonly property bool mediaBorderless: Settings.settings.mediaIconBorderless !== false
    onMediaAccentChanged: { accentVersion++; }
    Component.onCompleted: { colorSampler.requestPaint(); accentRetry.restart() }
    onVisibleChanged: { if (visible) { colorSampler.requestPaint(); accentRetry.restart() } }
    // When cover/album changes, reuse cached accent (if any) to avoid UI flicker while sampling
    Connections {
        target: MusicManager
        function onCoverUrlChanged() {
            try {
                const url = MusicManager.coverUrl || "";
                if (mediaControl._accentCache && mediaControl._accentCache[url]) {
                    mediaControl.mediaAccent = mediaControl._accentCache[url];
                    mediaControl.accentReady = true;
                } // else keep previous accent/color and readiness until sampler updates
            } catch (e) { /* ignore */ }
            colorSampler.requestPaint();
            accentRetry.restart();
        }
        function onTrackAlbumChanged() {
            try {
                const url = MusicManager.coverUrl || "";
                if (mediaControl._accentCache && mediaControl._accentCache[url]) {
                    mediaControl.mediaAccent = mediaControl._accentCache[url];
                    mediaControl.accentReady = true;
                } // else keep previous accent/color and readiness until sampler updates
            } catch (e) { /* ignore */ }
            colorSampler.requestPaint();
            accentRetry.restart();
        }
    }
    // Retry sampler a few times while UI/cover settles
    property int _accentRetryCount: 0
    // Active visualizer profile (if any). Settings are schema-validated, so no clamps here.
    property var _vizProfile: (Settings.settings.visualizerProfiles
                               && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile])
                              ? Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile]
                              : null
    Timer { id: accentRetry; interval: Theme.mediaAccentRetryMs; repeat: false; onTriggered: { colorSampler.requestPaint(); if (!mediaControl.accentReady && mediaControl._accentRetryCount < Theme.mediaAccentRetryMax) { mediaControl._accentRetryCount++; start() } else { mediaControl._accentRetryCount = 0 } } }

    function _resolveIconPx(settingVal, themeVal, fallback) {
        var s = Number(settingVal);
        if (isFinite(s) && s > 0) return Math.round(s * mediaControl.capsuleScale);
        var t = Number(themeVal);
        if (isFinite(t) && t > 0) return Math.round(t * mediaControl.capsuleScale);
        return fallback;
    }
    WidgetCapsule {
        id: capsule
        anchors.fill: parent
        backgroundKey: "media"
        centerContent: false
        borderVisible: !mediaControl.mediaBorderless
        backgroundColorOverride: mediaControl.mediaBorderless ? Theme.background : "transparent"

        Item {
            id: layoutHost
            anchors.fill: parent

            RowLayout {
                id: mediaRow
                anchors.fill: parent
                spacing: mediaControl.mediaRowSpacing
                visible: !mediaControl.stretchMode && !mediaControl.panelMode
                enabled: visible

                Item {
                    id: compactIconHost
                    implicitWidth: mediaControl.iconPreferredWidth
                    implicitHeight: mediaControl.baseHeight
                    Layout.preferredWidth: mediaControl.iconPreferredWidth
                    Layout.minimumWidth: mediaControl.iconMinWidth
                    Layout.maximumWidth: mediaControl.iconMaxWidth
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter

                    Item {
                        id: albumArtContainer
                        anchors.fill: parent
                        implicitWidth: mediaControl.iconPreferredWidth
                        implicitHeight: mediaControl.iconPreferredWidth
                        readonly property real iconExtent: Math.min(width, height)

                        Rectangle {
                            id: albumArtwork
                            anchors.fill: parent
                            color: mediaControl.mediaBorderless ? Theme.background : Theme.surface
                            border.color: "transparent"
                            border.width: Theme.uiBorderNone
                            clip: true
                            antialiasing: true
                            layer.enabled: true
                            layer.smooth: true
                            layer.samples: 4

                            HiDpiImage {
                                id: cover
                                anchors.fill: parent
                                source: (MusicManager.coverUrl || "")
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                onStatusChanged: {
                                    if (status === Image.Ready) {
                                        colorSampler.requestPaint();
                                        mediaControl._accentRetryCount = 0;
                                        accentRetry.restart();
                                    }
                                }
                                onSourceChanged: {
                                    colorSampler.requestPaint();
                                    mediaControl._accentRetryCount = 0;
                                    accentRetry.restart();
                                }
                            }

                            Canvas {
                                id: colorSampler
                                width: Theme.mediaAccentSamplerPx
                                height: Theme.mediaAccentSamplerPx
                                visible: false
                                onPaint: {
                                    try {
                                        var ctx = getContext('2d');
                                        ctx.clearRect(0, 0, width, height);
                                        var url = MusicManager.coverUrl || "";
                                        if (!cover.visible) {
                                            if (mediaControl._accentCache && mediaControl._accentCache[url]) {
                                                mediaControl.mediaAccent = mediaControl._accentCache[url];
                                                mediaControl.accentReady = true;
                                            }
                                            return;
                                        }
                                        ctx.drawImage(cover, 0, 0, width, height);
                                        var img = ctx.getImageData(0, 0, width, height);
                                        var data = img.data;
                                        var len = data.length;
                                        var rs = 0, gs = 0, bs = 0, n = 0;
                                        for (var i = 0; i < len; i += 4) {
                                            var a = data[i + 3]; if (a < 128) continue;
                                            var r = data[i], g = data[i + 1], b = data[i + 2];
                                            var maxv = Math.max(r, g, b), minv = Math.min(r, g, b);
                                            var sat = maxv - minv; if (sat < 10) continue;
                                            var lum = (r + g + b) / 3; if (lum < 20 || lum > 235) continue;
                                            rs += r; gs += g; bs += b; ++n;
                                        }
                                        if (n === 0) {
                                            rs = 0; gs = 0; bs = 0; n = 0;
                                            for (var j = 0; j < len; j += 4) {
                                                var a2 = data[j + 3]; if (a2 < 128) continue;
                                                var r2 = data[j], g2 = data[j + 1], b2 = data[j + 2];
                                                var max2 = Math.max(r2, g2, b2), min2 = Math.min(r2, g2, b2);
                                                var sat2 = max2 - min2; if (sat2 < 8) continue;
                                                var lum2 = (r2 + g2 + b2) / 3; if (lum2 < 20 || lum2 > 240) continue;
                                                rs += r2; gs += g2; bs += b2; ++n;
                                            }
                                        }
                                        if (n > 0) {
                                            var rr = Math.min(255, Math.round(rs / n));
                                            var gg = Math.min(255, Math.round(gs / n));
                                            var bb = Math.min(255, Math.round(bs / n));
                                            var col = Qt.rgba(rr / 255.0, gg / 255.0, bb / 255.0, 1);
                                            mediaControl.mediaAccent = col;
                                            mediaControl.accentReady = true;
                                            if (mediaControl._accentCache) mediaControl._accentCache[url] = col;
                                        } else {
                                            if (mediaControl._accentCache && mediaControl._accentCache[url]) {
                                                mediaControl.mediaAccent = mediaControl._accentCache[url];
                                                mediaControl.accentReady = true;
                                            } else {
                                                mediaControl.mediaAccent = Theme.accentPrimary;
                                                mediaControl.accentReady = false;
                                            }
                                        }
                                    } catch (e) { /* ignore */ }
                                }
                            }

                            MaterialIcon {
                                id: fallbackIcon
                                anchors.centerIn: parent
                                icon: "music_note"
                                size: Math.max(12, Math.round(albumArtContainer.iconExtent * 0.6))
                                color: Color.withAlpha(Theme.textPrimary, Theme.mediaAlbumArtFallbackOpacity)
                                visible: !cover.visible
                            }

                    Rectangle {
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.overlayWeak
                        visible: (!mediaControl.panelMode) && playButton.containsMouse
                        z: 2

                                Item {
                                    id: albumActionIconBox
                                    anchors.centerIn: parent
                                    width: albumArtContainer.iconExtent
                                    height: albumArtContainer.iconExtent

                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        icon: MusicManager.isPlaying ? "pause" : "play_arrow"
                                        size: Math.max(12, Math.round(albumActionIconBox.height * mediaControl.albumActionIconScale))
                                        color: Theme.onAccent
                                    }
                                }
                            }

                    MouseArea {
                        id: playButton
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: !mediaControl.panelMode
                        enabled: (!mediaControl.panelMode) && (MusicManager.canPlay || MusicManager.canPause)
                        onClicked: MusicManager.playPause()
                    }
                        }
                    }
                }

                Item {
                    id: compactTrackHost
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.max(trackContainer.implicitWidth, 1)

                    Item {
                        id: trackContainer
                        anchors.fill: parent
                        implicitWidth: trackText.implicitWidth
                        implicitHeight: Math.max(mediaControl.musicTextPx * 1.6,
                                                 trackText.implicitHeight
                                                 + (linearSpectrum.visible ? linearSpectrum.height : 0))

                        MouseArea {
                            id: trackSidePanelClick
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton
                            property real _lastMoveTs: 0
                            property bool _armed: false
                            onEntered: {
                                _lastMoveTs = Date.now();
                                _armed = true;
                                hoverOpenTimer.restart();
                            }
                            onExited: {
                                _armed = false;
                                if (hoverOpenTimer.running) hoverOpenTimer.stop();
                            }
                            onPositionChanged: {
                                _lastMoveTs = Date.now();
                                if (!hoverOpenTimer.running) hoverOpenTimer.restart();
                            }
                            Timer {
                                id: hoverOpenTimer
                                interval: Theme.mediaHoverOpenDelayMs
                                repeat: false
                                onTriggered: {
                                    try {
                                        if (!trackSidePanelClick._armed) return;
                                        const stillMs = Date.now() - trackSidePanelClick._lastMoveTs;
                                        if (stillMs < Theme.mediaHoverStillThresholdMs) {
                                            restart();
                                            return;
                                        }
                                        if (mediaControl.sidePanelPopup && trackText.text && trackText.text.length > 0) {
                                            mediaControl.sidePanelPopup.showAt();
                                        }
                                    } catch (e) { /* ignore */ }
                                }
                            }
                            onClicked: {
                                try {
                                    if (mediaControl.sidePanelPopup) {
                                        if (mediaControl.sidePanelPopup.visible) mediaControl.sidePanelPopup.hidePopup();
                                        else mediaControl.sidePanelPopup.showAt();
                                    }
                                } catch (e) { /* ignore */ }
                            }
                            cursorShape: Qt.PointingHandCursor
                        }

                        Text {
                            id: titleMeasure
                            visible: false
                            text: (MusicManager.trackArtist || MusicManager.trackTitle)
                                  ? [MusicManager.trackArtist, MusicManager.trackTitle]
                                        .filter(function(x){ return !!x; })
                                        .join(" — ")
                                  : ""
                            font.family: Theme.fontFamily
                            font.weight: Font.Medium
                            font.pixelSize: Theme.fontSizeSmall * mediaControl.capsuleScale
                        }

                        LinearSpectrum {
                            id: linearSpectrum
                            visible: Settings.settings.showMediaVisualizer === true
                                     && MusicManager.isPlaying
                                     && (trackText.text && trackText.text.length > 0)
                            anchors.left: parent.left
                            anchors.top: textFrame.bottom
                            anchors.topMargin: -Math.round(trackText.font.pixelSize * (
                                ((_vizProfile && _vizProfile.spectrumOverlapFactor !== undefined)
                                    ? _vizProfile.spectrumOverlapFactor
                                    : Settings.settings.spectrumOverlapFactor)
                                + ((_vizProfile && _vizProfile.spectrumVerticalRaise !== undefined)
                                    ? _vizProfile.spectrumVerticalRaise
                                    : Settings.settings.spectrumVerticalRaise)
                            ))
                            height: Math.round(trackText.font.pixelSize * (
                                (_vizProfile && _vizProfile.spectrumHeightFactor !== undefined)
                                    ? _vizProfile.spectrumHeightFactor
                                    : Settings.settings.spectrumHeightFactor))
                            width: Math.ceil(titleMeasure.width)
                            values: MusicManager.cavaValues
                            amplitudeScale: 1.0
                            barGap: (((_vizProfile && _vizProfile.spectrumBarGap !== undefined)
                                       ? _vizProfile.spectrumBarGap
                                       : Settings.settings.spectrumBarGap)) * mediaControl.capsuleScale
                            minBarWidth: 2 * mediaControl.capsuleScale
                            mirror: ((_vizProfile && _vizProfile.spectrumMirror !== undefined) ? _vizProfile.spectrumMirror : Settings.settings.spectrumMirror)
                            drawTop: ((_vizProfile && _vizProfile.showSpectrumTopHalf !== undefined) ? _vizProfile.showSpectrumTopHalf : Settings.settings.showSpectrumTopHalf)
                            drawBottom: true
                            fillOpacity: ((_vizProfile && _vizProfile.spectrumFillOpacity !== undefined)
                                              ? _vizProfile.spectrumFillOpacity
                                              : (Settings.settings.spectrumFillOpacity !== undefined
                                                  ? Settings.settings.spectrumFillOpacity
                                                  : Theme.spectrumFillOpacity))
                            peakOpacity: Theme.spectrumPeakOpacity
                            useGradient: (Settings.settings.visualizerProfiles
                                          && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile]
                                          && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].spectrumUseGradient !== undefined)
                                         ? Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile].spectrumUseGradient
                                         : Settings.settings.spectrumUseGradient
                            barColor: mediaControl.accentReady ? mediaControl.mediaAccent : Theme.borderSubtle
                            z: -1
                        }

                        Item {
                            id: textFrame
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.uiMarginNone
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            clip: true

                            Text {
                                id: trackText
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.RichText
                                renderType: Text.NativeRendering
                                wrapMode: Text.NoWrap
                                property string timeColor: (function(){
                                    var c = MusicManager.isPlaying ? Theme.textPrimary : Theme.textSecondary;
                                    var a = MusicManager.isPlaying ? Theme.mediaTimeAlphaPlaying : Theme.mediaTimeAlphaPaused;
                                    return Format.colorCss(c, a);
                                })()
                                property string titlePart: (MusicManager.trackArtist || MusicManager.trackTitle)
                                    ? [MusicManager.trackArtist, MusicManager.trackTitle].filter(function(x){return !!x;}).join(" - ")
                                    : ""
                                property string _accentCss: (mediaControl.mediaAccentCss ? mediaControl.mediaAccentCss : Format.colorCss(Theme.accentPrimary, 1))
                                property bool _accentReady: mediaControl.accentReady
                                property int _accentVer: mediaControl.accentVersion
                                text: (function(){
                                    if (!trackText.titlePart) return "";
                                    const sepChar = (Settings.settings.mediaTitleSeparator || '—');
                                    let _v = trackText._accentVer;
                                    let t = Rich.esc(trackText.titlePart)
                                               .replace(/\s(?:-|–|—)\s/g, function(){
                                                    return trackText._accentReady
                                                        ? ("&#8201;" + Rich.sepSpan(trackText._accentCss, sepChar) + "&#8201;")
                                                        : ("&#8201;" + Rich.esc(sepChar) + "&#8201;");
                                               });
                                    const cur = Format.fmtTime(MusicManager.currentPosition || 0);
                                    const tot = Format.fmtTime(Time.mprisToMs(MusicManager.trackLength || 0));
                                    const bp = Rich.bracketPair(Settings.settings.timeBracketStyle || "square");
                                    if (trackText._accentReady) {
                                        return t
                                               + " &#8201;" + Rich.bracketSpan(trackText._accentCss, bp.l)
                                               + Rich.timeSpan(trackText.timeColor, cur)
                                               + Rich.sepSpan(trackText._accentCss, '/')
                                               + Rich.timeSpan(trackText.timeColor, tot)
                                               + Rich.bracketSpan(trackText._accentCss, bp.r);
                                    } else {
                                        return t
                                               + " &#8201;" + Rich.esc(bp.l)
                                               + Rich.timeSpan(trackText.timeColor, cur)
                                               + Rich.esc('/')
                                               + Rich.timeSpan(trackText.timeColor, tot)
                                               + Rich.esc(bp.r);
                                    }
                                })()
                                color: Theme.textPrimary
                                font.family: Theme.fontFamily
                                font.weight: Font.Medium
                                font.pixelSize: mediaControl.musicTextPx
                                maximumLineCount: 1
                                z: 2
                            }
                        }
                    }
                }
            }

            Item {
                id: stretchLayout
                anchors.fill: parent
                visible: mediaControl.stretchMode && !mediaControl.panelMode
                enabled: visible
                implicitWidth: mediaControl.stretchContentWidth
                implicitHeight: mediaControl.baseHeight

                Item {
                    id: stretchIconHost
                    anchors.fill: parent
                }

                Item {
                    id: stretchTrackHost
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: mediaControl.iconOverlayPadding
                    implicitHeight: trackContainer.implicitHeight
                    height: Math.max(implicitHeight, mediaControl.stretchTrackHeightHint)
                }
            }

            Item {
                id: panelLayout
                anchors.fill: parent
                visible: mediaControl.panelMode
                enabled: visible

                Item {
                    id: panelIconHost
                    anchors.fill: parent
                }

                Item {
                    id: panelTrackHost
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.margins: mediaControl.panelOverlayPadding
                    readonly property real _maxWidth: Math.max(mediaControl.baseHeight, Math.min(parent.width - mediaControl.panelOverlayPadding * 2, mediaControl.panelOverlayMaxWidth))
                    width: Math.max(mediaControl.baseHeight, Math.min(_maxWidth, trackContainer.implicitWidth + mediaControl.panelOverlayContentPadding * 2))
                    implicitHeight: trackContainer.implicitHeight + mediaControl.panelOverlayContentPadding * 2
                    height: Math.max(implicitHeight, mediaControl.musicTextPx * 1.8)
                    visible: mediaControl.panelMode && trackText.text && trackText.text.length > 0

                    Rectangle {
                        id: panelTrackBackdrop
                        anchors.fill: parent
                        radius: Theme.cornerRadiusSmall
                        color: mediaControl.panelOverlayBgColor
                        border.width: Theme.uiBorderWidth
                        border.color: Color.withAlpha(Theme.textPrimary, 0.08)
                    }

                    Item {
                        id: panelTrackContent
                        anchors.fill: parent
                        anchors.margins: mediaControl.panelOverlayContentPadding
                    }

                    Item {
                        id: panelPlayButtonHost
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Math.max(2, Math.round(mediaControl.panelOverlayContentPadding * (Settings.settings.mediaPanelButtonLargerIcon ? 0.25 : 0.5)))
                        width: Math.min(
                            Math.max(24, mediaControl.musicTextPx * (Settings.settings.mediaPanelButtonLargerIcon ? 1.6 : 1.4)),
                            parent.width * (Settings.settings.mediaPanelButtonLargerIcon ? 0.5 : 0.4)
                        )
                        height: width

                        Rectangle {
                            anchors.fill: parent
                            radius: width / 2
                            color: Settings.settings.mediaPanelButtonBorderless !== false
                                ? Theme.background
                                : Color.withAlpha(mediaControl.mediaAccent, 0.85)
                            border.width: Settings.settings.mediaPanelButtonBorderless !== false ? 0 : Theme.uiBorderWidth
                            border.color: Settings.settings.mediaPanelButtonBorderless !== false
                                ? "transparent"
                                : Color.withAlpha(Theme.textPrimary, 0.12)
                            visible: mediaControl.panelMode
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            icon: MusicManager.isPlaying ? "pause" : "play_arrow"
                            size: Math.round(width * (Settings.settings.mediaPanelButtonLargerIcon ? 0.75 : 0.6))
                            color: Theme.onAccent
                            visible: mediaControl.panelMode
                        }

                        MouseArea {
                            id: panelPlayButton
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: mediaControl.panelMode && (MusicManager.canPlay || MusicManager.canPause)
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: MusicManager.playPause()
                            visible: mediaControl.panelMode
                        }
                    }
                }
            }
        }

        states: [
            State {
                name: "panel"
                when: mediaControl.panelMode
                ParentChange { target: albumArtContainer; parent: panelIconHost }
                ParentChange { target: trackContainer; parent: panelTrackContent }
            },
            State {
                name: "stretch"
                when: mediaControl.stretchMode && !mediaControl.panelMode
                ParentChange { target: albumArtContainer; parent: stretchIconHost }
                ParentChange { target: trackContainer; parent: stretchTrackHost }
            },
            State {
                name: "compact"
                when: !mediaControl.stretchMode && !mediaControl.panelMode
                ParentChange { target: albumArtContainer; parent: compactIconHost }
                ParentChange { target: trackContainer; parent: compactTrackHost }
            }
        ]
    }
}
