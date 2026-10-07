// The tube workbench: `qs -p files/quickshell/greeter/tube-lab.qml`.
//
// A window with one lamp, large, and the handles that matter: which numeral is
// lit, how big the numeral is next to the cage, how thick its discharge is, how
// warm the glow is, how bright the envelope is. Every handle is live — the point
// is to stop rebuilding the world to answer "what if the numeral were 20% wider",
// and to look at the answer while turning the knob.
//
// The numerals come from the pre-rendered sprite set (assets/tubes/), one per
// digit: the sprite carries the glass, the cage, the cathode stack, the lit
// numeral and its discharge, all of it path-traced on the GPU. Drag the slider,
// watch the tube.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs.lock

ShellRoot {
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
implicitWidth: 380

Text {
id: caption
anchors.verticalCenter: parent.verticalCenter
width: 190
text: knob.label + ": " + knob.value.toFixed(2)
color: "#c8ccd6"
font.pixelSize: 14
}

Rectangle {
id: track
anchors {
left: caption.right
leftMargin: 10
right: parent.right
verticalCenter: parent.verticalCenter
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
anchors.fill: parent
anchors.margins: -8
function set(mx) {
const t = Math.max(0, Math.min(1, mx / width));
knob.moved(knob.from + t * (knob.to - knob.from));
}
onPositionChanged: mouse => set(mouse.x)
onPressed: mouse => set(mouse.x)
}
}
}

FloatingWindow {
id: win
implicitWidth: 720
implicitHeight: 900
color: "#14161c"

// ---- the handles -------------------------------------------------
property int digit: 6
property real tubeScale: 1.0      // the whole tube, in the frame
property real glassGloss: 0.35    // the additive glass layer's strength
property real warm: 1.0           // how much the discharge warms its halo
property real envelope: 1.0       // brightness of the hardware itself
property bool showCage: true

// The clock's own tube, not a copy of it: what is tuned here is what the
// login screen shows, down to the shader.
Item {
id: stage
anchors {
top: parent.top
left: parent.left
right: parent.right
bottom: controls.top
bottomMargin: 18
}

Item {
id: tubeHolder
anchors.centerIn: parent
width: Math.min(stage.width * 0.46, stage.height * 0.46) * win.tubeScale
height: width * 2304 / 1120

NixieTube {
anchors.fill: parent
digit: win.digit
numeralSize: Math.round(parent.width * 3.55)
tubeIndex: 0
}
}
}

// ---- the panel ---------------------------------------------------
Column {
id: controls
anchors {
left: parent.left
right: parent.right
bottom: parent.bottom
margins: 22
}
spacing: 10

Row {
spacing: 8
Repeater {
model: 10
Rectangle {
required property int index
width: 44
height: 44
radius: 8
color: win.digit === index ? "#2f6f8f" : "#20242c"
border.color: win.digit === index ? "#63c8e8" : "#333842"
Text {
anchors.centerIn: parent
text: parent.index
color: "#e8eaf0"
font.pixelSize: 22
}
MouseArea {
anchors.fill: parent
onClicked: win.digit = parent.index
}
}
}
}

Knob {
label: "крупнее цифра"
value: win.tubeScale
from: 0.6
to: 1.8
onMoved: win.tubeScale = value
}
Knob {
label: "стекло"
value: win.glassGloss
from: 0.0
to: 1.0
onMoved: win.glassGloss = value
}
Knob {
label: "тепло разряда"
value: win.warm
from: 0.0
to: 2.0
onMoved: win.warm = value
}
Knob {
label: "яркость железa"
value: win.envelope
from: 0.2
to: 1.5
onMoved: win.envelope = value
}
}
}
}
