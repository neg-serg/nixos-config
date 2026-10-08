pragma ComponentBehavior: Bound
import QtQuick
import qs

// The four tubes of the login clock, drawn in one pass (shaders/nixie.frag).
//
// They are one object on purpose. A tube's item is finite and its light is not,
// so four items put four rectangles of lamp-lit wallpaper around the clock and
// left a step where one met the next. Here the item is the whole row, the
// shader loops over its four tubes, and their light adds up into one lamp —
// which is also what the eye expects of four tubes on one desk.
Item {
id: root

property int hours: 0
property int minutes: 0
// The wallpaper the glass bends: handed straight down to the row's patch.
property Item backdrop: null

readonly property real uiScale: GreeterTheme.uiScale
// The numeral size: the tubes and every gap between them are built from it.
readonly property real numeralSize: Math.round(GreeterTheme.nixieDigitSize * root.uiScale)
// The room a tube keeps around its glass for the bloom (the theme's
// nixieTubeMargin): the shader is told it as the tube's own margin, and the
// item below is the row plus one of them on each side.
readonly property real tubeMargin: Math.round(GreeterTheme.nixieTubeMargin * root.uiScale)
// What the eye sees between two glasses, and between the two pairs. The
// colon is not drawn — the clock is four tubes — so the break between the
// hours and the minutes is only this much wider than a tube's own gap.
readonly property real tubeGap: Math.round(root.numeralSize * 0.055)
readonly property real pairGap: Math.round(root.numeralSize * 0.20)

// The tube's own item, straight off the drawing: 21 x 35 mm at the numeral's
// scale (numeralSize is 18 mm of the sheet), plus the margin for the bloom.
readonly property real mmPerPx: root.numeralSize / 18.0
readonly property real glassWidth: Math.max(2, Math.round(21.0 * root.mmPerPx))
readonly property real glassHeight: Math.max(2, Math.round(35.0 * root.mmPerPx))
readonly property real tileWidth: root.glassWidth + 2 * root.tubeMargin
readonly property real tileHeight: root.glassHeight + 2 * root.tubeMargin

readonly property real rowGlassWidth: 4 * root.glassWidth + 2 * root.tubeGap + root.pairGap
implicitWidth: root.rowGlassWidth + 2 * root.tubeMargin
implicitHeight: root.tileHeight

// Where the four tubes stand across the item, in px from its centre: two
// pairs with the break between them, all of it measured on the glass.
readonly property var tubeX: {
const half = root.glassWidth / 2;
const left = [half,
              half + root.glassWidth + root.tubeGap,
              half + 2 * root.glassWidth + root.tubeGap + root.pairGap,
              half + 3 * root.glassWidth + 2 * root.tubeGap + root.pairGap];
const mid = root.width / 2;
return left.map(function (x) { return root.tubeMargin + x - mid; });
}

// -1 in a tube that has nothing to light (see the shader's digit).
function hourDigit(place) {
const text = String(Math.max(0, Math.min(23, root.hours))).padStart(2, "0");
const digit = Number(text[place]);
return (place === 0 && digit === 0) ? -1 : digit;
}

function minuteDigit(place) {
return Number(String(Math.max(0, Math.min(59, root.minutes))).padStart(2, "0")[place]);
}

readonly property var digits: [root.hourDigit(0), root.hourDigit(1),
                               root.minuteDigit(0), root.minuteDigit(1)]

// A nixie does not cross-fade. On a digit change it stutters for a few frames
// and then holds — and the four tubes never stutter together, or the clock
// reads as an animation instead of four lamps. It is never perfectly still
// either: the discharge breathes and the wire hums a few per cent (see the
// shader's breathe and hum), which is what `time` below carries.
property var ignition: [1.0, 1.0, 1.0, 1.0]
property var strikesLeft: [0, 0, 0, 0]
// Seconds of idle time, advanced in small steps so the shimmer has something
// to move with. The interval is the price of the life: 15 repaints a second
// over one item, and nothing else on the screen moves.
property real time: 0

function strike(index) {
const left = root.strikesLeft.slice();
left[index] = 5 + (index % 3);
root.strikesLeft = left;
const ign = root.ignition.slice();
ign[index] = 0.0;
root.ignition = ign;
if (index === 0)
strike0.restart();
else if (index === 1)
strike1.restart();
else if (index === 2)
strike2.restart();
else
strike3.restart();
}

function tick(index) {
const left = root.strikesLeft.slice();
const ign = root.ignition.slice();
if (left[index] <= 0) {
ign[index] = 1.0;
root.ignition = ign;
return;
}
left[index] -= 1;
root.strikesLeft = left;
// The gas strikes unevenly: some frames almost out, the last ones all but
// settled — the floor sits at 0.08 so no frame reads as a clean fade.
ign[index] = 0.08 + 0.92 * Math.random() * Math.random();
root.ignition = ign;
}

// One timer per tube: the same stutter, its own moment, its own jitter.
Timer {
id: strike0
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8))
repeat: true
onTriggered: root.tick(0)
}

Timer {
id: strike1
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + 11
repeat: true
onTriggered: root.tick(1)
}

Timer {
id: strike2
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + 22
repeat: true
onTriggered: root.tick(2)
}

Timer {
id: strike3
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + 10
repeat: true
onTriggered: root.tick(3)
}

Timer {
interval: 66
repeat: true
running: true
onTriggered: root.time += interval / 1000.0
}

// Every tube strikes when its own digit changes; at startup they all do.
function strikeAll() {
for (let i = 0; i < 4; i++)
root.strike(i);
}

onDigitsChanged: root.strikeAll()

Component.onCompleted: root.strikeAll()

// The row itself: one pass, four tubes, one light.
ShaderEffect {
id: row
anchors.fill: parent

property Item source: wallpaperPatch
property vector2d pSize: Qt.vector2d(row.width, row.height)
property vector2d pBackdrop: Qt.vector2d(row.width + 2 * root.tubeMargin,
                                         row.height + 2 * root.tubeMargin)
property real pInset: root.tubeMargin
property vector4d pTile: Qt.vector4d(root.tileWidth, root.tileHeight, root.tubeMargin, 1)
property vector4d pRowX: Qt.vector4d(root.tubeX[0], root.tubeX[1], root.tubeX[2], root.tubeX[3])
property vector4d pRowDigit: Qt.vector4d(root.digits[0], root.digits[1],
                                         root.digits[2], root.digits[3])
property vector4d pRowFlicker: Qt.vector4d(root.ignition[0], root.ignition[1],
                                           root.ignition[2], root.ignition[3])
property real pRadius: 9.5 * root.mmPerPx            // the bulb, Ø19 mm
property real pBase: 0
property real pGlow: GreeterTheme.nixieGlow
property real pWire: GreeterTheme.nixieWire
property real pStack: GreeterTheme.nixieStack
property real pHighlight: GreeterTheme.nixieHighlight
property real pWarmth: GreeterTheme.nixieWarmth
property real pExposure: GreeterTheme.nixieExposure
property real pTempK: GreeterTheme.nixieTempK
property real pTime: root.time
property real pMm: root.numeralSize / 18.0
property real pThick: Math.max(0.8, 0.9 * root.mmPerPx)   // the wall, ~0.9 mm
property real pRefract: 1.0
property color pHalo: GreeterTheme.nixieGlowColor
property color pGlass: GreeterTheme.nixieGlassColor
property color pCathode: GreeterTheme.nixieCathodeColor
property color pTint: GreeterTheme.nixieTint
// The single tube's own handles: the row does not read them, but they are
// in the block, and Qt warns about every uniform with no property.
property real pDigit: -1
property real pFlicker: 1
property real pBulb: 0
property real padCore0: 0
property real padCore3: 0

fragmentShader: Qt.resolvedUrl("../shaders/nixie.frag.qsb")
}

// The wallpaper the glass bends: the row's rect, one margin wider on every
// side, captured from the backdrop the host handed in. Live while any tube is
// striking — that is also when the layout settles at startup, so the patch is
// taken again exactly when it has to be.
readonly property bool striking: root.ignition[0] < 0.999 || root.ignition[1] < 0.999
                                || root.ignition[2] < 0.999 || root.ignition[3] < 0.999

readonly property point sampleOrigin: {
if (root.backdrop === null || root.width <= 0 || root.height <= 0)
return Qt.point(0, 0);
return root.mapToItem(root.backdrop, -root.tubeMargin, -root.tubeMargin);
}

ShaderEffectSource {
id: wallpaperPatch
sourceItem: root.backdrop
visible: false
live: root.striking
smooth: true
sourceRect: Qt.rect(root.sampleOrigin.x, root.sampleOrigin.y,
                    root.width + 2 * root.tubeMargin, root.height + 2 * root.tubeMargin)
}
}
