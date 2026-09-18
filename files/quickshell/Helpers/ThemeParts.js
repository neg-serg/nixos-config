// ThemeParts — the pure half of the theme-parts system: JSON with comments in,
// one merged token object out.
//
// The parts of Theme.qml that only transform data used to sit between the QML
// bits that own state (the FileView, the timers, the property list), which made
// the file long and the transformations untestable. Nothing here touches QML:
// every function takes its inputs as arguments, so a test can feed it fixtures.
//
// The flat-compat map lives here too: it is what makes a theme written against
// the old flat tokens still resolve through the nested reader, and keeping it
// next to `val()` (ThemeTokens.js) is what keeps the two halves of that
// compatibility in one place.

.pragma library

// Legacy flat-compat map: nested token path → old flat key. A theme file that
// still uses `background` resolves through `colors.background`, and the strict
// token checker stays quiet about it until the removal date.
var FLAT_COMPAT_MAP = {
    'colors.background': 'background',
    'colors.surface': 'surface',
    'colors.surfaceVariant': 'surfaceVariant',
    'colors.text.primary': 'textPrimary',
    'colors.text.secondary': 'textSecondary',
    'colors.text.disabled': 'textDisabled',
    'colors.accent.primary': 'accentPrimary',
    'colors.status.error': 'error',
    'colors.status.warning': 'warning',
    'colors.highlight': 'highlight',
    'colors.onAccent': 'onAccent',
    'colors.outline': 'outline',
    'colors.shadow': 'shadow'
};

function stripJsonComments(raw) {
    try {
        var input = String(raw || "");
        if (!input.length)
            return "";
        if (input.charCodeAt(0) === 0xFEFF)
            input = input.slice(1);
        var out = "";
        var inString = false;
        var escaped = false;
        var inSingle = false;
        var inMulti = false;
        for (var i = 0; i < input.length; i++) {
            var ch = input[i];
            var next = (i + 1 < input.length) ? input[i + 1] : "";
            if (inSingle) {
                if (ch === '\n' || ch === '\r') {
                    inSingle = false;
                    out += ch;
                }
                continue;
            }
            if (inMulti) {
                if (ch === '*' && next === '/') {
                    inMulti = false;
                    i++;
                }
                continue;
            }
            if (!inString && ch === '/' && next === '/') {
                inSingle = true;
                i++;
                continue;
            }
            if (!inString && ch === '/' && next === '*') {
                inMulti = true;
                i++;
                continue;
            }
            out += ch;
            if (inString) {
                if (!escaped && ch === '"')
                    inString = false;
                escaped = (!escaped && ch === '\\');
                continue;
            }
            if (ch === '"') {
                inString = true;
                escaped = false;
            }
        }
        return out;
    } catch (e) {
        return String(raw || "");
    }
}

function parseJsonSafe(raw, fileName) {
    try {
        var cleaned = stripJsonComments(String(raw || ""));
        if (!cleaned || !String(cleaned).trim().length)
            return {};
        return JSON.parse(String(cleaned));
    } catch (e) {
        console.warn("[ThemeParts] JSON parse error in", fileName + ":", e);
        return null;
    }
}

function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function mergeThemeObjects(target, source, ctx, origin, origins) {
    if (!source)
        return;
    for (var key in source) {
        if (!source.hasOwnProperty(key))
            continue;
        var value = source[key];
        var pathKey = ctx ? (ctx + "." + key) : key;
        if (!(key in target)) {
            target[key] = value;
            origins[pathKey] = origin;
            continue;
        }
        var existing = target[key];
        if (isPlainObject(existing) && isPlainObject(value)) {
            mergeThemeObjects(existing, value, pathKey, origin, origins);
        } else {
            var prev = origins[pathKey] || "<unknown>";
            console.warn("[ThemeParts] Duplicate token", pathKey, "from", origin, "(previous:", prev + ")");
        }
    }
}

// Final removal date for flat (legacy) tokens compatibility

// Flatten a nested token tree into {"colors.text.primary": "#…", …}. The theme
// reader asks for tokens by path, and walking the object per call is what makes
// a theme lookup a chain of dynamic property reads; one pass here turns every
// later lookup into a dictionary hit.
function flatten(root) {
    var out = {};
    if (!root || typeof root !== "object")
        return out;
    (function walk(node, prefix) {
        for (var key in node) {
            var value = node[key];
            var path = prefix ? (prefix + "." + key) : key;
            if (value && typeof value === "object" && !Array.isArray(value)) {
                walk(value, path);
            } else if (value !== undefined) {
                out[path] = value;
            }
        }
    })(root, "");
    return out;
}

// Warn once per token that is missing from the theme file, unless the legacy flat
// key for it is still present (then the theme is merely old, not wrong). The
// warned set is module state: it is reset by resetWarnings() whenever the theme
// is reloaded, so a fixed theme stops warning immediately.
var _warnedMissing = {};

function resetWarnings() {
    _warnedMissing = {};
}

function warnMissingToken(path, fallback, flatTokens, lookup) {
    var key = String(path);
    // Optional override keys: do not warn when absent
    if (/^colors\.overrides\./.test(key))
        return;
    var compat = FLAT_COMPAT_MAP[key];
    var hasCompat = compat && (flatTokens && flatTokens[compat] !== undefined);
    if (hasCompat || _warnedMissing[key])
        return;
    _warnedMissing[key] = true;
    console.warn('[ThemeStrict] Missing token', key, '→ using fallback', fallback);
}
