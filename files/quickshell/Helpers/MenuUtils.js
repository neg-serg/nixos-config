.pragma library

function unwindMenuChildren(opener) {
    try {
        const ch = opener && opener.children ? opener.children : null;
        if (!ch) return [];
        const v = ch.values;
        if (typeof v === 'function') return [...v.call(ch)];
        if (v && v.length !== undefined) return v;
        if (ch && ch.length !== undefined) return ch;
        return [];
    } catch (_) { console.warn("[MenuUtils.unwindMenuChildren]", _); return []; }
}

// The label a menu entry is shown and matched with (QsMenuEntry exposes the
// text under different names depending on the toolkit that published it).
function entryLabel(item) {
    if (!item)
        return "";
    var t = item.text;
    if (!t || !String(t).length)
        t = item.label;
    if (!t || !String(t).length)
        t = item.title;
    return (t && String(t).length) ? String(t) : "";
}

var MenuUtils = {
    unwindMenuChildren: unwindMenuChildren,
    entryLabel: entryLabel
};
