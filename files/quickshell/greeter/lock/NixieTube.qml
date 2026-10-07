pragma ComponentBehavior: Bound
import QtQuick
import qs

// One gas-discharge tube of the login clock (lock/NixieClock.qml).
//
// The tube is a single shader pass and nothing else: the glass, the numerals, the
// cathode stack, the metal base and the discharge all live in
// shaders/nixie.frag. There is no font, no texture of its own and no second layer
// — a digit change is one uniform, and a struck tube has nothing to redraw.
//
// What it does take from the screen is the wallpaper patch behind it: the glass
// refracts the picture and the glow lands on it, so the tube is a surface in the
// login screen and not a picture of a tube pasted on it.
Item {
id: root

// The lit cathode, 0..9. -1 leaves the tube dark: a real clock has no cathode
// for the tens of hours before 10:00.
property int digit: -1
// The colon: the same envelope, lit as one round bulb.
property bool bulb: false
// Four tubes striking in lockstep read as an animation; the index keeps their
// flicker apart.
property int tubeIndex: 0

// The numeral's size in px — the clock scales it by the theme's uiScale.
property real numeralSize: 92
readonly property real uiScale: GreeterTheme.uiScale

// The envelope. Thin and tall, as a nixie is: a cylinder with a domed top,
// with the metal base covering its foot.
readonly property real glassWidth: root.bulb ? Math.round(root.numeralSize * 0.24) : Math.round(root.numeralSize * 0.60)
readonly property real glassHeight: root.bulb ? root.glassWidth : Math.round(root.numeralSize * 1.60)
// Room around the envelope for the bloom and for the refracted wallpaper, which
// the lens pulls in by a good part of the radius.
readonly property real pad: Math.round(16 * root.uiScale)

implicitWidth: root.glassWidth + root.pad * 2
implicitHeight: root.glassHeight + root.pad * 2

// Discharge of the current digit: 1 while it burns steadily, and a stutter
// between 0 and 1 for the frames after it changed.
property real ignition: 1.0
property int strikesLeft: 0

// A nixie does not cross-fade. On a digit change it stutters for a few frames
// and then holds — and nothing animates at all once it has struck, which is
// what keeps a still login screen still.
function strike() {
root.strikesLeft = 5 + (root.tubeIndex % 3);
root.ignition = 0.0;
strikeTimer.restart();
}

Timer {
id: strikeTimer
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + ((root.tubeIndex * 11) % 23)

onTriggered: {
if (root.strikesLeft <= 0) {
root.ignition = 1.0;
return;
}
root.strikesLeft -= 1;
// The gas strikes unevenly: some frames almost out, the last ones all but
// settled. The floor used to sit at a fifth of full, and the strike read as a
// dim instead of a stutter.
root.ignition = 0.08 + 0.92 * Math.random() * Math.random();
strikeTimer.restart();
}
}

onDigitChanged: root.strike()
Component.onCompleted: root.strike()



// The whole tube — glass, anode cage, cathode stack, crimped collar and the
// discharge of the lit numeral — is a pre-rendered sprite, one per digit. The
// hardware never changes, and offline there is room for real optics: the sprite
// is a path-traced render, and the discharge in it was traced with it, so a tube
// arrives lit rather than being drawn on top of afterwards.
//
// The hardware is a path-traced sprite; the numeral is drawn by the shader on
// top of it. Ten sprites, one per digit, each with its own numeral burned in,
// were tried and thrown away: a numeral bent out of 0.9 mm wire at the size this
// clock is drawn at turns into a tangle with the cage and the nine dark cathodes
// it hangs among, and it stops being a digit. A drawn glyph stays a glyph at any
// size, and the sprite keeps what a glyph cannot have — real glass, real cage.
Image {
anchors.fill: parent
source: "../assets/nixie-tube.png"
smooth: true
visible: !root.bulb
}

// The discharge cannot be re-shaped any more, but it can still stutter: a nixie
// that changes digit strikes unevenly for a few frames. The strike timer drives
// `ignition`, and the sprite fades with it — a lit tube that never quite goes out.


// The discharge shader is retired: the sprites carry the glow now. It stays in
// the tree switched off so the flicker wiring keeps working, and so that going
// back to a drawn numeral is a one-line change.
ShaderEffect {
id: tube
anchors.fill: parent

property vector2d pSize: Qt.vector2d(tube.width, tube.height)
property real pInset: root.pad
property real pBase: root.bulb ? 0 : Math.round(root.glassHeight * 0.17)
property real pGlow: (root.bulb || root.digit >= 0) ? GreeterTheme.nixieGlow : 0.0
property real pDigit: root.bulb ? -1 : root.digit
property real pBulb: root.bulb ? 1 : 0
property real pWire: GreeterTheme.nixieWire
property real pWarmth: GreeterTheme.nixieWarmth
property real pFlicker: root.ignition
property color pCore: GreeterTheme.nixieCoreColor
property color pHalo: GreeterTheme.nixieGlowColor

fragmentShader: Qt.resolvedUrl("../shaders/nixie.frag.qsb")
}


// The glass goes on top of the metal, additively: its reflections are light on
// the pane, and light does not hide the numeral behind it the way an opaque
// sprite would. (The sprite's alpha carries the metal only.)
ShaderEffect {
anchors.fill: parent
visible: !root.bulb
property Item source: glassLayer
// The sprite now carries the lit numeral and its own reflections; the glass layer
// on top of it only has to add what a pane adds, and at 0.75 it added enough to
// clip the numeral to white.
property real pStrength: 0.35
fragmentShader: Qt.resolvedUrl("../shaders/nixie_glass.frag.qsb")
}

Image {
id: glassLayer
visible: false
width: parent.width
height: parent.height
source: "../assets/nixie-glass.png"
smooth: true
}
}