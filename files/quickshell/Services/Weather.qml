pragma Singleton
import QtQuick
import qs.Settings
import qs.Services as Services
import "../Helpers/Weather.js" as WeatherHelper

// Weather service with TTL caching; consumers set enabled and read weatherData/errorString
Item {
    id: root

    // Inputs
    property string city: (Settings.settings && Settings.settings.weatherCity) ? Settings.settings.weatherCity : ""
    property int ttlMs: 60000
    // State
    property var weatherData: null
    property string errorString: ""
    property bool isLoading: false
    property int lastFetchTime: 0

    function fetchNow() {
        if (!root.city || String(root.city).trim() === "") { root.errorString = "No city configured"; return; }
        var now = Date.now();
        if (root.lastFetchTime > 0 && (now - root.lastFetchTime) < ttlMs) return;
        root.isLoading = true;
        root.errorString = "";

        var opts = {
            userAgent: Settings.settings.userAgent,
            debug: Settings.settings.debugNetwork,
            timeoutMs: Theme.weatherHttpTimeoutMs,
            weatherApiBaseUrl: Settings.settings.weatherApiBaseUrl || undefined,
            geocodingApiBaseUrl: Settings.settings.weatherGeocodingBaseUrl || undefined
        };

        function _onWeather(weatherData) {
            root.weatherData = weatherData;
            root.lastFetchTime = now;
            root.errorString = "";
            root.isLoading = false;
        }
        function _onError(err) {
            root.errorString = String(err || "Weather error");
            root.isLoading = false;
        }

        // Skip geocoding if coordinates are provided directly
        var lat = Number(Settings.settings.weatherLatitude);
        var lon = Number(Settings.settings.weatherLongitude);
        if (isFinite(lat) && isFinite(lon) && lat !== 0 && lon !== 0) {
            WeatherHelper.fetchWeather(lat, lon, _onWeather, _onError, {
                weatherTtlMs: opts.weatherTtlMs,
                errorTtlMs: opts.errorTtlMs,
                timeoutMs: opts.timeoutMs,
                cityKey: root.city,
                weatherApiBaseUrl: opts.weatherApiBaseUrl
            });
        } else {
            WeatherHelper.fetchCityWeather(root.city,
                function(result) { _onWeather(result.weather); },
                _onError, opts
            );
        }
    }

    function start() { enabled = true; fetchNow(); }
    function stop() { enabled = false; }

    Connections {
        target: Settings.settings
        function onWeatherCityChanged() { try { root.city = Settings.settings.weatherCity || ""; root.lastFetchTime = 0; if (enabled) fetchNow(); } catch (e) { console.warn("[Weather.onCityChanged]", e) } }
    }

    // Periodic TTL check using consolidated timers
    Connections {
        target: Services.Timers
        function onTick2s() { if (enabled) fetchNow(); }
    }
}

