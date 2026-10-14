import QtQuick
import QtQuick.Layouts

// One labelled slider of the nixie settings menu: a hairline track, an accent
// fill up to the value, and a knob that grows under the cursor. The whole row
// is the target — click to jump, drag to sweep. The value stays an input: the
// menu binds it from GreeterTheme and writes changes back through `moved`,
// which keeps a preset able to move every slider at once.
ColumnLayout {
    id: control

    property string label: ""
    property real value: 0
    property real from: 0
    property real to: 1
    property real step: 0
    property string unit: ""
    signal moved(real value)

    Layout.fillWidth: true
    spacing: 3

    readonly property int _decimals: step > 0 && step < 1
        ? Math.max(0, Math.ceil(-Math.log(step) / Math.LN10)) : 0
    property bool _dragging: false
    property real _dragValue: 0
    readonly property real _shownValue: _dragging ? _dragValue : value
    readonly property real _fraction: (to - from) !== 0
        ? Math.max(0, Math.min(1, (_shownValue - from) / (to - from))) : 0

    implicitHeight: head.implicitHeight + 4 + track.height

    function valueAt(x) {
        var f = Math.max(0, Math.min(1, x / Math.max(1, track.width)));
        var v = from + f * (to - from);
        if (step > 0)
            v = Math.round(v / step) * step;
        v = Math.max(from, Math.min(to, v));
        return Number(v.toFixed(_decimals));
    }

    RowLayout {
        id: head
        Layout.fillWidth: true
        spacing: 8

        Text {
            Layout.fillWidth: true
            text: control.label
            color: "#c8ccd6"
            font.pixelSize: 13
            elide: Text.ElideRight
        }

        Text {
            text: Number(control._shownValue).toFixed(control._decimals) + control.unit
            color: control._dragging ? "#63c8e8" : "#8f98a8"
            font.pixelSize: 12
        }
    }

    Item {
        id: track
        Layout.fillWidth: true
        implicitHeight: 18

        Rectangle {
            id: groove
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: 3
            radius: height / 2
            color: "#262a33"
        }

        Rectangle {
            anchors.left: groove.left
            anchors.verticalCenter: groove.verticalCenter
            height: groove.height
            radius: groove.radius
            width: groove.width * control._fraction
            color: "#63c8e8"
            opacity: control._dragging || area.containsMouse ? 1.0 : 0.85
        }

        Rectangle {
            id: knob
            width: 12
            height: 12
            radius: width / 2
            color: "#63c8e8"
            border.width: 2
            border.color: "#14161c"
            x: Math.max(0, Math.min(track.width - width, groove.width * control._fraction - width / 2))
            y: (track.height - height) / 2
            scale: control._dragging ? 1.15 : (area.containsMouse ? 1.05 : 1.0)
        }

        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => {
                control._dragging = true;
                control._dragValue = control.valueAt(mouse.x);
                control.moved(control._dragValue);
            }
            onPositionChanged: (mouse) => {
                if (!pressed)
                    return;
                control._dragValue = control.valueAt(mouse.x);
                control.moved(control._dragValue);
            }
            onReleased: control._dragging = false
            onCanceled: control._dragging = false
        }
    }
}
