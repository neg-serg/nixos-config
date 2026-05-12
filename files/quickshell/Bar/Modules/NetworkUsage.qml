import QtQuick
import qs.Settings
import qs.Components

NetClusterCapsule {
    id: root

    property color textColor: Theme.textPrimary
    property string deviceMatch: ""
    property alias throughput: root.throughputText

    backgroundKey: "network"
    vpnVisible: false
    linkVisible: false
    labelColor: textColor
}
