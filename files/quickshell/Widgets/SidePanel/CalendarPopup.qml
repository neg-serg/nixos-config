import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Components
import qs.Settings
import "../Helpers/Holidays.js" as Holidays
import "../Helpers/ProductionCalendar.js" as ProdCal
import "../Helpers/Color.js" as Color
import "../Helpers/TooltipText.js" as TooltipText
import "../Helpers/Utils.js" as Utils
import "." as SidePanel

SidePanel.OverlayPopupBase {
    id: root

    popupNamespace: "qs-calendar"
    popupWidth: Math.round(420 * Theme.scale(Screen))
    popupHeight: Math.round(540 * Theme.scale(Screen))
    edgeMargin: Theme.sidePanelPopupOuterMargin

    // ── Medieval theme tokens ──
    readonly property color parchmentBg: Color.withAlpha("#1a1410", 0.88)
    readonly property color goldAccent: Color.withAlpha("#c9a050", 0.9)
    readonly property color goldDim: Color.withAlpha("#8b7332", 0.7)
    readonly property color textWarm: "#e8dcc8"
    readonly property color textWarmDim: "#a09880"

    // ── Internal state ──
    property var holidays: []
    property var prodCalHolidays: []
    property int currentYear: Time.date.getFullYear()
    property int currentMonth: Time.date.getMonth()
    readonly property int illustrationCount: 12
    property string currentIllustration: "qrc:/art/calendar/" + (currentMonth + 1) + ".svg"

    function updateAll() {
        currentYear = Time.date.getFullYear()
        currentMonth = Time.date.getMonth()
        prodCalHolidays = ProdCal.getHolidays(currentYear, currentMonth)
        Holidays.getHolidaysForMonth(currentYear, currentMonth, function(data) {
            holidays = data
        })
    }

    onVisibleChanged: {
        if (visible) updateAll()
    }

    Timer {
        interval: 300000  // refresh every 5 min (in case day changes)
        repeat: true
        running: root.visible
        onTriggered: { if (root.visible) root.updateAll() }
    }

    // ── Content ──
    Item {
        anchors.fill: parent
        anchors.margins: Math.round(8 * Theme.scale(Screen))

        // Glass-morphism background
        Rectangle {
            anchors.fill: parent
            radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen))
            color: root.parchmentBg
            border.color: Color.withAlpha(root.goldAccent, 0.2)
            border.width: 1

            // Subtle inner glow (top edge)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Color.withAlpha(root.goldAccent, 0.3)
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Math.round(12 * Theme.scale(Screen))
            spacing: Math.round(8 * Theme.scale(Screen))

            // ── Month / Year header ──
            RowLayout {
                Layout.fillWidth: true
                spacing: Math.round(4 * Theme.scale(Screen))

                PanelIconButton {
                    icon: "chevron_left"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        var d = new Date(root.currentYear, root.currentMonth - 1, 1)
                        root.currentYear = d.getFullYear()
                        root.currentMonth = d.getMonth()
                        root.updateAll()
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: {
                        var months = ["January","February","March","April","May","June",
                                      "July","August","September","October","November","December"]
                        return months[root.currentMonth] + "  ·  " + root.currentYear
                    }
                    color: root.goldAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(20 * Theme.scale(Screen))
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.5
                }

                PanelIconButton {
                    icon: "chevron_right"
                    Layout.alignment: Qt.AlignVCenter
                    onClicked: {
                        var d = new Date(root.currentYear, root.currentMonth + 1, 1)
                        root.currentYear = d.getFullYear()
                        root.currentMonth = d.getMonth()
                        root.updateAll()
                    }
                }
            }

            // ── Medieval illustration ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(80 * Theme.scale(Screen))
                radius: Math.round(4 * Theme.scale(Screen))
                color: Color.withAlpha(root.goldDim, 0.08)
                border.color: Color.withAlpha(root.goldDim, 0.15)
                border.width: 1

                HiDpiImage {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    height: parent.height - 8
                    fillMode: Image.PreserveAspectFit
                    source: root.currentIllustration

                    // Fade between months
                    Behavior on source {
                        NumberAnimation { 
                            target: monthIllustrationFade
                            property: "opacity"
                            from: 0.3; to: 1.0
                            duration: 400
                        }
                    }

                    Rectangle {
                        id: monthIllustrationFade
                        anchors.fill: parent
                        color: "transparent"
                        opacity: 1.0
                    }
                }

                // Moon phase icon overlay
                MoonPhaseIcon {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Math.round(6 * Theme.scale(Screen))
                    size: Math.round(24 * Theme.scale(Screen))
                }
            }

            // ── Calendar grid ──
            DayOfWeekRow {
                Layout.fillWidth: true
                spacing: 0
                Layout.leftMargin: Math.round(4 * Theme.scale(Screen))
                Layout.rightMargin: Math.round(4 * Theme.scale(Screen))

                delegate: Text {
                    required property string shortName
                    text: shortName
                    color: root.textWarmDim
                    opacity: 0.8
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(14 * Theme.scale(Screen))
                    font.weight: Font.Normal
                    font.italic: true
                    horizontalAlignment: Text.AlignHCenter
                    width: Theme.calendarCellSize
                }
            }

            MonthGrid {
                id: calendar

                Layout.fillWidth: true
                Layout.leftMargin: Math.round(4 * Theme.scale(Screen))
                Layout.rightMargin: Math.round(4 * Theme.scale(Screen))
                spacing: 0
                month: root.currentMonth
                year: root.currentYear

                delegate: Rectangle {
                    id: dayCell
                    required property var model
                    property bool isToday: model.today
                    property bool isCurrentMonth: model.month === calendar.month
                    property var holidayInfos: {
                        var all = []
                        // Holidays from API
                        for (var i = 0; i < root.holidays.length; i++) {
                            var h = root.holidays[i]
                            var d = new Date(h.date)
                            if (d.getDate() === model.day && d.getMonth() === model.month && d.getFullYear() === model.year)
                                all.push(h)
                        }
                        // Production calendar holidays
                        for (var j = 0; j < root.prodCalHolidays.length; j++) {
                            var pc = root.prodCalHolidays[j]
                            if (pc.day === model.day) all.push({localName: pc.label, type: pc.type})
                        }
                        return all
                    }
                    property bool isHoliday: holidayInfos.length > 0
                    property bool isWeekend: model.dayOfWeek === 0 || model.dayOfWeek === 6

                    width: Theme.calendarCellSize
                    height: Theme.calendarCellSize
                    radius: Math.round(Theme.cornerRadius * 0.33)
                    color: {
                        if (isToday) return Color.withAlpha(root.goldAccent, 0.35)
                        if (mouseArea.containsMouse) return Color.withAlpha(root.goldAccent, 0.2)
                        return "transparent"
                    }
                    border.color: isToday ? root.goldAccent : "transparent"
                    border.width: isToday ? 1.5 : 0

                    Text {
                        anchors.centerIn: parent
                        text: model.day
                        color: {
                            if (isToday) return root.goldAccent
                            if (isHoliday) return "#ff6b6b"  // red for holidays
                            if (isWeekend) return root.textWarmDim
                            return root.textWarm
                        }
                        opacity: isCurrentMonth ? 0.9 : 0.3
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(16 * Theme.scale(Screen))
                        font.weight: isToday ? Font.Bold : Font.Normal
                    }

                    // Holiday dot indicator
                    Rectangle {
                        visible: isHoliday
                        width: 4 * Theme.scale(Screen)
                        height: width
                        radius: width / 2
                        color: "#ff6b6b"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 2
                    }

                    MouseArea {
                        id: mouseArea
                        anchors.fill: dayCell
                        hoverEnabled: true
                        onEntered: {
                            if (isHoliday && holidayInfos.length > 0) {
                                var names = holidayInfos.map(function(h) { return h.localName || h.label || "Holiday" })
                                holidayTooltip.text = names.join(" · ")
                                holidayTooltip.targetItem = dayCell
                                holidayTooltip.visibleWhen = true
                            }
                        }
                        onExited: holidayTooltip.visibleWhen = false
                    }

                    PanelTooltip {
                        id: holidayTooltip
                        text: ""
                        targetItem: null
                        visibleWhen: false
                    }
                }  // end delegate
            }  // end MonthGrid

            // ── Today's details ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: todayDetails.height + 12 * Theme.scale(Screen)
                radius: Math.round(4 * Theme.scale(Screen))
                color: Color.withAlpha(root.goldDim, 0.06)
                visible: todayLabel.text !== ""

                Column {
                    id: todayDetails
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Math.round(8 * Theme.scale(Screen))
                    spacing: Math.round(2 * Theme.scale(Screen))

                    Text {
                        id: todayLabel
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            var todayHolidays = []
                            for (var i = 0; i < root.holidays.length; i++) {
                                var h = root.holidays[i]
                                var d = new Date(h.date)
                                if (d.getDate() === Time.date.getDate() && 
                                    d.getMonth() === Time.date.getMonth() && 
                                    d.getFullYear() === Time.date.getFullYear())
                                    todayHolidays.push(h.localName || h.name)
                            }
                            for (var j = 0; j < root.prodCalHolidays.length; j++) {
                                var pc = root.prodCalHolidays[j]
                                if (pc.day === Time.date.getDate())
                                    todayHolidays.push(pc.label)
                            }
                            return todayHolidays.length > 0 ? todayHolidays.join(" · ") : ""
                        }
                        color: root.textWarm
                        opacity: 0.7
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(12 * Theme.scale(Screen))
                        font.italic: true
                    }
                }
            }

        }  // end ColumnLayout
    }  // end background Item
}
