// WorkspaceName — how a Hyprland workspace name is read: the leading private-use
// glyph (every workspace here is named "󰆍term", "󰖟web", …) and whether the rest
// means "this is a terminal workspace".
//
// Both the bar and the workspace indicator parsed this themselves, with the same
// three terminal icons and the same startsWith/endsWith("term") rule written out
// twice — one copy drifting from the other would make the bar and its own
// indicator disagree about the same workspace. The rule lives here once.

.pragma library

// Note: JS libraries here do not import each other (a `.pragma library` file
// cannot use QML imports inside the script), so the private-use-area test is
// repeated from RichText.js rather than shared. This module is what keeps the
// *workspace* rule in one place — the bar and the workspace indicator both ask
// it — which is where the drift risk actually was.

// The glyphs that mean a terminal workspace (Font Awesome terminal variants).
var TERMINAL_ICONS = ["\uf120", "\ue795", "\ue7a2"];

// Private-use area, where the workspace glyphs live.
function isPua(codePoint) {
    return codePoint >= 0xE000 && codePoint <= 0xF8FF;
}

// The leading glyph of a workspace name, or "" when it has none.
function leadingIcon(name) {
    if (!name || typeof name !== "string" || name.length === 0) return "";
    const cp = name.codePointAt(0);
    return isPua(cp) ? String.fromCodePoint(cp) : "";
}

// The name without its leading glyph (leading whitespace trimmed).
function restAfterIcon(name) {
    if (!name || typeof name !== "string" || name.length === 0) return "";
    const cp = name.codePointAt(0);
    if (!isPua(cp)) return name;
    const skip = cp > 0xFFFF ? 2 : 1;
    return name.substring(skip).replace(/^\s+/, "");
}

// Whether a workspace name denotes a terminal workspace: the glyph says so, or
// the remaining name starts/ends with "term" ("term", "term2", "dev-term").
function isTerminal(name) {
    const glyph = leadingIcon(name);
    const rest = restAfterIcon(name).toLowerCase().trim();
    if (glyph && TERMINAL_ICONS.indexOf(glyph) !== -1) return true;
    if (rest.startsWith("term")) return true;
    if (rest.endsWith("term")) return true;
    return false;
}
