import QtQuick
import "." as LocalComponents

LocalComponents.WidgetCapsule {
    id: root

    property bool interactive: true
    property bool enabled: true
    property bool checkable: false
    property bool checked: false
    property bool autoExclusive: false
    property alias cursorShape: hover.cursorShape
    signal clicked()
    signal pressAndHold()
    signal toggled(bool checked)

    hoverEnabled: interactive && enabled

    HoverHandler {
        id: hover
        enabled: root.interactive && root.enabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchPad
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        enabled: root.interactive && root.enabled
        onTapped: {
            if (root.checkable) {
                root.checked = root.autoExclusive ? true : !root.checked;
                root.toggled(root.checked);
            }
            root.clicked()
        }
        onLongPressed: root.pressAndHold()
    }
}
