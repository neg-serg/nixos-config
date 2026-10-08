pragma ComponentBehavior: Bound
import QtQuick
import qs

// The clock of the login screen: four gas-discharge tubes with the colon between
// them, the way a nixie clock reads. Each tube is an item of its own
// (lock/NixieTube.qml, shaders/nixie.frag) — its own glass, its own cathode stack,
// its own discharge.
//
// The tens of hours stay dark before 10:00: a real clock has no cathode for a
// leading zero, and the hour reads better without one.
Item {
id: root

property int hours: 0
property int minutes: 0
// The wallpaper the glass bends: handed straight down to every tube.
property Item backdrop: null
readonly property real uiScale: GreeterTheme.uiScale

// The numeral size: the tubes and every gap between them are built from it.
readonly property real numeralSize: Math.round(GreeterTheme.nixieDigitSize * root.uiScale)
// The tubes are one row of glass, not four islands: each item is wider than its
// glass by the margin the discharge's bloom needs (GreeterTheme.nixieTubeMargin,
// which NixieTube pads itself by), so the row's spacing goes negative by two of
// those margins and what is left between the glass edges is "tubeGap".
readonly property real tubeMargin: Math.round(GreeterTheme.nixieTubeMargin * root.uiScale)
readonly property real tubeGap: Math.round(root.numeralSize * 0.055)
// The break between the two pairs. The colon is not drawn — the clock is four
// tubes — so this item is only the space the hours and the minutes are held
// apart by: "pairGap" is what that break comes to between the glass edges, and
// the item is the rest of the arithmetic.
readonly property real pairGap: Math.round(root.numeralSize * 0.20)
readonly property real colonWidth: Math.max(0, root.pairGap - 2 * root.tubeGap + 2 * root.tubeMargin)
// The two bulbs sit where the tops and the bottoms of the digits are, not in
// the middle of the row.
readonly property real bulbOffset: Math.round(root.numeralSize * 0.25)

// -1 in a tube that has nothing to light (see NixieTube.digit).
function hourDigit(place) {
const text = String(Math.max(0, Math.min(23, root.hours))).padStart(2, "0");
const digit = Number(text[place]);
return (place === 0 && digit === 0) ? -1 : digit;
}

function minuteDigit(place) {
return Number(String(Math.max(0, Math.min(59, root.minutes))).padStart(2, "0")[place]);
}

implicitWidth: row.implicitWidth
implicitHeight: row.implicitHeight

Row {
id: row
anchors.centerIn: parent
spacing: root.tubeGap - 2 * root.tubeMargin

NixieTube {
id: hourTens
backdrop: root.backdrop
tubeIndex: 0
numeralSize: root.numeralSize
digit: root.hourDigit(0)
}

NixieTube {
				backdrop: root.backdrop
tubeIndex: 1
numeralSize: root.numeralSize
digit: root.hourDigit(1)
}

// The space between the two pairs: the colon used to be drawn here (two bulbs
// of the same tube), and this item is what holds the break now.
Item {
id: colon
implicitWidth: root.colonWidth
implicitHeight: hourTens.implicitHeight
}

NixieTube {
				backdrop: root.backdrop
tubeIndex: 2
numeralSize: root.numeralSize
digit: root.minuteDigit(0)
}

NixieTube {
				backdrop: root.backdrop
tubeIndex: 3
numeralSize: root.numeralSize
digit: root.minuteDigit(1)
}
}
}
