pragma ComponentBehavior: Bound
import "../../Helpers/Holidays.js" as Holidays
import "../../Helpers/ProductionCalendar.js" as ProdCal
import "../../Helpers/CalendarEvents.js" as CalendarEvents
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import qs.Components
import qs.Services as Services
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

    // Optional pill-tracker overlay: when enabled, the calendar also marks
    // which days the pill was taken, missed, is still pending, or had no data.
    property bool showPill: false
    property var dayInfoLookup: ({})
    property var pillLookup: ({})
    readonly property var pillHistory: Services.PillTracker.history
    readonly property string pillToday: Services.PillTracker.todayDate
    readonly property bool pillTakenToday: Services.PillTracker.taken

    function updateAll() {
        holidays = []
        prodCal = ProdCal.getHolidays(currentYear, currentMonth)
        Holidays.getHolidaysForMonth(currentYear, currentMonth, function(data) { holidays = data; refreshLookups() })
        CalendarEvents.getEvents(currentYear, currentMonth, function(data) { calendarEvents = data; refreshLookups() })
        refreshLookups()
    }

    // Build per-month lookup caches so the 42 MonthGrid delegate cells perform
    // O(1) reads instead of scanning root.holidays / root.prodCal /
    // root.calendarEvents / pillHistory on every re-evaluation.
    function refreshLookups() {
        var newDayInfo = {}
        var i, key
        // Holidays are month/year-qualified; add them first so the merged array
        // keeps the original order (holidays, then production, then events).
        for (i = 0; i < holidays.length; i++) {
            var h = holidays[i]
            var d = new Date(h.date)
            if (d.getFullYear() === currentYear && d.getMonth() === currentMonth) {
                key = d.getDate()
                if (!newDayInfo[key]) newDayInfo[key] = []
                newDayInfo[key].push(h)
            }
        }
        for (i = 0; i < prodCal.length; i++) {
            var pc = prodCal[i]
            key = pc.day
            if (key === undefined || key === null) continue
            if (!newDayInfo[key]) newDayInfo[key] = []
            newDayInfo[key].push({localName: pc.label, type: pc.type})
        }
        for (i = 0; i < calendarEvents.length; i++) {
            var ce = calendarEvents[i]
            key = ce.day
            if (key === undefined || key === null) continue
            if (!newDayInfo[key]) newDayInfo[key] = []
            newDayInfo[key].push({localName: ce.title, type: "event", calendar: ce.calendar})
        }
        dayInfoLookup = newDayInfo

        var newPill = {}
        if (root.showPill) {
            // The 42-cell grid can show leading/trailing cells from the previous
            // and next months, so precompute statuses for all three months.
            for (var offset = -1; offset <= 1; offset++) {
                var ym = new Date(currentYear, currentMonth + offset, 1)
                var py = ym.getFullYear()
                var pm = ym.getMonth()
                var pdays = new Date(py, pm + 1, 0).getDate()
                for (var dd = 1; dd <= pdays; dd++) {
                    var dateKey = String(py) + "-" + String(pm + 1).padStart(2, "0") + "-" + String(dd).padStart(2, "0")
                    newPill[dateKey] = computePillStatus(dateKey, Services.PillTracker.todayDate, Services.PillTracker.history, Services.PillTracker.taken)
                }
            }
        }
        pillLookup = newPill
    }

    function computePillStatus(dateKey, today, history, takenToday) {
        if (history && Array.isArray(history)) {
            for (var i = 0; i < history.length; i++) {
                if (history[i] && history[i].date === dateKey) {
                    return history[i].taken ? "taken" : "missed";
                }
            }
        }
        if (dateKey === today) return takenToday ? "taken" : "pending";
        if (dateKey < today) return "nodata";
        return null;
    }

    function pillStatusFor(year, month, day, today, history, takenToday) {
        if (!root.showPill || !day) return null;
        var m = String(month + 1).padStart(2, "0");
        var d = String(day).padStart(2, "0");
        return computePillStatus(year + "-" + m + "-" + d, today, history, takenToday);
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

    // Rebuild the pill cache when the tracker's reactive props change, and when
    // the pill overlay is toggled, so stale statuses never leak into the grid.
    Connections {
        target: Services.PillTracker
        function onHistoryChanged() { refreshLookups() }
        function onTodayDateChanged() { refreshLookups() }
        function onTakenChanged() { refreshLookups() }
    }
    Connections {
        target: root
        function onShowPillChanged() { refreshLookups() }
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
            height: Math.round((root.showPill ? 520 : 480) * Theme.scale(root.screen))
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

                // Streak header (pill tracker only)
                RowLayout {
                    visible: root.showPill && Services.PillTracker.streak > 0
                    Layout.alignment: Qt.AlignHCenter
                    spacing: Math.round(6 * Theme.scale(root.screen))
                    MaterialIcon {
                        icon: "local_fire_department"
                        size: Math.round(14 * Theme.scale(root.screen))
                        color: Theme.warning
                    }
                    Text {
                        text: Services.PillTracker.streak + (Services.PillTracker.streak === 1 ? " day" : " days")
                        color: root.textWarmDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(12 * Theme.scale(root.screen))
                        font.weight: Font.DemiBold
                    }
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
                        property var pillStatus: {
                            if (!root.showPill) return null;
                            var dateKey = String(model.year) + "-" + String(model.month + 1).padStart(2, "0") + "-" + String(model.day).padStart(2, "0");
                            var v = root.pillLookup[dateKey];
                            return v === undefined ? null : v;
                        }
                        property var holidayInfos: {
                            var all = root.dayInfoLookup[model.day] || [];
                            if (!isCurrentMonth) {
                                // Holiday entries belong to the displayed month; strip
                                // them from adjacent-month cells while keeping the
                                // day-only production-calendar/event matches.
                                var out = [];
                                for (var i = 0; i < all.length; i++) {
                                    if (!all[i].date) out.push(all[i]);
                                }
                                return out;
                            }
                            return all;
                        }
                        property bool hasRealHoliday: { for(var n=0;n<holidayInfos.length;n++){if(holidayInfos[n].type!=="event")return true} return false }
                        property bool isHoliday: holidayInfos.length>0
                        property bool isWeekend: model.dayOfWeek===0||model.dayOfWeek===6

                        width: Math.round(26*Theme.scale(root.screen)); height: Math.round(26*Theme.scale(root.screen))
                        radius: Math.round(Theme.cornerRadius*0.33)
                        color: {
                            if(root.showPill && pillStatus==="taken") return Color.withAlpha(root.goldAccent,0.35);
                            if(root.showPill && pillStatus==="missed") return Color.withAlpha(Theme.error,0.28);
                            if(root.showPill && pillStatus==="pending") return Color.withAlpha(Theme.error,0.12);
                            if(root.showPill && pillStatus==="nodata") return Color.withAlpha(Theme.textSecondary,0.06);
                            if(isToday)return Color.withAlpha(root.goldAccent,0.3);
                            if(hasRealHoliday)return Color.withAlpha(Theme.error,0.1);
                            if(isHoliday)return Color.withAlpha(root.goldAccent,0.22);
                            if(isWeekend)return Color.withAlpha(root.goldAccent,0.22);
                            if(dayMouse.containsMouse)return Color.withAlpha(root.goldAccent,0.15);
                            return"transparent"
                        }
                        border.color: isToday?root.goldAccent:"transparent"; border.width: isToday?1.5:0

                        Text {
                            anchors.centerIn: parent; text: model.day
                            color: {
                                if(root.showPill && pillStatus==="taken") return root.goldAccent;
                                if(root.showPill && pillStatus==="missed") return Theme.error;
                                if(root.showPill && pillStatus==="pending") return Theme.textSecondary;
                                if(root.showPill && pillStatus==="nodata") return Theme.textDisabled;
                                if(isToday)return root.goldAccent;
                                if(hasRealHoliday)return Theme.error;
                                if(isWeekend){ if(isCurrentMonth)return root.goldAccent; return Color.mix(root.textWarm,root.goldAccent,0.35) }
                                return root.textWarm
                            }
                            opacity: isCurrentMonth?0.9:0.3; font.family: Theme.fontFamily; font.pixelSize: Math.round(13*Theme.scale(root.screen)); font.weight: (isToday||(isWeekend&&isCurrentMonth))?Font.Bold:Font.Normal }

                        // Weekend ring: square red outline around Sat/Sun of the
                        // current month (today keeps its gold ring).
                        Rectangle {
                            visible: isWeekend && isCurrentMonth && !isToday
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: 0
                            color: "transparent"
                            border.color: Theme.error
                            border.width: Math.max(1, Math.round(1.2 * Theme.scale(root.screen)))
                        }

                        Rectangle { visible:isHoliday; width:4*Theme.scale(root.screen); height:width; radius:width/2; color:hasRealHoliday?Theme.error:root.goldAccent; anchors.top:parent.top; anchors.right:parent.right; anchors.margins:2 }
                        Rectangle { visible:root.showPill&&(pillStatus==="taken"||pillStatus==="missed"); width:4*Theme.scale(root.screen); height:width; radius:width/2; color:pillStatus==="taken"?root.goldAccent:Theme.error; anchors.top:parent.top; anchors.left:parent.left; anchors.margins:2 }

                        MouseArea { id:dayMouse; anchors.fill:dayCell; hoverEnabled:true
                            onEntered:{
                                var tip=[]
                                if(isHoliday&&holidayInfos.length>0) tip.push(holidayInfos.map(function(h){return h.localName||h.label||""}).join(" · "))
                                if(root.showPill && pillStatus==="taken") tip.push("Pill: taken")
                                if(root.showPill && pillStatus==="missed") tip.push("Pill: missed")
                                if(root.showPill && pillStatus==="pending") tip.push("Pill: pending")
                                if(tip.length>0){ holidayTooltip.text=tip.join(" · "); holidayTooltip.targetItem=dayCell; holidayTooltip.visibleWhen=true }
                            }
                            onExited:{ holidayTooltip.visibleWhen=false }
                            onClicked:{ root.selectedDay=model.day } }
                        PanelTooltip { id:holidayTooltip; text:""; targetItem:null; visibleWhen:false }
                    }
                }

                // Pill tracker legend (pill only)
                RowLayout {
                    visible: root.showPill
                    spacing: Math.round(10 * Theme.scale(root.screen))
                    Layout.alignment: Qt.AlignHCenter

                    Rectangle {
                        width: Math.round(8 * Theme.scale(root.screen)); height: width; radius: width / 2
                        color: root.goldAccent
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "Taken"
                        color: root.textWarmDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(10 * Theme.scale(root.screen))
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle {
                        width: Math.round(8 * Theme.scale(root.screen)); height: width; radius: width / 2
                        color: Theme.error
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "Missed"
                        color: root.textWarmDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(10 * Theme.scale(root.screen))
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle {
                        width: Math.round(8 * Theme.scale(root.screen)); height: width; radius: width / 2
                        color: Theme.error
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "Pending"
                        color: root.textWarmDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(10 * Theme.scale(root.screen))
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle {
                        width: Math.round(8 * Theme.scale(root.screen)); height: width; radius: width / 2
                        color: Theme.textDisabled
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Text {
                        text: "No data"
                        color: root.textWarmDim
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(10 * Theme.scale(root.screen))
                        opacity: 0.8
                        Layout.alignment: Qt.AlignVCenter
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
                    text: { var todayInfos = root.dayInfoLookup[Time.date.getDate()] || []; var todayH=[]; for(var i=0;i<todayInfos.length;i++){ var ti=todayInfos[i]; if(typeof ti.calendar === "string")continue; if(ti.date){ var dd=new Date(ti.date); if(!(dd.getFullYear()===Time.date.getFullYear()&&dd.getMonth()===Time.date.getMonth()&&dd.getDate()===Time.date.getDate()))continue } todayH.push(ti.localName||ti.name) } return todayH.length>0?todayH.join(" · "):"" }
                    color: root.textWarm; opacity:0.6; font.family: Theme.fontFamily; font.pixelSize: Math.round(12*Theme.scale(root.screen)); font.italic:true }
            }
        }
    ]
}
