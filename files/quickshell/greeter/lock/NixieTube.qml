pragma ComponentBehavior: Bound
import QtQuick
import qs

// One gas-discharge tube of the login clock (lock/NixieClock.qml).
//
// The tube is one fragment shader and nothing else: the glass, the picture bent
// through it, the cathode stack, the anode cage, the crimped collar and the
// discharge of the lit numeral all live in shaders/nixie.frag. Nothing here is
// pre-rendered — a digit change is one uniform, and every part of the tube is a
// number the workbench can turn while it draws. It costs quality against a path
// tracer: no real caustics, no dispersion, one bounce of the picture. It buys
// being able to see the change now.
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

// The wallpaper the glass bends. The host hands it in (LockContent.qml); when it
// is null the tube still draws, it just has nothing to refract.
property Item backdrop: null

// The workbench's handles (greeter/tube-lab.qml). They are multipliers on what
// the theme says, so 1.0 is the clock's own look and nothing here can drift from
// it: the lab turns these, the login screen never touches them.
property real glowScale: 1.0        // how hard the discharge burns
property real glassLightScale: 1.0  // how much light the envelope catches
property real warmthScale: 1.0      // how much of the discharge lands on the glass
property real metalScale: 1.0       // how present the drawn metal is
property real glassThickness: 1.0   // the wall of the envelope, 1 = a nixie's own
property real glassRefraction: 1.0  // how hard the glass bends the picture behind it

// The numeral's size in px — the clock scales it by the theme's uiScale.
property real numeralSize: 92
readonly property real uiScale: GreeterTheme.uiScale

// The envelope, in the drawing's own millimetres. Reflector's IN-12A/B data
// sheet (1988) gives: bulb 19 x 28 mm, base 21 x 7 mm — 35 mm with the base and
// without the pins — pins 1 mm on an 11.5 mm circle, 7 mm long, the pip 3.5 mm,
// and the numerals 18 mm high. The numeral is the scale: everything else is a
// ratio of it, so the tube stays IN-12 at any size the clock asks for.
readonly property real mmPerPx: root.numeralSize / 18.0   // px per millimetre
readonly property real glassWidth: Math.max(2, Math.round(21.0 * root.mmPerPx))
readonly property real glassHeight: Math.max(2, Math.round(35.0 * root.mmPerPx))
// Room around the envelope for the bloom and for the refracted wallpaper, which
// the lens pulls in by a good part of the radius.
readonly property real pad: Math.round(GreeterTheme.nixieTubeMargin * root.uiScale)

implicitWidth: root.glassWidth + root.pad * 2
implicitHeight: root.glassHeight + root.pad * 2

// The camera follows the pointer over the tube when nixieCameraFollow is on:
// the pointer adds at most nixieCameraRange degrees to the base yaw and pitch
// (the base itself is not clamped), smoothed by a Behavior; a pointer outside
// the tube leaves the camera on its base. pView's third member carries the
// pitch; the shader consumes it from P6 on.
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
Behavior on effectiveYaw { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
Behavior on effectivePitch { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

HoverHandler {
id: cameraHover
}

// Discharge of the current digit: 1 while it burns steadily, and a stutter
// between 0 and 1 for the frames after it changed. steady = true holds it at 1
// from the first frame: the workbench screenshots a tube that is not stuttering.
property bool steady: false
property real ignition: 1.0
// One-shot ticks still owed; 0 is settled.
property int strikesLeft: 0
// Seconds of idle time, advanced only by the shimmer tick (nixieShimmerMs;
// frozen with nixieShimmer=0 and in steady mode).
property real clock: 0

// nixieFlicker=false holds the tube at full ignition and starts no timers;
// nixieFlickerMs=0 means the same "no restrike" the docs always promised.
readonly property bool strikeEnabled: GreeterTheme.nixieFlicker && GreeterTheme.nixieFlickerMs > 0
readonly property bool shimmerOn: GreeterTheme.nixieShimmer > 0
// A steady tube never strikes, so its patch is never kept live for one.
readonly property bool striking: !root.steady && root.ignition < 0.999

// How many one-shot ticks the tube owes: strike() sets zero, the tick that
// reaches 1 settles. nixieJitter spreads the lengths apart (1.0 is the tube
// lab's own 5/6/7); 0 makes every tube strike alike.
function strikeLength() {
    return 6 + Math.round((root.tubeIndex % 3) * Math.max(0.0, GreeterTheme.nixieJitter));
}

// The tube's own moment, so four tubes never start together.
function strikeOffset() {
    return Math.round(((root.tubeIndex * 11) % 23) * Math.max(0.0, GreeterTheme.nixieJitter));
}

// A nixie does not cross-fade. On a digit change it stutters for a few frames
// and then holds. It is never perfectly still, though: the discharge breathes
// and the wire hums a few per cent (see nixie.frag). The screen was built to
// stand still once, and the owner has since asked it to live, so the motion is
// slow and small — a strobing login screen would be a bug, not a lamp.
function strike() {
    if (!root.strikeEnabled) {
        root.ignition = 1.0;
        return;
    }
    root.strikesLeft = root.strikeLength();
    root.ignition = 0.0;
    strikeTimer.restart();
}

// One one-shot tick. A settled tube is not touched: no write, no restart.
function tick() {
    if (root.strikesLeft <= 0)
        return;
    root.strikesLeft -= 1;
    if (root.strikesLeft <= 0) {
        root.ignition = 1.0; // the settle
        return;
    }
    root.ignition = 0.08 + 0.92 * Math.random() * Math.random();
    strikeTimer.restart();
}

// The shimmer tick: nixieShimmerMs, only while the shimmer is on and the tube
// is visible, and never in steady mode (the workbench wants a still tube).
Timer {
    id: clockTimer
    interval: Math.max(1, Math.round(GreeterTheme.nixieShimmerMs))
    repeat: true
    running: !root.steady && root.shimmerOn && root.visible
    onTriggered: root.clock += interval / 1000.0
}

// One-shot: a settled tube stops its timer instead of waking up forever.
Timer {
    id: strikeTimer
    interval: Math.max(24, Math.round(GreeterTheme.nixieFlickerMs / 8)) + root.strikeOffset()
    repeat: false
    onTriggered: root.tick()
}

onDigitChanged: {
    if (!root.steady)
        root.strike();
}

onStrikeEnabledChanged: {
    if (!root.strikeEnabled) {
        strikeTimer.stop();
        root.strikesLeft = 0;
        root.ignition = 1.0;
    }
}

Component.onCompleted: {
    root.ignition = 1.0
    if (!root.steady)
        root.strike()
    patchWarmup.restart()
}



// The tube is two layers now, and the split is what each is good at.
//
// The glass is drawn here, live: it is a lens over the wallpaper patch behind it
// (ShaderEffectSource below), and what makes a tube sit in a picture instead of
// being pasted on it is that the picture bends through it. It also carries the
// discharge — a numeral is a curve, and a curve stays sharp at any size.
//
// Everything is analytic: the metal is distance fields of wire, the glass is a
// lens over the wallpaper patch, the discharge is the numeral's own curve. The
// whole tube is a handful of uniforms, which is what makes it tunable in place.
ShaderEffect {
id: tube
anchors.fill: parent

property Item source: wallpaperPatch
property vector2d pSize: Qt.vector2d(tube.width, tube.height)
property vector2d pBackdrop: Qt.vector2d(tube.width + 2 * root.pad, tube.height + 2 * root.pad)
property real pInset: root.pad
property real pRadius: root.bulb ? root.glassWidth * 0.42 : 9.5 * root.mmPerPx   // the bulb, Ø19 mm
property real pBase: root.bulb ? 0 : Math.round(7.0 * root.mmPerPx)          // the collar, 7 mm
property real pGlow: (root.bulb || root.digit >= 0) ? GreeterTheme.nixieGlow * root.glowScale : 0.0
property real pDigit: root.bulb ? -1 : root.digit
property real pBulb: root.bulb ? 1 : 0
property real pWire: GreeterTheme.nixieWire
property real pStack: (root.bulb ? 0 : GreeterTheme.nixieStack) * root.metalScale
property real pHighlight: GreeterTheme.nixieHighlight * root.glassLightScale
property real pWarmth: GreeterTheme.nixieWarmth * root.warmthScale
property real pFlicker: root.ignition
property real pTime: root.clock
property real pExposure: GreeterTheme.nixieExposure
// The quality tier, the shimmer strength and the ageing, straight off their
// tokens; the shader work behind them is P3's, and the defaults keep today's
// picture.
property real pQuality: GreeterTheme.nixieQuality === "balanced" ? 1.0
                      : (GreeterTheme.nixieQuality === "lite" ? 2.0 : 0.0)
property real pShimmer: GreeterTheme.nixieShimmer
property real pAge: GreeterTheme.nixieAge
property real pBaseOn: GreeterTheme.nixieBase ? 1.0 : 0.0
// The row's uniforms: a single tube has no row, so they stay zero. pTile must
// still be declared — the shader reads pTile.x for its lab offset and Qt warns
// about every uniform with no property behind it — and pTile.w = 0 keeps the
// shader in single-tube mode.
property vector4d pTile: Qt.vector4d(0, 0, 0, 0)
property vector4d pRowX: Qt.vector4d(0, 0, 0, 0)
property vector4d pRowDigit: Qt.vector4d(0, 0, 0, 0)
property vector4d pRowFlicker: Qt.vector4d(0, 0, 0, 0)
// The block's two pure std140 paddings. A vec4 of the shader's own floats has
// to start on a 16-byte boundary, so the slots carrying the temperature and the
// highlight have a spare float each; nothing reads them, but Qt warns about
// every uniform with no property behind it — a warning per tube per frame is
// noise in the greeter's log.
property real padCore0: 0
property real padCore3: 0
property real pMm: root.numeralSize / 18.0   // px per millimetre, the drawing's scale
property real pThick: Math.max(0.8, 0.9 * root.mmPerPx) * root.glassThickness  // the wall, ~0.9 mm
property real pRefract: root.glassRefraction
property real pTempK: GreeterTheme.nixieTempK
property color pHalo: GreeterTheme.nixieGlowColor
property color pGlass: GreeterTheme.nixieGlassColor
property color pCathode: GreeterTheme.nixieCathodeColor
property color pTint: GreeterTheme.nixieTint
property vector4d pWallpaper: Qt.vector4d(GreeterTheme.nixieTintWallpaper, 0, 0, 0)
property vector4d pView: Qt.vector4d(root.effectiveYaw, GreeterTheme.nixieViewDistance, root.effectivePitch, 0)

fragmentShader: Qt.resolvedUrl("../shaders/nixie.frag.qsb")
}

// The wallpaper the glass bends: the tube's rect, one pad wider on every side,
// captured from the backdrop the host handed in. Live while the tube strikes
// plus a short warm-up — the wallpaper can arrive asynchronously, and one
// scheduled update re-captures the glass once the strike settles, so a steady
// tube (or a late picture) does not leave a blank patch until the next change.
readonly property point sampleOrigin: {
const w = root.width;
const h = root.height;
if (root.backdrop === null || w <= 0 || h <= 0)
return Qt.point(0, 0);
return root.mapToItem(root.backdrop, -root.pad, -root.pad);
}

Timer {
id: patchWarmup
interval: 1500
repeat: false
}

onBackdropChanged: patchWarmup.restart()

onStrikingChanged: {
    if (!root.striking)
        wallpaperPatch.scheduleUpdate();
}

ShaderEffectSource {
id: wallpaperPatch
sourceItem: root.backdrop
visible: false
live: root.striking || patchWarmup.running
smooth: true
sourceRect: Qt.rect(root.sampleOrigin.x, root.sampleOrigin.y,
root.width + 2 * root.pad, root.height + 2 * root.pad)
}
}
