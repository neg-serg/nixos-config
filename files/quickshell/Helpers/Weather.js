// In-memory caches with TTL
var _geoCache = {}; // key: cityLower -> { value: {lat, lon}, expiry: ts, errorUntil?: ts }
var _weatherCache = {}; // key: cityLower -> { value: weatherObject, expiry: ts, errorUntil?: ts }
try { Qt.include("./HttpCache.js"); } catch (e) { }
var __httpCache = (typeof HttpCache === "object") ? HttpCache : null;
var _httpGetJson = __httpCache && __httpCache.httpGetJson ? __httpCache.httpGetJson : function(url, timeoutMs, success, fail, userAgent) {
    fail && fail({ type: 'exception', message: 'HttpCache helper missing' });
};
var _now = __httpCache && __httpCache.now ? __httpCache.now : function() { return Date.now(); };
var _buildUrl = __httpCache && __httpCache.buildUrl ? __httpCache.buildUrl : function(base, paramsObj) {
    var qs = [];
    var obj = paramsObj || {};
    for (var key in obj) {
        if (!obj.hasOwnProperty(key)) continue;
        var val = obj[key];
        if (val === undefined || val === null) continue;
        qs.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(val)));
    }
    return qs.length ? (base + "?" + qs.join("&")) : base;
};
var _readCache = __httpCache && __httpCache.readEntry ? __httpCache.readEntry : function() { return null; };
var _writeCacheSuccess = __httpCache && __httpCache.writeSuccess ? __httpCache.writeSuccess : function(store, key, value, ttlMs) { store[key] = { value: value, expiry: _now() + ttlMs }; };
var _writeCacheError = __httpCache && __httpCache.writeError ? __httpCache.writeError : function(store, key, errTtl) { store[key] = { errorUntil: _now() + errTtl }; };


// Defaults (can be overridden via options argument)
var DEFAULTS = {
    geocodeTtlMs: 24 * 60 * 60 * 1000,   // 24h
    weatherTtlMs: 5 * 60 * 1000,         // 5m
    errorTtlMs: 2 * 60 * 1000,           // 2m backoff for 429/5xx
    timeoutMs: 8000                      // 8s timeout
};

// Use httpGetJson from Helpers/Http.js

function fetchCoordinates(city, callback, errorCallback, options) {
    options = options || {};
    var cfg = {
        geocodeTtlMs: options.geocodeTtlMs || DEFAULTS.geocodeTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs
    };
    var key = String(city || "").trim().toLowerCase();
    if (!key) {
        if (errorCallback) errorCallback("City is empty");
        return;
    }

    var cached = _readCache(_geoCache, key);
    if (cached) {
        if (cached.error) {
            errorCallback && errorCallback("Geocoding temporarily unavailable; retry later");
            return;
        }
        if (cached.value) {
            callback(cached.value.lat, cached.value.lon);
            return;
        }
    }

    var geoUrl = _buildUrl("https://geocoding-api.open-meteo.com/v1/search", {
        name: city,
        language: "en",
        format: "json",
        count: 1
    });

    // Use shared HTTP helper with User-Agent
    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";
    var dbg = !!(options && options.debug);
    _httpGetJson(geoUrl, cfg.timeoutMs, function(geoData) {
        try {
            if (geoData && geoData.results && geoData.results.length > 0) {
                var lat = geoData.results[0].latitude;
                var lon = geoData.results[0].longitude;
                _writeCacheSuccess(_geoCache, key, { lat: lat, lon: lon }, cfg.geocodeTtlMs);
                callback(lat, lon);
            } else {
                _writeCacheError(_geoCache, key, cfg.errorTtlMs);
                errorCallback && errorCallback("City not found");
            }
        } catch (e) {
            _writeCacheError(_geoCache, key, cfg.errorTtlMs);
            errorCallback && errorCallback("Failed to parse geocoding data");
        }
    }, function(err) {
        if (err) {
            var backoff = (err.retryAfter && err.retryAfter > 0) ? err.retryAfter : 0;
            if (!backoff && (err.status === 429 || (err.status >= 500 && err.status <= 599))) backoff = cfg.errorTtlMs;
            if (backoff) writeCacheError(_geoCache, key, backoff);
        }
        errorCallback && errorCallback("Geocoding error: " + (err.status || err.type || "unknown"));
    }, _ua);
}

function fetchWeather(latitude, longitude, callback, errorCallback, options) {
    options = options || {};
    var cfg = {
        weatherTtlMs: options.weatherTtlMs || DEFAULTS.weatherTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs,
        cityKey: options.cityKey || null
    };

    var cacheKey = cfg.cityKey ? String(cfg.cityKey).toLowerCase() : null;
    if (cacheKey) {
        var cached = readCache(_weatherCache, cacheKey);
        if (cached) {
            if (cached.error) {
                errorCallback && errorCallback("Weather temporarily unavailable; retry later");
                return;
            }
            if (cached.value) {
                callback(cached.value);
                return;
            }
        }
    }

    var url = buildUrl("https://api.open-meteo.com/v1/forecast", {
        latitude: String(latitude),
        longitude: String(longitude),
        current_weather: "true",
        current: "relativehumidity_2m,surface_pressure",
        daily: "temperature_2m_max,temperature_2m_min,weathercode",
        timezone: "auto"
    });
    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";
    var dbg = !!(options && options.debug);
    _httpGetJson(url, cfg.timeoutMs, function(weatherData) {
        if (cacheKey) _writeCacheSuccess(_weatherCache, cacheKey, weatherData, cfg.weatherTtlMs);
        callback(weatherData);
    }, function(err) {
        if (cacheKey && err) {
            var backoff = (err.retryAfter && err.retryAfter > 0) ? err.retryAfter : 0;
            if (!backoff && (err.status === 429 || (err.status >= 500 && err.status <= 599))) backoff = cfg.errorTtlMs;
            if (backoff) _writeCacheError(_weatherCache, cacheKey, backoff);
        }
        errorCallback && errorCallback("Weather fetch error: " + (err.status || err.type || "unknown"));
    }, _ua);
}

function fetchCityWeather(city, callback, errorCallback, options) {
    options = options || {};
    var cityKey = String(city || "").trim();
    fetchCoordinates(cityKey, function(lat, lon) {
        fetchWeather(lat, lon, function(weatherData) {
            callback({
                city: cityKey,
                latitude: lat,
                longitude: lon,
                weather: weatherData
            });
        }, errorCallback, {
            weatherTtlMs: options.weatherTtlMs || DEFAULTS.weatherTtlMs,
            errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
            timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs,
            cityKey: cityKey
        });
    }, errorCallback, {
        geocodeTtlMs: options.geocodeTtlMs || DEFAULTS.geocodeTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs
    });
} 
