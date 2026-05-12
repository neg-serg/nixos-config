import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Settings

PanelWindow {
    id: outerPanel
    // Dimming overlay removed - background is always transparent
    property int topMargin: Math.round(Theme.panelModuleHeight * Theme.scale(screen))
    property int bottomMargin: Math.round(Theme.panelModuleHeight * Theme.scale(screen))
    property string layerNamespace: "quickshell"
    WlrLayershell.namespace: layerNamespace
    property bool closeOnBackgroundClick: true
    signal backgroundClicked()
    
    function dismiss() {
        visible = false;
    }

    function show() {
        visible = true;
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
