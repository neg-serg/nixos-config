import QtQuick
import qs

// Action button of the login card: a bare monospace glyph with a soft round halo
// on hover, and nothing else drawn around it.
//
// It deliberately has no frame and no tooltip of its own: a box drawn around a
// glyph adds an edge for no information, and a tooltip box floats over whatever
// is next to it. The action is named by the card's own status line instead
// (LockContent reads `text` through `hovered`), which never covers the field.
Item {
	id: root

	// The glyph shown in the button: "x" powers off, "r" restarts…
	property string glyph: ""
	// What the action does, in words — the status line and nothing else.
	property string text: ""
	property bool hovered: mouse.containsMouse
	signal clicked()

	implicitWidth: Math.round(42 * GreeterTheme.uiScale)
	implicitHeight: Math.round(34 * GreeterTheme.uiScale)

	// Hover halo: a flat accent disc, wide enough to be a target, faint enough
	// not to read as a button face.
	Rectangle {
		anchors.centerIn: parent
		width: Math.round(38 * GreeterTheme.uiScale)
		height: width
		radius: width / 2
		color: GreeterTheme.accentColor
		opacity: (mouse.containsMouse || mouse.pressed) ? 0.14 : 0.0

		Behavior on opacity {
			NumberAnimation {
				duration: GreeterTheme.animFastMs
			}
		}
	}

	Text {
		anchors.centerIn: parent
		text: root.glyph
		color: root.hovered ? GreeterTheme.accentColor : GreeterTheme.textMutedColor
		font.family: GreeterTheme.uiFont
		font.pixelSize: Math.round(17 * GreeterTheme.uiScale)
		font.hintingPreference: Font.PreferFullHinting
		renderType: Text.NativeRendering

		Behavior on color {
			ColorAnimation {
				duration: GreeterTheme.animFastMs
			}
		}
	}

	MouseArea {
		id: mouse
		anchors.fill: parent
		hoverEnabled: true
		cursorShape: Qt.PointingHandCursor
		onClicked: root.clicked()
	}
}
