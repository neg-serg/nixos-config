import QtQuick
import qs.Components

NetClusterCapsule {
    id: root

    property bool useTheme: true
    property bool showLabel: true
    property alias accentSaturateBoost: root.accentSaturateBoost
    property alias accentLightenTowardWhite: root.accentLightenTowardWhite
    property alias desaturateAmount: root.desaturateAmount
    property alias accentBase: root.accentBase
    property alias accentColor: root.accentColor
    property alias vpnOffColor: root.vpnOffColor

    readonly property bool connected: ConnectivityState.vpnConnected

    backgroundKey: "vpn"
    vpnVisible: connected
    linkVisible: false
    throughputText: showLabel ? "VPN" : ""
    labelVisible: showLabel
    labelColor: vpnIconColor
    visible: connected

    property alias iconRounded: vpnIconRounded
}
