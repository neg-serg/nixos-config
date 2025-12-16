import QtQuick
import qs.Components

NetClusterCapsule {
    id: root

    property bool showLabel: false
    property string labelTextValue: "NET"
    property alias linkIconDefault: root.linkIconDefault
    property alias vpnIconDefault: root.vpnIconDefault
    property alias iconConnected: root.iconConnected
    property alias iconNoInternet: root.iconNoInternet
    property alias iconDisconnected: root.iconDisconnected
    property alias useStatusFallbackIcons: root.useStatusFallbackIcons

    backgroundKey: "networkLink"
    vpnVisible: false
    linkVisible: true
    labelVisible: showLabel
    throughputText: showLabel ? labelTextValue : ""
}
