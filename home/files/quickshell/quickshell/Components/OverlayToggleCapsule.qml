import QtQuick
import qs.Components
import qs.Settings

/*!
 * OverlayToggleCapsule bundles a WidgetCapsule trigger with OverlayToggle
 * plumbing. Consumers provide capsule content and overlay content; this helper
 * wires up toggle/open/close and exposes consistent styling knobs.
 */
Item {
    id: root

    property bool capsuleVisible: true
    property bool autoToggleOnTap: true
    property var screen: null
    property alias capsule: capsule
    property alias overlay: overlay
    property alias overlayChildren: overlayHost.data
    property alias overlayNamespace: overlay.overlayNamespace
    property alias overlayColor: overlay.overlayColor
    property alias showOverlay: overlay.showOverlay
    property alias closeOnBackgroundClick: overlay.closeOnBackgroundClick
    property alias expanded: overlay.expanded
    property real capsuleHoverYOffset: 0

    default property alias content: capsule.content

    signal opened()
    signal dismissed(string reason)

    implicitWidth: capsuleVisible ? capsule.implicitWidth : 0
    implicitHeight: capsuleVisible ? capsule.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight

    WidgetCapsule {
        id: capsule
        visible: root.capsuleVisible
        anchors.fill: parent
        screen: root.screen
        contentYOffset: root.capsuleHoverYOffset
    }

    TapHandler {
        id: toggleTap
        target: capsule
        enabled: capsule.visible && root.autoToggleOnTap
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: root.toggle()
    }

    OverlayToggle {
        id: overlay
        screen: root.screen
        overlayNamespace: "quickshell"
        showOverlay: Settings.settings.dimPanels
        closeOnBackgroundClick: true
        onOpened: root.opened()
        onDismissed: reason => root.dismissed(reason)
        Item {
            id: overlayHost
            anchors.fill: parent
        }
    }

    function open(reason = "open") { overlay.open(reason); }
    function close(reason = "programmatic") { overlay.close(reason); }
    function toggle(reason = "toggle") { overlay.toggle(reason); }
}
