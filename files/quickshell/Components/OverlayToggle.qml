import QtQuick
import qs.Settings
import "." as LocalComponents

/*!
 * OverlayToggle encapsulates PanelWithOverlay lifecycle:
 * - exposes an `expanded` state and helper open/close/toggle functions
 * - emits `opened`/`dismissed(reason)` signals so callers can react
 * - optionally closes when the dimmed background is clicked
 *
 * Example:
 *     OverlayToggle {
 *         id: weatherOverlay
 *         overlayNamespace: "sideleft-weather"
 *         onOpened: Services.Weather.start()
 *         onDismissed: Services.Weather.stop()
 *         Rectangle { ... } // overlay content
 *     }
 */
Item {
    id: root

    property bool expanded: false
    property bool closeOnBackgroundClick: true
    property bool showOverlay: Settings.settings.dimPanels
    property color overlayColor: showOverlay ? Theme.overlayStrong : "transparent"
    property var screen: null
    property string overlayNamespace: "quickshell"

    readonly property alias overlayWindow: overlayWindow
    property alias topMargin: overlayWindow.topMargin
    property alias bottomMargin: overlayWindow.bottomMargin

    default property alias content: overlayContent.data

    signal opened()
    signal dismissed(string reason)

    function open(reason = "open") {
        if (expanded) return;
        _pendingReason = reason || "open";
        expanded = true;
    }

    function close(reason = "programmatic") {
        if (!expanded && !overlayWindow.visible) return;
        _pendingReason = reason || "programmatic";
        expanded = false;
    }

    function dismiss(reason = "programmatic") {
        close(reason);
    }

    function toggle(reason = "toggle") {
        expanded ? close(reason) : open(reason);
    }

    property bool _syncingFromExpanded: false
    property bool _syncingFromOverlay: false
    property string _pendingReason: "programmatic"

    onExpandedChanged: {
        if (_syncingFromOverlay) return;
        _syncingFromExpanded = true;
        overlayWindow.visible = expanded;
    }

    LocalComponents.PanelWithOverlay {
        id: overlayWindow
        visible: false
        screen: root.screen
        showOverlay: root.showOverlay
        overlayColor: root.overlayColor
        closeOnBackgroundClick: root.closeOnBackgroundClick
        layerNamespace: (root.overlayNamespace && root.overlayNamespace.length)
            ? root.overlayNamespace
            : "quickshell"

        onBackgroundClicked: root._pendingReason = "background"

        onVisibleChanged: {
            _syncingFromOverlay = true;
            if (_syncingFromExpanded) {
                _syncingFromExpanded = false;
            }
            root.expanded = visible;
            if (visible) {
                root.opened();
            } else {
                root.dismissed(root._pendingReason);
                root._pendingReason = "programmatic";
            }
            _syncingFromOverlay = false;
        }

        Item {
            id: overlayContent
            anchors.fill: parent
        }
    }
}
