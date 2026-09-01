import QtQuick
import Quickshell
import qs.Components
import qs.Settings
import "../../Components" as LocalComponents
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/ConnectivityUi.js" as ConnUi
import "../../Helpers/TooltipText.js" as TooltipText

ConnectivityCapsule {
    id: root

    property string throughputText: ConnectivityState.throughputText
    property bool vpnIconRounded: false
    property bool iconSquare: true

    property color accentBase: Color.saturate(Theme.accentPrimary, Theme.vpnAccentSaturateBoost)
    property color accentColor: Color.desaturate(accentBase, Theme.vpnDesaturateAmount)

    // The stacked two-line column (14px rows at 11px font) must not inflate
    // the capsule beyond the bar strip: cap at the uniform capsule height so
    // the readout fits the bar instead of overflowing/clipping at the screen.
    implicitHeight: root.uniformCapsuleHeight
    // Center the capsule in its wrapper's content area: without this the
    // 26px capsule hangs below the 20px content slot and its icon sits
    // ~4px lower than the neighboring capsules' icons.
    anchors.verticalCenter: parent.verticalCenter

    Component.onCompleted: {
        if (ConnectivityState) {
            // Initialization verified
        }
        // One-shot diagnostics (remove after widget visibility confirmed).
        console.log("[netdbg] stacked=" + Theme.networkCapsuleStacked +
            " throughput=" + JSON.stringify(throughputText) +
            " rx=" + JSON.stringify(_rxPlain) + " tx=" + JSON.stringify(_txPlain) +
            " labelVisible=" + labelVisible +
            " scale=" + capsuleScale)
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
    // Two-row RX/TX readout, plain text (no rich-text spans / Font.Black —
    // those rendered as unreadable glyphs). Leading zero-padding is stripped.
    readonly property string _rxPlain: _stripZeroPad(ConnUi.formatRxText(throughputText))
    readonly property string _txPlain: _stripZeroPad(ConnUi.formatTxText(throughputText))
    readonly property int _stackedRowFontPx: Math.max(8, Math.round(labelPixelSize * 0.55))

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
                labelRef: Theme.networkCapsuleStacked ? null : root.labelItem
                alignTarget: Theme.networkCapsuleStacked ? null : root.labelItem
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
            labelRef: Theme.networkCapsuleStacked ? null : root.labelItem
            alignTarget: Theme.networkCapsuleStacked ? null : root.labelItem
            outerHorizontalMargin: root.iconHorizontalMargin
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    // Stacked two-row throughput display (RX top, TX bottom)
    Column {
        visible: Theme.networkCapsuleStacked && root.throughputText && root.throughputText.length > 0
        spacing: -2

        Text {
            text: root._rxPlain
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.weight: Font.Medium
            font.pixelSize: root._stackedRowFontPx
            color: Theme.textPrimary
        }
        Text {
            text: root._txPlain
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.weight: Font.Medium
            font.pixelSize: root._stackedRowFontPx
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

    // Strip leading zero-padding ("058.2K" -> "58.2K") for the plain rows.
    function _stripZeroPad(s) {
        return String(s || "").replace(/^0+(?=\d)/, "");
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

    // Link / internet / VPN / addresses + live RX/TX on hover.
    readonly property string _tooltipText: (function() {
        var hints = [];
        hints.push(!hasLink ? "Соединения нет"
            : (hasInternet ? "Интернет: доступен" : "Локальная сеть, интернета нет"));
        if (vpnConnected) hints.push("VPN: подключён");
        if (ConnectivityState && ConnectivityState.interfaces) {
            for (var i = 0; i < ConnectivityState.interfaces.length; i++) {
                var it = ConnectivityState.interfaces[i];
                if (!it) continue;
                var nm = String(it.ifname || "");
                if (!nm || nm === "lo") continue;
                var ai = Array.isArray(it.addr_info) ? it.addr_info : [];
                for (var j = 0; j < ai.length; j++) {
                    var a = ai[j];
                    if (a && a.local) hints.push(nm + ": " + a.local);
                }
            }
        }
        hints.push("Клик — потоковая панель");
        var rx = (ConnectivityState && isFinite(ConnectivityState.rxKiBps) && ConnectivityState.rxKiBps > 0)
            ? ConnUi.formatScaledKiBps(ConnectivityState.rxKiBps) : "-";
        var tx = (ConnectivityState && isFinite(ConnectivityState.txKiBps) && ConnectivityState.txKiBps > 0)
            ? ConnUi.formatScaledKiBps(ConnectivityState.txKiBps) : "-";
        return TooltipText.compose("Сеть", "RX " + rx + " · TX " + tx, hints);
    })()

    PanelTooltip {
        targetItem: root
        text: root._tooltipText
        visibleWhen: root.hovered
    }
}
