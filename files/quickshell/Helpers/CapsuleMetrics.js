.pragma library

function padding(theme, scale) {
    try {
        var pad = Math.max(2, Math.round(theme.uiSpacingXSmall * scale));
        return pad;
    } catch (e) {
        console.warn("[CapsuleMetrics.padding]", e);
        return Math.max(2, Math.round(scale * 2));
    }
}

function inner(theme, scale) {
    try {
        var innerPx = Math.max(1, Math.round(theme.fontSizeSmall * theme.timeFontScale * scale));
        return innerPx;
    } catch (e) {
        console.warn("[CapsuleMetrics.inner]", e);
        return Math.max(10, Math.round(12 * scale));
    }
}

function metrics(theme, scale) {
    var pad = padding(theme, scale);
    var innerPx = inner(theme, scale);
    return {
        padding: pad,
        inner: innerPx,
        height: innerPx + pad * 2
    };
}
