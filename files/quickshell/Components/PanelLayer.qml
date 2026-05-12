import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root
    // Allow callers to declare visual children directly while providing a
    // convenient handle to the underlying content item.
    Item {
        id: layerContent
        anchors.fill: parent
    }

    default property alias layerData: layerContent.data
    property alias layerItem: layerContent
}
