import QtQuick
import QtQuick.Layouts

// Label + switch row of the nixie settings menu. Modelled on the shell's glass
// toggle: track, sliding disc, no Material chrome. `value` is the input; the
// switch reports the new state through `toggled`.
RowLayout {
    id: control

    property string label: ""
    property bool value: false
    signal toggled(bool value)

    Layout.fillWidth: true
    spacing: 8

    implicitHeight: 26

    Text {
        Layout.fillWidth: true
        text: control.label
        color: "#c8ccd6"
        font.pixelSize: 13
        elide: Text.ElideRight
    }

    Rectangle {
        id: track
        implicitWidth: 36
        implicitHeight: 18
        radius: height / 2
        color: control.value ? "#b063c8e8" : "#2a2f38"

        Rectangle {
            width: parent.height - 4
            height: width
            radius: width / 2
            y: 2
            x: control.value ? parent.width - width - 2 : 2
            color: control.value ? "#f2f6fa" : "#7c8494"
        }

        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.toggled(!control.value)
        }
    }
}
