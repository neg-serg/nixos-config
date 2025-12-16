import QtQuick
import qs.Settings
import "." as LocalComponents

/*
 * Square icon slot for connectivity capsules. Wraps BaselineAlignedIcon so network/VPN
 * modules can share identical sizing, padding, and baseline tuning driven by Theme tokens.
 */
Item {
    id: slot

    // Toggle visibility without breaking layout bindings
    property bool active: true
    property int box: 0
    property bool square: true
    property string mode: "material" // material, text, svg
    property string icon: ""
    property string text: ""
    property bool rounded: false
    property color color: Theme.textPrimary
    property var screen: null
    property var labelRef: null
    property var alignTarget: null
    property real scaleToken: Theme.networkCapsuleIconScale
    property int baselineToken: Theme.networkCapsuleIconBaselineOffset
    property string alignModeToken: Theme.networkCapsuleIconAlignMode
    property int padding: Theme.networkCapsuleIconPadding
    property int outerHorizontalMargin: Theme.networkCapsuleIconHorizontalMargin
    property bool debugBorderVisible: false
    property color debugBorderColor: "#ff0000"
    property real debugBorderWidth: 1

    visible: active
    readonly property int _box: Math.max(0, box)
    readonly property int _outerMargin: Math.max(0, outerHorizontalMargin)
    implicitWidth: (square ? _box : glyph.implicitWidth) + _outerMargin * 2
    implicitHeight: square ? _box : glyph.implicitHeight
    width: active ? implicitWidth : 0
    height: square ? implicitHeight : glyph.implicitHeight

    Item {
        id: glyphFrame
        anchors {
            top: parent.top
            bottom: parent.bottom
            left: parent.left
            right: parent.right
            leftMargin: _outerMargin
            rightMargin: _outerMargin
        }
    }

    LocalComponents.BaselineAlignedIcon {
        id: glyph
        anchors.centerIn: glyphFrame
        mode: slot.mode
        icon: slot.icon
        text: slot.text
        rounded: slot.rounded
        color: slot.color
        screen: slot.screen
        labelRef: slot.labelRef
        alignTarget: slot.alignTarget
        alignMode: slot.alignModeToken
        padding: Math.max(0, slot.padding)
        scaleToken: slot.scaleToken
        baselineOffsetToken: slot.baselineToken - glyph.baselineVisualDelta
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.color: slot.debugBorderColor
        border.width: slot.debugBorderVisible ? Math.max(1, slot.debugBorderWidth) : 0
        radius: slot.square ? slot.height / 2 : Math.min(slot.width, slot.height) / 2
        visible: slot.debugBorderVisible && border.width > 0
    }
}
