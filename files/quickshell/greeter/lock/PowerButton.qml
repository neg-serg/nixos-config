import QtQuick
import qs

// Small glass button for the login card's action row (screen off, media pause,
// suspend, restart, power off). Same hover interpolation, border and radius
// language as the rest of the lock UI, sized for a row inside the card.
Item {
	id: root

	property string icon: ""
	property string text: ""
	signal clicked()

	implicitWidth: 44
	implicitHeight: 44

	Rectangle {
		id: face
		anchors.fill: parent
		radius: 10
		color: ShellGlobals.interpolateColors(hoverProgress * 0.001, ShellGlobals.colors.widget, ShellGlobals.colors.widgetActive)
		border.width: 1
		border.color: ShellGlobals.colors.widgetOutline

		property int hoverProgress: mouse.containsMouse || mouse.pressed ? 1000 : 0
		Behavior on hoverProgress { SmoothedAnimation { velocity: 10000 } }

		Image {
			anchors.fill: parent
			anchors.margins: 10
			opacity: 0.85
			source: root.icon
			sourceSize.width: width
			sourceSize.height: height
		}
	}

	// Tooltip above the button: the three power glyphs are near-identical at this
	// size, and "which one powers off" is not a thing to learn by trying.
	Rectangle {
		id: tooltip
		anchors.horizontalCenter: parent.horizontalCenter
		anchors.bottom: parent.top
		anchors.bottomMargin: 10
		implicitWidth: tooltipLabel.implicitWidth + 22
		implicitHeight: 30
		radius: 8
		color: "#e60f141c"
		border.width: 1
		border.color: GreeterTheme.cardOutline
		opacity: mouse.containsMouse && root.text.length > 0 ? 1.0 : 0.0
		visible: opacity > 0

		Behavior on opacity {
			NumberAnimation {
				duration: GreeterTheme.animFastMs
			}
		}

		Text {
			id: tooltipLabel
			anchors.centerIn: parent
			text: root.text
			color: GreeterTheme.textColor
			font.family: "Iosevka"
			font.pixelSize: 15
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
