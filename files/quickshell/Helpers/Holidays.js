var _countryCode = null;
var _regionCode = null;
var _regionName = null;
var _locationExpiry = 0;
var _holidaysCache = {}; // key: "year-country" -> { value, expiry, errorUntil }

var DEFAULTS = {
    locationTtlMs: 24 * 60 * 60 * 1000,  // 24h
    holidaysTtlMs: 24 * 60 * 60 * 1000,  // 24h (holidays are static per year)
    errorTtlMs: 30 * 60 * 1000,          // 30m backoff on 429/5xx
    timeoutMs: 8000                      // 8s timeout
};

Qt.include("./HttpJson.js")

function getCountryCode(callback, errorCallback, options) {
    options = options || {};
    var cfg = {
        locationTtlMs: options.locationTtlMs || DEFAULTS.locationTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs
    };
    var t = _now();
    if (_countryCode && t < _locationExpiry) {
        callback(_countryCode);
        return;
    }

    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";
    var url = _buildUrl("https://nominatim.openstreetmap.org/search", {
        city: Settings.settings.weatherCity || "",
        country: "",
        format: "json",
        addressdetails: 1,
        extratags: 1
    });
    var dbg = !!(options && options.debug);
    _httpGetJson(url, cfg.timeoutMs, function(response) {
        try {
            _countryCode = (response && response[0] && response[0].address && response[0].address.country_code) ? response[0].address.country_code : "US";
            _regionCode = (response && response[0] && response[0].address && response[0].address["ISO3166-2-lvl4"]) ? response[0].address["ISO3166-2-lvl4"] : "";
            _regionName = (response && response[0] && response[0].address && response[0].address.state) ? response[0].address.state : "";
            _locationExpiry = _now() + cfg.locationTtlMs;
            callback(_countryCode);
        } catch (e) {
            errorCallback && errorCallback("Failed to parse location data");
        }
    }, function(err) {
        // Back off location lookup if Retry-After or server error
        if (err) {
            var backoff = (err.retryAfter && err.retryAfter > 0) ? err.retryAfter : 0;
            if (!backoff && (err.status === 429 || (err.status >= 500 && err.status <= 599))) backoff = cfg.errorTtlMs;
            if (backoff > 0) _locationExpiry = _now() + backoff;
        }
        errorCallback && errorCallback("Location lookup error: " + (err.status || err.type || "unknown"));
    }, _ua);
}

function getHolidays(year, countryCode, callback, errorCallback, options) {
    options = options || {};
    var cfg = {
        holidaysTtlMs: options.holidaysTtlMs || DEFAULTS.holidaysTtlMs,
        errorTtlMs: options.errorTtlMs || DEFAULTS.errorTtlMs,
        timeoutMs: options.timeoutMs || DEFAULTS.timeoutMs
    };
    var cacheKey = year + "-" + (countryCode || "");
    var cached = _readCache(_holidaysCache, cacheKey);
    if (cached) {
        if (cached.error) {
            errorCallback && errorCallback("Holidays temporarily unavailable; retry later");
            return;
        }
        callback(cached.value);
        return;
    }

    var url = "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + countryCode;
    var _ua = (options && options.userAgent) ? String(options.userAgent) : "Quickshell";
    var dbg = !!(options && options.debug);
    _httpGetJson(url, cfg.timeoutMs, function(list) {
        try {
            var augmented = filterHolidaysByRegion(list || []);
            _writeCacheSuccess(_holidaysCache, cacheKey, augmented, cfg.holidaysTtlMs);
            callback(augmented);
        } catch (e) {
            errorCallback && errorCallback("Failed to process holidays");
        }
    }, function(err) {
        if (err) {
            var backoff = (err.retryAfter && err.retryAfter > 0) ? err.retryAfter : 0;
            if (!backoff && (err.status === 429 || (err.status >= 500 && err.status <= 599))) backoff = cfg.errorTtlMs;
            if (backoff > 0) _writeCacheError(_holidaysCache, cacheKey, backoff);
        }
        errorCallback && errorCallback("Holidays fetch error: " + (err.status || err.type || "unknown"));
    }, _ua);
}

function filterHolidaysByRegion(holidays) {
    if (!_regionCode) {
        return holidays;
    }
    const retHolidays = [];
    holidays.forEach(function(holiday) {
        if (holiday.counties?.length > 0) {
            let found = false;
            holiday.counties.forEach(function(county) {
                if (county.toLowerCase() === _regionCode.toLowerCase()) {
                    found = true;
                }
            });
            if (found) {
                var regionText = " (" + _regionName + ")";
                holiday.name = holiday.name + regionText;
                holiday.localName = holiday.localName + regionText;
                retHolidays.push(holiday);
            }
        } else {
            retHolidays.push(holiday);
        }
    });
    return retHolidays;
}

function getHolidaysForMonth(year, month, callback, errorCallback, options) {
    getCountryCode(function(countryCode) {
        getHolidays(year, countryCode, function(holidays) {
            var filtered = holidays.filter(function(h) {
                var date = new Date(h.date);
                return date.getFullYear() === year && date.getMonth() === month;
            });
            callback(filtered);
        }, errorCallback, options);
    }, errorCallback, options);
}
