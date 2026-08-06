pragma ComponentBehavior: Bound
import "../../Helpers/Holidays.js" as Holidays
import "../../Helpers/ProductionCalendar.js" as ProdCal
import "../../Helpers/CalendarEvents.js" as CalendarEvents
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Components
import qs.Settings
import "../../Helpers/Color.js" as Color
import "../../Helpers/TooltipText.js" as TooltipText

OverlayToggleCapsule {
    id: root
    visible: false
    capsuleVisible: false
    autoToggleOnTap: true
    overlayNamespace: "qs-calendar"

    property color parchmentBg: Color.withAlpha(Theme.surface, 0.85)
    property color goldAccent: Color.withAlpha(Theme.accentPrimary, 0.85)
    property color goldDim: Color.withAlpha(Theme.accentPrimary, 0.35)
    property color textWarm: Theme.textPrimary
    property color textWarmDim: Theme.textSecondary

    property var holidays: []
    property var calendarEvents: []
    property var prodCal: []
    property int currentYear: Time.date.getFullYear()
    property int currentMonth: Time.date.getMonth()
    property int selectedDay: -1

    function updateAll() {
        holidays = []
        prodCal = ProdCal.getHolidays(currentYear, currentMonth)
        Holidays.getHolidaysForMonth(currentYear, currentMonth, function(data) { holidays = data })
        CalendarEvents.getEvents(currentYear, currentMonth, function(data) { calendarEvents = data })
    }

    onOpened: {
        currentYear = Time.date.getFullYear()
        currentMonth = Time.date.getMonth()
        updateAll()
        eventRefreshTimer.start()
    }

    // Refresh calendar events every 5 min while overlay is open
    Timer {
        id: eventRefreshTimer
        interval: 300000
        repeat: true
        running: false
        onTriggered: CalendarEvents.refresh(root.currentYear, root.currentMonth)
    }

    overlayChildren: [
        PanelOverlaySurface {
            id: sf
            screen: root.screen
            backgroundColor: root.parchmentBg
            borderColor: "transparent"
            borderWidth: 0
            cornerRadiusOverride: Math.round(Theme.cornerRadiusLarge / 3)
            width: Math.round(380 * Theme.scale(root.screen))
            height: Math.round(480 * Theme.scale(root.screen))
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.bottomMargin: Theme.calendarPopupMargin
            anchors.leftMargin: Theme.calendarPopupMargin

            Rectangle { anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right; height: 1; color: Color.withAlpha(root.goldAccent, 0.25) }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Math.round(8 * Theme.scale(root.screen))
                spacing: Math.round(6 * Theme.scale(root.screen))

                RowLayout {
                    Layout.fillWidth: true; spacing: 2
                    PanelIconButton { icon: "chevron_left"
                        onClicked: { var d=new Date(root.currentYear,root.currentMonth-1,1); root.currentYear=d.getFullYear(); root.currentMonth=d.getMonth(); root.updateAll() } }
                    Text {
                        Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                        text: { var m=["January","February","March","April","May","June","July","August","September","October","November","December"]; return m[root.currentMonth]+"  ·  "+root.currentYear }
                        color: root.goldAccent; font.family: Theme.fontFamily; font.pixelSize: Math.round(16*Theme.scale(root.screen)); font.weight: Font.DemiBold; font.letterSpacing: 1.2 }
                    PanelIconButton { icon: "chevron_right"
                        onClicked: { var d=new Date(root.currentYear,root.currentMonth+1,1); root.currentYear=d.getFullYear(); root.currentMonth=d.getMonth(); root.updateAll() } }
                }

                // --- Illustration ---
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: Math.round(140*Theme.scale(root.screen)); color: "transparent"
                    HiDpiImage {
                        id: monthIllustration
                        anchors.centerIn: parent; width: parent.width-16; height: parent.height-8; fillMode: Image.PreserveAspectFit
                        source: Qt.resolvedUrl("../../art/calendar/"+(root.currentMonth+1)+".svg")
                        Behavior on source { NumberAnimation { target:monthFade; property:"opacity"; from:0.3; to:1.0; duration: Theme.panelAnimStdMs } }
                        Rectangle { id:monthFade; anchors.fill:parent; color:"transparent"; opacity:1.0 }
                        layer.enabled: true
                        layer.effect: MultiEffect { colorization: 0.85; colorizationColor: root.goldAccent }
                    }
                }

                DayOfWeekRow {
                    Layout.fillWidth: true; spacing: 0
                    Layout.leftMargin: Math.round(2*Theme.scale(root.screen))
                    Layout.rightMargin: Math.round(2*Theme.scale(root.screen))
                    delegate: Text {
                        required property string shortName
                        text: shortName; color: root.textWarmDim; opacity: 0.7
                        font.family: Theme.fontFamily; font.pixelSize: Math.round(12*Theme.scale(root.screen)); font.italic: true
                        horizontalAlignment: Text.AlignHCenter; width: Math.round(26*Theme.scale(root.screen)) }
                }

                MonthGrid {
                    id: calendarGrid
                    Layout.fillWidth: true; spacing: 0
                    Layout.leftMargin: Math.round(2*Theme.scale(root.screen))
                    Layout.rightMargin: Math.round(2*Theme.scale(root.screen))
                    month: root.currentMonth; year: root.currentYear

                    delegate: Rectangle {
                        id: dayCell
                        required property var model
                        property bool isToday: model.today
                        property bool isCurrentMonth: model.month===calendarGrid.month
                        property var holidayInfos: { var all=[]; for (var i=0;i<root.holidays.length;i++){var h=root.holidays[i];var d=new Date(h.date);if(d.getDate()===model.day&&d.getMonth()===model.month&&d.getFullYear()===model.year)all.push(h)} for(var j=0;j<root.prodCal.length;j++){var pc=root.prodCal[j];if(pc.day===model.day)all.push({localName:pc.label,type:pc.type})} for(var k=0;k<root.calendarEvents.length;k++){var ce=root.calendarEvents[k];if(ce.day===model.day)all.push({localName:ce.title,type:"event",calendar:ce.calendar})} return all }
                        property bool hasRealHoliday: { for(var n=0;n<holidayInfos.length;n++){if(holidayInfos[n].type!=="event")return true} return false }
                        property bool isHoliday: holidayInfos.length>0
                        property bool isWeekend: model.dayOfWeek===0||model.dayOfWeek===6

                        width: Math.round(26*Theme.scale(root.screen)); height: Math.round(26*Theme.scale(root.screen))
                        radius: Math.round(Theme.cornerRadius*0.33)
                        color: { if(isToday)return Color.withAlpha(root.goldAccent,0.3); if(hasRealHoliday)return Color.withAlpha(Theme.error,0.1); if(isHoliday)return Color.withAlpha(root.goldAccent,0.22); if(isWeekend)return Color.withAlpha(root.goldAccent,0.22); if(dayMouse.containsMouse)return Color.withAlpha(root.goldAccent,0.15); return"transparent" }
                        border.color: isToday?root.goldAccent:"transparent"; border.width: isToday?1.5:0

                        Text {
                            anchors.centerIn: parent; text: model.day
                            color: { if(isToday)return root.goldAccent; if(hasRealHoliday)return Theme.error; if(isWeekend){ if(isCurrentMonth)return root.goldAccent; return Color.mix(root.textWarm,root.goldAccent,0.35) } return root.textWarm }
                            opacity: isCurrentMonth?0.9:0.3; font.family: Theme.fontFamily; font.pixelSize: Math.round(13*Theme.scale(root.screen)); font.weight: (isToday||(isWeekend&&isCurrentMonth))?Font.Bold:Font.Normal }

                        Rectangle { visible:isHoliday; width:4*Theme.scale(root.screen); height:width; radius:width/2; color:hasRealHoliday?Theme.error:root.goldAccent; anchors.top:parent.top; anchors.right:parent.right; anchors.margins:2 }

                        MouseArea { id:dayMouse; anchors.fill:dayCell; hoverEnabled:true
                            onEntered:{ if(isHoliday&&holidayInfos.length>0){ holidayTooltip.text=holidayInfos.map(function(h){return h.localName||h.label||""}).join(" · "); holidayTooltip.targetItem=dayCell; holidayTooltip.visibleWhen=true } }
                            onExited:{ holidayTooltip.visibleWhen=false }
                            onClicked:{ root.selectedDay=model.day } }
                        PanelTooltip { id:holidayTooltip; text:""; targetItem:null; visibleWhen:false }
                    }
                }

                // --- Selected day events ---
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.round(60 * Theme.scale(root.screen))
                    visible: root.selectedDay >= 0 && _selectedEvents.length > 0
                    property var _selectedEvents: {
                        if (root.selectedDay < 0) return [];
                        var result = [];
                        for (var i = 0; i < root.calendarEvents.length && result.length < 3; i++) {
                            if (root.calendarEvents[i].day === root.selectedDay)
                                result.push(root.calendarEvents[i]);
                        }
                        return result;
                    }
                    Column {
                        anchors.fill: parent
                        spacing: Math.round(2 * Theme.scale(root.screen))
                        Repeater {
                            model: parent.parent._selectedEvents
                            RowLayout {
                                spacing: Math.round(4 * Theme.scale(root.screen))
                                Rectangle {
                                    width: 5 * Theme.scale(root.screen); height: width
                                    radius: width / 2
                                    color: root.goldAccent
                                }
                                Text {
                                    text: modelData.title
                                    color: root.textWarmDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.round(11 * Theme.scale(root.screen))
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: modelData.calendar
                                    color: root.goldDim
                                    font.family: Theme.fontFamily
                                    font.pixelSize: Math.round(10 * Theme.scale(root.screen))
                                    visible: modelData.calendar !== ""
                                }
                            }
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                    text: { var todayH=[]; for(var i=0;i<root.holidays.length;i++){var h=root.holidays[i];var d=new Date(h.date);if(d.getDate()===Time.date.getDate()&&d.getMonth()===Time.date.getMonth()&&d.getFullYear()===Time.date.getFullYear())todayH.push(h.localName||h.name)} for(var j=0;j<root.prodCal.length;j++){var pc=root.prodCal[j];if(pc.day===Time.date.getDate())todayH.push(pc.label)} return todayH.length>0?todayH.join(" · "):"" }
                    color: root.textWarm; opacity:0.6; font.family: Theme.fontFamily; font.pixelSize: Math.round(12*Theme.scale(root.screen)); font.italic:true }
            }
        }
    ]
}
