import QtQuick
import QtQuick.Layouts
import qs.Settings
import "../../Helpers/Color.js" as Color

// Slider for the Glass panel.
//
// QtQuick.Controls' default slider drags a Material groove and handle into a
// shell that is otherwise frameless and flat, and it reads as a foreign widget in
// the middle of the panel. This is the shell's own: a hairline track, an accent
// fill up to the value, and a small knob that grows under the cursor. The whole
// row is the target — click to jump, drag to sweep.
//
// `value` stays an input: the caller binds it (and gets changes through `moved`),
// so a preset button can move every slider at once without a binding being
// destroyed by the drag.
Item {
    id: control

    property string label: ""
    property real from: 0
    property real to: 1
    property real stepSize: 0
    property int decimals: 2
    property real value: 0
    signal moved(real newValue)

    readonly property real _scale: Theme.scale(Screen)
    readonly property int _trackHeight: Math.max(3, Math.round(4 * _scale))
    readonly property int _knobSize: Math.round(11 * _scale)

    // While dragging, the knob follows the cursor even though the bound `value`
    // only catches up when the caller writes it back.
    property bool dragging: false
    property real dragValue: 0
    readonly property real shownValue: dragging ? dragValue : value
    readonly property real fraction: (to - from) !== 0
        ? Math.max(0, Math.min(1, (shownValue - from) / (to - from))) : 0

    implicitHeight: head.implicitHeight + Math.round(4 * _scale) + _knobSize

    function valueAt(x) {
        var f = Math.max(0, Math.min(1, x / Math.max(1, track.width)));
        var v = from + f * (to - from);
        if (stepSize > 0) v = Math.round(v / stepSize) * stepSize;
        return Math.max(from, Math.min(to, v));
    }

    RowLayout {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Math.round(6 * control._scale)

        Text {
            Layout.fillWidth: true
            text: control.label
            color: Theme.textPrimary
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * control._scale)
        }

        Text {
            text: Number(control.shownValue).toFixed(control.decimals)
            color: control.dragging
                ? Theme.accentPrimary
                : Color.withAlpha(Theme.textPrimary, 0.65)
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(Theme.fontSizeSmall * control._scale)
            Behavior on color { ColorAnimation { duration: 120 } }
        }
    }

    // Track, with the fill and the knob riding on it.
    Item {
        id: track
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: control._knobSize

        Rectangle {
            id: groove
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: control._trackHeight
            radius: height / 2
            color: Color.withAlpha(Theme.textPrimary, 0.12)
        }

        Rectangle {
            id: fill
            anchors.left: groove.left
            anchors.verticalCenter: groove.verticalCenter
            height: groove.height
            radius: groove.radius
            width: groove.width * control.fraction
            color: Theme.accentPrimary
            opacity: control.dragging || area.containsMouse ? 1 : 0.85
            Behavior on opacity { NumberAnimation { duration: 120 } }

            // Bloom under the filled part, the same trick the seek line uses.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.round(control._knobSize * 0.9)
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Color.withAlpha(Theme.accentPrimary, 0.0) }
                    GradientStop { position: 1.0; color: Color.withAlpha(Theme.accentPrimary, 0.28) }
                }
                z: -1
            }
        }

        Rectangle {
            id: knob
            width: control._knobSize
            height: control._knobSize
            radius: width / 2
            color: Theme.accentPrimary
            border.width: Math.max(1, Math.round(1 * control._scale))
            border.color: Color.withAlpha(Theme.surface, 0.7)
            x: Math.max(0, Math.min(track.width - width, fill.width - width / 2))
            scale: control.dragging ? 1.15 : (area.containsMouse ? 1.08 : 1)
            Behavior on x { enabled: !control.dragging; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }

        MouseArea {
            id: area
            anchors.fill: parent
            anchors.margins: -Math.round(4 * control._scale)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPressed: (mouse) => {
                control.dragging = true;
                control.dragValue = control.valueAt(mouse.x);
                control.moved(control.dragValue);
            }
            onPositionChanged: (mouse) => {
                if (!pressed) return;
                control.dragValue = control.valueAt(mouse.x);
                control.moved(control.dragValue);
            }
            onReleased: control.dragging = false
            onCanceled: control.dragging = false
        }
    }
}
