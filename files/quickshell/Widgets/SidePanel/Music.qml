import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Window 2.15
import qs.Settings
import qs.Components
import qs.Services
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "." as MusicWidgets

Rectangle {
    id: musicCard
    // Use attached Window.window when available; fallback to Screen
    property var screen: (Window.window && Window.window.screen) ? Window.window.screen : Screen
    color: "transparent"
    implicitHeight: playerUI.implicitHeight

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
            color: Theme.background
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
            anchors.fill: parent
            anchors.leftMargin: Theme.uiMarginNone
            anchors.rightMargin: Theme.uiMarginNone
            anchors.topMargin: Theme.uiMarginNone
            anchors.bottomMargin: Theme.uiMarginNone
            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
            visible: !!MusicManager.currentPlayer

            // Typography
            property int musicFontPx: Math.round(Theme.fontSizeSmall * Theme.scale(screen))
            property int musicTextPx: Math.round(Theme.fontSizeSmall * Theme.scale(screen))
            property color musicTextColor: Theme.textOn(card.color)
            Component.onCompleted: musicCard.warnContrast(card.color, musicTextColor, 'musicText')
            property int musicFontWeight: Font.Medium

            

            // Player selector
            property var uniquePlayers: []
            readonly property bool showCombo: false
            readonly property bool showSingleLabel: false
            function dedupePlayers() {
                try {
                    const list = MusicManager.getAvailablePlayers() || [];
                    function nameOf(p, i) {
                        if (!p) return `Player ${i+1}`;
                        return p.identity || p.name || p.id || `Player ${i+1}`;
                    }
                    const seen = Object.create(null);
                    const out = [];
                    for (let i = 0; i < list.length; i++) {
                        const p = list[i];
                        if (!p) continue;
                        const key = (p.identity || p.name || p.id || ("idx_"+i));
                        if (seen[key]) continue;
                        seen[key] = true;
                        out.push({ identity: nameOf(p, i), idx: i });
                    }
                    uniquePlayers = out;
                    // Try to keep current selection in sync
                    if (MusicManager.currentPlayer) {
                        const curKey = (MusicManager.currentPlayer.identity || MusicManager.currentPlayer.name || MusicManager.currentPlayer.id);
                        let idx = 0;
                        for (let j = 0; j < uniquePlayers.length; j++) {
                            const upName = uniquePlayers[j] && uniquePlayers[j].identity;
                            if (upName === curKey) { idx = j; break; }
                        }
                        playerSelector.currentIndex = idx;
                    }
                } catch (e) { console.warn("[Music.dedupePlayers]", e) }
            }
            // Refresh list periodically and on player change (centralized timer)
            Connections { target: Timers; function onTick2s() { playerUI.dedupePlayers() } }
            Connections { target: MusicManager; function onCurrentPlayerChanged() { playerUI.dedupePlayers() } }
            ComboBox {
                id: playerSelector
                Layout.fillWidth: true
                Layout.preferredHeight: playerUI.showCombo ? 40 * Theme.scale(screen) : 0
                visible: playerUI.showCombo
                height: visible ? implicitHeight : 0
                model: playerUI.uniquePlayers
                textRole: "identity"
                currentIndex: 0
                onActivated: (index) => {
                    try {
                        if (playerUI.uniquePlayers && playerUI.uniquePlayers[index]) {
                            MusicManager.selectedPlayerIndex = playerUI.uniquePlayers[index].idx;
                            MusicManager.updateCurrentPlayer();
                        }
                    } catch (e) { console.warn("[Music.playerSelector]", e) }
                }

                background: Rectangle {
                    implicitWidth: Math.round(Theme.sidePanelSelectorMinWidth * Theme.scale(screen))
                    implicitHeight: Math.round(Theme.uiControlHeight * Theme.scale(screen))
                    // Match window/card palette
                    color: card.color
                    border.color: "transparent"
                    border.width: Theme.uiBorderNone
                    radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen))
                }

                contentItem: Text {
                    leftPadding: Math.round(Theme.sidePanelSpacingTight * Theme.scale(screen))
                    rightPadding: playerSelector.indicator.width + playerSelector.spacing
                    text: playerSelector.displayText
                    font.pixelSize: playerUI.musicTextPx
                    color: playerUI.musicTextColor
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }

                indicator: Text {
                    x: playerSelector.width - width - Math.round(Theme.sidePanelSpacing * Theme.scale(screen))
                    y: playerSelector.topPadding + (playerSelector.availableHeight - height) / 2
                    text: "arrow_drop_down"
                    font.family: "Material Symbols Outlined"
                    font.pixelSize: playerUI.musicTextPx
                    color: playerUI.musicTextColor
                }

                popup: Popup {
                    y: playerSelector.height
                    width: playerSelector.width
                    implicitHeight: contentItem.implicitHeight
                    padding: Math.round(Theme.uiGapTiny * Theme.scale(screen))

                    contentItem: ListView {
                        clip: true
                        implicitHeight: contentHeight
                        model: playerSelector.popup.visible ? playerSelector.delegateModel : null
                        currentIndex: playerSelector.highlightedIndex

                        ScrollIndicator.vertical: ScrollIndicator {}
                    }

                    background: Rectangle {
                        color: card.color
                        border.color: "transparent"
                        border.width: Theme.uiBorderNone
                        radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen))
                    }
                }

                delegate: ItemDelegate {
                    width: playerSelector.width
                    contentItem: Text {
                        text: modelData.identity
                        font.weight: playerUI.musicFontWeight
                        font.pixelSize: playerUI.musicTextPx
                        color: playerUI.musicTextColor
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                    highlighted: playerSelector.highlightedIndex === index

                    background: ThemedHoverRect {
                        colorToken: Theme.surfaceHover
                        radiusFactor: 0
                        epsToken: Theme.uiVisibilityEpsilon
                        intensity: highlighted ? 1.0 : 0.0
                    }
                }

            Text {
                visible: playerUI.showSingleLabel
                Layout.preferredHeight: visible ? (28 * Theme.scale(screen)) : 0
                height: visible ? implicitHeight : 0
                text: playerUI.showSingleLabel ? playerUI.uniquePlayers[0].identity : ""
                color: playerUI.musicTextColor
                font.family: Theme.fontFamily
                font.pixelSize: playerUI.musicTextPx
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            }

            RowLayout {
                spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(screen))
                Layout.fillWidth: true

                Item {
                    id: albumArtContainer
                    width: albumArtwork.width
                    height: albumArtwork.height
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter

                    

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
                    spacing: Math.round(Theme.sidePanelSpacingSmall * 0.5 * Theme.scale(screen))

                    // Details block: time + identity + metadata
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: detailsCol.implicitHeight
                        color: card.color
                        radius: Theme.sidePanelInnerRadius
                        border.width: Theme.uiBorderNone
                        anchors.leftMargin: Theme.uiMarginNone
                        anchors.rightMargin: Theme.uiMarginNone

                        ColumnLayout {
                            id: detailsCol
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
                                fontPixelSize: playerUI.musicTextPx
                                textValue: MusicManager.trackAlbum
                                textColor: playerUI.musicTextColor
                            }

                            

                            // Genre (if available)
                            MusicWidgets.MusicDetailRow {
                                visible: !!MusicManager.trackGenre
                                screen: musicCard.screen
                                iconName: "category"
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
                                    font.weight: (detailsCol && detailsCol.textWeight !== undefined) ? detailsCol.textWeight : Font.DemiBold
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: MusicManager.trackChannelLayout
                                    color: playerUI.musicTextColor
                                    font.family: Theme.fontFamily
                                    font.pixelSize: playerUI.musicTextPx
                                    font.weight: (detailsCol && detailsCol.textWeight !== undefined) ? detailsCol.textWeight : Font.DemiBold
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
                                iconColor: detailsCol.musicAccentReady ? detailsCol.musicAccent : playerUI.musicTextColor
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
