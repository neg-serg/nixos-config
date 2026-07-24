pragma ComponentBehavior: Bound
import "../../Helpers/Holidays.js" as Holidays
import "../../Helpers/ProductionCalendar.js" as ProdCal
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
    property var prodCal: []
    property int currentYear: Time.date.getFullYear()
    property int currentMonth: Time.date.getMonth()
    property int selectedDay: -1

    function updateAll() {
        holidays = []
        prodCal = ProdCal.getHolidays(currentYear, currentMonth)
        Holidays.getHolidaysForMonth(currentYear, currentMonth, function(data) { holidays = data })
    }

    onOpened: {
        currentYear = Time.date.getFullYear()
        currentMonth = Time.date.getMonth()
        updateAll()
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
            anchors.right: parent.right
            anchors.bottomMargin: Theme.calendarPopupMargin
            anchors.rightMargin: Theme.calendarPopupMargin

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

                // ── Illustration (2x larger, compact spacing) ──
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: Math.round(140*Theme.scale(root.screen)); color: "transparent"
                    HiDpiImage {
                        id: monthIllustration
                        anchors.centerIn: parent; width: parent.width-16; height: parent.height-8; fillMode: Image.PreserveAspectFit
                        source: Qt.resolvedUrl("../../art/calendar/"+(root.currentMonth+1)+".svg")
                        Behavior on source { NumberAnimation { target:monthFade; property:"opacity"; from:0.3; to:1.0; duration:400 } }
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
                        property var holidayInfos: { var all=[]; for (var i=0;i<root.holidays.length;i++){var h=root.holidays[i];var d=new Date(h.date);if(d.getDate()===model.day&&d.getMonth()===model.month&&d.getFullYear()===model.year)all.push(h)} for(var j=0;j<root.prodCal.length;j++){var pc=root.prodCal[j];if(pc.day===model.day)all.push({localName:pc.label,type:pc.type})} return all }
                        property bool isHoliday: holidayInfos.length>0
                        property bool isWeekend: model.dayOfWeek===0||model.dayOfWeek===6

                        width: Math.round(26*Theme.scale(root.screen)); height: Math.round(26*Theme.scale(root.screen))
                        radius: Math.round(Theme.cornerRadius*0.33)
                        color: { if(isToday)return Color.withAlpha(root.goldAccent,0.3); if(isHoliday)return Color.withAlpha(Theme.error,0.1); if(isWeekend)return Color.withAlpha(root.goldAccent,0.06); if(dayMouse.containsMouse)return Color.withAlpha(root.goldAccent,0.15); return"transparent" }
                        border.color: isToday?root.goldAccent:"transparent"; border.width: isToday?1.5:0

                        Text {
                            anchors.centerIn: parent; text: model.day
                            color: { if(isToday)return root.goldAccent; if(isHoliday)return Theme.error; if(isWeekend)return Color.withAlpha(root.textWarmDim,0.5); return root.textWarm }
                            opacity: isCurrentMonth?0.9:0.3; font.family: Theme.fontFamily; font.pixelSize: Math.round(13*Theme.scale(root.screen)); font.weight: isToday?Font.Bold:Font.Normal }

                        Rectangle { visible:isHoliday; width:4*Theme.scale(root.screen); height:width; radius:width/2; color:Theme.error; anchors.top:parent.top; anchors.right:parent.right; anchors.margins:2 }

                        MouseArea { id:dayMouse; anchors.fill:dayCell; hoverEnabled:true
                            onEntered:{ if(isHoliday&&holidayInfos.length>0){ holidayTooltip.text=holidayInfos.map(function(h){return h.localName||h.label||""}).join(" · "); holidayTooltip.targetItem=dayCell; holidayTooltip.visibleWhen=true } }
                            onExited:{ holidayTooltip.visibleWhen=false }
                            onClicked:{ root.selectedDay=model.day } }
                        PanelTooltip { id:holidayTooltip; text:""; targetItem:null; visibleWhen:false }
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
