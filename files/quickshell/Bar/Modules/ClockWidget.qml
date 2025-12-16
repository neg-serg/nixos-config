import QtQuick
import qs.Settings
import qs.Components

CenteredCapsuleRow {
    id: clockWidget
    property var screen: (typeof modelData !== 'undefined' ? modelData : null)
    backgroundKey: "clock"
    iconVisible: false
    labelText: Time.time
    labelColor: Theme.timeTextColor
    fontPixelSize: Math.round(Theme.fontSizeSmall * Theme.timeFontScale * capsuleScale)
    labelFontFamily: Theme.fontFamily
    labelFontWeight: Theme.timeFontWeight

    interactive: true
    onClicked: calendar.toggle()

    Calendar {
        id: calendar
        screen: clockWidget.screen
    }
}
