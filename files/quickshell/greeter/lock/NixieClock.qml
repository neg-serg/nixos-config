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
readonly property real uiScale: GreeterTheme.uiScale

// The numeral size: the tubes and every gap between them are built from it.
readonly property real numeralSize: Math.round(GreeterTheme.nixieDigitSize * root.uiScale)
readonly property real tubeGap: Math.round(root.numeralSize * 0.09)
readonly property real colonWidth: Math.round(root.numeralSize * 0.30)
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
spacing: root.tubeGap

NixieTube {
id: hourTens
tubeIndex: 0
numeralSize: root.numeralSize
digit: root.hourDigit(0)
}

NixieTube {
tubeIndex: 1
numeralSize: root.numeralSize
digit: root.hourDigit(1)
}

// The colon: two small round tubes that burn steadily, centred on the row.
Item {
id: colon
implicitWidth: root.colonWidth
implicitHeight: hourTens.implicitHeight

Repeater {
model: 2

NixieTube {
required property int index

bulb: true
tubeIndex: 4 + index
numeralSize: root.numeralSize
x: Math.round((colon.width - width) / 2)
y: Math.round((colon.height / 2) + (index === 0 ? -root.bulbOffset : root.bulbOffset) - (height / 2))
}
}
}

NixieTube {
tubeIndex: 2
numeralSize: root.numeralSize
digit: root.minuteDigit(0)
}

NixieTube {
tubeIndex: 3
numeralSize: root.numeralSize
digit: root.minuteDigit(1)
}
}
}
