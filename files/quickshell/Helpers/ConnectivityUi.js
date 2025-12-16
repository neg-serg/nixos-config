.pragma library

function clampNumber(value, min, max) {
    const n = Number(value);
    if (!isFinite(n)) return min;
    if (n < min) return min;
    if (n > max) return max;
    return n;
}

function formatKiBps(value) {
    const n = Number(value);
    if (!isFinite(n)) return "0.0";
    return n.toFixed(1);
}

function formatThroughput(rxKiBps, txKiBps) {
    const rx = Number(rxKiBps);
    const tx = Number(txKiBps);
    if ((!isFinite(rx) || rx === 0) && (!isFinite(tx) || tx === 0)) return "0";
    return `${formatKiBps(rx)}\/${formatKiBps(tx)}K`;
}

function warningColor(settings, theme) {
    const warn = settings && settings.networkNoInternetColor;
    return warn || theme.warning;
}

function errorColor(settings, theme) {
    const err = settings && settings.networkNoLinkColor;
    return err || theme.error;
}

function iconColor(hasLink, hasInternet, settings, theme) {
    if (!hasLink) return errorColor(settings, theme);
    if (!hasInternet) return warningColor(settings, theme);
    return theme.textSecondary;
}

function state(hasLink, hasInternet) {
    if (!hasLink) return "no-link";
    if (!hasInternet) return "no-internet";
    return "ok";
}
