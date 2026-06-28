import QtQuick
import Quickshell
import qs.Components
import qs.Settings
import "../../Components" as LocalComponents
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/ConnectivityUi.js" as ConnUi

ConnectivityCapsule {
    id: root

    property string throughputText: ConnectivityState.throughputText
    property bool vpnIconRounded: false
    property bool iconSquare: true

    property color accentBase: Color.saturate(Theme.accentPrimary, Theme.vpnAccentSaturateBoost)
    property color accentColor: Color.desaturate(accentBase, Theme.vpnDesaturateAmount)

    Component.onCompleted: {
        if (ConnectivityState) {
            // Initialization verified
        }
    }

    readonly property bool vpnConnected: ConnectivityState.vpnConnected
    readonly property bool hasLink: ConnectivityState.hasLink
    readonly property bool hasInternet: ConnectivityState.hasInternet
    readonly property var hiddifyTrayItem: ConnectivityState.hiddifyTrayItem
    readonly property bool hiddifyHasTrayIcon: !!(hiddifyTrayItem && hiddifyTrayItem.icon)
    readonly property bool _hasLeading: true
    readonly property int _baseClusterSpacing: Math.max(0, Theme.networkCapsuleIconSpacing)
    readonly property int _baseIconMargin: Math.max(0, Theme.networkCapsuleIconHorizontalMargin)
    readonly property int _gapTighten: Math.min(Math.max(0, Theme.networkCapsuleGapTightenPx), Math.round(_baseClusterSpacing))
    readonly property int clusterSpacing: Math.max(0, _baseClusterSpacing - _gapTighten)
    readonly property int iconHorizontalMargin: Math.max(0, _baseIconMargin - Math.round(_gapTighten / 2))
    readonly property color vpnIconColor: vpnConnected ? accentColor : Theme.textDisabled
    readonly property color linkIconColor: (!hasLink)
        ? ConnUi.errorColor(Settings.settings, Theme)
        : (!hasInternet ? ConnUi.warningColor(Settings.settings, Theme) : accentColor)
    readonly property string currentLinkIconName: "lan"

    backgroundKey: "network"
    iconVisible: false
    glyphLeadingActive: _hasLeading
    labelIsRichText: true
    labelText: Theme.networkCapsuleStacked ? "" : _richThroughputText
    labelVisible: !Theme.networkCapsuleStacked && throughputText && throughputText.length > 0
    readonly property string _richThroughputText: _formatThroughputRich(throughputText)

    // Stacked (two-row) layout properties
    readonly property string _rxRichText: _dimLeadingZeros(ConnUi.formatRxText(throughputText))
    readonly property string _txRichText: _dimLeadingZeros(ConnUi.formatTxText(throughputText))
    readonly property int _stackedRowFontPx: Math.max(8, Math.round(labelPixelSize * 0.7))

    // Hiddify tray menu popup
    CustomTrayMenu { id: hiddifyMenu }

    leadingContent: Row {
        id: iconRow
        visible: root._hasLeading
        spacing: root.clusterSpacing
        height: root.desiredInnerHeight

        Item {
            id: vpnSlotWrapper
            width: vpnSlot.width
            height: vpnSlot.height
            visible: root.vpnConnected
            anchors.verticalCenter: parent.verticalCenter

            LocalComponents.ConnectivityIconSlot {
                id: vpnSlot
                active: ConnectivityState.vpnConnected
                square: root.iconSquare
                box: root.desiredInnerHeight
                mode: "material"
                icon: "verified_user"
                rounded: root.vpnIconRounded
                // Dim the fallback icon when Hiddify icon is shown on top
                color: root.hiddifyHasTrayIcon ? "transparent" : root.vpnIconColor
                screen: root.screen
                labelRef: root.labelItem
                alignTarget: root.labelItem
                outerHorizontalMargin: root.iconHorizontalMargin

                // Hiddify real tray icon rendered on top when available
                LocalComponents.TrayIcon {
                    visible: root.hiddifyHasTrayIcon
                    anchors.centerIn: parent
                    size: Math.max(8, vpnSlot.box - 4)
                    source: root.hiddifyTrayItem ? (root.hiddifyTrayItem.icon || "") : ""
                    screen: root.screen
                }
            }

            MouseArea {
                anchors.fill: parent
                visible: !!root.hiddifyTrayItem
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (!root.hiddifyTrayItem) return
                    if (mouse.button === Qt.LeftButton) {
                        if (!root.hiddifyTrayItem.onlyMenu)
                            root.hiddifyTrayItem.activate()
                    } else if (mouse.button === Qt.RightButton) {
                        if (root.hiddifyTrayItem.hasMenu && root.hiddifyTrayItem.menu) {
                            hiddifyMenu.menu = root.hiddifyTrayItem.menu
                            hiddifyMenu.showAt(vpnSlotWrapper,
                                (vpnSlotWrapper.width / 2) - (hiddifyMenu.width / 2),
                                vpnSlotWrapper.height + 4)
                        }
                    }
                }
            }
        }

        LocalComponents.ConnectivityIconSlot {
            id: linkSlot
            square: root.iconSquare
            box: root.desiredInnerHeight
            mode: "material"
            icon: root.currentLinkIconName
            color: root.linkIconColor
            screen: root.screen
            labelRef: root.labelItem
            alignTarget: root.labelItem
            outerHorizontalMargin: root.iconHorizontalMargin
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Stacked two-row throughput display (RX top, TX bottom)
    Column {
        visible: Theme.networkCapsuleStacked && root.throughputText && root.throughputText.length > 0
        spacing: -2
        y: 2

        Text {
            text: root._rxRichText
            textFormat: Text.RichText
            font.family: Theme.fontFamily
            font.weight: Font.Black
            font.pixelSize: root._stackedRowFontPx
            font.letterSpacing: 0.5
            color: Theme.textPrimary
        }
        Text {
            text: root._txRichText
            textFormat: Text.RichText
            font.family: Theme.fontFamily
            font.weight: Font.Black
            font.pixelSize: root._stackedRowFontPx
            font.letterSpacing: 0.5
            color: Theme.textPrimary
        }
    }

    function vpnAccentColor() {
        const boost = Theme.vpnAccentSaturateBoost || 0;
        const desat = Theme.vpnDesaturateAmount || 0;
        const base = Color.saturate(Theme.accentPrimary, boost);
        return Color.desaturate(base, desat);
    }

    readonly property color slashAccentColor: (function() {
        const first = Color.saturate(vpnAccentColor(), 0.2);
        const towardBlack = Color.towardsBlack(first, 0.3);
        const satAgain = Color.saturate(towardBlack, 0.2);
        return Color.towardsBlack(satAgain, 0.3);
    })()
    readonly property string _slashAccentCss: Format.colorCss(slashAccentColor, 1)
    readonly property string _dimZeroCss: Format.colorCss(Theme.textDisabled, 1)
    readonly property color _unitAccentColor: Color.matchLightness(accentColor, Theme.textDisabled)
    readonly property string _unitAccentCss: Format.colorCss(_unitAccentColor, 1)

    // Dim leading zeros and unit suffix in "NNN.DU" or "NNNU" formatted string
    function _dimLeadingZeros(side) {
        var unit = side.slice(-1);
        var body = side.slice(0, -1);
        var dotIdx = body.indexOf(".");
        var intPart, decPart;
        if (dotIdx !== -1) {
            intPart = body.slice(0, dotIdx);
            decPart = body.slice(dotIdx + 1);
        } else {
            intPart = body;
            decPart = "";
        }
        var i = 0;
        while (i < intPart.length && intPart[i] === "0") i++;
        var dimmed = (i > 0) ? Rich.colorSpan(_dimZeroCss, intPart.slice(0, i)) : "";
        var rest = Rich.esc(intPart.slice(i));
        var dotAndDec = (decPart !== "") ? Rich.dotSpan() + Rich.esc(decPart) : "";
        var unitSuffix = (unit === "K")
            ? ""
            : Rich.colorSpan(_unitAccentCss, unit);
        return dimmed + rest + dotAndDec + unitSuffix;
    }

    function _formatThroughputRich(text) {
        const raw = (text === undefined || text === null) ? "" : String(text);
        if (!raw.length)
            return "";
        const slashIdx = raw.indexOf("/");
        if (slashIdx === -1)
            return Rich.esc(raw);
        const left = _dimLeadingZeros(raw.slice(0, slashIdx));
        const right = _dimLeadingZeros(raw.slice(slashIdx + 1));
        return left + Rich.sepSpan(_slashAccentCss, "/", true) + right;
    }

}
