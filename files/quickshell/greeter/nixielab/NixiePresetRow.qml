pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// The preset strip of the nixie menu: one button per preset, wrapping when the
// panel is narrow. Each preset is { text, values } — values is a map of token
// names to values — or { text, reset: true } for the reset entry.
ColumnLayout {
    id: control

    property var presets: []
    signal chosen(var preset)

    Layout.fillWidth: true
    spacing: 6

    Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: control.presets

            delegate: Rectangle {
                id: button
                required property var modelData

                implicitWidth: label.implicitWidth + 20
                implicitHeight: 26
                radius: 6
                color: buttonArea.containsMouse ? "#2a3f4d" : "#1b1f27"
                border.width: 1
                border.color: buttonArea.containsMouse ? "#63c8e8" : "#333842"

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: button.modelData.text
                    color: "#d5dae3"
                    font.pixelSize: 12
                }

                MouseArea {
                    id: buttonArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: control.chosen(button.modelData)
                }
            }
        }
    }
}
