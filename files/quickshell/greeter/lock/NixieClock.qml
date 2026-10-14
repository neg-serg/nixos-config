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
readonly property real tubeGap: Math.round(root.numeralSize * 0.055 * GreeterTheme.nixieSpacing)
readonly property real pairGap: Math.round(root.numeralSize * 0.20 * GreeterTheme.nixieSpacing)

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

// The camera follows the pointer over the clock when nixieCameraFollow is on:
// the pointer adds at most nixieCameraRange degrees to the base yaw and pitch
// (the base itself is not clamped), and the drift is smoothed so the lamp
// drifts after the cursor instead of snapping. A pointer outside the clock
// leaves the camera on its base. pView's third member carries the pitch; the
// shader consumes it from P6 on.
readonly property real cameraX: cameraHover.active
                                ? (cameraHover.point.position.x / Math.max(1, root.width) - 0.5) * 2 : 0
readonly property real cameraY: cameraHover.active
                                ? (cameraHover.point.position.y / Math.max(1, root.height) - 0.5) * 2 : 0
readonly property real cameraRange: Math.max(0, GreeterTheme.nixieCameraRange)
readonly property real yawOffset: GreeterTheme.nixieCameraFollow
        ? Math.max(-root.cameraRange, Math.min(root.cameraRange, root.cameraX * root.cameraRange)) : 0
readonly property real pitchOffset: GreeterTheme.nixieCameraFollow
        ? Math.max(-root.cameraRange, Math.min(root.cameraRange, root.cameraY * root.cameraRange)) : 0
// The Behavior below needs a writable property, so these two are not readonly:
// the binding keeps them on the base camera plus the clamped pointer offset,
// and the animation is the smoothing.
property real effectiveYaw: GreeterTheme.nixieViewAngle + root.yawOffset
property real effectivePitch: GreeterTheme.nixieViewPitch + root.pitchOffset

HoverHandler {
id: cameraHover
}

// -1 in a tube that has nothing to light (see the shader's digit). nixie24h
// picks the format; nixieLeadingZero lights the tens of the hours as 0 instead
// of leaving that tube dark.
function hourDigit(place) {
    const h = Math.max(0, Math.min(23, root.hours));
    if (!GreeterTheme.nixie24h) {
        const text = String(h % 12 === 0 ? 12 : h % 12);
        if (place === 0)
            return text.length < 2 ? (GreeterTheme.nixieLeadingZero ? 0 : -1) : Number(text[0]);
        return Number(text[text.length - 1]);
    }
    const text = String(h).padStart(2, "0");
    const digit = Number(text[place]);
    return (place === 0 && digit === 0 && !GreeterTheme.nixieLeadingZero) ? -1 : digit;
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
// shader's breathe and hum), which is what the shimmer timer below carries.
property var ignition: [1.0, 1.0, 1.0, 1.0]
// One-shot ticks still owed per tube; 0 is settled.
property var strikesLeft: [0, 0, 0, 0]
// The digits the last decision was made on, so a minute restrikes only the
// tubes whose value actually changed.
property var previousDigits: []
// Seconds of idle time, advanced only by the shimmer tick: with nixieShimmer
// off nothing here wakes up at all.
property real time: 0

// nixieFlicker=false holds every tube at full ignition and starts no timers;
// nixieFlickerMs=0 means the same "no restrike" the docs always promised.
readonly property bool strikeEnabled: GreeterTheme.nixieFlicker && GreeterTheme.nixieFlickerMs > 0
readonly property bool shimmerOn: GreeterTheme.nixieShimmer > 0

// How many one-shot ticks a struck tube owes: strike() sets zero, the tick
// that reaches 1 settles. nixieJitter spreads the lengths apart (1.0 is the
// clock's own 5/6/7 and the old timings); 0 makes every tube strike alike.
function strikeLength(index) {
    return 6 + Math.round((index % 3) * Math.max(0.0, GreeterTheme.nixieJitter));
}

// The per-tube moment that keeps the four from ever starting together.
function strikeOffset(index) {
    return Math.round(((index * 11) % 23) * Math.max(0.0, GreeterTheme.nixieJitter));
}

function restartStrike(index) {
    if (index === 0)
        strike0.restart();
    else if (index === 1)
        strike1.restart();
    else if (index === 2)
        strike2.restart();
    else
        strike3.restart();
}

function strike(index) {
    if (!root.strikeEnabled)
        return;
    const left = root.strikesLeft.slice();
    left[index] = root.strikeLength(index);
    const ign = root.ignition.slice();
    ign[index] = 0.0;
    root.strikesLeft = left;
    root.ignition = ign;
    root.restartStrike(index);
}

// One one-shot tick of a tube's strike. A settled tube is left completely
// alone — no slice, no ignition write, no timer — so an idle clock has nothing
// to do; the last tick settles the tube instead of leaving it mid-stutter.
function tick(index) {
    const left = root.strikesLeft[index];
    if (left <= 0)
        return;
    const next = root.strikesLeft.slice();
    next[index] = left - 1;
    const ign = root.ignition.slice();
    if (left === 1)
        ign[index] = 1.0;
    else
        ign[index] = 0.08 + 0.92 * Math.random() * Math.random();
    root.strikesLeft = next;
    root.ignition = ign;
    if (next[index] > 0)
        root.restartStrike(index); // one-shot: only while more ticks are owed
}

// Drop every tube to rest and stop the timers, e.g. when flicker is switched
// off while a strike is in flight.
function settleAll() {
    strike0.stop();
    strike1.stop();
    strike2.stop();
    strike3.stop();
    root.strikesLeft = [0, 0, 0, 0];
    root.ignition = [1.0, 1.0, 1.0, 1.0];
}

// One timer per tube: the same stutter, its own moment, its own jitter. They
// are one-shot — a settled tube stops its timer instead of waking up forever —
// and restart only while the tube still owes ticks.
Timer {
id: strike0
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + root.strikeOffset(0)
repeat: false
onTriggered: root.tick(0)
}

Timer {
id: strike1
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + root.strikeOffset(1)
repeat: false
onTriggered: root.tick(1)
}

Timer {
id: strike2
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + root.strikeOffset(2)
repeat: false
onTriggered: root.tick(2)
}

Timer {
id: strike3
interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + root.strikeOffset(3)
repeat: false
onTriggered: root.tick(3)
}

// The only periodic work this item does: advance the shader's pTime. It runs
// only while the shimmer is on and the clock is visible, at nixieShimmerMs, so
// nixieShimmer=0 leaves the whole clock with nothing to wake it.
Timer {
id: shimmerTimer
interval: Math.max(1, Math.round(GreeterTheme.nixieShimmerMs))
repeat: true
running: root.shimmerOn && root.visible
onTriggered: root.time += interval / 1000.0
}

// At startup every tube strikes; on a minute change only the tubes whose digit
// changed do — the four never restrike in the same event-loop turn, which is
// what the design above and the per-tube timers are for.
function strikeAll() {
    if (!root.strikeEnabled) {
        root.settleAll();
        return;
    }
    for (let i = 0; i < 4; i++)
        root.strike(i);
}

function applyDigits() {
    if (root.strikeEnabled && root.previousDigits.length !== 4) {
        root.previousDigits = root.digits.slice();
        root.strikeAll();
        return;
    }
    if (root.strikeEnabled) {
        for (let i = 0; i < 4; i++) {
            if (root.digits[i] !== root.previousDigits[i])
                root.strike(i);
        }
    }
    root.previousDigits = root.digits.slice();
}

onDigitsChanged: root.applyDigits()

onStrikeEnabledChanged: {
    if (!root.strikeEnabled)
        root.settleAll();
}

Component.onCompleted: {
    root.applyDigits();
    patchWarmup.restart();
}

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
// The quality tier, the shimmer strength and the ageing, straight off their
// tokens; the shader work behind them is P3's, and the defaults keep today's
// picture.
property real pQuality: GreeterTheme.nixieQuality === "balanced" ? 1.0
                      : (GreeterTheme.nixieQuality === "lite" ? 2.0 : 0.0)
property real pShimmer: GreeterTheme.nixieShimmer
property real pAge: GreeterTheme.nixieAge
property real pBaseOn: GreeterTheme.nixieBase ? 1.0 : 0.0
property real pTime: root.time
property real pMm: root.numeralSize / 18.0
property real pThick: Math.max(0.8, 0.9 * root.mmPerPx)   // the wall, ~0.9 mm
property real pRefract: 1.0
property color pHalo: GreeterTheme.nixieGlowColor
property color pGlass: GreeterTheme.nixieGlassColor
property color pCathode: GreeterTheme.nixieCathodeColor
property color pTint: GreeterTheme.nixieTint
property vector4d pWallpaper: Qt.vector4d(GreeterTheme.nixieTintWallpaper, 0, 0, 0)
property vector4d pView: Qt.vector4d(root.effectiveYaw, GreeterTheme.nixieViewDistance, root.effectivePitch, 0)
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
// side, captured from the backdrop the host handed in. The wallpaper can load
// asynchronously, so the patch cannot be live only while the tubes strike: the
// strike can be over before the picture is decoded. It stays live for a short
// warm-up after creation, a backdrop change or a resize, and one scheduled
// update re-captures it once the last strike settles — otherwise the glass
// could refract a blank patch until the next minute.
readonly property bool striking: root.ignition[0] < 0.999 || root.ignition[1] < 0.999
                                || root.ignition[2] < 0.999 || root.ignition[3] < 0.999

Timer {
id: patchWarmup
interval: 1500
repeat: false
}

onBackdropChanged: patchWarmup.restart()
onWidthChanged: patchWarmup.restart()
onHeightChanged: patchWarmup.restart()

onStrikingChanged: {
    if (!root.striking)
        wallpaperPatch.scheduleUpdate();
}

readonly property point sampleOrigin: {
if (root.backdrop === null || root.width <= 0 || root.height <= 0)
return Qt.point(0, 0);
return root.mapToItem(root.backdrop, -root.tubeMargin, -root.tubeMargin);
}

ShaderEffectSource {
id: wallpaperPatch
sourceItem: root.backdrop
visible: false
live: root.striking || patchWarmup.running
smooth: true
sourceRect: Qt.rect(root.sampleOrigin.x, root.sampleOrigin.y,
                    root.width + 2 * root.tubeMargin, root.height + 2 * root.tubeMargin)
}
}
