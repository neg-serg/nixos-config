import QtQuick
import QtQuick.Layouts
import qs.Settings
import "../../Helpers/Color.js" as Color

// Label + switch row for the Glass panel: the shell's own toggle, because a
// Material checkbox next to the hand-rolled sliders reads as a foreign widget.
RowLayout {
    id: control

    property string label: ""
    property bool checked: false
    signal toggled(bool value)

    Layout.fillWidth: true
    spacing: Math.round(8 * Theme.scale(Screen))

    Text {
        Layout.fillWidth: true
        text: control.label
        color: Theme.textPrimary
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall * Theme.scale(Screen)
    }

    Rectangle {
        id: track
        implicitWidth: Math.round(34 * Theme.scale(Screen))
        implicitHeight: Math.round(18 * Theme.scale(Screen))
        radius: height / 2
        color: control.checked
            ? Color.withAlpha(Theme.accentPrimary, 0.85)
            : Color.withAlpha(Theme.textPrimary, 0.14)
        Behavior on color { ColorAnimation { duration: 140 } }

        Rectangle {
            width: parent.height - Math.round(4 * Theme.scale(Screen))
            height: width
            radius: width / 2
            y: Math.round(2 * Theme.scale(Screen))
            x: control.checked
                ? parent.width - width - Math.round(2 * Theme.scale(Screen))
                : Math.round(2 * Theme.scale(Screen))
            color: Theme.surface
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: control.toggled(!control.checked)
        }
    }
}
