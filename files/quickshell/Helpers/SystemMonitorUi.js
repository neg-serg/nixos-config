.pragma library

function thresholdColor(value, neutralColor, warnColor, critColor, warnThreshold, critThreshold) {
    if (typeof warnThreshold !== "number") warnThreshold = 0.5;
    if (typeof critThreshold !== "number") critThreshold = 0.8;
    var v = Number(value);
    if (!isFinite(v)) return neutralColor;
    if (v >= critThreshold) return critColor;
    if (v >= warnThreshold) return warnColor;
    return neutralColor;
}

function formatPercent(value) {
    var v = Number(value);
    if (!isFinite(v)) return "0%";
    return Math.round(v * 100) + "%";
}

function formatGiB(valueKiB) {
    var v = Number(valueKiB);
    if (!isFinite(v)) return "0.0";
    return (v / 1048576).toFixed(1);
}

function formatTemp(celsius) {
    var v = Number(celsius);
    if (!isFinite(v)) return "0\u00B0C";
    return Math.round(v) + "\u00B0C";
}

function formatKiBps(value) {
    var v = Number(value);
    if (!isFinite(v) || v < 1) return "0";
    if (v >= 1048576) return (v / 1048576).toFixed(1) + " GiB/s";
    if (v >= 1024) return (v / 1024).toFixed(1) + " MiB/s";
    return Math.round(v) + " KiB/s";
}
