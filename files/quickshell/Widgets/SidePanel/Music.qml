import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window
import qs.Settings
import qs.Components
import qs.Services
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format
import "../../Helpers/Time.js" as Time
import "../../Helpers/RichText.js" as Rich
import "." as MusicWidgets

Rectangle {
    id: musicCard
    // Use attached Window.window when available; fallback to Screen
    property var screen: (Window.window && Window.window.screen) ? Window.window.screen : Screen
    color: "transparent"
    implicitWidth: playerUI.implicitWidth + Math.round(Theme.sidePanelSpacingMedium * Theme.scale(screen))
    implicitHeight: playerUI.implicitHeight
    // Whether this card is really on screen. The popup stays loaded while hidden
    // and its local `visible` bindings are still true, so the analyser feed is
    // gated on this: pushing cava frames into a hidden spectrum re-animates every
    // bar and dirties the window on each frame.
    //
    // (Named isOnScreen, not onScreen: QML reads an `on<Capital>` name as a signal
    // handler, so assigning to it from the host fails with "Cannot assign a value
    // to a signal".)
    //
    // It used to ask `Window.window.visible`, which is null here — the card lives
    // inside a top-level PanelWindow (shell.qml loads MusicPopup there so its
    // surface actually maps), and the attached `Window` property resolves for
    // items inside a window while a PanelWindow *is* the window. The condition
    // was therefore always false and the panel's spectrum never received a frame
    // (values stayed [] while cava streamed into MusicManager.cavaValues). The
    // host that owns the surface says whether it is shown.
    property bool isOnScreen: false

    // ── Colored "(current/total)" readout ────────────────────────────────
    // Composed exactly like the bar capsule's time span (accent brackets and
    // slash, digits in the card's text colour). The strings are cached and
    // refreshed at 1 Hz for the same reason the bar caches them: re-rendering
    // rich text on every currentPosition tick fed the QQuickText::setText
    // crash cascade.
    property string _timeCur: ""
    property string _timeTot: ""
    Timer {
        id: playerTimeTimer
        interval: 1000
        repeat: true
        running: musicCard.isOnScreen && MusicManager.hasPlayer
        triggeredOnStart: true
        onTriggered: {
            musicCard._timeCur = Format.fmtTime(Math.max(0, MusicManager.currentPosition || 0));
            musicCard._timeTot = Format.fmtTime(Math.max(0, Time.mprisToMs(MusicManager.trackLength || 0)));
        }
    }
    readonly property string timeReadout: {
        var bp = Rich.bracketPair(Settings.settings.timeBracketStyle || "square");
        var accent = Format.colorCss(MusicManager.accentColor, 1);
        var digits = Format.colorCss(playerUI.musicTextColor, 1);
        return Rich.bracketSpan(accent, bp.l)
             + Rich.timeSpan(digits, musicCard._timeCur)
             + Rich.sepSpan(accent, "/")
             + Rich.timeSpan(digits, musicCard._timeTot)
             + Rich.bracketSpan(accent, bp.r);
    }

    function warnContrast(bg, fg, label) {
        try {
            if (!(Settings.settings && Settings.settings.debugLogs)) return;
            var ratio = Color.contrastRatio(bg, fg);
            var th = (Settings.settings && Settings.settings.contrastWarnRatio) ? Settings.settings.contrastWarnRatio : 4.5;
            if (ratio < th) console.debug('[Music] Low contrast', label || 'text', ratio.toFixed(2));
        } catch (e) { console.warn("[Music.warnContrast]", e) }
    }

        Rectangle {
            id: card
            anchors.fill: parent
            // Frameless card (user preference): a slightly higher fill opacity
            // keeps it legible over dark backgrounds without a visible border.
            color: Color.withAlpha("#000000", 0.92)
            border.color: "transparent"
            border.width: Theme.uiBorderNone
            radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen))

        Item {
            width: parent.width
            height: parent.height
            visible: !MusicManager.currentPlayer

            ColumnLayout {
                anchors.centerIn: parent
                spacing: Math.round(Theme.sidePanelSpacing * 1.33 * Theme.scale(screen))

                Text {
                    text: "music_note"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: Theme.fontSizeHeader * Theme.scale(screen)
                    color: Theme.textOn(card.color, Theme.textSecondary, Theme.textPrimary)
                    Layout.alignment: Qt.AlignHCenter
                    Component.onCompleted: musicCard.warnContrast(card.color, color, 'fallbackIcon')
                }

                Text {
                    text: MusicManager.hasPlayer ? "No controllable player selected" : "No music player detected"
                    color: playerUI.musicTextColor
                    font.family: Theme.fontFamily
                    font.pixelSize: playerUI.musicTextPx
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        ColumnLayout {
            id: playerUI
            // Pin the content to the bottom of the card so the cover sits right
            // on top of the panel; only the natural empty card space stays above.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
            visible: !!MusicManager.currentPlayer

            // Typography (toast body text: ~25% smaller than the bar default)
            property int musicFontPx: Math.round(Theme.fontSizeSmall * Theme.scale(screen) * 0.75)
            property int musicTextPx: Math.round(Theme.fontSizeSmall * Theme.scale(screen) * 0.75)
            property color musicTextColor: Theme.textOn(card.color)
            Component.onCompleted: musicCard.warnContrast(card.color, musicTextColor, 'musicText')
            property int musicFontWeight: Font.Medium
            // Playback progress 0..1 for the toast progress bar.
            function musicProgress() {
                const total = Time.mprisToMs(MusicManager.trackLength || 0);
                const pos = Math.max(0, MusicManager.currentPosition || 0);
                return total > 0 ? Math.min(1, pos / total) : 0;
            }
            // Copy cava values to a fresh array on a timer: MusicManager.cavaValues
            // is often mutated in place, so a direct binding never re-evaluates and
            // the analyzer sits frozen. Reassigning a copy forces IPhoneSpectrum to
            // re-animate every tick.
            property var _spec: []
            Timer {
                id: specTick
                // ~30 Hz sample of the CAVA stream (was 12.5 Hz — looked laggy).
                interval: 32
                repeat: true
                running: musicCard.isOnScreen && MusicManager.hasPlayer && MusicManager.isPlaying
                onTriggered: playerUI._spec = (MusicManager.cavaValues || []).slice()
            }
            // Mouse scrubbing: map an x position on the progress bar to a seek.
            function seekFromX(x, w) {
                const total = Time.mprisToMs(MusicManager.trackLength || 0);
                if (!total || total <= 0) return;
                const frac = Math.min(1, Math.max(0, x / Math.max(1, w)));
                if (typeof MusicManager.seek === "function") MusicManager.seek(Math.round(frac * total));
            }

            RowLayout {
                spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
                Layout.fillWidth: true

                Item {
                    id: albumArtContainer
                    width: albumArtwork.width
                    height: albumArtwork.height
                    // Bottom-align the cover so it sits right on the card edge,
                    // i.e. just above the panel.
                    Layout.alignment: Qt.AlignLeft | Qt.AlignBottom

                    

                    Rectangle {
                        id: albumArtwork
                            width: Math.round(Theme.sidePanelAlbumArtSize * Theme.scale(screen))
                            height: Math.round(Theme.sidePanelAlbumArtSize * Theme.scale(screen))
                            anchors.fill: parent
                            radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(screen))
                            color: "transparent"
                            border.color: "transparent"
                            border.width: Theme.uiBorderNone

                        HiDpiImage {
                            id: albumArt
                            anchors.fill: parent
                            anchors.margins: Theme.uiMarginNone
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            source: (MusicManager.coverUrl || "")
                            visible: source && source.toString() !== ""
                            // Apply rounded-rect mask (corner radius)
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: mask
                            }
                        }

                        Item {
                            id: mask

                            anchors.fill: albumArt
                            layer.enabled: true
                            visible: false

                            Rectangle {
                                width: albumArt.width
                                height: albumArt.height
                                radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(screen))
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "album"
                            font.family: "Material Symbols Outlined"
                            font.pixelSize: Theme.fontSizeBody * Theme.scale(screen)
                            color: Theme.textOn(card.color, Theme.textSecondary, Theme.textPrimary)
                            visible: !albumArt.visible
                        }
                    }
                }

                // Track metadata
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Math.round(Theme.sidePanelSpacingSmall * 0.5 * Theme.scale(screen))

                    // Now-playing header: title, artist, time/progress, transport.
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Math.round(Theme.sidePanelSpacingSmall * 0.6 * Theme.scale(screen))

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Math.round(8 * Theme.scale(screen))

                            Item {
                                id: progressBand
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(10, Math.round(84 * Theme.scale(screen)))
                                implicitHeight: Layout.preferredHeight
                                // Fill colour: custom spectrum colour, else cover accent.
                                readonly property color _progressFillColor: {
                                    var c = (Settings.settings.spectrumColor !== undefined && Settings.settings.spectrumColor !== "")
                                        ? Settings.settings.spectrumColor
                                        : (Settings.settings.musicPopupColoredProgress ? detailsCol.musicAccent : "");
                                    return (c !== "") ? c : Color.withAlpha(playerUI.musicTextColor, 0.7);
                                }

                                // Spectrum analyzer in the background of the
                                // progress area, coloured with the cover accent.
                                // Reuses the bar's IPhoneSpectrum so values and
                                // animation are proven to work in this shell.
                                IPhoneSpectrum {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    // Leave room at the bottom so the bars end above
                                    // the progress line instead of growing from behind it.
                                    anchors.bottomMargin: Math.max(2, Math.round(Settings.settings.musicPopupProgressHeight * Theme.scale(screen))) + Math.round(3 * Theme.scale(screen))
                                    values: playerUI._spec
                                    targetBars: Settings.settings.toastAnalyserBars
                                    mirror: Settings.settings.toastAnalyserMirror
                                    // Empty style => cover accent; set the accent so the
                                    // analyser follows the album cover colour.
                                    accentColor: detailsCol.musicAccent
                                    style: Settings.settings.toastAnalyserStyle
                                    animDurationMs: 40
                                    opacity: 1.0
                                    visible: Settings.settings.musicPopupSpectrum
                                }

                                // Thin, glowing scrub bar at the bottom of the band.
                                Rectangle {
                                    id: scrubTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: Math.max(2, Math.round(Settings.settings.musicPopupProgressHeight * Theme.scale(screen)))
                                    // Subtle hairline track (the spectrum ends well above it).
                                    // Hairline track tinted with the cover accent.
                                    color: Color.withAlpha(progressBand._progressFillColor, 0.14)
                                    radius: height / 2

                                    Item {
                                        id: scrubFill
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height
                                        width: parent.width * playerUI.musicProgress()

                                        // Vertical bloom: rises from the line up into the
                                        // band (anchored to the line bottom so it never
                                        // overlaps the title below). Sized relative to the
                                        // band height so it fully fits the current layout.
                                        Rectangle {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            width: parent.width
                                            height: Math.max(2, Math.round(progressBand.height * 0.3))
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: Color.withAlpha(progressBand._progressFillColor, 0.0) }
                                                GradientStop { position: 0.6; color: Color.withAlpha(progressBand._progressFillColor, 0.15) }
                                                GradientStop { position: 1.0; color: Color.withAlpha(progressBand._progressFillColor, 0.38) }
                                            }
                                            z: -1
                                        }
                                        // Sharp bright core.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: parent.height / 2
                                            color: progressBand._progressFillColor
                                        }
                                    }
                                }

                                // Mouse scrubbing: click/drag to seek.
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (mouse) => playerUI.seekFromX(mouse.x, width)
                                    onPositionChanged: (mouse) => { if (pressed) playerUI.seekFromX(mouse.x, width) }
                                }
                            }
                        }

                        // Colored now-playing readout, composed the same way as the
                        // bar capsule's time span: accent brackets and slash, digits
                        // in the card's text colour. Replaces the two counters that
                        // used to flank the spectrum.
                        Text {
                            Layout.fillWidth: true
                            textFormat: Text.RichText
                            text: musicCard.timeReadout
                            horizontalAlignment: Text.AlignHCenter
                            color: playerUI.musicTextColor
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(playerUI.musicTextPx * 0.9)
                            font.weight: Font.Normal
                        }

                        // Track title removed on request: the card carries the
                        // identity rows below and the bar keeps the title.

                    }

                    // Details block: time + identity + metadata
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: detailsCol.implicitHeight
                        color: "transparent"
                        radius: Theme.sidePanelInnerRadius
                        border.width: Theme.uiBorderNone
                        anchors.leftMargin: Theme.uiMarginNone
                        anchors.rightMargin: Theme.uiMarginNone

                        ColumnLayout {
                            id: detailsCol
                            clip: true
                            anchors.fill: parent
                            anchors.leftMargin: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
                            anchors.rightMargin: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
                            anchors.topMargin: Theme.uiMarginNone
                            anchors.bottomMargin: Theme.uiMarginNone
                            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
                            // layout follows tokens; no special table-like props
                            // Accent color — centralized in MusicManager
                            property color musicAccent: MusicManager.accentColor
                            property string musicAccentCss: Format.colorCss(musicAccent, 1)
                            property bool musicAccentReady: MusicManager.accentReady
                            

                    

                            // Artist
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackArtist
                                screen: musicCard.screen
                                iconName: "person"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.05
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackArtist
                                textColor: playerUI.musicTextColor
                            }

                            // Album artist (if different)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackAlbumArtist && MusicManager.trackAlbumArtist !== MusicManager.trackArtist
                                screen: musicCard.screen
                                iconName: "person"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.05
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackAlbumArtist
                                textColor: playerUI.musicTextColor
                            }

                            // Album
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackAlbum
                                screen: musicCard.screen
                                iconName: "album"
                                iconColor: detailsCol.musicAccent
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackAlbum
                                textColor: playerUI.musicTextColor
                            }

                            

                            // Genre (if available)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackGenre
                                screen: musicCard.screen
                                iconName: "category"
                                iconColor: detailsCol.musicAccent
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackGenre
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            // Year (hide when Date is present)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackYear && !MusicManager.trackDateStr
                                screen: musicCard.screen
                                iconName: "calendar_month"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.15
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackYear
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            // Label/Publisher (if available)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackLabel
                                screen: musicCard.screen
                                iconName: "sell"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.15
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackLabel
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            // Composer (if available)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackComposer
                                screen: musicCard.screen
                                iconName: "piano"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.15
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackComposer
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            // Quality summary (combined)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackQualitySummary
                                screen: musicCard.screen
                                iconName: "high_quality"
                                iconColor: detailsCol.musicAccent
                                fontPixelSize: playerUI.musicTextPx
                                textFormat: Text.RichText
                                textValue: Rich.decorateGlyphs(MusicManager.trackQualitySummary || "", { pua: detailsCol.musicAccentCss })
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            // DSD rate (icon + value, consistent with other rows)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackDsdRateStr
                                screen: musicCard.screen
                                iconName: "speed"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.15
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackDsdRateStr
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }


                            // Channel layout (hide when Quality is shown)
                            RowLayout {
                                visible: !!MusicManager.trackChannelLayout && !MusicManager.trackQualitySummary
                                Layout.fillWidth: true
                                spacing: Math.round(Theme.sidePanelSpacingTight * Theme.scale(screen))
                                Text {
                                    text: "Layout"
                                    color: playerUI.musicTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: playerUI.musicTextPx
                                    font.weight: Font.DemiBold
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: MusicManager.trackChannelLayout
                                    color: playerUI.musicTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: playerUI.musicTextPx
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }


                            // Path (if available)
                            

                            // Date (if available)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackDateStr
                                screen: musicCard.screen
                                iconName: "calendar_month"
                                iconColor: detailsCol.musicAccent
                                iconSizeMultiplier: 1.15
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackDateStr
                                textColor: playerUI.musicTextColor
                                textAlignment: Qt.AlignVCenter
                                iconAlignment: Qt.AlignVCenter
                            }

                            

                            // ReplayGain removed per configuration
                        }
                    }
                }
            }

            
        }
    }
}
