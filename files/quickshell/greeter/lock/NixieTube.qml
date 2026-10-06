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

// The wallpaper item (login.qml/preview.qml). Null on a host without one: the
// shader then draws the tube over nothing, which is what cage mode needs.
property Item backdrop: null

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
numeralTexture.scheduleUpdate();
return;
}
root.strikesLeft -= 1;
// The gas strikes unevenly: some frames almost full, some almost out.
root.ignition = 0.20 + 0.80 * Math.random();
strikeTimer.restart();
}
}

onDigitChanged: root.strike()
Component.onCompleted: root.strike()

// The tube's own rect, plus the room the bloom needs, in the backdrop's
// coordinates. root.width/height are read on purpose: they are the dependency
// that re-evaluates the origin when the surface (or the clock) resizes.
readonly property point sampleOrigin: {
const w = root.width;
const h = root.height;
if (root.backdrop === null || w <= 0 || h <= 0)
return Qt.point(0, 0);
return root.mapToItem(root.backdrop, -root.pad, -root.pad);
}

ShaderEffectSource {
id: numeralTexture
// Sampler for the shader must be called `source`.
sourceItem: root.backdrop
visible: false
// The patch the glass will bend: the tube's rect, one pad wider on every
// side. live only while the tube is striking — that is also when the layout
// settles at startup, so the patch is taken again exactly when it has to be.
live: root.ignition < 0.999
smooth: true
sourceRect: Qt.rect(root.sampleOrigin.x, root.sampleOrigin.y,
root.width + 2 * root.pad, root.height + 2 * root.pad)
}

ShaderEffect {
id: tube
anchors.fill: parent

property Item source: numeralTexture
property vector2d pSize: Qt.vector2d(tube.width, tube.height)
property vector2d pBackdrop: Qt.vector2d(tube.width + 2 * root.pad, tube.height + 2 * root.pad)
property real pInset: root.pad
property real pRadius: root.glassWidth * 0.5
property real pBase: root.bulb ? 0 : Math.round(root.glassHeight * 0.17)
property real pGlow: (root.bulb || root.digit >= 0) ? GreeterTheme.nixieGlow : 0.0
property real pDigit: root.bulb ? -1 : root.digit
property real pBulb: root.bulb ? 1 : 0
property real pWire: GreeterTheme.nixieWire
property real pStack: root.bulb ? 0 : GreeterTheme.nixieStack
property real pHighlight: GreeterTheme.nixieHighlight
property real pWarmth: GreeterTheme.nixieWarmth
property real pFlicker: root.ignition
property color pCore: GreeterTheme.nixieCoreColor
property color pHalo: GreeterTheme.nixieGlowColor
property color pGlass: GreeterTheme.nixieGlassColor
property color pCathode: GreeterTheme.nixieCathodeColor

fragmentShader: Qt.resolvedUrl("../shaders/nixie.frag.qsb")
}
}
