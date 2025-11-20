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
    } catch (_) { return []; }
}

var MenuUtils = {
    unwindMenuChildren: unwindMenuChildren
};
