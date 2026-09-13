pragma Singleton
import QtQuick
import qs.Components
import qs.Settings
import qs.Services as Services

/*!
 * SystemMonitor — singleton service that polls procfs/sysfs for system metrics.
 * Uses ProcessRunner (poll mode) with one-line shell output per probe.
 */
Item {
    id: root

    // Polling follows panelLayout (evaluated when the service is created).
    property bool pollEnabled: !!Services.WidgetRegistry.visibleSetFor(
        Settings.settings ? Settings.settings.panelLayout : undefined)["sysmon"]

    // ── CPU ──
    property real cpuPercent: 0.0

    // ── RAM ──
    property real ramPercent: 0.0
    property real ramUsedGiB: 0.0
    property real ramTotalGiB: 0.0

    // ── Swap ──
    property real swapPercent: 0.0
    property real swapUsedGiB: 0.0
    property real swapTotalGiB: 0.0
    property bool swapAvailable: false

    // ── Disk I/O ──
    property real ioPercent: 0.0
    property real ioReadKiBps: 0.0
    property real ioWriteKiBps: 0.0

    // ── GPU ──
    property real gpuPercent: 0.0
    property bool gpuAvailable: false

    // ── Temperature ──
    property real cpuTempCelsius: 0.0
    property real cpuTempPercent: 0.0

    // ── Internal state ──
    property var _prevCpu: null
    property var _prevIo: null
    property real _prevIoTs: 0
    property string _gpuPath: ""
    property string _tempPath: ""

    readonly property int _pollMs: {
        var v = Settings.settings.systemMonitorPollMs;
        return (typeof v === "number" && v >= 500) ? v : 2000;
    }

    readonly property real _ioMaxKiBps: {
        var v = Settings.settings.systemMonitorIoMaxMiBps;
        return (typeof v === "number" && v > 0) ? v * 1024 : 512000;
    }

    // ── Poll timer ──
    Timer {
        id: pollTimer
        interval: root._pollMs
        repeat: true
        running: root.pollEnabled
        onTriggered: {
            if (!probeAll.running)
                probeAll.start();
        }
    }

    // ── One-time GPU path discovery (pick discrete GPU by largest VRAM) ──
    ProcessRunner {
        id: gpuDiscover
        cmd: ["dash", "-c", "best=''; bv=0;" + "for d in /sys/class/drm/card[0-9]*/device; do " + "  [ -f \"$d/gpu_busy_percent\" ] || continue;" + "  v=$(cat \"$d/mem_info_vram_total\" 2>/dev/null) || v=0;" + "  [ \"$v\" -gt \"$bv\" ] && bv=$v && best=$d;" + "done;" + "[ -n \"$best\" ] && echo \"$best/gpu_busy_percent\""]
        autoStart: true
        restartOnExit: false
        onLine: s => {
            var p = String(s).trim();
            if (p) {
                root._gpuPath = p;
                root.gpuAvailable = true;
            }
        }
    }

    // ── One-time temperature path discovery (k10temp/coretemp/zenpower via hwmon) ──
    ProcessRunner {
        id: tempDiscover
        cmd: ["dash", "-c", "for h in /sys/class/hwmon/hwmon*/; do " + "  n=$(cat \"${h}name\" 2>/dev/null);" + "  case $n in k10temp|coretemp|zenpower) " + "    f=\"${h}temp1_input\";" + "    [ -r \"$f\" ] && echo \"$f\" && exit;; esac;" + "done;" + "f=/sys/class/thermal/thermal_zone0/temp;" + "[ -r \"$f\" ] && echo \"$f\""]
        autoStart: true
        restartOnExit: false
        onLine: s => {
            var p = String(s).trim();
            if (p)
                root._tempPath = p;
        }
    }

    // ── System probe: one shell + one awk per poll ──
    // Tagged output: "cpu <user..steal>", "mem <totalKB> <availKB>",
    // "swap <totalKB> <usedKB>", "io <readSectors> <writeSectors>",
    // "temp <millideg>" and "gpu <busyPercent>".
    //
    // This replaces five separate runners, which spawned dash, head, awk and
    // two cats (nine processes) every _pollMs. Measured at ~135 spawns/min,
    // that churn cost ~0.6% of a core on its own; one awk reading all four
    // procfs files plus the discovered sysfs paths costs two processes.
    readonly property string _awkProgram: [
        'FILENAME=="/proc/stat"      { if (FNR==1) print "cpu", $2,$3,$4,$5,$6,$7,$8,$9; next }',
        'FILENAME=="/proc/meminfo"   { if ($1=="MemTotal:") t=$2; else if ($1=="MemAvailable:") a=$2; next }',
        'FILENAME=="/proc/swaps"     { if (FNR>1) { st+=$3; su+=$4 } next }',
        'FILENAME=="/proc/diskstats" { if ($3 ~ /^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$/) { r+=$6; w+=$10 } next }',
        'FILENAME==tp                { print "temp", $1+0; next }',
        'FILENAME==gp                { print "gpu", $1+0; next }',
        'END { print "mem", t+0, a+0; print "swap", st+0, su+0; print "io", r+0, w+0 }'
    ].join("; ")

    readonly property var _probeCmd: {
        var tp = String(root._tempPath || "");
        var gp = String(root._gpuPath || "");
        var files = ["/proc/stat", "/proc/meminfo", "/proc/swaps", "/proc/diskstats"];
        if (tp) files.push(tp);
        if (gp) files.push(gp);
        return ["dash", "-c", "awk -v tp='" + tp + "' -v gp='" + gp + "' '" + root._awkProgram + "' " + files.join(" ")];
    }

    ProcessRunner {
        id: probeAll
        cmd: root._probeCmd
        autoStart: root.pollEnabled
        restartOnExit: false
        onLine: s => root._handleProbeLine(s)
    }

    // Routes a tagged probe line to its parser.
    function _handleProbeLine(s) {
        try {
            var line = String(s).trim();
            if (line.length === 0)
                return;
            var tag = line.split(/\s+/)[0];
            if (tag === "cpu") { _parseCpu(line); return; }
            if (tag === "mem") { _parseMem(line); return; }
            if (tag === "swap") { _parseSwap(line); return; }
            if (tag === "io") { _parseIo(line); return; }
            if (tag === "temp") { _parseTemp(line); return; }
            if (tag === "gpu") { _parseGpu(line); return; }
        } catch (e) {
            console.warn("[SystemMonitor.probe]", e);
        }
    }

    function _parseMem(line) {
        var parts = line.split(/\s+/);
        var totalKB = parseInt(parts[1], 10) || 0;
        var availKB = parseInt(parts[2], 10) || 0;
        root.ramTotalGiB = totalKB / 1048576;
        var usedKB = totalKB - availKB;
        root.ramUsedGiB = usedKB / 1048576;
        root.ramPercent = totalKB > 0 ? Math.max(0, Math.min(1, usedKB / totalKB)) : 0;
    }

    // "swap <totalKB> <usedKB>" or "swap 0 0"
    function _parseSwap(line) {
        var parts = line.split(/\s+/);
        var totalKB = parseInt(parts[1], 10) || 0;
        var usedKB = parseInt(parts[2], 10) || 0;
        root.swapAvailable = totalKB > 0;
        root.swapTotalGiB = totalKB / 1048576;
        root.swapUsedGiB = usedKB / 1048576;
        root.swapPercent = totalKB > 0 ? Math.max(0, Math.min(1, usedKB / totalKB)) : 0;
    }

    // "io <totalReadSectors> <totalWriteSectors>"
    function _parseIo(line) {
        var parts = line.split(/\s+/);
        var totalRead = parseInt(parts[1], 10) || 0;
        var totalWrite = parseInt(parts[2], 10) || 0;
        var now = Date.now();
        if (root._prevIo !== null && root._prevIoTs > 0) {
            var dtSec = (now - root._prevIoTs) / 1000;
            if (dtSec > 0) {
                var rdKiBps = ((totalRead - root._prevIo.rd) * 0.5) / dtSec;
                var wrKiBps = ((totalWrite - root._prevIo.wr) * 0.5) / dtSec;
                root.ioReadKiBps = Math.max(0, rdKiBps);
                root.ioWriteKiBps = Math.max(0, wrKiBps);
                var totalKiBps = root.ioReadKiBps + root.ioWriteKiBps;
                root.ioPercent = Math.max(0, Math.min(1, totalKiBps / root._ioMaxKiBps));
            }
        }
        root._prevIo = {
            rd: totalRead,
            wr: totalWrite
        };
        root._prevIoTs = now;
    }

    // "temp <millideg>" (path resolved once by tempDiscover)
    function _parseTemp(line) {
        var millideg = parseInt(line.split(/\s+/)[1], 10) || 0;
        root.cpuTempCelsius = millideg / 1000;
        root.cpuTempPercent = Math.max(0, Math.min(1, (root.cpuTempCelsius - 30) / 70));
    }

    // "gpu <busyPercent>" (path resolved once by gpuDiscover)
    function _parseGpu(line) {
        var val = parseInt(line.split(/\s+/)[1], 10) || 0;
        root.gpuPercent = Math.max(0, Math.min(1, val / 100));
    }

    // ── CPU delta parser ──
    function _parseCpu(line) {
        var parts = line.split(/\s+/);
        if (parts.length < 5)
            return;
        var user = parseInt(parts[1], 10) || 0;
        var nice = parseInt(parts[2], 10) || 0;
        var system = parseInt(parts[3], 10) || 0;
        var idle = parseInt(parts[4], 10) || 0;
        var iowait = parseInt(parts[5], 10) || 0;
        var irq = parseInt(parts[6], 10) || 0;
        var softirq = parseInt(parts[7], 10) || 0;
        var steal = parseInt(parts[8], 10) || 0;
        var total = user + nice + system + idle + iowait + irq + softirq + steal;
        var idleAll = idle + iowait;

        if (_prevCpu !== null) {
            var dTotal = total - _prevCpu.total;
            var dIdle = idleAll - _prevCpu.idle;
            if (dTotal > 0) {
                root.cpuPercent = Math.max(0, Math.min(1, (dTotal - dIdle) / dTotal));
            }
        }
        _prevCpu = {
            total: total,
            idle: idleAll
        };
    }
}
