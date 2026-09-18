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
    // On-screen x of the capsule (bar-local x == screen x: the bar spans the
    // full width at the bottom). Used to open the flow popup next to the widget.
    property real triggerX: 0

    overlayNamespace: "qs-netflow"

    content: NetClusterCapsule {
        id: netClusterContent
        screen: root.screen
        vpnIconRounded: root.vpnIconRounded
        throughputText: root.throughputText
    }

    // The host capsule owns the panel: the cluster below is a capsule too and
    // must stay transparent, otherwise the panel is filled twice (see
    // NetClusterCapsule.qml). Key kept here so widgetBackgrounds.network still
    // applies, exactly like systemMonitor/weather.
    capsule.backgroundKey: "network"

    // WidgetCapsule defaults to implicitWidth 0; derive it from the content
    // or the whole capsule collapses to zero width and vanishes from the bar
    // (same pattern as WeatherButton/PillCapsule/SystemMonitorCapsule).
    capsule.implicitWidth: Math.max(0, netClusterContent.implicitWidth)

    overlayChildren: [
        NetFlowPopup {
            id: netFlowPopup
            screen: root.screen
            triggerX: root.triggerX
        }
    ]

    onOpened: netFlowPopup.start()
    onDismissed: netFlowPopup.stop()

    // Resolve the capsule's global x once laid out (Qt.callLater defers past
    // the initial (0,0) layout position).
    Component.onCompleted: {
        Qt.callLater(function () {
            root.triggerX = capsule.mapToGlobal(0, 0).x;
        });
    }
}
