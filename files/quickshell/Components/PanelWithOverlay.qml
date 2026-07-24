import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Settings
import qs.Services
import "../Helpers/Utils.js" as Utils

PanelWindow {
    id: outerPanel
    // Dimming overlay removed - background is always transparent
    property int topMargin: Math.round(Theme.panelModuleHeight * Theme.scale(screen))
    property int bottomMargin: Math.round(Theme.panelModuleHeight * Theme.scale(screen))
    property string layerNamespace: "quickshell"
    WlrLayershell.namespace: layerNamespace
    property bool closeOnBackgroundClick: true
    signal backgroundClicked()

    // Auto-dismiss timer: closes overlay after N ms of inactivity.
    // Pauses while mouse hovers over it; resets on any interaction.
    property int autoDismissMs: Theme.sidePanelPopupAutoHideMs
    property int _dismissRemainingMs: autoDismissMs
    property real _dismissStartedAtMs: 0

    function dismiss() {
        visible = false;
    }

    function show() {
        visible = true;
    }

    onVisibleChanged: {
        if (visible) {
            OverlayManager.registerOverlay(outerPanel);
            _startAutoDismiss();
        } else {
            OverlayManager.unregisterOverlay(outerPanel);
            _cancelAutoDismiss();
        }
    }

    function _startAutoDismiss(ms) {
        _dismissRemainingMs = (ms !== undefined && ms !== null) ? ms : autoDismissMs;
        _dismissStartedAtMs = Date.now();
        dismissTimer.interval = _dismissRemainingMs;
        dismissTimer.restart();
    }

    function _pauseAutoDismiss() {
        if (!dismissTimer.running) return;
        var elapsed = Utils.clamp(Date.now() - _dismissStartedAtMs, 0, 3600000);
        _dismissRemainingMs = Utils.clamp(_dismissRemainingMs - elapsed, 0, 3600000);
        dismissTimer.stop();
    }

    function _resumeAutoDismiss() {
        if (_dismissRemainingMs <= 0) { dismiss(); return; }
        _dismissStartedAtMs = Date.now();
        dismissTimer.interval = _dismissRemainingMs;
        dismissTimer.restart();
    }

    function _cancelAutoDismiss() {
        dismissTimer.stop();
        _dismissRemainingMs = autoDismissMs;
    }

    Timer {
        id: dismissTimer
        repeat: false
        onTriggered: {
            if (visible && !contentHover.hovered) {
                outerPanel.dismiss();
            }
        }
    }

    implicitWidth: screen.width
    implicitHeight: screen.height
    color: "transparent"
    visible: false
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    screen: (typeof modelData !== 'undefined' ? modelData : null)
    anchors.top: true
    anchors.left: true
    anchors.right: true
    anchors.bottom: true
    margins.top: 0
    margins.bottom: bottomMargin

    // Keyboard dismissal: k, d, Escape
    FocusScope {
        anchors.fill: parent
        focus: true
        Keys.onPressed: function(event) {
            if (event.key === Qt.Key_K || event.key === Qt.Key_D || event.key === Qt.Key_Escape) {
                event.accepted = true;
                outerPanel.dismiss();
            }
        }
    }

    // Hover over content pauses auto-dismiss
    HoverHandler {
        id: contentHover
        onHoveredChanged: {
            if (contentHover.hovered) {
                outerPanel._pauseAutoDismiss();
            } else {
                outerPanel._resumeAutoDismiss();
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: outerPanel.closeOnBackgroundClick
        acceptedButtons: Qt.AllButtons
        onClicked: {
            outerPanel.backgroundClicked();
            outerPanel.dismiss();
        }
    }
}
