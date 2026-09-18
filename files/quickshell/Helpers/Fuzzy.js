.pragma library

// Fuzzy matching for menu lists (tray menus, submenus).
//
// This is a port of the `lusty-fuzzy` crate (lusty repo: crates/lusty-fuzzy —
// scorer.rs, rank.rs, layout.rs). The pickers and the tray share one algorithm
// on purpose: two implementations of "how a score is computed" drift
// immediately, so the port is pinned instead of trusted:
//
//   * files/quickshell/Helpers/tests/fuzzy-vectors.json is generated from the
//     crate (`lusty --fuzzy-vectors`);
//   * scripts/dev/check-fuzzy-parity.mjs replays that fixture against this file
//     and fails on any difference in score, order or spans.
//
// Do not touch a constant, a tie-break or the span extraction without
// regenerating the fixture (`scripts/dev/gen-fuzzy-vectors.sh`), and keep
// WEIGHTS_VERSION in sync with the crate's.
//
// Menus differ from the file pickers in policy, not in math: no first-letter
// anchor (people type a word from the middle of a label) and Unicode case
// folding (labels from DBus apps are localized: "настройки" must find
// "Настройки"). Both are RankOpts flags, mirroring the crate.

var WEIGHTS_VERSION = 1;
// Mirrors scorer.rs: the anchor's winning weights. Scores are doubles on both
// sides and the operation order is identical, so results are bit-equal.
var LEADING_PENALTY = 0.012; // per skipped byte before the first match
var INNER_GAP = 0.02; // per skipped byte between two matches
var CONSECUTIVE_BONUS = 0.05;

// UTF-8 encoding: QJSEngine has no TextEncoder, and every offset in this file
// (scores, spans) is a *byte* offset, exactly like the Rust side.
function utf8Bytes(s) {
    var out = [];
    for (var i = 0; i < s.length; i++) {
        var cp = s.codePointAt(i);
        if (cp > 0xffff)
            i++;
        if (cp < 0x80) {
            out.push(cp);
        } else if (cp < 0x800) {
            out.push(0xc0 | (cp >> 6), 0x80 | (cp & 63));
        } else if (cp < 0x10000) {
            out.push(0xe0 | (cp >> 12), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
        } else {
            out.push(0xf0 | (cp >> 18), 0x80 | ((cp >> 12) & 63), 0x80 | ((cp >> 6) & 63), 0x80 | (cp & 63));
        }
    }
    return out;
}

// Rust lowers with `to_ascii_lowercase`: only A-Z fold, the rest is untouched.
// Using `String.toLowerCase` here would fold Cyrillic and diverge.
function asciiLower(bytes) {
    var out = new Array(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
        var b = bytes[i];
        out[i] = (b >= 65 && b <= 90) ? b + 32 : b;
    }
    return out;
}

function bonusFor(bytes, i) {
    if (i === 0)
        return 0.9;
    var ch = bytes[i];
    if (ch === 47) // '/'
        return 0.9;
    var prev = bytes[i - 1];
    if (prev === 45 || prev === 95 || prev === 32 || prev === 46) // -_ .
        return 0.8;
    if (prev === 47) // '/'
        return 0.9;
    // camelCase: lower-case byte followed by an upper-case one.
    if (prev >= 97 && prev <= 122 && ch >= 65 && ch <= 90)
        return 0.7;
    return 0.0;
}

function hasMatch(hay, needle) {
    var a = 0;
    var b = 0;
    while (a < needle.length && b < hay.length) {
        if (needle[a] === hay[b])
            a++;
        b++;
    }
    return a === needle.length;
}

// Hot path: two DP rows, no backtracking (mirrors Scorer::score).
function score(label, query) {
    if (query.length === 0)
        return 0.75; // neutral score for an empty query
    var raw = utf8Bytes(label);
    var hay = asciiLower(raw);
    var needle = asciiLower(utf8Bytes(query));
    if (needle.length > hay.length)
        return 0.0;
    if (!hasMatch(hay, needle))
        return 0.0;
    var m = hay.length;
    var n = needle.length;
    var neg = -Infinity;
    var prev = new Array(m + 1);
    var cur = new Array(m + 1);
    for (var j = 0; j <= m; j++) {
        prev[j] = neg;
        cur[j] = neg;
    }
    var best = neg;
    for (var i = 1; i <= n; i++) {
        var bestGap = neg;
        for (var k = 1; k <= m; k++) {
            var scoreJ = neg;
            if (needle[i - 1] === hay[k - 1]) {
                var bon = bonusFor(raw, k - 1);
                if (i === 1) {
                    scoreJ = bon - LEADING_PENALTY * (k - 1);
                } else {
                    var cand = neg;
                    if (isFinite(prev[k - 1]))
                        cand = prev[k - 1] + CONSECUTIVE_BONUS;
                    if (isFinite(bestGap)) {
                        var viaGap = bestGap - INNER_GAP * (k - 1);
                        if (viaGap > cand)
                            cand = viaGap;
                    }
                    if (isFinite(cand))
                        scoreJ = cand + bon;
                }
            }
            cur[k] = scoreJ;
            if (isFinite(scoreJ) && i === n && scoreJ > best)
                best = scoreJ;
            if (isFinite(prev[k])) {
                var withK = prev[k] + INNER_GAP * k;
                if (withK > bestGap)
                    bestGap = withK;
            }
        }
        var swap = prev;
        prev = cur;
        cur = swap;
    }
    return isFinite(best) ? best : 0.0;
}

// Score plus coalesced byte spans of the winning alignment (mirrors
// score_with_spans). Result: { score: number, spans: [[start, end], ...] }.
function scoreWithSpans(label, query) {
    if (query.length === 0)
        return { score: 0.75, spans: [] };
    var raw = utf8Bytes(label);
    var hay = asciiLower(raw);
    var needle = asciiLower(utf8Bytes(query));
    if (needle.length > hay.length || !hasMatch(hay, needle))
        return { score: 0.0, spans: [] };

    var m = hay.length;
    var n = needle.length;
    var neg = -Infinity;
    var CONSEC = -1;
    var dp = [];
    var pred = [];
    for (var i = 0; i <= n; i++) {
        var row = new Array(m + 1);
        var prow = new Array(m + 1);
        for (var j = 0; j <= m; j++) {
            row[j] = neg;
            prow[j] = CONSEC;
        }
        dp.push(row);
        pred.push(prow);
    }

    for (var ii = 1; ii <= n; ii++) {
        var bestGap = neg;
        var bestGapK = 0;
        for (var jj = 1; jj <= m; jj++) {
            var scoreJ = neg;
            if (needle[ii - 1] === hay[jj - 1]) {
                var bon = bonusFor(raw, jj - 1);
                if (ii === 1) {
                    scoreJ = bon - LEADING_PENALTY * (jj - 1);
                } else {
                    var cand = neg;
                    var fromGap = false;
                    if (isFinite(dp[ii - 1][jj - 1]))
                        cand = dp[ii - 1][jj - 1] + CONSECUTIVE_BONUS;
                    if (isFinite(bestGap)) {
                        var viaGap = bestGap - INNER_GAP * (jj - 1);
                        if (viaGap > cand) {
                            cand = viaGap;
                            fromGap = true;
                        }
                    }
                    if (isFinite(cand)) {
                        scoreJ = cand + bon;
                        pred[ii][jj] = fromGap ? bestGapK : CONSEC;
                    }
                }
            }
            dp[ii][jj] = scoreJ;
            if (isFinite(dp[ii - 1][jj])) {
                var withK = dp[ii - 1][jj] + INNER_GAP * jj;
                if (withK > bestGap) {
                    bestGap = withK;
                    bestGapK = jj;
                }
            }
        }
    }

    // First maximum in the last row, exactly like the Rust side.
    var best = neg;
    var bestJ = 0;
    for (var jb = 1; jb <= m; jb++) {
        if (isFinite(dp[n][jb]) && dp[n][jb] > best) {
            best = dp[n][jb];
            bestJ = jb;
        }
    }
    if (!isFinite(best))
        return { score: 0.0, spans: [] };

    var matched = [];
    var i = n;
    var j = bestJ;
    while (i >= 1) {
        matched.push(j - 1);
        if (i === 1)
            break;
        if (pred[i][j] === CONSEC) {
            i -= 1;
            j -= 1;
        } else {
            j = pred[i][j];
            i -= 1;
        }
    }
    matched.reverse();
    var spans = [];
    for (var mi = 0; mi < matched.length; mi++) {
        var pos = matched[mi];
        var last = spans[spans.length - 1];
        if (last && last[1] === pos)
            last[1] = pos + 1;
        else
            spans.push([pos, pos + 1]);
    }
    return { score: best, spans: spans };
}

// Case-fold with a byte-offset map back into the original string (mirrors
// fold_with_map): spans must address the label the UI drew, not a folded copy.
function foldWithMap(s) {
    var folded = "";
    var map = [];
    var srcByte = 0;
    for (var i = 0; i < s.length;) {
        var cp = s.codePointAt(i);
        var ch = String.fromCodePoint(cp);
        var step = (cp > 0xffff) ? 2 : 1;
        var lowered = ch.toLowerCase();
        for (var li = 0; li < lowered.length;) {
            var lcp = lowered.codePointAt(li);
            var lch = String.fromCodePoint(lcp);
            var lstep = (lcp > 0xffff) ? 2 : 1;
            folded += lch;
            var bytes = utf8Bytes(lch);
            for (var bi = 0; bi < bytes.length; bi++)
                map.push(srcByte);
            li += lstep;
        }
        srcByte += utf8Bytes(ch).length;
        i += step;
    }
    map.push(srcByte); // sentinel: end of the original string
    return { text: folded, map: map };
}

function unmapSpans(spans, map) {
    var out = [];
    for (var i = 0; i < spans.length; i++) {
        var a = spans[i][0];
        var b = spans[i][1];
        var start = (a < map.length) ? map[a] : 0;
        var end = (b < map.length) ? map[b] : start;
        var last = out[out.length - 1];
        if (last && last[1] === start)
            last[1] = end;
        else
            out.push([start, end]);
    }
    return out;
}

// RU (йцукен) → EN, mirrored from layout.rs / the Lua table (`lusty --ru-map`
// is the parity dump for that table).
var RU_TO_EN = {
    "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i",
    "щ": "o", "з": "p", "х": "[", "ъ": "]", "ф": "a", "ы": "s", "в": "d", "а": "f",
    "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'", "я": "z",
    "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": "."
};

function normalizeQueryChar(c) {
    var lower = c.toLowerCase();
    var mapped = RU_TO_EN[lower];
    if (mapped === undefined)
        mapped = lower;
    var out = (c !== lower) ? mapped.toUpperCase() : mapped;
    var code = out.charCodeAt(0);
    if (out.length === 1 && ((code >= 33 && code <= 126) || code === 32))
        return out;
    return null;
}

function normalizeQuery(query) {
    var out = "";
    for (var i = 0; i < query.length; i++) {
        var mapped = normalizeQueryChar(query[i]);
        if (mapped !== null)
            out += mapped;
    }
    return out;
}

function isAscii(s) {
    for (var i = 0; i < s.length; i++) {
        if (s.charCodeAt(i) > 127)
            return false;
    }
    return true;
}

function rankEffective(labels, query, opts) {
    var foldCase = opts.foldCase !== false;
    var needle = foldCase ? foldWithMap(query).text : query;
    var first = null;
    if (opts.anchor === "prefix-on-first" && needle.length > 0) {
        var b = utf8Bytes(needle)[0];
        first = (b >= 65 && b <= 90) ? b + 32 : b;
    }
    var out = [];
    for (var i = 0; i < labels.length; i++) {
        var hay = labels[i];
        var map = null;
        if (foldCase) {
            var folded = foldWithMap(labels[i]);
            hay = folded.text;
            map = folded.map;
        }
        if (first !== null) {
            var hb = utf8Bytes(hay)[0];
            if (hb !== first)
                continue;
        }
        var res = scoreWithSpans(hay, needle);
        if (res.score !== 0.0) {
            out.push({
                index: i,
                label: labels[i],
                score: res.score,
                spans: (map !== null) ? unmapSpans(res.spans, map) : res.spans
            });
        }
    }
    out.sort(function(a, b) { return (b.score - a.score) || (a.index - b.index); });
    return out;
}

function rank(labels, query, optsIn) {
    var opts = optsIn || { anchor: "none", layout: "ru-to-en-fallback", foldCase: true };
    if (query.length === 0) {
        var all = [];
        for (var i = 0; i < labels.length; i++)
            all.push({ index: i, label: labels[i], score: 0.75, spans: [] });
        return all;
    }
    var out = rankEffective(labels, query, opts);
    if (opts.layout !== "off" && !isAscii(query)) {
        var mapped = normalizeQuery(query);
        if (mapped !== query && mapped.length > 0 && isAscii(mapped)) {
            var alt = rankEffective(labels, mapped, opts);
            var byIndex = {};
            for (var a = 0; a < out.length; a++)
                byIndex[out[a].index] = out[a];
            for (var b2 = 0; b2 < alt.length; b2++) {
                var prev = byIndex[alt[b2].index];
                if (!prev || alt[b2].score > prev.score)
                    byIndex[alt[b2].index] = alt[b2];
            }
            out = [];
            for (var key in byIndex)
                out.push(byIndex[key]);
            out.sort(function(x, y) { return (y.score - x.score) || (x.index - y.index); });
        }
    }
    return out;
}

// ── UI helpers (not part of the parity contract) ─────────────────────────────

// Byte spans → UTF-16 index ranges, for slicing the label the UI renders.
function byteSpansToCharRanges(text, spans) {
    var byteToChar = [0];
    var byteCount = 0;
    var charIndex = 0;
    while (charIndex < text.length) {
        var cp = text.codePointAt(charIndex);
        charIndex += (cp > 0xffff) ? 2 : 1;
        byteCount += utf8Bytes(String.fromCodePoint(cp)).length;
        byteToChar.push(byteCount);
    }
    var out = [];
    for (var i = 0; i < spans.length; i++) {
        var startChar = 0;
        var endChar = 0;
        for (var c = 0; c < byteToChar.length; c++) {
            if (byteToChar[c] <= spans[i][0])
                startChar = c;
            if (byteToChar[c] <= spans[i][1])
                endChar = c;
        }
        if (endChar > startChar)
            out.push([startChar, endChar]);
    }
    return out;
}

function escapeHtml(text) {
    return String(text)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

// Rich-text label with the matched runs wrapped in `spanCss` (QML Text with
// textFormat: RichText). Spans are byte ranges from rank(); they are converted
// to string ranges first and every slice is escaped, because menu labels come
// from third-party apps verbatim.
function highlightMarkup(label, spans, spanCss) {
    if (!spans || spans.length === 0)
        return escapeHtml(label);
    var ranges = byteSpansToCharRanges(label, spans);
    if (ranges.length === 0)
        return escapeHtml(label);
    var out = "";
    var pos = 0;
    for (var i = 0; i < ranges.length; i++) {
        var start = ranges[i][0];
        var end = ranges[i][1];
        if (start > pos)
            out += escapeHtml(label.slice(pos, start));
        out += "<span style='" + spanCss + "'>" + escapeHtml(label.slice(start, end)) + "</span>";
        pos = end;
    }
    return out + escapeHtml(label.slice(pos));
}

// DBus menu labels carry mnemonic markers ("&File" from Qt, "_Open" from GTK).
// Matching uses the cleaned text; the label shown to the user stays as-is.
function stripMnemonic(label) {
    if (!label)
        return "";
    var out = label.replace(/&&/g, "\u0000").replace(/__/g, "\u0001");
    out = out.replace(/[&_]/g, "");
    return out.replace(/\u0000/g, "&").replace(/\u0001/g, "_").trim();
}

var Fuzzy = {
    WEIGHTS_VERSION: WEIGHTS_VERSION,
    score: score,
    scoreWithSpans: scoreWithSpans,
    rank: rank,
    normalizeQuery: normalizeQuery,
    stripMnemonic: stripMnemonic,
    byteSpansToCharRanges: byteSpansToCharRanges,
    highlightMarkup: highlightMarkup
};
