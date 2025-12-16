import QtQuick
import qs.Components
import qs.Settings
import "../../Components" as LocalComponents
import "../../Helpers/Color.js" as Color
import "../../Helpers/Format.js" as Format
import "../../Helpers/RichText.js" as Rich
import "../../Helpers/ConnectivityUi.js" as ConnUi

ConnectivityCapsule {
    id: root

    property bool vpnVisible: ConnectivityState.vpnConnected
    property bool linkVisible: true
    property string throughputText: ConnectivityState.throughputText
    property bool vpnIconRounded: false
    property bool linkIconRounded: false
    property bool iconSquare: true
    property bool iconDebugFrames: false
    property color iconDebugFrameColor: "#ff0000"
    property real iconDebugFrameWidth: 1.5

    property real accentSaturateBoost: Theme.vpnAccentSaturateBoost
    property real accentLightenTowardWhite: Theme.vpnAccentLightenTowardWhite
    property real desaturateAmount: Theme.vpnDesaturateAmount
    property color accentBase: Color.saturate(Theme.accentPrimary, accentSaturateBoost)
    property color accentColor: desaturateColor(accentBase, desaturateAmount)
    property color vpnOffColor: Theme.textDisabled

    property string linkIconDefault: "lan"
    property string vpnIconDefault: "verified_user"
    property string iconConnected: "network_check"
    property string iconNoInternet: "network_ping"
    property string iconDisconnected: "link_off"
    property bool useStatusFallbackIcons: false

    readonly property bool vpnConnected: ConnectivityState.vpnConnected
    readonly property bool hasLink: ConnectivityState.hasLink
    readonly property bool hasInternet: ConnectivityState.hasInternet
    readonly property bool _hasLeading: vpnVisible || linkVisible
    readonly property int _baseClusterSpacing: Math.max(0, Theme.networkCapsuleIconSpacing)
    readonly property int _baseIconMargin: Math.max(0, Theme.networkCapsuleIconHorizontalMargin)
    readonly property int _gapTighten: Math.min(Math.max(0, Theme.networkCapsuleGapTightenPx), Math.round(_baseClusterSpacing))
    readonly property int clusterSpacing: Math.max(0, _baseClusterSpacing - _gapTighten)
    readonly property int iconHorizontalMargin: Math.max(0, _baseIconMargin - Math.round(_gapTighten / 2))
    readonly property color vpnIconColor: vpnConnected ? accentColor : vpnOffColor
    readonly property color linkIconColor: (!hasLink)
        ? ConnUi.errorColor(Settings.settings, Theme)
        : (!hasInternet ? ConnUi.warningColor(Settings.settings, Theme) : accentColor)
    readonly property string currentLinkIconName: useStatusFallbackIcons ? (!hasLink ? iconDisconnected : (!hasInternet ? iconNoInternet : iconConnected)) : linkIconDefault

    backgroundKey: "network"
    iconVisible: false
    glyphLeadingActive: _hasLeading
    labelIsRichText: true
    labelText: _richThroughputText
    labelVisible: throughputText && throughputText.length > 0
    readonly property string _richThroughputText: _formatThroughputRich(throughputText)

    leadingContent: Row {
        id: iconRow
        visible: root._hasLeading
        spacing: root.clusterSpacing
        height: root.desiredInnerHeight

        LocalComponents.ConnectivityIconSlot {
            id: vpnSlot
            active: root.vpnVisible
            square: root.iconSquare
            box: root.desiredInnerHeight
            mode: "material"
            icon: root.vpnIconDefault
            rounded: root.vpnIconRounded
            color: root.vpnIconColor
            screen: root.screen
            labelRef: root.labelItem
            alignTarget: root.labelItem
            outerHorizontalMargin: root.iconHorizontalMargin
            debugBorderVisible: root.iconDebugFrames
            debugBorderColor: root.iconDebugFrameColor
            debugBorderWidth: root.iconDebugFrameWidth
            anchors.verticalCenter: parent.verticalCenter
        }

        LocalComponents.ConnectivityIconSlot {
            id: linkSlot
            active: root.linkVisible
            square: root.iconSquare
            box: root.desiredInnerHeight
            mode: "material"
            icon: root.currentLinkIconName
            rounded: root.linkIconRounded
            color: root.linkIconColor
            screen: root.screen
            labelRef: root.labelItem
            alignTarget: root.labelItem
            outerHorizontalMargin: root.iconHorizontalMargin
            debugBorderVisible: root.iconDebugFrames
            debugBorderColor: root.iconDebugFrameColor
            debugBorderWidth: root.iconDebugFrameWidth
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    function mixColor(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t, a.g * (1 - t) + b.g * t, a.b * (1 - t) + b.b * t, a.a * (1 - t) + b.a * t);
    }

    function grayOf(c) {
        const y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return Qt.rgba(y, y, y, c.a);
    }

    function desaturateColor(c, amount) {
        const clamped = Math.min(1, Math.max(0, amount || 0));
        return mixColor(c, grayOf(c), clamped);
    }

    function vpnAccentColor() {
        const boost = Theme.vpnAccentSaturateBoost || 0;
        const desat = Theme.vpnDesaturateAmount || 0;
        const base = Color.saturate(Theme.accentPrimary, boost);
        return desaturateColor(base, desat);
    }

    readonly property color slashAccentColor: (function() {
        const first = Color.saturate(vpnAccentColor(), 0.2);
        const towardBlack = Color.towardsBlack(first, 0.3);
        const satAgain = Color.saturate(towardBlack, 0.2);
        return Color.towardsBlack(satAgain, 0.3);
    })()
    readonly property string _slashAccentCss: Format.colorCss(slashAccentColor, 1)

    function _formatThroughputRich(text) {
        const raw = (text === undefined || text === null) ? "" : String(text);
        if (!raw.length)
            return "";
        const slashIdx = raw.indexOf("/");
        if (slashIdx === -1)
            return Rich.esc(raw);
        const left = Rich.esc(raw.slice(0, slashIdx));
        const right = Rich.esc(raw.slice(slashIdx + 1));
        return left + Rich.sepSpan(_slashAccentCss, "/", true) + right;
    }

}
