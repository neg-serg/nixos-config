//
// Nixie settings lab (nixie-lab)
// (moved out of the docs tree; keep it in sync with the code it describes)
//
//
// The lab is a live settings menu for the login clock. It is built from reusable widgets
// (`qs.nixielab`) and mounted into two development harnesses only; the real login screen stays a lock
// surface and gains nothing interactive. Every knob writes a runtime override into
// `GreeterTheme.overrides`, so the running shader follows the hand immediately and nothing is written
// to disk until Save.
//
// ## Files
//
// | file                                              | what it is                                                      |
// | ------------------------------------------------- | --------------------------------------------------------------- |
// | `files/quickshell/greeter/nixielab/`              | the widget kit and the assembled panel (`qs.nixielab`)          |
// | `files/quickshell/greeter/nixielab/NixieMenu.qml` | the panel: sections, presets, Save / Reset / Export             |
// | `files/quickshell/greeter/nixielab/NixieLab.js`   | JSONC parsing and the `#AARRGGBB` conversion helpers            |
// | `files/quickshell/greeter/tube-lab.qml`           | the tube workbench; shows the menu always                       |
// | `files/quickshell/greeter/preview.qml`            | the login-card preview; shows the menu only when asked          |
// | `files/quickshell/Theme/greeter.jsonc`            | the commented repository part: source of truth for the defaults |
//
// ## Opening the lab
//
// The login preview mounts the real `LockContent.qml` and can host the menu:
//
//     qs -p files/quickshell/greeter/preview.qml              # login screen only
//     PREVIEW_LAB=1 qs -p files/quickshell/greeter/preview.qml # + the settings menu
//
// `F10` toggles the menu during a preview run. The tube workbench always shows the menu, because it is
// the surface the widget kit was built for:
//
//     qs -p files/quickshell/greeter/tube-lab.qml
//
// Both harnesses need a logged-in session (`XDG_CONFIG_HOME/quickshell/Theme/.theme.json`), like any
// other preview under `files/quickshell/greeter/`.
//
// ## Editing model
//
// - While a slider is dragged, the value lives only in `GreeterTheme.overrides` (a process-local map);
//   the preview follows it because every binding in `NixieClock`/`NixieTube` reads through
//   `GreeterTheme.effective()`. Releasing the mouse does not touch any file.
// - `Save` is the only disk path. `Reset` writes the repository defaults explicitly. `Export` is
//   read-only.
// - Sections, in order: Presets, Discharge (glow, temperature, exposure, glow colour, glass tint,
//   wallpaper tint), Glass (glass colour, cathode colour, highlight, warmth, wire, stack), Camera
//   (yaw, distance, pitch, pointer follow, follow range), Row (digit size, tube margin, spacing),
//   Motion (restrike, restrike length, shimmer, shimmer period, jitter), Format (24 h, leading zero),
//   Quality (shader tier, ageing, base), Actions.
//
// ## What Save touches, and what it does not
//
// `Save` writes only the keys whose value differs from what the user's part already said:
//
// | path                                       | touched by Save | notes                                                              |
// | ------------------------------------------ | --------------- | ------------------------------------------------------------------ |
// | `~/.config/quickshell/Theme/greeter.jsonc` | yes             | the user's machine-state part; atomically replaced                 |
// | `~/.config/quickshell/Theme/.theme.json`   | no              | a merge artifact rebuilt by the main shell's theme merge           |
// | `files/quickshell/Theme/greeter.jsonc`     | no              | the commented repository part; patched outside the lab, never here |
//
// The write itself is the same shape as the shell's theme merge: the new JSON is composed and parse
// checked first, written to a sibling `*.new`, and renamed over the part. The menu waits about 250 ms
// after the Save click before writing, so a burst of clicks cannot produce a burst of writes; a second
// Save with no further edits writes nothing. After the write the part is read back and checked against
// the values that were sent; the panel reports whether the write verified.
//
// ### Copy-once caveat
//
// The user's part is machine state, not a source file: it has no comments after the first Save (the
// JSON is reformatted) and it is copied once from the repository by the owner. The repository part
// stays the commented truth, and a value that should land there is applied outside the lab — never by
// the panel. `Export` shows the current values as a repository-ready snippet for exactly that.
//
// ### Reset
//
// `Reset` does not delete keys: because the hardcoded fallback for `nixieTempK` differs from the
// repository default, deleting a key would silently resurrect the wrong value. It writes the explicit
// defaults of every menu token instead, read from the repository part when it is reachable and from an
// embedded map otherwise, then verifies the file like a Save. The picture returns to the defaults at
// once, before the write lands.
//
// ## Presets
//
// | button (UI)    | what it sets                                |
// | -------------- | ------------------------------------------- |
// | Vintage        | `nixieTempK` 2100, `nixieExposure` 2.5      |
// | Modern amber   | `nixieTempK` 2400, `nixieExposure` 1.5      |
// | Cyan tube      | `nixieTint` `#cc66e0ff`                     |
// | Wallpaper-lit  | `nixieTintWallpaper` 0.35                   |
// | Camera 15°/10° | `nixieViewPitch` 15, `nixieViewAngle` 10    |
// | Dim/off        | `nixieGlow` 0                               |
// | Reset          | the repository defaults, as described above |
//
// ## llvmpipe / GPU caveat
//
// In an environment without a usable GPU (for example a sandbox that cannot open `/dev/dri`) the
// preview and the workbench fall back to llvmpipe, Mesa's software rasteriser. The menu still works,
// but the preview is slow, the first frame after a change can take a moment, and absolute frame or CPU
// numbers say nothing about a real GPU. Compare runs in the same environment, relatively.
//
// If the panel reports that a write could not be verified, the process running the menu could not
// create and rename the temporary file next to the user's part. Save needs write permission on the
// directory, not only on the file: an atomic replace creates `greeter.jsonc.new` and renames it.

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
