import QtQuick
import qs

// Action button of the login card: a hard-edged box with a monospace glyph, the
// way a terminal draws a button. No rounding and no pictures — the glyph and its
// tooltip say what it does, and the box lights up on hover.
Item {
id: root

// Two-or-three character code shown in the box: "x" powers off, "r" restarts…
property string glyph: ""
property string text: ""
signal clicked()

implicitWidth: Math.round(46 * GreeterTheme.uiScale)
implicitHeight: Math.round(30 * GreeterTheme.uiScale)

Rectangle {
id: face
anchors.fill: parent
radius: GreeterTheme.buttonRadius
color: ShellGlobals.interpolateColors(hoverProgress * 0.001, ShellGlobals.colors.widget, ShellGlobals.colors.widgetActive)
border.width: 1
border.color: ShellGlobals.colors.widgetOutline

property int hoverProgress: mouse.containsMouse || mouse.pressed ? 1000 : 0
Behavior on hoverProgress { SmoothedAnimation { velocity: 10000 } }

Text {
anchors.centerIn: parent
text: root.glyph
color: GreeterTheme.textColor
font.family: GreeterTheme.uiFont
font.pixelSize: Math.round(16 * GreeterTheme.uiScale)
font.hintingPreference: Font.PreferFullHinting
renderType: Text.NativeRendering
}
}

Rectangle {
id: tooltip
anchors.horizontalCenter: parent.horizontalCenter
anchors.bottom: parent.top
anchors.bottomMargin: 10
implicitWidth: tooltipLabel.implicitWidth + 18
implicitHeight: Math.round(26 * GreeterTheme.uiScale)
radius: 0
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
font.family: GreeterTheme.uiFont
font.pixelSize: Math.round(15 * GreeterTheme.uiScale)
font.hintingPreference: Font.PreferFullHinting
renderType: Text.NativeRendering
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
