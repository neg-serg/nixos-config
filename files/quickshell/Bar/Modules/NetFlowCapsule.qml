import QtQuick
import qs.Components
import qs.Settings

/*!
 * NetFlowCapsule — networking capsule that opens the flow dashboard popup
 * on click. Reuses NetClusterCapsule for the bar content; the popup streams
 * `flow -json-stream` for live throughput + history chart.
 */
OverlayToggleCapsule {
    id: root

    property bool vpnIconRounded: false
    property string throughputText: ""

    overlayNamespace: "qs-netflow"

    content: NetClusterCapsule {
        screen: root.screen
        vpnIconRounded: root.vpnIconRounded
        throughputText: root.throughputText
    }

    overlayChildren: [
        NetFlowPopup {
            id: netFlowPopup
            screen: root.screen
        }
    ]

    onOpened: netFlowPopup.start()
    onDismissed: netFlowPopup.stop()
}
