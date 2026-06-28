.pragma library

function currentDateStr() {
    var d = new Date();
    var y = d.getFullYear();
    var m = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
}

function currentTimeStr() {
    var d = new Date();
    var h = String(d.getHours()).padStart(2, "0");
    var min = String(d.getMinutes()).padStart(2, "0");
    return h + ":" + min;
}

function calculateStreak(today, history) {
    var count = 0;
    if (today && today.taken) count = 1;
    else return 0;

    if (!history || !Array.isArray(history)) return count;

    var sorted = history.slice().sort(function(a, b) {
        return a.date < b.date ? 1 : a.date > b.date ? -1 : 0;
    });

    var prev = today.date;
    for (var i = 0; i < sorted.length; i++) {
        var entry = sorted[i];
        if (!entry || !entry.taken) break;
        var expected = prevDay(prev);
        if (entry.date !== expected) break;
        count++;
        prev = entry.date;
    }
    return count;
}

function prevDay(dateStr) {
    var parts = dateStr.split("-");
    var d = new Date(parseInt(parts[0]), parseInt(parts[1]) - 1, parseInt(parts[2]));
    d.setDate(d.getDate() - 1);
    var y = d.getFullYear();
    var m = String(d.getMonth() + 1).padStart(2, "0");
    var day = String(d.getDate()).padStart(2, "0");
    return y + "-" + m + "-" + day;
}

function isDeadlinePassed(deadlineStr) {
    if (!deadlineStr || deadlineStr.indexOf(":") < 0) return false;
    var parts = deadlineStr.split(":");
    var dh = parseInt(parts[0]);
    var dm = parseInt(parts[1]);
    var now = new Date();
    var nh = now.getHours();
    var nm = now.getMinutes();
    return (nh > dh) || (nh === dh && nm >= dm);
}

function calendarData(year, month, todayState, history) {
    var first = new Date(year, month, 1);
    var startDow = (first.getDay() + 6) % 7; // Monday=0
    var daysInMonth = new Date(year, month + 1, 0).getDate();

    var lookup = {};
    if (todayState && todayState.date) {
        lookup[todayState.date] = todayState;
    }
    if (history && Array.isArray(history)) {
        for (var i = 0; i < history.length; i++) {
            if (history[i] && history[i].date) {
                lookup[history[i].date] = history[i];
            }
        }
    }

    var todayStr = currentDateStr();
    var cells = [];
    for (var c = 0; c < 42; c++) {
        var dayNum = c - startDow + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
            cells.push({ day: 0, inMonth: false, status: null, takenAt: "" });
            continue;
        }
        var m = String(month + 1).padStart(2, "0");
        var d = String(dayNum).padStart(2, "0");
        var dateKey = year + "-" + m + "-" + d;
        var entry = lookup[dateKey];
        var status;
        if (entry) {
            status = entry.taken ? "taken" : "missed";
        } else if (dateKey < todayStr) {
            status = "nodata";
        } else if (dateKey === todayStr) {
            status = "missed"; // not taken yet today
        } else {
            status = null; // future
        }
        cells.push({
            day: dayNum,
            inMonth: true,
            status: status,
            takenAt: (entry && entry.takenAt) ? entry.takenAt : ""
        });
    }
    return cells;
}
