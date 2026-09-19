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
            // Glass card: the fill is deliberately translucent because
            // hyprglass blurs and refracts what is *behind* the surface — an
            // opaque fill (0.92 black before) showed none of it, which is why
            // the popup never looked glassy even though `qs-music` is in the
            // plugin's layer namespace list. The hairline border is the glass
            // edge the plugin's fresnel pass then lights up.
            color: Color.withAlpha(Theme.surface, Theme.sidePanelPopupGlassOpacity)
            border.color: Color.withAlpha(Theme.textPrimary, Theme.sidePanelPopupGlassBorderOpacity)
            border.width: Theme.uiBorderWidth
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
                // A little more air between the art and the text column than the
                // tight token used to give.
                spacing: Math.round(Theme.sidePanelSpacingMedium * Theme.scale(screen))
                Layout.fillWidth: true

                Item {
                    id: albumArtContainer
                    // Square cover. It used to declare only `width`/`height` while
                    // the RowLayout owns those properties — the layout sized the
                    // item from its (zero) implicit size and simply overrode the
                    // bindings, so the art came out smaller than the theme value
                    // and, being bottom-aligned, floated with a gap above it
                    // whenever the metadata block grew. Now the item carries real
                    // layout sizes and its side follows the info column: same
                    // height as the text block, never below the theme size, so the
                    // two columns line up on the card edge.
                    readonly property real side: Math.max(
                        Math.round(Theme.sidePanelAlbumArtSize * Theme.scale(musicCard.screen)),
                        Math.round(infoColumn.implicitHeight))
                    // Centred vertically (user preference): the art is a fixed
                    // square that is usually taller than the metadata block, and
                    // centring shares the slack between top and bottom instead of
                    // dropping the gap onto one side.
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    Layout.preferredWidth: side
                    Layout.preferredHeight: side
                    implicitWidth: side
                    implicitHeight: side

                    Rectangle {
                        id: albumArtwork
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
                    id: infoColumn
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBottom
                    spacing: Math.round(Theme.sidePanelSpacingSmall * 0.5 * Theme.scale(screen))

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

                    // Spectrum/scrub, deliberately LAST in the column and therefore at
                    // the bottom of the card: the card's content is bottom-anchored and
                    // the seek line sits on the band's bottom edge, so the spectrogram
                    // and the line both sit on the card's bottom.
                    ColumnLayout {
                        Layout.fillWidth: true
                        // Same side padding as the metadata rows above, so the
                        // spectrum and the seek line start where the text does.
                        Layout.leftMargin: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(musicCard.screen))
                        Layout.rightMargin: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(musicCard.screen))
                        spacing: Math.round(Theme.sidePanelSpacingSmall * 0.6 * Theme.scale(screen))

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Math.round(8 * Theme.scale(screen))

                            Item {
                                id: progressBand
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(10, Math.round(84 * Theme.scale(screen)))
                                implicitHeight: Layout.preferredHeight
                                // ── Seek preview state ───────────────────────────────
                                // Cursor position over the band in px (-1 = pointer away).
                                // Everything below (playhead, ghost fill, timestamp bubble)
                                // hangs off it, so a click is predictable instead of a leap
                                // of faith.
                                property real seekX: -1
                                readonly property real seekTotalMs: Math.max(0, Time.mprisToMs(MusicManager.trackLength || 0))
                                readonly property bool seekReady: seekTotalMs > 0
                                readonly property real seekFraction: (seekX < 0 || width <= 0)
                                    ? 0 : Math.max(0, Math.min(1, seekX / width))
                                readonly property bool seekPreviewVisible: seekX >= 0 && seekReady
                                readonly property string seekTimeText: Format.fmtTime(seekFraction * seekTotalMs)

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
                                    // The hairline fattens and brightens while the cursor is on
                                    // the band: the seek target should look grabbable, not
                                    // decorative.
                                    readonly property real baseHeight: Math.max(2, Math.round(Settings.settings.musicPopupProgressHeight * Theme.scale(screen)))
                                    height: baseHeight + (progressBand.seekPreviewVisible
                                        ? Math.max(1, Math.round(2 * Theme.scale(musicCard.screen))) : 0)
                                    // Subtle hairline track (the spectrum ends well above it).
                                    // Hairline track tinted with the cover accent.
                                    color: Color.withAlpha(progressBand._progressFillColor,
                                        progressBand.seekPreviewVisible ? 0.3 : 0.14)
                                    radius: height / 2
                                    Behavior on height {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on color {
                                        enabled: Theme.animationsEnabled
                                        ColorAnimation { duration: 140 }
                                    }

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

                                    // Ghost fill: runs from the start to the cursor, i.e. the
                                    // part that would be played after a click. Kept above the
                                    // real fill so both stay readable at once.
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: parent.height
                                        width: parent.width * progressBand.seekFraction
                                        visible: progressBand.seekPreviewVisible
                                            && progressBand.seekFraction > playerUI.musicProgress()
                                        radius: height / 2
                                        color: Color.withAlpha(progressBand._progressFillColor, 0.34)
                                        opacity: visible ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }
                                }

                                // Cursor tracking for the preview. A HoverHandler rather than
                                // `MouseArea.hoverEnabled`: the handler reports the pointer
                                // position without taking part in click delivery, so the band
                                // below stays one seek target for press/drag.
                                HoverHandler {
                                    id: seekHover
                                    onPointChanged: progressBand.seekX = point.position.x
                                    onHoveredChanged: if (!hovered && !scrubArea.pressed) progressBand.seekX = -1
                                }

                                // Mouse scrubbing: click/drag to seek. The whole band is the
                                // target; the drag also updates the preview drawn after it.
                                MouseArea {
                                    id: scrubArea
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onPressed: (mouse) => playerUI.seekFromX(mouse.x, width)
                                    onPositionChanged: (mouse) => {
                                        progressBand.seekX = mouse.x;
                                        if (pressed) playerUI.seekFromX(mouse.x, width);
                                    }
                                }

                                // ── Seek preview (hover / drag) ──────────────────────
                                // Drawn after the MouseArea on purpose: plain items never take
                                // hover or clicks, so the band stays a single seek target while
                                // the cursor gets a playhead, a glow and the timestamp it would
                                // jump to.
                                Item {
                                    id: seekCursor
                                    anchors.top: parent.top
                                    anchors.bottom: parent.bottom
                                    width: Math.max(2, Math.round(1.6 * Theme.scale(musicCard.screen)))
                                    x: Math.max(0, Math.min(progressBand.width - width, progressBand.seekX - width / 2))
                                    visible: progressBand.seekPreviewVisible
                                    opacity: visible ? 1 : 0
                                    Behavior on opacity {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }

                                    // Bloom: a soft column behind the line so the playhead reads
                                    // as light, not as a hard rule over the spectrum.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: Math.max(6, Math.round(progressBand.height * 0.22))
                                        gradient: Gradient {
                                            GradientStop { position: 0.0; color: Color.withAlpha(progressBand._progressFillColor, 0.0) }
                                            GradientStop { position: 0.55; color: Color.withAlpha(progressBand._progressFillColor, 0.18) }
                                            GradientStop { position: 1.0; color: Color.withAlpha(progressBand._progressFillColor, 0.42) }
                                        }
                                    }

                                    // Core line, with a dark hairline under it so it stays
                                    // readable over bright spectrum bars too.
                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -Math.max(0, Math.round(1 * Theme.scale(musicCard.screen)))
                                        radius: width / 2
                                        color: Color.withAlpha(card.color, 0.55)
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: width / 2
                                        color: progressBand._progressFillColor
                                    }

                                    // Knob sitting on the track, with a halo.
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: Math.max(4, Math.round(2.6 * Theme.scale(musicCard.screen)))
                                        height: width
                                        radius: width / 2
                                        color: progressBand._progressFillColor

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width * 2.4
                                            height: width
                                            radius: width / 2
                                            color: Color.withAlpha(progressBand._progressFillColor, 0.22)
                                        }
                                    }
                                }

                                // Target timestamp, in the bar capsule's bracket style, so the
                                // hover answers both "where" and "when". Filled with the cover
                                // accent (a dark bubble on the dark card reads as nothing) and
                                // popped in with a small scale, like the capsule's own pills.
                                Rectangle {
                                    id: seekBubble
                                    anchors.top: parent.top
                                    anchors.topMargin: Math.round(2 * Theme.scale(musicCard.screen))
                                    x: Math.max(0, Math.min(progressBand.width - width, progressBand.seekX - width / 2))
                                    width: seekBubbleLabel.implicitWidth + Math.round(14 * Theme.scale(musicCard.screen))
                                    height: seekBubbleLabel.implicitHeight + Math.round(5 * Theme.scale(musicCard.screen))
                                    radius: height / 2
                                    visible: progressBand.seekPreviewVisible
                                    opacity: visible ? 1 : 0
                                    scale: visible ? 1 : 0.92
                                    color: Color.withAlpha(progressBand._progressFillColor, 0.92)
                                    border.width: Theme.uiBorderWidth
                                    border.color: Color.withAlpha(Theme.textPrimary, 0.22)
                                    Behavior on opacity {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
                                    }
                                    Behavior on scale {
                                        enabled: Theme.animationsEnabled
                                        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                                    }

                                    Text {
                                        id: seekBubbleLabel
                                        anchors.centerIn: parent
                                        text: progressBand.seekTimeText
                                        color: Theme.textOn(progressBand._progressFillColor)
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Math.max(8, Math.round(playerUI.musicTextPx * 0.85))
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                        }

                        // Track title removed on request: the card carries the
                        // identity rows below and the bar keeps the title.
                    }
                }
            }

            
        }
    }
}
