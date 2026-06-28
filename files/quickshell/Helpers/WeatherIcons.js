// WMO Weather Code → Material Symbols icon mapping
// Shared between Bar/Modules/WeatherButton.qml and Widgets/SidePanel/Weather.qml
// Reference: https://open-meteo.com/en/docs#weathervariables (WMO Weather interpretation codes)

function materialSymbolForCode(code) {
    if (code === 0) return "sunny";
    if (code === 1 || code === 2) return "partly_cloudy_day";
    if (code === 3) return "cloud";
    if (code >= 45 && code <= 48) return "foggy";
    if (code >= 51 && code <= 67) return "rainy";
    if (code >= 71 && code <= 77) return "weather_snowy";
    if (code >= 80 && code <= 82) return "rainy";
    if (code >= 95 && code <= 99) return "thunderstorm";
    return "cloud";
}

// Wind direction: degrees → compass label, rotation angle for arrow icon
// Meteorological convention: 0°=N means wind blows FROM north
function windDirection(deg) {
    var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
    var idx = Math.round(deg / 45) % 8;
    return dirs[idx];
}

// Rotation for a "navigation" icon (▲ points up at 0°).
// Add 180° so arrow shows where wind blows TO (matching meteorological convention).
function windRotation(deg) {
    return (typeof deg === 'number') ? (deg + 180) % 360 : 0;
}

// Compact format for bar: "3.2"
function formatWindSpeed(speed) {
    if (typeof speed !== 'number') return "";
    return speed.toFixed(1);
}

// Verbose format for tooltip/panel: "3.2 m/s N"
function formatWindFull(speed, deg) {
    if (typeof speed !== 'number') return "";
    return speed.toFixed(1) + " m/s " + windDirection(deg);
}

// Moon phase calculation based on synodic month (~29.53059 days).
// Reference new moon: 2000-01-06 18:14 UTC (JD 2451550.26)
var _SYNODIC_MONTH = 29.53059;
var _KNOWN_NEW_MOON_MS = Date.UTC(2000, 0, 6, 18, 14, 0); // Jan 6 2000 18:14 UTC

// Returns fractional phase 0..1 (0 = new moon, 0.5 = full moon)
function moonAge(date) {
    var ms = (date instanceof Date) ? date.getTime() : Date.now();
    var days = (ms - _KNOWN_NEW_MOON_MS) / 86400000;
    var cycles = days / _SYNODIC_MONTH;
    var frac = cycles - Math.floor(cycles);
    return frac < 0 ? frac + 1 : frac;
}

// 8-phase index: 0=new, 1=waxing crescent, …, 7=waning crescent
function moonPhaseIndex(date) {
    return Math.round(moonAge(date) * 8) % 8;
}

var _MOON_ICONS = [
    "\u{1F311}", // 🌑 New Moon
    "\u{1F312}", // 🌒 Waxing Crescent
    "\u{1F313}", // 🌓 First Quarter
    "\u{1F314}", // 🌔 Waxing Gibbous
    "\u{1F315}", // 🌕 Full Moon
    "\u{1F316}", // 🌖 Waning Gibbous
    "\u{1F317}", // 🌗 Last Quarter
    "\u{1F318}"  // 🌘 Waning Crescent
];

var _MOON_NAMES = [
    "New Moon", "Waxing Crescent", "First Quarter", "Waxing Gibbous",
    "Full Moon", "Waning Gibbous", "Last Quarter", "Waning Crescent"
];

function moonIcon(date) {
    return _MOON_ICONS[moonPhaseIndex(date)];
}

function moonName(date) {
    return _MOON_NAMES[moonPhaseIndex(date)];
}
