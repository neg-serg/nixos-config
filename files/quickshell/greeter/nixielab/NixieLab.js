.pragma library

// Shared helpers for the nixie settings menu (qs.nixielab): JSONC reading and
// the #AARRGGBB colour conversion the theme tokens are written in.
// Everything is string in / string or number out, so the callers stay plain QML.

// Strip // and /* */ comments, leaving string literals untouched.
function stripComments(text) {
    var out = [];
    var i = 0;
    var n = text.length;
    var inString = false;
    var escaped = false;
    while (i < n) {
        var c = text.charAt(i);
        if (inString) {
            out.push(c);
            if (escaped)
                escaped = false;
            else if (c === "\\")
                escaped = true;
            else if (c === "\"")
                inString = false;
            i += 1;
        } else if (c === "\"") {
            inString = true;
            out.push(c);
            i += 1;
        } else if (c === "/" && text.charAt(i + 1) === "/") {
            while (i < n && text.charAt(i) !== "\n")
                i += 1;
        } else if (c === "/" && text.charAt(i + 1) === "*") {
            i += 2;
            while (i < n && !(text.charAt(i) === "*" && text.charAt(i + 1) === "/"))
                i += 1;
            i += 2;
        } else {
            out.push(c);
            i += 1;
        }
    }
    return out.join("");
}

// Drop commas that sit directly before a closing brace or bracket. The scan is
// string aware, so a comma inside a value is never touched.
function stripTrailingCommas(text) {
    var out = [];
    var i = 0;
    var n = text.length;
    var inString = false;
    var escaped = false;
    while (i < n) {
        var c = text.charAt(i);
        if (inString) {
            out.push(c);
            if (escaped)
                escaped = false;
            else if (c === "\\")
                escaped = true;
            else if (c === "\"")
                inString = false;
            i += 1;
            continue;
        }
        if (c === "\"") {
            inString = true;
            out.push(c);
            i += 1;
            continue;
        }
        if (c === ",") {
            var j = i + 1;
            while (j < n && /\s/.test(text.charAt(j)))
                j += 1;
            var next = text.charAt(j);
            if (next === "}" || next === "]") {
                i += 1; // the comma is dropped
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    return out.join("");
}

// Parse a JSONC part into a plain JS value. Throws on malformed input; an
// empty file is a valid empty object. Callers catch and report.
function parseJsonc(text) {
    var source = text ? String(text) : "";
    if (source.trim() === "")
        return {};
    return JSON.parse(stripTrailingCommas(stripComments(source)));
}

function two(value) {
    var v = Math.max(0, Math.min(255, Math.round(value)));
    var s = v.toString(16);
    return s.length < 2 ? ("0" + s) : s;
}

// QML colour components (0..1 each) -> the theme's #AARRGGBB string.
function argbFromComponents(r, g, b, a) {
    return "#" + two(a * 255) + two(r * 255) + two(g * 255) + two(b * 255);
}

// "#AARRGGBB" | "#RRGGBB" | without the hash -> {a,r,g,b} floats 0..1, or null.
function componentsFromArgb(text) {
    if (text === undefined || text === null)
        return null;
    var s = String(text).trim();
    if (s.charAt(0) === "#")
        s = s.slice(1);
    if (!/^[0-9a-fA-F]+$/.test(s))
        return null;
    var a = 1.0;
    if (s.length === 8)
        a = parseInt(s.slice(0, 2), 16) / 255;
    else if (s.length !== 6)
        return null;
    var body = s.length === 8 ? s.slice(2) : s;
    return {
        a: a,
        r: parseInt(body.slice(0, 2), 16) / 255,
        g: parseInt(body.slice(2, 4), 16) / 255,
        b: parseInt(body.slice(4, 6), 16) / 255
    };
}
