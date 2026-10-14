pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

// A named choice: the label, then one pill per option. Used for the shader
// quality tier, whose options are strings ("full" | "balanced" | "lite").
ColumnLayout {
    id: control

    property string label: ""
    property var options: []
    property var value: undefined
    signal chosen(var value)

    Layout.fillWidth: true
    spacing: 4

    Text {
        Layout.fillWidth: true
        text: control.label
        color: "#c8ccd6"
        font.pixelSize: 13
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
            model: control.options

            delegate: Rectangle {
                id: pill
                required property var modelData
                readonly property bool active: control.value === modelData.value

                implicitWidth: pillText.implicitWidth + 18
                implicitHeight: 24
                radius: 6
                color: pill.active ? "#3f6f8f" : (pillArea.containsMouse ? "#232833" : "#1b1f27")
                border.width: 1
                border.color: pill.active ? "#63c8e8" : "#333842"

                Text {
                    id: pillText
                    anchors.centerIn: parent
                    text: pill.modelData.text
                    color: pill.active ? "#e8eaf0" : "#a8b0bd"
                    font.pixelSize: 12
                }

                MouseArea {
                    id: pillArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: control.chosen(pill.modelData.value)
                }
            }
        }

        Item {
            Layout.fillWidth: true
        }
    }
}
