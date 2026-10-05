pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import qs

// The login card — the login screen of the single-compositor session and the
// lock screen of the shell. greeter/login.qml hosts it inside the session-lock
// surface and feeds the keyboard layout through layoutName/toggleLayout; the old
// greeter session (greeter.qml) reuses it with a GreeterContext instead.
//
// Screen layout: wallpaper → scrim → clock (upper third) → glass card with the
// avatar, the user name, the password field and the action row (layout chip on
// the left, screen-off / media / power on the right).
//
// Everything this file changes about the login phase is cosmetic: the state
// machine (LockState, the marker the layer writes, the fade-out to dpms off,
// the password field contents) is untouched.
Item {
id: root
required property LockState state;
property GreeterContext context: null

// Keyboard-layout chip: the login layer owns the compositor's layout (the
// layer is what switches it), so it passes the current name and handles the
// toggle. Empty in greeter mode, where the chip is not shown.
property string layoutName: ""
signal toggleLayout()

// Whose session this is: the greeter context in greeter mode, $USER in the
// single-compositor login (this process runs as the main user already).
readonly property string userName: {
if (root.context && root.context.currentUser)
return root.context.currentUser;
const user = Quickshell.env("USER");
if (user)
return user;
return (Quickshell.env("HOME") || "").split("/").filter(part => part.length > 0).pop() || "";
}
readonly property string monogram: root.userName.length > 0 ? root.userName[0].toUpperCase() : "?"

property string hostName: ""
FileView {
id: hostNameView
path: "/etc/hostname"
blockLoading: false
onLoaded: root.hostName = text().trim()
onLoadFailed: root.hostName = ""
}

// Caps Lock cannot be read from QML, but the kernel exposes one LED per
// keyboard that has it. A password typed in the wrong case is exactly the
// failure this screen must not hide, so the field says it out loud.
property bool capsLock: false
property var capsPaths: []
property var capsValues: ({})
readonly property bool capsKnown: root.capsPaths.length > 0

Process {
id: capsProbe
command: ["sh", "-c", "ls /sys/class/leds/*capslock*/brightness 2> /dev/null || true"]
stdout: SplitParser {
onRead: line => {
const path = line.trim();
if (path.length > 0)
root.capsPaths = root.capsPaths.concat([path]);
}
}
Component.onCompleted: running = true
}

Repeater {
model: root.capsPaths

Item {
id: capsItem
required property string modelData

FileView {
id: capsView
path: capsItem.modelData
watchChanges: true
blockLoading: false
onLoaded: root.noteCaps(capsItem.modelData, capsView.text())
onFileChanged: reload()
}
}
}

function noteCaps(path, value) {
const next = Object.assign({}, root.capsValues);
next[path] = value.trim() === "1";

root.capsValues = next;
root.capsLock = Object.keys(next).some(key => next[key]);
}

// Clock line: the time from SystemClock, the date refreshed once a minute.
SystemClock {
id: clock
precision: SystemClock.Minutes
}

property string dateText: ""
Timer {
interval: 60000
running: true
repeat: true
triggeredOnStart: true
onTriggered: {
const locale = Qt.locale("ru_RU");
const text = locale.toString(new Date(), "dddd, d MMMM");
root.dateText = text.charAt(0).toUpperCase() + text.slice(1);
}
}

// Focus drives the scrim: an unfocused screen (the compositor still starting
// up, another window in front) reads as a background, not as a prompt.
property real focusAnim: root.focusAnimInternal * 0.001
property int focusAnimInternal: Window.active ? 1000 : 0
Behavior on focusAnimInternal { SmoothedAnimation { velocity: 5000 } }

// Entrance and failure feedback for the card.
property real appearProgress: 0
property real shakeOffset: 0
Behavior on appearProgress {
NumberAnimation {
duration: GreeterTheme.appearMs
easing.type: Easing.OutCubic
}
}
SequentialAnimation {
id: shake
NumberAnimation { target: root; property: "shakeOffset"; to: -12; duration: 60 }
NumberAnimation { target: root; property: "shakeOffset"; to: 12; duration: 90 }
NumberAnimation { target: root; property: "shakeOffset"; to: -8; duration: 80 }
NumberAnimation { target: root; property: "shakeOffset"; to: 8; duration: 80 }
NumberAnimation { target: root; property: "shakeOffset"; to: 0; duration: 70 }
}
Component.onCompleted: root.appearProgress = 1
Connections {
target: root.state
function onFailedChanged() {
if (root.state.failed)
shake.restart();
}
}

function powerAction(action) {
power.run(action);
}

Process {
id: power
function run(action) {
command = ["systemctl", action];
running = true;
}
}

// Wake-up on mouse movement while the screen is dark (dpms off), exactly as
// before: the old behaviour is part of what the compositor does at login.
MouseArea {
id: wakeupMouseArea
anchors.fill: parent
hoverEnabled: true

property real startMoveX: 0
property real startMoveY: 0

onPositionChanged: event => {
if (root.state.fadedOut) {
if (root.state.mouseMoved()) {
const xOffset = Math.abs(event.x - wakeupMouseArea.startMoveX);
const yOffset = Math.abs(event.y - wakeupMouseArea.startMoveY);
const distanceSq = (xOffset * xOffset) + (yOffset * yOffset);
if (distanceSq > (100 * 100)) root.state.fadeIn();
} else {
wakeupMouseArea.startMoveX = event.x;
wakeupMouseArea.startMoveY = event.y;
}
}
}
}

Rectangle {
id: scrim
anchors.fill: parent
color: "black"
opacity: 0.24 + (0.26 * (1.0 - root.focusAnim))
}

Item {
id: content
anchors.fill: parent
y: (root.height * 0.55) * root.state.fadeOutMul

ColumnLayout {
id: clockBlock
anchors.horizontalCenter: parent.horizontalCenter
anchors.top: parent.top
anchors.topMargin: root.height * 0.11
spacing: 4

Text {
id: timeText
Layout.alignment: Qt.AlignHCenter

font {
pixelSize: 104
hintingPreference: Font.PreferFullHinting
family: "Iosevka"
}

color: GreeterTheme.textColor
renderType: Text.NativeRendering
style: Text.Outline
styleColor: "#40000000"

text: {
const hours = clock.hours.toString().padStart(2, '0');
const minutes = clock.minutes.toString().padStart(2, '0');
return `${hours}:${minutes}`;
}
}

Text {
id: dateTextItem
Layout.alignment: Qt.AlignHCenter

font {
pixelSize: 18
hintingPreference: Font.PreferFullHinting
family: "Iosevka"
}

color: GreeterTheme.textMutedColor
renderType: Text.NativeRendering
visible: text.length > 0
text: root.dateText
}
}

Item {
id: cardWrapper
anchors.horizontalCenter: parent.horizontalCenter
anchors.verticalCenter: parent.verticalCenter
anchors.horizontalCenterOffset: root.shakeOffset
anchors.verticalCenterOffset: (1.0 - root.appearProgress) * 18
implicitWidth: card.implicitWidth
implicitHeight: card.implicitHeight
opacity: root.appearProgress

Rectangle {
id: card
anchors.fill: parent
implicitWidth: 400
implicitHeight: cardLayout.implicitHeight + 56
radius: 18
color: GreeterTheme.cardColor
border.width: 1
border.color: root.state.failed ? GreeterTheme.dangerColor
: (textBox.activeFocus ? GreeterTheme.accentColor : GreeterTheme.cardOutline)

Behavior on border.color {
ColorAnimation {
duration: GreeterTheme.animMediumMs
}
}

// Soft top highlight — the sheen that reads as glass over a photo.
Rectangle {
anchors.top: parent.top
anchors.left: parent.left
anchors.right: parent.right
anchors.margins: 1
height: parent.radius
radius: parent.radius - 1
gradient: Gradient {
GradientStop { position: 0.0; color: "#1affffff" }
GradientStop { position: 1.0; color: "#00ffffff" }
}
}

ColumnLayout {
id: cardLayout
anchors.fill: parent
anchors.margins: 28
spacing: 0

Item {
id: avatarBlock
Layout.alignment: Qt.AlignHCenter
Layout.bottomMargin: 16
implicitWidth: 88
implicitHeight: 88

Rectangle {
id: avatar
anchors.fill: parent
radius: width / 2
color: GreeterTheme.avatarColor
border.width: 2
border.color: root.state.failed ? GreeterTheme.dangerColor : GreeterTheme.cardOutline

Text {
anchors.centerIn: parent
text: root.monogram
color: GreeterTheme.textColor
font.family: "Iosevka"
font.pixelSize: 38
}
}

Item {
id: spinner
anchors.fill: parent
visible: root.state.isUnlocking

RotationAnimation on rotation {
running: spinner.visible
loops: Animation.Infinite
from: 0
to: 360
duration: 1100
}

Shape {
anchors.fill: parent

ShapePath {
strokeColor: GreeterTheme.accentColor
strokeWidth: 3
fillColor: "transparent"
capStyle: ShapePath.RoundCap

PathAngleArc {
centerX: spinner.width / 2
centerY: spinner.height / 2
radiusX: (spinner.width / 2) - 2
radiusY: (spinner.height / 2) - 2
startAngle: -90
sweepAngle: 280
}
}
}
}
}

Text {
id: nameText
Layout.alignment: Qt.AlignHCenter
text: root.userName
color: GreeterTheme.textColor
font.family: "Iosevka"
font.pixelSize: 22
}

Text {
id: hostText
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 2
text: root.hostName
color: GreeterTheme.textMutedColor
font.family: "Iosevka"
font.pixelSize: 14
visible: text.length > 0
}

Rectangle {
id: field
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 24
implicitWidth: 320
implicitHeight: 48
radius: 12
color: ShellGlobals.interpolateColors(0.55, "#00000000", ShellGlobals.colors.widget)
border.width: 1
border.color: root.state.failed ? GreeterTheme.dangerColor
: (textBox.activeFocus ? GreeterTheme.accentColor : ShellGlobals.colors.widgetOutline)

TextInput {
id: textBox
anchors.fill: parent
anchors.leftMargin: field.radius + 12
anchors.rightMargin: field.radius + 12
focus: true

color: {
if (!textBox.enabled)
return GreeterTheme.textMutedColor;
return root.state.failed ? GreeterTheme.dangerColor : GreeterTheme.textColor;
}

font.pixelSize: 20
font.family: "Iosevka"
horizontalAlignment: TextInput.AlignHCenter
verticalAlignment: TextInput.AlignVCenter
echoMode: TextInput.Password
inputMethodHints: Qt.ImhSensitiveData

cursorVisible: textBox.text != ""
onCursorVisibleChanged: textBox.cursorVisible = (textBox.text != "")

onTextChanged: {
root.state.currentText = textBox.text;
textBox.cursorVisible = (textBox.text != "")
}

Window.onActiveChanged: {
if (Window.active) {
textBox.text = root.state.currentText;
}
}

Connections {
id: stateTextConnection
target: root.state

function onCurrentTextChanged() {
textBox.text = root.state.currentText;
}
}

onAccepted: {
if (textBox.text != "") root.state.tryPasswordUnlock();
}

enabled: !root.state.isUnlocking
}

Text {
id: placeholderText
anchors.fill: textBox
font: textBox.font
color: GreeterTheme.textMutedColor
horizontalAlignment: Text.AlignHCenter
verticalAlignment: Text.AlignVCenter
visible: !textBox.cursorVisible
text: textBox.enabled
? (root.state.fprintAvailable ? "Коснитесь сенсора или введите пароль" : "Введите пароль")
: "Проверка пароля…"
}

// Fingerprint hint: the icon is the one the old field used.
Image {
anchors.right: parent.right
anchors.verticalCenter: parent.verticalCenter
anchors.rightMargin: 12
width: 22
height: 22
visible: root.state.fprintAvailable
source: "root:icons/fingerprint.svg"
sourceSize.width: width
sourceSize.height: height
opacity: 0.6
}
}

Text {
id: capsHint
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 10
text: "Caps Lock включён"
color: GreeterTheme.dangerColor
font.family: "Iosevka"
font.pixelSize: 13
visible: root.capsKnown && root.capsLock
}

Text {
id: errorText
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 12
text: root.state.error
color: GreeterTheme.dangerColor
font.family: "Iosevka"
font.pixelSize: 14
horizontalAlignment: Text.AlignHCenter
visible: root.state.failed && text.length > 0
}

RowLayout {
id: actionRow
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 22
Layout.fillWidth: true
spacing: 8

Rectangle {
id: layoutChip
visible: root.layoutName.length > 0
implicitWidth: layoutChipLabel.implicitWidth + 24
implicitHeight: 40
radius: 10
color: ShellGlobals.interpolateColors(chipHover * 0.001, ShellGlobals.colors.widget, ShellGlobals.colors.widgetActive)
border.width: 1
border.color: ShellGlobals.colors.widgetOutline

property int chipHover: chipMouse.containsMouse || chipMouse.pressed ? 1000 : 0
Behavior on chipHover { SmoothedAnimation { velocity: 10000 } }

Text {
id: layoutChipLabel
anchors.centerIn: parent
text: "раскладка: " + root.layoutName
color: GreeterTheme.textMutedColor
font.family: "Iosevka"
font.pixelSize: 15
}

MouseArea {
id: chipMouse
anchors.fill: parent
hoverEnabled: true
cursorShape: Qt.PointingHandCursor
onClicked: root.toggleLayout()
}
}

Item { Layout.fillWidth: true }

PowerButton {
id: monitorButton
icon: "root:icons/monitor.svg"
onClicked: root.state.fadeOut()
}

PowerButton {
id: mediaPauseButton
icon: "root:icons/pause.svg"
visible: root.state.mediaPlaying
onClicked: root.state.pauseMedia()
}

PowerButton {
id: sleepButton
icon: "root:icons/sleep.svg"
onClicked: root.powerAction("suspend")
}

PowerButton {
id: restartButton
icon: "root:icons/restart.svg"
onClicked: root.powerAction("reboot")
}

PowerButton {
id: powerButton
icon: "root:icons/power.svg"
onClicked: root.powerAction("poweroff")
}
}

// User and session selector — the old greeter session only
// (context is null in the single-compositor login).
RowLayout {
id: selectorRow
Layout.alignment: Qt.AlignHCenter
Layout.topMargin: 16
spacing: 18
visible: root.context !== null

Text {
id: userLabel
color: GreeterTheme.textMutedColor
font.pixelSize: 16
font.family: "Iosevka"
text: root.context ? root.context.currentUser : ""
renderType: Text.NativeRendering

MouseArea {
anchors.fill: parent
cursorShape: root.context && root.context.users.length > 1
? Qt.PointingHandCursor : Qt.ArrowCursor
onClicked: {
if (root.context) root.context.cycleUser();
}
}
}

Text {
color: GreeterTheme.textMutedColor
opacity: 0.4
font.pixelSize: 16
font.family: "Iosevka"
text: "|"
renderType: Text.NativeRendering
}

Text {
id: sessionLabel
color: GreeterTheme.textMutedColor
font.pixelSize: 16
font.family: "Iosevka"
text: root.context ? root.context.currentSessionName : ""
renderType: Text.NativeRendering

MouseArea {
anchors.fill: parent
cursorShape: root.context && root.context.sessions.length > 1
? Qt.PointingHandCursor : Qt.ArrowCursor
onClicked: {
if (root.context) root.context.cycleSession();
}
}
}
}
}
}
}
}

Rectangle {
id: darkenOverlay
anchors.fill: root
color: "black"
opacity: root.state.fadeOutMul
visible: darkenOverlay.opacity != 0
}
}
