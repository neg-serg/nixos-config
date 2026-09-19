import QtQuick
import "." as LocalComponents

LocalComponents.WidgetCapsule {
    id: root

    property bool interactive: true
    enabled: true
    property bool checkable: false
    property bool checked: false
    property bool autoExclusive: false
    property alias cursorShape: hover.cursorShape
    signal clicked()
    signal pressAndHold()
    signal toggled(bool checked)

    // Activation point. `false` (default) keeps classic button semantics: the tap
    // fires on release *inside* the capsule, anything else cancels it. `true` fires
    // on press instead, which is what capsules need whose neighbours slide in on
    // hover: the reveal moves the capsule out from under the pointer, and Qt's
    // TapHandler never emits a tap unless the release lands inside the item — no
    // gesturePolicy changes that (see qquicktaphandler.cpp, setPressed()).
    property bool activateOnPress: false

    // Single place for the activation payload, shared by both handlers below.
    function activate(): void {
        if (root.checkable) {
            root.checked = root.autoExclusive ? true : !root.checked;
            root.toggled(root.checked);
        }
        root.clicked();
    }

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
        enabled: root.interactive && root.enabled && !root.activateOnPress
        onTapped: root.activate()
        onLongPressed: root.pressAndHold()
    }

    TapHandler {
        id: tapOnPress
        acceptedButtons: Qt.LeftButton
        enabled: root.interactive && root.enabled && root.activateOnPress
        onPressedChanged: if (pressed) root.activate()
    }
}
