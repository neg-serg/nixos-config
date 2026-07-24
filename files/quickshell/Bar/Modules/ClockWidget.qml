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

    HoverHandler {
        id: clockHover
        enabled: true
        onHoveredChanged: {
            if (hovered) { calendar.open("hover") }
            else { hoverCloseTimer.restart() }
        }
    }
    Timer {
        id: hoverCloseTimer
        interval: 250
        onTriggered: {
            if (!clockHover.hovered && !calendar.overlayContainsMouse)
                calendar.close("hover")
        }
    }

    Calendar {
        id: calendar
        screen: clockWidget.screen
    }
}
