import QtQuick
import qs

// Small glass button for the login card's action row (screen off, media pause,
// suspend, restart, power off). Same hover interpolation, border and radius
// language as the rest of the lock UI, sized for a row inside the card.
Item {
id: root

property string icon: ""
signal clicked()

implicitWidth: 40
implicitHeight: 40

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

MouseArea {
id: mouse
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: root.clicked()
}
}
