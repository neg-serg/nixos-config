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

    // Ensure state directory exists
    Item {
        Component.onCompleted: {
            Quickshell.execDetached(["mkdir", "-p", root.stateDir]);
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

    function toggle() {
        if (_adapter.taken) {
            _adapter.taken = false;
            _adapter.takenAt = "";
        } else {
            _adapter.taken = true;
            _adapter.takenAt = PillHistory.currentTimeStr();
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
        }
    }

    function _checkDeadline() {
        var now = PillHistory.currentTimeStr();
        if (now === root._lastMinuteCheck) return;
        root._lastMinuteCheck = now;
        var deadline = Settings.settings ? Settings.settings.pillReminderDeadline : "10:00";
        root._deadlinePassed = PillHistory.isDeadlinePassed(deadline || "10:00");
    }

    Connections {
        target: Timers
        function onTickTime() {
            root._checkDate();
            root._checkDeadline();
        }
    }
}
