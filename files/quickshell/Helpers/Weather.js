// In-memory caches with TTL
var _geoCache = {}; // key: cityLower -> { value: {lat, lon}, expiry: ts, errorUntil?: ts }
var _weatherCache = {}; // key: cityLower -> { value: weatherObject, expiry: ts, errorUntil?: ts }

// ── Fallback provider: wttr.in ──────────────────────────────────────────────

// WorldWeatherOnline (WWO) weather codes → WMO weather interpretation codes
// wttr.in uses WWO codes internally; this maps them to the WMO standard used
// by Open-Meteo and the WeatherIcons.js icon mapping.
var _WWO_TO_WMO = {
    "113": 0,   // Sunny / Clear
    "116": 2,   // Partly cloudy
    "119": 3,   // Cloudy
    "122": 3,   // Overcast
    "143": 45,  // Mist
    "176": 80,  // Light rain shower
    "179": 85,  // Light snow shower
    "182": 86,  // Heavy snow shower
    "185": 87,  // Light sleet showers
    "200": 95,  // Thundery outbreaks
    "227": 76,  // Blowing snow
    "230": 77,  // Blizzard
    "248": 45,  // Fog
    "260": 48,  // Freezing fog
    "263": 51,  // Light drizzle
    "266": 53,  // Drizzle
    "281": 56,  // Freezing drizzle
    "284": 57,  // Heavy freezing drizzle
    "293": 61,  // Light rain
    "296": 61,  // Light rain
    "299": 63,  // Moderate rain
    "302": 65,  // Heavy rain
    "305": 65,  // Heavy rain
    "308": 65,  // Very heavy rain
    "311": 66,  // Light sleet
    "314": 67,  // Moderate sleet
    "317": 67,  // Heavy sleet
    "320": 71,  // Light snow
    "323": 71,  // Light snow
    "326": 71,  // Light snow
    "329": 73,  // Moderate snow
    "332": 73,  // Moderate snow
    "335": 75,  // Heavy snow
    "338": 75,  // Heavy snow
    "350": 77,  // Hail
    "353": 80,  // Light rain shower
    "356": 81,  // Moderate rain shower
    "359": 82,  // Heavy rain shower
    "362": 85,  // Light sleet shower
    "365": 86,  // Moderate sleet shower
    "368": 85,  // Light snow shower
    "371": 86,  // Heavy snow shower
    "374": 85,  // Light sleet shower
    "377": 86,  // Heavy sleet shower
    "386": 95,  // Thundery outbreaks with light rain
    "389": 96,  // Thundery outbreaks with heavy rain
    "392": 97,  // Thundery snow showers
    "395": 99   // Heavy thundery snow
};

function _wwoToWmo(wwoCode) {
    return _WWO_TO_WMO[String(wwoCode)] !== undefined ? _WWO_TO_WMO[String(wwoCode)] : 2;
}

// ── wttr.in text-format helpers ────────────────────────────────────────────
// Used when the JSON format (format=j1) is truncated or unparseable.

// Emoji weather icon → WMO weather code mapping.
// Matches the icons wttr.in returns for %c.
var _EMOJI_TO_WMO = {
    "\u2600\uFE0F": 0,   // ☀️ Sunny
    "\uD83C\uDF24\uFE0F": 2, // 🌤️ Partly cloudy
    "\u26C5": 2,          // ⛅ Partly cloudy
    "\uD83C\uDF25\uFE0F": 3, // 🌥️ Cloudy
    "\u2601\uFE0F": 3,    // ☁️ Overcast
    "\uD83C\uDF26\uFE0F": 61, // 🌦️ Light rain
    "\uD83C\uDF27\uFE0F": 63, // 🌧️ Rain
    "\u26C8\uFE0F": 95,   // ⛈️ Thunderstorm
    "\uD83C\uDF28\uFE0F": 71, // 🌨️ Snow
    "\uD83C\uDF2A\uFE0F": 45, // 🌪️ Wind/fog
    "\uD83C\uDF2B\uFE0F": 45, // 🌫️ Fog
    "\u2744\uFE0F": 71,   // ❄️ Snowflake
    "\uD83C\uDF00": 0,    // 🌐 Clear (fallback)
};

function _emojiToWmo(raw) {
    if (!raw) return 2;
    var trimmed = String(raw).trim();
    return _EMOJI_TO_WMO[trimmed] !== undefined ? _EMOJI_TO_WMO[trimmed] : 2;
}

// Arrow character → wind direction degrees
var _ARROW_TO_DEG = {
    "\u2191": 0,    // ↑ N
    "\u2197": 45,   // ↗ NE
    "\u2192": 90,   // → E
    "\u2198": 135,  // ↘ SE
    "\u2193": 180,  // ↓ S
    "\u2199": 225,  // ↙ SW
    "\u2190": 270,  // ← W
    "\u2196": 315,  // ↖ NW
};

function _arrowToDeg(raw) {
    if (!raw) return 0;
    var first = String(raw).charAt(0);
    return _ARROW_TO_DEG[first] !== undefined ? _ARROW_TO_DEG[first] : 0;
}

// Parse pipe-separated wttr.in text format:
//   %c|%t|%h|%w|%C|%p|%P|%u
//   icon|temp|humidity|wind|condition|precip|pressure|uv_index
// Example: 🌤️ |+25°C|65%|→15km/h|Partly cloudy|0.0mm|1017hPa|1
function _parseWttrText(text) {
    if (!text) return null;
    var parts = String(text).split("|");
    if (parts.length < 6) return null;

    var icon = parts[0] || "";
    var tempRaw = parts[1] || "";
    var humRaw = parts[2] || "";
    var windRaw = parts[3] || "";
    var condRaw = parts[4] || "";
    var presRaw = (parts[6] || "");

    var tempC = parseFloat(String(tempRaw).replace("°C", "").replace("+", "").replace("−", "-").replace("−", "-"));
    if (isNaN(tempC)) return null;

    var humidity = parseFloat(String(humRaw).replace("%", "")) || 0;
    var wmoCode = _emojiToWmo(icon);

    // Parse wind: "→15km/h" or "→ 15km/h"
    var windDirDeg = 0;
    var windSpeedKmph = 0;
    if (windRaw) {
        var ws = String(windRaw).trim();
        windDirDeg = _arrowToDeg(ws);
        var speedMatch = ws.match(/(\d+(?:\.\d+)?)/);
        if (speedMatch) windSpeedKmph = parseFloat(speedMatch[1]) || 0;
    }

    var pressure = parseFloat(String(presRaw).replace("hPa", "").trim()) || 0;

    return {
        temperature_2m: tempC,
        weather_code: wmoCode,
        wind_speed_10m: windSpeedKmph / 3.6,
        wind_direction_10m: windDirDeg,
        relative_humidity_2m: humidity,
        surface_pressure: pressure
    };
}

// Normalise wttr.in "format=j1" JSON to the Open-Meteo shape the QML expects.
// Handles possible truncation gracefully — returns current conditions even if
// daily forecast is missing.
function _normalizeWttrIn(data) {
    if (!data || !data.current_condition || !data.current_condition[0]) return null;
    var cc = data.current_condition[0];

    var tempC = parseFloat(cc.temp_C);
    if (isNaN(tempC)) return null;

    var wmoCode = _wwoToWmo(cc.weatherCode);
    var humidity = parseFloat(cc.humidity) || 0;
    var windDir = parseFloat(cc.winddirDegree) || 0;
    var windMs = (parseFloat(cc.windspeedKmph) || 0) / 3.6;
    var pressure = parseFloat(cc.pressure) || 0;

    // Derive daily forecast from the "weather" array (up to 7 days).
    // wttr.in doesn't provide explicit maxtempC/mintempC in free tier,
    // so we compute them from hourly entries.
    var daily = { time: [], weathercode: [], temperature_2m_max: [], temperature_2m_min: [] };
    if (data.weather && data.weather.length > 0) {
        for (var i = 0; i < data.weather.length; i++) {
            var day = data.weather[i];
            if (!day || !day.date) break;
            daily.time.push(day.date);

            var hrs = day.hourly;
            var maxT = -Infinity, minT = Infinity;
            var noonCode = wmoCode;
            if (hrs && hrs.length > 0) {
                for (var h = 0; h < hrs.length; h++) {
                    var ht = parseFloat(hrs[h].tempC);
                    if (!isNaN(ht)) { if (ht > maxT) maxT = ht; if (ht < minT) minT = ht; }
                    // Use the middle-of-day hourly for representative weather code
                    if (h === Math.floor(hrs.length / 2) && hrs[h].weatherCode)
                        noonCode = _wwoToWmo(hrs[h].weatherCode);
                }
            }
            daily.temperature_2m_max.push(isFinite(maxT) ? maxT : (parseFloat(day.avgtempC) || 0));
            daily.temperature_2m_min.push(isFinite(minT) ? minT : (parseFloat(day.avgtempC) || 0));
            daily.weathercode.push(noonCode);
        }
    }

    return {
        current: {
            temperature_2m: tempC,
            weather_code: wmoCode,
            wind_speed_10m: windMs,
            wind_direction_10m: windDir,
            relative_humidity_2m: humidity,
            surface_pressure: pressure
        },
        daily: daily,
        timezone_abbreviation: "MSK",
        _provider: "wttr.in"
    };
}

function _fetchWttrIn(latitude, longitude, callback, errorCallback, options) {
    options = options || {};
    var timeoutMs = options.timeoutMs || DEFAULTS.timeoutMs;
    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";

    var coords = String(latitude) + "," + String(longitude);

    // Skip JSON (format=j1) entirely — wttr.in's JSON response is often
    // truncated mid-stream, which causes JSON.parse to always fail.
    // Go straight to the tiny pipe-separated text format (~80 bytes) which
    // completes before any connection can be dropped.  The side effect is
    // no daily forecast in the side panel when this provider is active.
    if (_openMeteoFailures <= _OPEN_METEO_SKIP_THRESHOLD) {
        console.warn("[Weather] Open-Meteo unreachable, falling back to wttr.in text for", coords);
    }
    var textUrl = "https://wttr.in/" + coords + "?format=%c|%t|%h|%w|%C|%p|%P|%u";
    _fetchWttrText(textUrl, timeoutMs, _ua, callback, errorCallback);
}

function _fetchWttrText(url, timeoutMs, userAgent, callback, errorCallback) {
    try {
        var xhr = new XMLHttpRequest();
        xhr.open("GET", url, true);
        if (timeoutMs !== undefined && timeoutMs !== null) xhr.timeout = timeoutMs;
        try {
            if (xhr.setRequestHeader) {
                var ua = userAgent || 'Quickshell';
                try { xhr.setRequestHeader('User-Agent', ua); } catch (e2) {}
            }
        } catch (e) {}
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status === 200) {
                var text = xhr.responseText;
                var current = _parseWttrText(text);
                if (current) {
                    callback({
                        current: current,
                        daily: { time: [], weathercode: [], temperature_2m_max: [], temperature_2m_min: [] },
                        timezone_abbreviation: "",
                        _provider: "wttr.in"
                    });
                } else {
                    errorCallback && errorCallback("Could not parse wttr.in text response");
                }
            } else {
                errorCallback && errorCallback("wttr.in text HTTP error: " + xhr.status);
            }
        };
        xhr.ontimeout = function() { errorCallback && errorCallback("wttr.in text timeout"); };
        xhr.onerror = function() { errorCallback && errorCallback("wttr.in text network error"); };
        xhr.send();
    } catch (e) {
        errorCallback && errorCallback("wttr.in text exception: " + String(e));
    }
}

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
    store[key] = { value: value, expiry: _now() + ttlMs };
}

function _writeCacheError(store, key, errTtl) {
    store[key] = { errorUntil: _now() + errTtl };
}

// Inline XMLHttpRequest — Qt.include() was removed in Qt 6, so Http.js/HttpCache.js
// cannot be included from JS. This self-contained implementation avoids that dependency.
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


// ── Open-Meteo persistent failure tracking ─────────────────────────────
// After N consecutive Open-Meteo failures, skip it entirely for the
// session and go straight to wttr.in. Reset on any successful fetch.
var _openMeteoFailures = 0;
var _OPEN_METEO_SKIP_THRESHOLD = 5;

// Defaults (can be overridden via options argument)
var DEFAULTS = {
    geocodeTtlMs: 24 * 60 * 60 * 1000,   // 24h
    weatherTtlMs: 5 * 60 * 1000,         // 5m
    errorTtlMs: 2 * 60 * 1000,           // 2m backoff for 429/5xx
    timeoutMs: 8000                      // 8s timeout
};

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

    // Open-Meteo geocoding API (free, no key required)
    var geoBase = (options && options.geocodingApiBaseUrl) ? String(options.geocodingApiBaseUrl) : "https://geocoding-api.open-meteo.com/v1";
    var geoUrl = _buildUrl(geoBase + "/search", {
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
            if (backoff) _writeCacheError(_geoCache, key, backoff);
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
        var cached = _readCache(_weatherCache, cacheKey);
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

    // After N consecutive failures, skip Open-Meteo entirely and go
    // straight to wttr.in. Resets on any successful Open-Meteo fetch.
    var skipOpenMeteo = _openMeteoFailures >= _OPEN_METEO_SKIP_THRESHOLD;

    if (skipOpenMeteo) {
        // Open-Meteo persistently failing — use wttr.in directly
        _fetchWttrIn(latitude, longitude, function(fbData) {
            if (cacheKey) _writeCacheSuccess(_weatherCache, cacheKey, fbData, cfg.weatherTtlMs);
            callback(fbData);
        }, function(fbErr) {
            if (cacheKey && fbErr) {
                var backoff = (fbErr.retryAfter && fbErr.retryAfter > 0) ? fbErr.retryAfter : 0;
                if (!backoff && (fbErr.status === 429 || (fbErr.status >= 500 && fbErr.status <= 599))) backoff = cfg.errorTtlMs;
                if (backoff) _writeCacheError(_weatherCache, cacheKey, backoff);
            }
            errorCallback && errorCallback("Weather fetch error: " + (fbErr.status || fbErr.type || "unknown"));
        }, options);
        return;
    }

    // Open-Meteo forecast API (free, no key required)
    var weatherBase = (options && options.weatherApiBaseUrl) ? String(options.weatherApiBaseUrl) : "https://api.open-meteo.com/v1";
    var url = _buildUrl(weatherBase + "/forecast", {
        latitude: String(latitude),
        longitude: String(longitude),
        current: "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,relative_humidity_2m,surface_pressure",
        daily: "temperature_2m_max,temperature_2m_min,weathercode",
        wind_speed_unit: "ms",
        timezone: "auto"
    });
    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";
    var dbg = !!(options && options.debug);
    _httpGetJson(url, cfg.timeoutMs, function(weatherData) {
        // Open-Meteo succeeded — reset failure counter
        _openMeteoFailures = 0;
        if (cacheKey) _writeCacheSuccess(_weatherCache, cacheKey, weatherData, cfg.weatherTtlMs);
        callback(weatherData);
    }, function(err) {
        // Open-Meteo failed — increment counter, try fallback (wttr.in)
        _openMeteoFailures++;
        _fetchWttrIn(latitude, longitude, function(fbData) {
            if (cacheKey) _writeCacheSuccess(_weatherCache, cacheKey, fbData, cfg.weatherTtlMs);
            callback(fbData);
        }, function(fbErr) {
            // Both providers failed → report the primary error
            if (cacheKey && err) {
                var backoff = (err.retryAfter && err.retryAfter > 0) ? err.retryAfter : 0;
                if (!backoff && (err.status === 429 || (err.status >= 500 && err.status <= 599))) backoff = cfg.errorTtlMs;
                if (backoff) _writeCacheError(_weatherCache, cacheKey, backoff);
            }
            errorCallback && errorCallback("Weather fetch error: " + (err.status || err.type || "unknown"));
        }, options);
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
            cityKey: cityKey,
            weatherApiBaseUrl: options.weatherApiBaseUrl
        });
    }, errorCallback, {
        geocodeTtlMs: options.geocodeTtlMs || DEFAULTS.geocodeTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs,
        geocodingApiBaseUrl: options.geocodingApiBaseUrl
    });
} 
