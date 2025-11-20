// Shared helpers for building URLs, handling TTL caches, and ensuring httpGetJson exists.
// QML JS files should `Qt.include("./HttpCache.js")` and call the exported functions.

try { Qt.include("./Http.js"); } catch (e) {}

function _hcNow() { return Date.now(); }

function _hcQsFrom(obj) {
    var parts = [];
    for (var k in obj) {
        if (!obj || !obj.hasOwnProperty(k)) continue;
        var v = obj[k];
        if (v === undefined || v === null) continue;
        parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(v)));
    }
    return parts.join("&");
}

function _hcBuildUrl(base, paramsObj) {
    try {
        if (typeof URL !== "undefined" && typeof URLSearchParams !== "undefined") {
            var u = new URL(base);
            var p = new URLSearchParams();
            for (var key in paramsObj) {
                if (!paramsObj.hasOwnProperty(key)) continue;
                var val = paramsObj[key];
                if (val === undefined || val === null) continue;
                p.set(key, String(val));
            }
            u.search = p.toString();
            return u.toString();
        }
    } catch (e) { /* fallthrough to manual qs */ }
    var qs = _hcQsFrom(paramsObj || {});
    return qs ? (base + "?" + qs) : base;
}

function _hcReadEntry(store, key) {
    var entry = store[key];
    if (!entry) return null;
    var t = _hcNow();
    if (entry.errorUntil && t < entry.errorUntil)
        return { error: true, retryAt: entry.errorUntil };
    if (entry.expiry && t < entry.expiry)
        return { value: entry.value };
    delete store[key];
    return null;
}

function _hcWriteSuccess(store, key, value, ttlMs) {
    store[key] = { value: value, expiry: _hcNow() + ttlMs };
}

function _hcWriteError(store, key, errorTtlMs) {
    store[key] = { errorUntil: _hcNow() + errorTtlMs };
}

function _hcHttpFallback(url, timeoutMs, success, fail, userAgent) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        if (timeoutMs !== undefined && timeoutMs !== null) xhr.timeout = timeoutMs;
        try {
            if (xhr.setRequestHeader) {
                try { xhr.setRequestHeader('Accept', 'application/json'); } catch (e1) {}
                if (userAgent) { try { xhr.setRequestHeader('User-Agent', String(userAgent)); } catch (e2) {} }
            }
        } catch (e) {}
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            var status = xhr.status;
            if (status === 200) {
                try { success && success(JSON.parse(xhr.responseText)); }
                catch (parseErr) { fail && fail({ type: 'parse', message: 'Failed to parse JSON' }); }
            } else {
                var retryAfter = 0;
                try {
                    var ra = xhr.getResponseHeader && xhr.getResponseHeader('Retry-After');
                    if (ra) retryAfter = Number(ra) * 1000;
                } catch (hdrErr) {}
                fail && fail({ type: 'http', status: status, retryAfter: retryAfter });
            }
        };
        xhr.ontimeout = function(){ fail && fail({ type: 'timeout' }); };
        xhr.onerror = function(){ fail && fail({ type: 'network' }); };
        xhr.send();
    } catch (e) {
        fail && fail({ type: 'exception', message: String(e) });
    }
}

function _hcHttpGetJson(url, timeoutMs, success, fail, userAgent) {
    if (typeof httpGetJson === 'function')
        return httpGetJson(url, timeoutMs, success, fail, userAgent);
    return _hcHttpFallback(url, timeoutMs, success, fail, userAgent);
}

var HttpCache = {
    now: _hcNow,
    qsFrom: _hcQsFrom,
    buildUrl: _hcBuildUrl,
    readEntry: _hcReadEntry,
    writeSuccess: _hcWriteSuccess,
    writeError: _hcWriteError,
    httpGetJson: _hcHttpGetJson
};
