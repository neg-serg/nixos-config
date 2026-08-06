.pragma library

// CalendarEvents — fetch calendar events from khal/vdirsyncer
// Singleton pattern; imported by Calendar.qml

var _cache = {};    // { "YYYY-MM": { events: [...], ts: <timestamp> } }

function _cacheDir() {
    var home = Quickshell.env("HOME") || "/home/neg";
    return home + "/.cache/quickshell";
}

function _monthKey(year, month) {
    return year + "-" + String(month + 1).padStart(2, "0");
}

function _lastDayOfMonth(year, month) {
    return new Date(year, month + 1, 0).getDate();
}

function _stripAnsi(s) {
    return s.replace(/\x1b\[[0-9;]*m/g, "");
}

// getEvents(year, month, callback)
//   year:   full year (e.g. 2026)
//   month:  0-indexed (0 = January)
//   callback(events): called with array of {day, title, calendar}
function getEvents(year, month, callback) {
    var key = _monthKey(year, month);
    var now = Date.now();

    // Serve from cache if fresh (< 2 min)
    if (_cache[key] && (now - _cache[key].ts) < 120000) {
        if (callback) callback(_cache[key].events);
        return;
    }

    var m = String(month + 1).padStart(2, "0");
    var lastDay = _lastDayOfMonth(year, month);
    var startDate = year + "-" + m + "-01";
    var endDate = year + "-" + m + "-" + String(lastDay).padStart(2, "0");
    var outFile = '"' + _cacheDir() + "/khal-events-" + key + '.txt"';

    // Spawn khal list → temp file
    Quickshell.execDetached([
        "sh", "-c",
        'mkdir -p "' + _cacheDir() + '" && ' +
        'khal list --format "{start-date}|{title}|{calendar}" ' +
        startDate + " " + endDate +
        " > " + outFile + " 2>/dev/null"
    ]);

    // Schedule read after khal completes
    var timer = Qt.createQmlObject(
        'import QtQuick; Timer { interval: 600; repeat: false }',
        null, "khal-poll-" + key
    );

    timer.triggered.connect(function () {
        _readAndParse(key, outFile.replace(/"/g, ""), callback);
        timer.destroy();
    });

    timer.start();
}

function _readAndParse(key, filePath, callback) {
    var fv;
    try {
        fv = Qt.createQmlObject(
            'import Quickshell.Io; FileView { path: "' +
            filePath.replace(/'/g, "\\'") +
            '"; preload: false }',
            null, "khal-fv-" + key
        );
    } catch (e) {
        // FileView creation failed (likely no file) — callback with empty
        _cache[key] = { events: [], ts: Date.now() };
        if (callback) callback([]);
        return;
    }

    var raw = "";
    try { raw = fv ? (fv.text() || "") : ""; } catch (e) { /* ignore */ }
    if (fv) fv.destroy();

    var events = [];
    if (raw) {
        var lines = raw.split("\n");
        for (var i = 0; i < lines.length; i++) {
            var line = _stripAnsi(lines[i]).trim();
            if (!line) continue;
            var parts = line.split("|");
            if (parts.length >= 3) {
                var datePart = parts[0].trim();
                var dayMatch = datePart.match(/-(\d{2})$/);
                if (dayMatch) {
                    events.push({
                        day: parseInt(dayMatch[1], 10),
                        title: parts[1].trim(),
                        calendar: parts[2].trim()
                    });
                }
            }
        }
    }

    _cache[key] = { events: events, ts: Date.now() };
    if (callback) callback(events);
}

// refresh(year, month) — invalidate cache for a given month
function refresh(year, month) {
    var key = _monthKey(year, month);
    delete _cache[key];
}
