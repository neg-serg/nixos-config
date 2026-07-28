pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Settings
import "../Helpers/PillHistory.js" as PillHistory

Singleton {
    id: root

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/"
    readonly property string stateFile: stateDir + "pill-tracker.json"
    readonly property string calDir: (Quickshell.env("HOME") || "/home/neg") + "/.config/vdirsyncer/calendars/pills/"

    // Public reactive properties
    readonly property bool taken: _adapter.taken
    readonly property string takenAt: _adapter.takenAt
    readonly property string todayDate: _adapter.todayDate
    readonly property var history: _adapter.history

    readonly property int streak: PillHistory.calculateStreak(
        { date: _adapter.todayDate, taken: _adapter.taken, takenAt: _adapter.takenAt },
        _adapter.history
    )

    readonly property bool reminderActive: !_adapter.taken && _deadlinePassed

    property bool _deadlinePassed: false
    property string _lastMinuteCheck: ""

    // Ensure state and calendar directories exist
    Item {
        Component.onCompleted: {
            Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
            Quickshell.execDetached(["mkdir", "-p", root.calDir]);
        }
    }

    FileView {
        id: stateFileView
        path: root.stateFile
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()
        Component.onCompleted: function() {
            reload()
            root._checkDate()
            root._checkDeadline()
            root._syncFromCalendar()
        }
        onLoadFailed: function(error) {
            console.warn("[PillTracker] load failed:", error, "— resetting to defaults")
            _adapter.todayDate = PillHistory.currentDateStr()
            _adapter.taken = false
            _adapter.takenAt = ""
            _adapter.history = []
            writeAdapter()
        }
        JsonAdapter {
            id: _adapter
            property string todayDate: PillHistory.currentDateStr()
            property bool taken: false
            property string takenAt: ""
            property var history: []
        }
    }

    // Calendar ICS path for today
    function _todayIcsPath() {
        return root.calDir + "pill-" + PillHistory.currentDateStr() + ".ics";
    }

    // Write a VEVENT to the calendar dir when pill is taken
    function _writeCalendarEvent() {
        var path = _todayIcsPath();
        var now = new Date();
        var today = PillHistory.currentDateStr();
        var dtstart = today.replace(/-/g, "");
        var summary = "Pill taken at " + _adapter.takenAt;
        // All-day event with description
        var ics = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Neg//PillTracker//EN",
            "BEGIN:VEVENT",
            "DTSTART;VALUE=DATE:" + dtstart,
            "DTEND;VALUE=DATE:" + dtstart,
            "SUMMARY:Pill \u2705",
            "DESCRIPTION:Taken at " + _adapter.takenAt,
            "CATEGORIES:Health",
            "END:VEVENT",
            "END:VCALENDAR",
            ""
        ].join("\r\n");
        Quickshell.execDetached(["sh", "-c", "cat > '" + path.replace(/'/g, "'\''") + "' << 'ICS_EOF'
" + ics + "
ICS_EOF"]);
    }

    // Delete today's ICS file when pill is untoggled
    function _deleteCalendarEvent() {
        var path = _todayIcsPath();
        Quickshell.execDetached(["rm", "-f", path]);
    }

    // On startup, check if a calendar event exists for today
    function _syncFromCalendar() {
        var path = _todayIcsPath();
        var fileText = "";
        var reader = Qt.createQmlObject('import Quickshell.Io; FileView { path: "' + path.replace(/'/g, "\'") + '"; preload: false }', root, "pillReader");
        if (reader) { fileText = reader.text() || ""; reader.destroy(); }
        if (fileText.indexOf("Pill") >= 0) {
            // Calendar says pill was taken today — restore state if not already set
            if (!_adapter.taken) {
                _adapter.taken = true;
                _adapter.takenAt = PillHistory.currentTimeStr();
                stateFileView.writeAdapter();
            }
        }
    }

    function toggle() {
        if (_adapter.taken) {
            _adapter.taken = false;
            _adapter.takenAt = "";
            _deleteCalendarEvent();
        } else {
            _adapter.taken = true;
            _adapter.takenAt = PillHistory.currentTimeStr();
            _writeCalendarEvent();
        }
        stateFileView.writeAdapter();
    }

    // Midnight reset: archive today to history, start fresh
    function _checkDate() {
        var now = PillHistory.currentDateStr();
        if (_adapter.todayDate && _adapter.todayDate !== now) {
            // Archive previous day
            var prev = {
                date: _adapter.todayDate,
                taken: _adapter.taken,
                takenAt: _adapter.takenAt
            };
            var h = _adapter.history ? _adapter.history.slice() : [];
            h.unshift(prev);
            _adapter.history = h;
            _adapter.todayDate = now;
            _adapter.taken = false;
            _adapter.takenAt = "";
            stateFileView.writeAdapter();
            // Check if calendar already has today's event
            root._syncFromCalendar();
        }
    }

    function _checkDeadline() {
        var now = PillHistory.currentTimeStr();
        if (now === root._lastMinuteCheck) return;
        root._lastMinuteCheck = now;
        var deadline = Settings.settings ? Settings.settings.pillReminderDeadline : "12:00";
        root._deadlinePassed = PillHistory.isDeadlinePassed(deadline || "12:00");
    }

    Connections {
        target: Timers
        function onTickTime() {
            root._checkDate();
            root._checkDeadline();
        }
    }
}
