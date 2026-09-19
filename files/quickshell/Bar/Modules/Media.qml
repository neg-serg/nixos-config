import QtQuick
import QtQuick.Layouts
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/Time.js" as Time
import "../../Helpers/Color.js" as Color
import "../../Helpers/AccentSampler.js" as AccentSampler
import "../../Helpers/TooltipText.js" as TooltipText
import qs.Settings
import qs.Services
import qs.Components

Item {
    id: mediaControl
    property var sidePanelPopup: null

    // Clicking the widget opens (or closes) the now-playing panel. Only the track
    // text did this before: the cover — the biggest thing in the capsule, and the
    // part that looks clickable — had no handler at all, so a click there did
    // nothing. Both go through here now.
    function toggleSidePanel() {
        try {
            if (!sidePanelPopup) {
                console.warn("[mediaDebug] sidePanelPopup is null, cannot open");
                return;
            }
            if (sidePanelPopup.visible) sidePanelPopup.hidePopup();
            else sidePanelPopup.showAt();
        } catch (e) { console.warn("[mediaDebug] toggle error", e) }
    }

    // Track + player info on hover.
    readonly property string _tooltipText: (function() {
        var title = MusicManager.trackTitle || "";
        var artist = MusicManager.trackArtist || "";
        var hints = [];
        if (MusicManager.trackAlbum) hints.push("Альбом: " + MusicManager.trackAlbum);
        var q = [];
        if (MusicManager.trackCodec) q.push(String(MusicManager.trackCodec));
        if (MusicManager.trackBitrateStr) q.push(String(MusicManager.trackBitrateStr));
        if (MusicManager.trackSampleRateStr) q.push(String(MusicManager.trackSampleRateStr));
        if (MusicManager.trackBitDepthStr) q.push(String(MusicManager.trackBitDepthStr));
        if (q.length) hints.push("Качество: " + q.join(" · "));
        var player = MusicManager.currentPlayer
            ? String(MusicManager.currentPlayer.service || MusicManager.currentPlayer.name || MusicManager.currentPlayer.identity || "")
            : "";
        if (player) hints.push("Плеер: " + player);
        return TooltipText.compose(title, artist, hints);
    })()
    // Plain "Artist — Title" label. The hidden width measurement (titleMeasure)
    // and the regex-restyled rendered title (trackText.titlePart) must derive
    // from this single expression, or the spectrum is sized against a string
    // that differs from the one displayed.
    readonly property string _trackTitlePlain: (MusicManager.trackArtist || MusicManager.trackTitle)
        ? [MusicManager.trackArtist, MusicManager.trackTitle].filter(function(x) { return !!x; }).join(" — ")
        : ""
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
    readonly property real mediaRowSpacing: Math.max(4, Math.round(Theme.panelWidgetSpacing * mediaControl.capsuleScale * 0.9))
    readonly property real stretchTrackHeightHint: Math.max(mediaControl.musicTextPx * 1.6, Math.round(mediaControl.baseHeight * Math.max(0, Math.min(1, 1 - mediaControl.iconStretchShare))))
    readonly property real compactContentWidth: mediaRow
        ? Math.max(mediaRow.implicitWidth, mediaControl.iconPreferredWidth + mediaControl.mediaRowSpacing + Math.max(trackContainer.implicitWidth, 1))
        : (mediaControl.iconPreferredWidth + Math.max(trackContainer.implicitWidth, 1))
    readonly property real stretchContentWidth: Math.max(trackContainer.implicitWidth + iconOverlayPadding * 2, baseHeight)
    implicitWidth: mediaControl.panelMode
        ? (capsule.horizontalPadding * 2 + mediaControl.baseHeight)
        : ((mediaControl.stretchMode ? mediaControl.stretchContentWidth : mediaControl.compactContentWidth)
            + capsule.horizontalPadding * 2)
    height: capsule.uniformCapsuleHeight
    implicitHeight: height
    visible: Settings.settings.showMediaInBar && MusicManager.hasPlayer && (MusicManager.isPlaying || MusicManager.isPaused)

    property int musicTextPx: Math.round(Theme.fontSizeSmall * capsuleScale)
    // Accent derived from current cover art — centralized in MusicManager
    property color mediaAccent: MusicManager.accentColor
    property string mediaAccentCss: Format.colorCss(mediaAccent, 1)
    // Version bump to force RichText recompute on accent changes
    property int accentVersion: 0
    property bool accentReady: MusicManager.accentReady
    readonly property bool mediaBorderless: Settings.settings.mediaIconBorderless !== false
    onMediaAccentChanged: { accentVersion++; }

    // Bar hover, driven by the right panel's top-level hover tracker in
    // Bar.qml. The media capsule's own WidgetCapsule.hovered is shadowed by
    // that tracker (z:10000), so the panel-level signal is the reliable one.
    property bool panelHovering: false

    // True while the transport strip is riding out next to the capsule: the
    // wedge triangle on the capsule's left edge would be drawn over the strip,
    // so it is dropped for as long as the strip is there.
    property bool transportRevealed: false

    // ── Cover hover ──────────────────────────────────────────────────────
    // Reveals the transport strip next to the capsule. Hover cannot be watched
    // from here: the panel-level tracker in Bar.qml (z: 10000) is the topmost
    // hover-enabled item, so a handler of our own would either never fire or
    // steal hover from it (taking the bar's analyser-on-hover with it). The
    // tracker therefore hands us the cursor position (panelPointerPos) and the
    // cover art rect is tested against it.
    property point panelPointerPos: Qt.point(-1, -1)
    readonly property bool coverHovered: (function() {
        if (!panelHovering || panelPointerPos.x < 0 || panelPointerPos.y < 0) return false;
        if (!albumArtContainer || albumArtContainer.width <= 0) return false;
        var origin = albumArtContainer.mapToItem(mediaControl, 0, 0);
        return panelPointerPos.x >= origin.x && panelPointerPos.x <= origin.x + albumArtContainer.width
            && panelPointerPos.y >= origin.y && panelPointerPos.y <= origin.y + albumArtContainer.height;
    })()

    // ── Small bar analyser: live copy of cava values (in-place mutation won't
    // trigger bindings, so copy on a timer) ──
    property var _barSpec: []
    // Stand-in bound while an analyser is off screen. Feeding a hidden spectrum
    // still updates every bar height (and its SmoothedAnimation), which dirties
    // the window on each cava frame: measured ~9% of a core while music played
    // with the bar not hovered and every analyser hidden.
    readonly property var _emptySpec: []
    // None of these read cavaValues, so they do not re-evaluate ~60x/s.
    readonly property bool _barSpecWanted: Settings.settings.musicPopupSpectrum === true
        && MusicManager.isPlaying
        && mediaControl.panelHovering
    readonly property bool _iphoneSpecWanted: Settings.settings.showIphoneVisualizer === true
        && MusicManager.visualizerAllowed
        && MusicManager.isPlaying
    readonly property bool _linearSpecWanted: Settings.settings.showMediaVisualizer === true
        && MusicManager.visualizerAllowed
        && MusicManager.isPlaying
    Timer {
        id: barSpecTick
        // ~30 Hz sample (was 12.5 Hz).
        interval: 32
        repeat: true
        running: mediaControl._barSpecWanted
        onTriggered: mediaControl._barSpec = (MusicManager.cavaValues || []).slice();
    }

    // ── Accent color sampling (Canvas must live in a windowed component) ──
    property int _accentRetryCount: 0

    function _requestAccentSample() {
        if (!MusicManager.accentNeedsSample()) return;
        _accentRetryCount = 0;
        sampleDebounce.restart();
    }

    Image {
        id: accentSamplerImg
        visible: false
        width: 64; height: 64
        sourceSize.width: 64; sourceSize.height: 64
        fillMode: Image.PreserveAspectCrop
        source: MusicManager.coverUrl || ""
        asynchronous: true
    }

    Canvas {
        id: colorSampler
        width: 64; height: 64
        opacity: 0
        renderStrategy: Canvas.Cooperative
        onPaint: {
            var ctx = getContext("2d");
            if (!accentSamplerImg || accentSamplerImg.status !== Image.Ready) return;
            ctx.clearRect(0, 0, 64, 64);
            ctx.drawImage(accentSamplerImg, 0, 0, 64, 64);
            var imgData = ctx.getImageData(0, 0, 64, 64);
            var url = MusicManager.coverUrl || "";
            var rgb = AccentSampler.sampleAccent(imgData);
            if (!rgb) {
                // First paint may yield empty data; retry once
                accentRetry.restart();
                return;
            }
            MusicManager.accentSetResult(url, rgb);
            accentRetry.stop();
        }
    }

    Timer {
        id: sampleDebounce
        interval: Theme.mediaArtDebounceMs
        repeat: false
        onTriggered: {
            if (accentSamplerImg.status === Image.Ready) {
                colorSampler.requestPaint();
            } else {
                accentRetry.restart();
            }
        }
    }

    Timer {
        id: accentRetry
        interval: Theme.mediaAccentRetryMs
        repeat: true
        onTriggered: {
            mediaControl._accentRetryCount++;
            if (mediaControl._accentRetryCount > Theme.mediaAccentRetryMax) {
                stop();
                MusicManager.accentSetResult(MusicManager.coverUrl || "", null);
                return;
            }
            if (accentSamplerImg.status === Image.Ready) {
                stop();
                colorSampler.requestPaint();
            }
        }
    }

    Connections {
        target: MusicManager
        function onCoverUrlChanged() { mediaControl._requestAccentSample(); }
    }
    Component.onCompleted: { _requestAccentSample(); }

    // Active visualizer profile (if any). Settings are schema-validated, so no clamps here.
    property var _vizProfile: (Settings.settings.visualizerProfiles
                               && Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile])
                              ? Settings.settings.visualizerProfiles[Settings.settings.activeVisualizerProfile]
                              : null

    function _resolveIconPx(settingVal, themeVal, fallback) {
        var s = Number(settingVal);
        if (isFinite(s) && s > 0) return Math.round(s * mediaControl.capsuleScale);
        var t = Number(themeVal);
        if (isFinite(t) && t > 0) return Math.round(t * mediaControl.capsuleScale);
        return fallback;
    }
    PanelTooltip {
        targetItem: capsule
        text: mediaControl._tooltipText
        visibleWhen: capsule.hovered
    }

    WidgetCapsule {
        id: capsule
        paddingScale: 1.5
        anchors.fill: parent
        backgroundKey: "media"
        centerContent: false
        borderVisible: !mediaControl.mediaBorderless
        leftTriangleVisible: !mediaControl.transportRevealed
        triangleHighlightEnabled: true
        triangleHighlightColor: Color.towardsBlack(Color.saturate(Color.towardsBlack(Color.saturate(Theme.accentPrimary, 0.2), 0.3), 0.2), 0.3)
        triangleHighlightWidth: Math.max(2, Math.round(capsule.capsuleScale * 3))
        backgroundColorOverride: mediaControl.mediaBorderless ? Theme.surface : "transparent"
        // Disable vertical padding to allow square cover art in all modes
        verticalPaddingScale: 0
        verticalPaddingMin: 0

        Item {
            id: layoutHost
            anchors.fill: parent

            RowLayout {
                id: mediaRow
                anchors.fill: parent
                spacing: mediaControl.mediaRowSpacing
                visible: !mediaControl.stretchMode && !mediaControl.panelMode
                enabled: visible

                // Small iPhone-style analyser to the left of the album art.
                // Metrics: width = album-art extent (iconPreferredWidth), height =
                // full capsule height so the mirrored bars fill the row — instead
                // of a tiny square that reads as "too short".
                IPhoneSpectrum {
                    id: barMiniSpec
                    Layout.preferredWidth: Math.round(mediaControl.iconPreferredWidth)
                    Layout.minimumWidth: Math.round(mediaControl.iconPreferredWidth)
                    Layout.preferredHeight: Math.round(mediaControl.baseHeight)
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter
                    values: mediaControl._barSpec
                    targetBars: Settings.settings.barAnalyserBars
                    mirror: Settings.settings.barAnalyserMirror
                    // Small preview keeps the classic flat cover-accent look;
                    // the 3D neon treatment stays on the large toast analyser.
                    accentColor: mediaControl.mediaAccent
                    fillOpacity: 0.8
                    barGap: 4
                    minBarWidth: 1
                    glow: false
                    threeD: false
                    animDurationMs: 80
                    opacity: 0.95
                    // Hover-only, gated on the bar panel hover signal.
                    visible: Settings.settings.musicPopupSpectrum && MusicManager.isPlaying
                        && mediaControl.panelHovering
                }

                Item {
                    id: compactIconHost
                    // Force square aspect ratio: use height for both dimensions
                    implicitWidth: mediaControl.baseHeight
                    implicitHeight: mediaControl.baseHeight
                    Layout.preferredWidth: mediaControl.baseHeight
                    Layout.minimumWidth: mediaControl.baseHeight
                    Layout.maximumWidth: mediaControl.baseHeight
                    Layout.fillHeight: true
                    Layout.alignment: Qt.AlignVCenter

                    Item {
                        id: albumArtContainer
                        anchors.fill: parent
                        implicitWidth: mediaControl.iconPreferredWidth
                        implicitHeight: mediaControl.iconPreferredWidth
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                console.warn("[mediaDebug] cover clicked, popup=" + (mediaControl.sidePanelPopup ? "yes" : "null"));
                                mediaControl.toggleSidePanel();
                            }
                        }
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
                    id: iphoneSpectrumHost
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: iphoneSpectrum.visible ? iphoneSpectrum.implicitWidth : 0
                    Layout.fillHeight: true
                    implicitWidth: iphoneSpectrum.visible ? iphoneSpectrum.implicitWidth : 0
                    implicitHeight: mediaControl.baseHeight

                    IPhoneSpectrum {
                        id: iphoneSpectrum
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Settings.settings.showIphoneVisualizer === true
                                 && MusicManager.visualizerAllowed
                                 && MusicManager.isPlaying
                                 && MusicManager.cavaValues.length > 0
                        implicitWidth: Math.round(mediaControl.baseHeight * 1.6)
                        implicitHeight: Math.round(mediaControl.baseHeight * 0.55)
                        height: implicitHeight
                        width: implicitWidth
                        values: mediaControl._iphoneSpecWanted ? MusicManager.cavaValues : mediaControl._emptySpec
                        targetBars: Math.max(12, Math.min(32, Math.round(implicitWidth / 2.5)))
                        accentColor: mediaControl.accentReady ? mediaControl.mediaAccent : Theme.accentPrimary
                        fillOpacity: 0.8
                        barGap: Math.max(1, Math.round(capsuleScale * 1.0))
                        minBarWidth: Math.max(1, Math.round(capsuleScale * 1.5))
                        animDurationMs: 70
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
                                console.warn("[mediaDebug] track clicked, popup=" + (mediaControl.sidePanelPopup ? "yes" : "null") + " popupVisible=" + (mediaControl.sidePanelPopup ? mediaControl.sidePanelPopup.visible : "n/a") + " textLen=" + (trackText.text ? trackText.text.length : 0));
                                mediaControl.toggleSidePanel();
                            }
                            cursorShape: Qt.PointingHandCursor
                        }

                        Text {
                            id: titleMeasure
                            visible: false
                            text: mediaControl._trackTitlePlain
                            font.pixelSize: mediaControl.musicTextPx
                            font.weight: Font.Medium
                        }

                        LinearSpectrum {
                            id: linearSpectrum
                            visible: Settings.settings.showMediaVisualizer === true
                                     && MusicManager.visualizerAllowed
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
                            values: mediaControl._linearSpecWanted ? MusicManager.cavaValues : mediaControl._emptySpec
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
                                property string titlePart: mediaControl._trackTitlePlain
                                property string _accentCss: (mediaControl.mediaAccentCss ? mediaControl.mediaAccentCss : Format.colorCss(Theme.accentPrimary, 1))
                                property bool _accentReady: mediaControl.accentReady
                                property int _accentVer: mediaControl.accentVersion
                                // Cached time strings: re-rendering rich text on every
                                // currentPosition tick (MPRIS/PipeWire churn) fed the
                                // QQuickText::setText crash cascade. Refresh at 1 Hz only.
                                property string _timeCur: ""
                                property string _timeTot: ""
                                Timer {
                                    id: trackTimeTimer
                                    interval: 1000
                                    repeat: true
                                    running: trackText.visible && MusicManager.hasPlayer
                                    triggeredOnStart: true
                                    onTriggered: {
                                        trackText._timeCur = Format.fmtTime(MusicManager.currentPosition || 0);
                                        trackText._timeTot = Format.fmtTime(Time.mprisToMs(MusicManager.trackLength || 0));
                                    }
                                }
                                onTitlePartChanged: trackTimeTimer.restart()
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
                                    const cur = trackText._timeCur;
                                    const tot = trackText._timeTot;
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
                                elide: Text.ElideRight
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
                    // Force square aspect ratio for cover art using explicit baseHeight
                    width: mediaControl.baseHeight
                    height: mediaControl.baseHeight
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
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
