import QtQuick
import QtQuick.Layouts
import "NixieLab.js" as Lab

// A colour token of the nixie menu: swatch, #AARRGGBB entry and, for tokens
// whose alpha is a strength (tint, glass), an alpha row. The entry accepts
// "#RRGGBB" and "#AARRGGBB" (the leading hash optional); an unparsable value
// is rejected and the field snaps back to the real colour. `alpha` is false
// for opaque tokens (glow, cathode), where the alpha line is hidden and the
// colour is forced opaque on every pick.
ColumnLayout {
    id: control

    property string label: ""
    property color value: "#00000000"
    property bool alpha: true
    signal picked(color value)

    Layout.fillWidth: true
    spacing: 4

    property bool _invalid: false

    function hexText() {
        return Lab.argbFromComponents(control.value.r, control.value.g,
                                      control.value.b, control.value.a);
    }

    function commit(entered) {
        var c = Lab.componentsFromArgb(entered);
        if (c === null) {
            control._invalid = true;
            hexInput.text = control.hexText();
            return;
        }
        control._invalid = false;
        hexInput.text = Lab.argbFromComponents(c.r, c.g, c.b, control.alpha ? c.a : 1.0);
        control.picked(Qt.rgba(c.r, c.g, c.b, control.alpha ? c.a : 1.0));
    }

    function setAlpha(a) {
        control.picked(Qt.rgba(control.value.r, control.value.g, control.value.b,
                               control.alpha ? Math.max(0, Math.min(1, a)) : 1.0));
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: control.label
            color: "#c8ccd6"
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Rectangle {
            implicitWidth: 22
            implicitHeight: 22
            radius: 4
            color: control.value
            border.width: 1
            border.color: "#4a505c"
        }

        Rectangle {
            implicitWidth: 104
            implicitHeight: 24
            radius: 4
            color: "#0d0f13"
            border.width: 1
            border.color: control._invalid ? "#e0736b" : "#333842"

            TextInput {
                id: hexInput
                anchors.fill: parent
                anchors.margins: 5
                verticalAlignment: TextInput.AlignVCenter
                color: "#e8eaf0"
                font.pixelSize: 12
                font.family: "monospace"
                selectByMouse: true
                clip: true
                inputMethodHints: Qt.ImhNoPredictiveText
                onAccepted: control.commit(hexInput.text)
                onEditingFinished: control.commit(hexInput.text)

                Connections {
                    target: control
                    function onValueChanged() {
                        if (!hexInput.activeFocus)
                            hexInput.text = control.hexText();
                    }
                }

                Component.onCompleted: hexInput.text = control.hexText()
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        visible: control.alpha

        Text {
            text: "Альфа"
            color: "#8f98a8"
            font.pixelSize: 12
        }

        Item {
            id: alphaTrack
            Layout.fillWidth: true
            implicitHeight: 18

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 3
                radius: height / 2
                color: "#262a33"
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                height: 3
                radius: height / 2
                width: parent.width * Math.max(0, Math.min(1, control.value.a))
                color: "#63c8e8"
            }

            Rectangle {
                width: 10
                height: 10
                radius: width / 2
                color: "#63c8e8"
                x: Math.max(0, Math.min(alphaTrack.width - width,
                                      alphaTrack.width * Math.max(0, Math.min(1, control.value.a)) - width / 2))
                y: (alphaTrack.height - height) / 2
            }

            MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onPressed: (mouse) => control.setAlpha(mouse.x / alphaTrack.width)
                onPositionChanged: (mouse) => {
                    if (pressed)
                        control.setAlpha(mouse.x / alphaTrack.width);
                }
            }
        }

        Text {
            text: Math.round(control.value.a * 100) + "%"
            color: "#8f98a8"
            font.pixelSize: 12
        }
    }
}
