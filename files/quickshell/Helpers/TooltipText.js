.pragma library

function normalizeHints(hints) {
    if (!hints) return [];
    if (Array.isArray(hints)) return hints;
    return [hints];
}

function compose(title, value, hints) {
    var parts = [];
    var titleText = (title === undefined || title === null) ? "" : String(title).trim();
    var valueText = (value === undefined || value === null) ? "" : String(value).trim();
    if (titleText && valueText)
        parts.push(titleText + ": " + valueText);
    else if (titleText)
        parts.push(titleText);
    else if (valueText)
        parts.push(valueText);

    var hintLines = normalizeHints(hints)
        .map(function(line) { return line === undefined || line === null ? "" : String(line).trim(); })
        .filter(function(line) { return line.length > 0; });

    for (var i = 0; i < hintLines.length; ++i)
        parts.push(hintLines[i]);

    return parts.join("\n");
}

function composePercent(title, valuePercent, hints) {
    var val = (valuePercent === undefined || valuePercent === null)
        ? "0%"
        : (String(valuePercent).trim().endsWith("%") ? String(valuePercent) : (String(valuePercent) + "%"));
    return compose(title, val, hints);
}

var TooltipText = {
    compose: compose,
    composePercent: composePercent
};
