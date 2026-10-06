// Every numeral of the clock in a row, for looking at them:
//   qs -p files/quickshell/greeter/digits.qml
// No clock, no greetd — ten tubes, one digit each, over the same wallpaper patch
// the login screen shows (PREVIEW_WALLPAPER overrides it).
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.lock
import qs.background

ShellRoot {
FloatingWindow {
id: win
implicitWidth: 1600
implicitHeight: 420
color: "#0a0a0c"

BackgroundImage {
id: backdrop
anchors.fill: parent
screen: win.screen
slideAmount: 0
asynchronous: false
wallpaperPath: Quickshell.env("PREVIEW_WALLPAPER")
|| ("file://" + (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/greeter-wallpaper")
}

Row {
anchors.centerIn: parent
spacing: 18

Repeater {
// 0..9, and one tube with nothing lit — the leading-zero case, and
// the only tube whose glass can be measured without the discharge.
model: 11

NixieTube {
required property int index

backdrop: backdrop
tubeIndex: index
numeralSize: 110
digit: index < 10 ? index : -1
}
}
}
}
}
