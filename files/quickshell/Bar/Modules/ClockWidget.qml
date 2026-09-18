import QtQuick
import qs.Settings
import qs.Components
import "../../Helpers/TooltipText.js" as TooltipText

CenteredCapsuleRow {
    id: clockWidget
    backgroundKey: "clock"
    iconVisible: false
    labelText: Time.time
    labelColor: Theme.timeTextColor
    fontPixelSize: Math.round(Theme.fontSizeSmall * Theme.timeFontScale * capsuleScale)
    labelFontFamily: Theme.fontFamily
    labelFontWeight: Theme.timeFontWeight

    // Full date + weekday on hover; click opens the calendar.
    // Day/month names are translated manually (Qt.locale("ru_RU") is not
    // available in the quickshell locale archive).
    readonly property string _tooltipText: (function() {
        var days = ["Воскресенье", "Понедельник", "Вторник", "Среда",
                    "Четверг", "Пятница", "Суббота"];
        var months = ["января", "февраля", "марта", "апреля", "мая", "июня",
                      "июля", "августа", "сентября", "октября", "ноября", "декабря"];
        var d = new Date();
        return TooltipText.compose(
            "Часы",
            days[d.getDay()] + ", " + d.getDate() + " " + months[d.getMonth()] + " " + d.getFullYear(),
            ["Клик — календарь"]);
    })()

    interactive: true
    onClicked: calendar.toggle()

    PanelTooltip {
        targetItem: clockWidget
        text: clockWidget._tooltipText
        visibleWhen: clockWidget.hovered
    }

    Calendar {
        id: calendar
        screen: clockWidget.screen
    }
}
