pragma Singleton
import QtQuick
import qs.Components
import qs.Settings

/*!
 * SystemMonitor — singleton service that polls procfs/sysfs for system metrics.
 * Uses ProcessRunner (poll mode) with one-line shell output per probe.
 */
Item {
    id: root

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
        running: true
        onTriggered: {
            if (!cpuRamProbe.running) cpuRamProbe.start();
            if (!swapProbe.running) swapProbe.start();
            if (!ioProbe.running) ioProbe.start();
            if (root._tempPath && !tempProbe.running) tempProbe.start();
            if (root._gpuPath && !gpuProbe.running) gpuProbe.start();
        }
    }

    // ── One-time GPU path discovery (pick discrete GPU by largest VRAM) ──
    ProcessRunner {
        id: gpuDiscover
        cmd: ["dash", "-c",
            "best=''; bv=0;" +
            "for d in /sys/class/drm/card[0-9]*/device; do " +
            "  [ -f \"$d/gpu_busy_percent\" ] || continue;" +
            "  v=$(cat \"$d/mem_info_vram_total\" 2>/dev/null) || v=0;" +
            "  [ \"$v\" -gt \"$bv\" ] && bv=$v && best=$d;" +
            "done;" +
            "[ -n \"$best\" ] && echo \"$best/gpu_busy_percent\""]
        autoStart: true
        restartOnExit: false
        onLine: (s) => {
            var p = String(s).trim();
            if (p) { root._gpuPath = p; root.gpuAvailable = true; }
        }
    }

    // ── One-time temperature path discovery (k10temp/coretemp/zenpower via hwmon) ──
    ProcessRunner {
        id: tempDiscover
        cmd: ["dash", "-c",
            "for h in /sys/class/hwmon/hwmon*/; do " +
            "  n=$(cat \"${h}name\" 2>/dev/null);" +
            "  case $n in k10temp|coretemp|zenpower) " +
            "    f=\"${h}temp1_input\";" +
            "    [ -r \"$f\" ] && echo \"$f\" && exit;; esac;" +
            "done;" +
            "f=/sys/class/thermal/thermal_zone0/temp;" +
            "[ -r \"$f\" ] && echo \"$f\""]
        autoStart: true
        restartOnExit: false
        onLine: (s) => {
            var p = String(s).trim();
            if (p) root._tempPath = p;
        }
    }

    // ── CPU + RAM probe ──
    // Outputs: "cpu <user> <nice> <sys> <idle> <iowait> <irq> <softirq> <steal>"
    // then: "mem <totalKB> <availKB>"
    ProcessRunner {
        id: cpuRamProbe
        cmd: ["dash", "-c",
            "head -1 /proc/stat;" +
            "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print \"mem\",t,a}' /proc/meminfo"]
        autoStart: true
        restartOnExit: false
        onLine: (s) => {
            try {
                var line = String(s).trim();
                if (line.indexOf("cpu ") === 0) {
                    root._parseCpu(line);
                } else if (line.indexOf("mem ") === 0) {
                    var parts = line.split(/\s+/);
                    var totalKB = parseInt(parts[1], 10) || 0;
                    var availKB = parseInt(parts[2], 10) || 0;
                    root.ramTotalGiB = totalKB / 1048576;
                    var usedKB = totalKB - availKB;
                    root.ramUsedGiB = usedKB / 1048576;
                    root.ramPercent = totalKB > 0
                        ? Math.max(0, Math.min(1, usedKB / totalKB))
                        : 0;
                }
            } catch (e) { console.warn("[SystemMonitor.cpuRam]", e); }
        }
    }

    // ── Swap probe ──
    // Outputs: "swap <totalKB> <usedKB>" or "swap 0 0"
    ProcessRunner {
        id: swapProbe
        cmd: ["dash", "-c",
            "awk 'NR>1{t+=$3;u+=$4} END{print \"swap\",t+0,u+0}' /proc/swaps"]
        autoStart: true
        restartOnExit: false
        onLine: (s) => {
            try {
                var parts = String(s).trim().split(/\s+/);
                if (parts[0] !== "swap") return;
                var totalKB = parseInt(parts[1], 10) || 0;
                var usedKB = parseInt(parts[2], 10) || 0;
                root.swapAvailable = totalKB > 0;
                root.swapTotalGiB = totalKB / 1048576;
                root.swapUsedGiB = usedKB / 1048576;
                root.swapPercent = totalKB > 0
                    ? Math.max(0, Math.min(1, usedKB / totalKB))
                    : 0;
            } catch (e) { console.warn("[SystemMonitor.swap]", e); }
        }
    }

    // ── Disk I/O probe ──
    // Outputs: "io <totalReadSectors> <totalWriteSectors>"
    ProcessRunner {
        id: ioProbe
        cmd: ["dash", "-c",
            "awk '$3~/^(sd[a-z]|nvme[0-9]+n[0-9]+|vd[a-z])$/{r+=$6;w+=$10} END{print \"io\",r+0,w+0}' /proc/diskstats"]
        autoStart: true
        restartOnExit: false
        onLine: (s) => {
            try {
                var parts = String(s).trim().split(/\s+/);
                if (parts[0] !== "io") return;
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
                root._prevIo = { rd: totalRead, wr: totalWrite };
                root._prevIoTs = now;
            } catch (e) { console.warn("[SystemMonitor.io]", e); }
        }
    }

    // ── CPU temperature probe (path resolved once by tempDiscover) ──
    ProcessRunner {
        id: tempProbe
        cmd: root._tempPath ? ["cat", root._tempPath] : []
        autoStart: false
        restartOnExit: false
        onLine: (s) => {
            try {
                var millideg = parseInt(String(s).trim(), 10) || 0;
                root.cpuTempCelsius = millideg / 1000;
                root.cpuTempPercent = Math.max(0, Math.min(1, (root.cpuTempCelsius - 30) / 70));
            } catch (e) { console.warn("[SystemMonitor.temp]", e); }
        }
    }

    // ── GPU probe (path resolved once by gpuDiscover) ──
    ProcessRunner {
        id: gpuProbe
        cmd: root._gpuPath ? ["cat", root._gpuPath] : []
        autoStart: false
        restartOnExit: false
        onLine: (s) => {
            try {
                var val = parseInt(String(s).trim(), 10) || 0;
                root.gpuPercent = Math.max(0, Math.min(1, val / 100));
            } catch (e) { console.warn("[SystemMonitor.gpu]", e); }
        }
    }

    // ── CPU delta parser ──
    function _parseCpu(line) {
        var parts = line.split(/\s+/);
        if (parts.length < 5) return;
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
        _prevCpu = { total: total, idle: idleAll };
    }
}
