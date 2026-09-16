// HttpJson.js — shared HTTP GET + TTL-cache helpers for QML JS modules.
// Consumers: Helpers/Holidays.js, Helpers/Weather.js.
// Usage from a QML JS resource: Qt.include("./HttpJson.js")

function _now() { return Date.now(); }

function _buildUrl(base, paramsObj) {
    var qs = [];
    var obj = paramsObj || {};
    for (var key in obj) {
        if (!obj.hasOwnProperty(key)) continue;
        var val = obj[key];
        if (val === undefined || val === null) continue;
        qs.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(val)));
    }
    return qs.length ? (base + "?" + qs.join("&")) : base;
}

function _readCache(store, key) {
    var entry = store[key];
    if (!entry) return null;
    var t = _now();
    if (entry.errorUntil && t < entry.errorUntil)
        return { error: true, retryAt: entry.errorUntil };
    if (entry.expiry && t < entry.expiry)
        return { value: entry.value };
    delete store[key];
    return null;
}

function _writeCacheSuccess(store, key, value, ttlMs) {
    store[key] = { value: value, expiry: _now() + (ttlMs || 86400000) };
}

function _writeCacheError(store, key, errTtl) {
    store[key] = { errorUntil: _now() + (errTtl || 60000) };
}

function _httpGetJson(url, timeoutMs, success, fail, userAgent) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        if (timeoutMs !== undefined && timeoutMs !== null) xhr.timeout = timeoutMs;
        try {
            if (xhr.setRequestHeader) {
                try { xhr.setRequestHeader('Accept', 'application/json'); } catch (e1) { /* header API unavailable */ }
                var ua = (userAgent === undefined || userAgent === null) ? 'Quickshell' : String(userAgent).trim();
                if (!ua) ua = 'Quickshell';
                try { xhr.setRequestHeader('User-Agent', ua); } catch (e2) { /* header API unavailable */ }
            }
        } catch (e) { /* ignore header setting failures */ }
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                try { success && success(JSON.parse(xhr.responseText)); }
                catch (pe) { fail && fail({ type: 'parse', message: 'Failed to parse JSON' }); }
            } else {
                var retryAfter = 0;
                try {
                    var ra = xhr.getResponseHeader && xhr.getResponseHeader('Retry-After');
                    if (ra) retryAfter = Number(ra) * 1000;
                } catch (he) { /* Retry-After header unavailable */ }
                fail && fail({ type: 'http', status: xhr.status, retryAfter: retryAfter });
            }
        };
        xhr.ontimeout = function() { fail && fail({ type: 'timeout' }); };
        xhr.onerror = function() { fail && fail({ type: 'network' }); };
        xhr.send();
    } catch (e) {
        fail && fail({ type: 'exception', message: String(e) });
    }
}
