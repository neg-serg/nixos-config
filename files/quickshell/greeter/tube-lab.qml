// The tube workbench: `qs -p files/quickshell/greeter/tube-lab.qml`.
//
// One lamp, large, and the handles that matter, all of them live. It hosts the
// clock's own lock/NixieTube.qml — the same tube the login screen draws — so
// what is tuned here is what the screen will show, not a copy that drifts.
//
// What each handle reaches:
//   digit        which numeral burns (LAB_DIGIT=3 to set it from a shell)
//   tubeScale    the whole tube, in the frame
//   glow         how hard the discharge burns          (NixieTube.glowScale)
//   glassLight   how much light the envelope catches   (glassLightScale)
//   warmth       how much of the discharge lands on the glass (warmthScale)
//   metal        how present the path-traced metal is  (metalScale)
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.lock

ShellRoot {
// A number from the shell, with a default: `Number(Quickshell.env(x) || d)`
// is wrong here — in JavaScript 0 is falsy, so a handle deliberately set to
// zero came back as the default and the knob did nothing.
function envNum(name, dflt) {
const raw = Quickshell.env(name);
return (raw === undefined || raw === null || raw === "") ? dflt : Number(raw);
}

// A labelled slider: the value it is given, the value it is dragged to, and
// the handle's name in plain words. Inline so the file stays self-contained —
// a neighbouring .qml is not a type until the directory is a module.
component Knob: Item {
id: knob
required property string label
required property real value
required property real from
required property real to
signal moved(real value)

implicitHeight: 34
implicitWidth: 400

Text {
id: caption
anchors.verticalCenter: knob.verticalCenter
width: 200
text: knob.label + ": " + knob.value.toFixed(2)
color: "#c8ccd6"
font.pixelSize: 14
}

Rectangle {
id: track
anchors {
left: caption.right
leftMargin: 10
right: knob.right
verticalCenter: knob.verticalCenter
}
height: 6
radius: 3
color: "#262a33"

Rectangle {
width: track.width * Math.max(0, Math.min(1, (knob.value - knob.from) / (knob.to - knob.from)))
height: track.height
radius: track.radius
color: "#63c8e8"
}

MouseArea {
id: grab
anchors.fill: track
anchors.margins: -8
function set(mx) {
const t = Math.max(0, Math.min(1, mx / grab.width));
knob.moved(knob.from + t * (knob.to - knob.from));
}
onPositionChanged: mouse => set(mouse.x)
onPressed: mouse => set(mouse.x)
}
}
}

FloatingWindow {
id: win
implicitWidth: 660
implicitHeight: 980
color: "#14161c"

// Every handle can be set from the shell as well as dragged, which is
// what lets a sweep be scripted: `LAB_GLOW=2 LAB_METAL=0 qs -p ...`.
property int digit: envNum("LAB_DIGIT", 6)
property real tubeScale: envNum("LAB_SCALE", 1.0)
property real glow: envNum("LAB_GLOW", 1.0)
property real glassLight: envNum("LAB_GLASSLIGHT", 1.0)
property real warmth: envNum("LAB_WARMTH", 1.0)
property real metal: envNum("LAB_METAL", 1.0)

// The tube refracts what stands behind it, and the glass in the shader
// samples the back wall. Without one the workbench drew a tube over black
// and everything the login screen shows through the glass was missing:
// the same wallpaper, or a flat card when there is none to be had.
Image {
id: backwall
anchors.fill: parent
source: "file://" + (Quickshell.env("XDG_CACHE_HOME")
|| (Quickshell.env("HOME") + "/.cache")) + "/greeter-wallpaper"
fillMode: Image.PreserveAspectCrop
asynchronous: false
}

// The login screen does not show the wallpaper raw: the card dims it, and
// the tube is judged against that. Without the dimmer the workbench is a
// lamp over a bright picture and every reflection is wrong.
Rectangle {
anchors.fill: parent
color: "#000000"
opacity: 0.55
}

Item {
id: stage
anchors {
top: win.top
left: win.left
right: win.right
bottom: controls.top
bottomMargin: 18
}

Item {
id: tubeHolder
anchors.centerIn: parent
width: Math.min(stage.width * 0.52, stage.height * 0.42) * win.tubeScale
height: tubeHolder.width * 2304 / 1120

NixieTube {
anchors.fill: tubeHolder
digit: win.digit
// The tube's own arithmetic, inverted: the item it wants to
// be is the envelope (0.60 of the numeral) plus its two pads,
// so the numeral's size follows from the room we give it.
numeralSize: Math.round(
(tubeHolder.width - 2 * 16 * GreeterTheme.uiScale) / 0.60)
tubeIndex: 0
backdrop: backwall
glowScale: win.glow
glassLightScale: win.glassLight
warmthScale: win.warmth
metalScale: win.metal
}
}
}

Column {
id: controls
anchors {
left: win.left
right: win.right
bottom: win.bottom
margins: 22
}
spacing: 8

Row {
spacing: 8
Repeater {
model: 10
Rectangle {
id: cell
required property int index
width: 42
height: 42
radius: 8
color: win.digit === index ? "#2f6f8f" : "#20242c"
border.color: win.digit === index ? "#63c8e8" : "#333842"
Text {
anchors.centerIn: cell
text: cell.index
color: "#e8eaf0"
font.pixelSize: 20
}
MouseArea {
anchors.fill: cell
onClicked: win.digit = cell.index
}
}
}
}

Knob {
label: "разряд ярче"
value: win.glow
from: 0.0
to: 2.5
onMoved: value => win.glow = value
}
Knob {
label: "стекло светлее"
value: win.glassLight
from: 0.0
to: 2.5
onMoved: value => win.glassLight = value
}
Knob {
label: "тепло на стекле"
value: win.warmth
from: 0.0
to: 2.5
onMoved: value => win.warmth = value
}
Knob {
label: "металл виднее"
value: win.metal
from: 0.0
to: 1.5
onMoved: value => win.metal = value
}
Knob {
label: "крупнее трубка"
value: win.tubeScale
from: 0.5
to: 1.8
onMoved: value => win.tubeScale = value
}
}
}
}
