pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Reads Theme/.theme.json from the user's config directory to synchronize
// greeter colors and timings with the main shell's Theme system.
// Falls back to hardcoded defaults if the file is missing or unreadable.
Singleton {
    id: root

    readonly property bool isLoaded: _data !== null

    // Path to shared theme file
    readonly property string _themePath: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME");
        var home = Quickshell.env("HOME");
        var base = xdg ? xdg : (home + "/.config");
        return base + "/quickshell/Theme/.theme.json";
    }

    property var _data: null

    FileView {
        id: themeFileView
        path: root._themePath
        watchChanges: true
        onFileChanged: reload()
        Component.onCompleted: reload()
        onLoadFailed: function() { root._data = null; }
        onAdapterUpdated: {
            try {
                root._data = themeAdapter;
            } catch (e) {
                root._data = null;
            }
        }
        JsonAdapter {
            id: themeAdapter
            property var greeter: ({})
        }
    }

    // Helper to resolve a dotted path from the loaded theme data
    function _val(path, fallback) {
        if (!_data) return fallback;
        try {
            var parts = path.split('.');
            var obj = _data;
            for (var i = 0; i < parts.length; i++) {
                if (obj === undefined || obj === null) return fallback;
                obj = obj[parts[i]];
            }
            return (obj !== undefined && obj !== null) ? obj : fallback;
        } catch (e) {
            return fallback;
        }
    }

    // Color tokens (synced with Theme/greeter.jsonc defaults)
    readonly property color barColor: _val('greeter.barColor', "#30c0ffff")
    readonly property color barOutline: _val('greeter.barOutline', "#50ffffff")
    readonly property color widgetColor: _val('greeter.widgetColor', "#25ceffff")
    readonly property color widgetActiveColor: _val('greeter.widgetActiveColor', "#80ceffff")
    readonly property color widgetOutline: _val('greeter.widgetOutline', "#40ffffff")
    readonly property color widgetOutlineSeparate: _val('greeter.widgetOutlineSeparate', "#20ffffff")
    readonly property color separatorColor: _val('greeter.separatorColor', "#60ffffff")

    // Login card tokens (lock/LockContent.qml)
    readonly property color cardColor: _val('greeter.cardColor', "#a60f141c")
    readonly property string avatarPath: _val('greeter.avatarPath', "assets/avatar.jpg")

    // Frosted glass card and the avatar disc (see the shaders)
    readonly property real glassBlur: _val('greeter.glassBlur', 9)
    readonly property color glassTint: _val('greeter.glassTint', "#c20a0e14")
    readonly property real glassHighlight: _val('greeter.glassHighlight', 0.045)
    readonly property real glassRefract: _val('greeter.glassRefract', 10)
    readonly property real glassShadow: _val('greeter.glassShadow', 26)
    readonly property real glassGrain: _val('greeter.glassGrain', 0.02)
    readonly property real glassLens: _val('greeter.glassLens', 16)
    readonly property real glassChroma: _val('greeter.glassChroma', 0.5)
    readonly property real glassSpecular: _val('greeter.glassSpecular', 0)
    readonly property real glassPointer: _val('greeter.glassPointer', 0.12)
    readonly property real fieldBlur: _val('greeter.fieldBlur', 6)
    readonly property color fieldTint: _val('greeter.fieldTint', "#e60a0e14")

    // Type scale and families: one number makes the whole card bigger
    readonly property real uiScale: _val('greeter.uiScale', 1.2)
    readonly property string uiFont: _val('greeter.uiFont', "Iosevka")
    readonly property string displayFont: _val('greeter.displayFont', "Iosevka")
    readonly property real avatarRingWidth: _val('greeter.avatarRingWidth', 0.05)
    readonly property real avatarGlow: _val('greeter.avatarGlow', 0.5)

    // The clock: four gas-discharge tubes (lock/NixieClock.qml, shaders/nixie.frag)
    readonly property real nixieDigitSize: _val('greeter.nixieDigitSize', 92)
    readonly property real nixieGlow: _val('greeter.nixieGlow', 1.0)
    readonly property real nixieTempK: _val('greeter.nixieTempK', 2550)
    readonly property color nixieGlowColor: _val('greeter.nixieGlowColor', "#ff5a10")
    readonly property color nixieGlassColor: _val('greeter.nixieGlassColor', "#4d120b06")
    readonly property color nixieCathodeColor: _val('greeter.nixieCathodeColor', "#aab6c4")
    // The lit cathode's radius in glyph units: the sprite's is 0.55 mm of a 23 mm
    // glyph, and the drawn numeral has to be the same wire or the two disagree.
    readonly property real nixieWire: _val('greeter.nixieWire', 0.0127)
    readonly property real nixieStack: _val('greeter.nixieStack', 0.5)
    readonly property real nixieHighlight: _val('greeter.nixieHighlight', 0.8)
    readonly property real nixieWarmth: _val('greeter.nixieWarmth', 0.45)
    readonly property int nixieFlickerMs: _val('greeter.nixieFlickerMs', 320)

    // Rounded and borderless by default (see the theme file)
    readonly property real cardRadius: _val('greeter.cardRadius', 6)
    readonly property real fieldRadius: _val('greeter.fieldRadius', 8)
    readonly property real chipRadius: _val('greeter.chipRadius', 999)
    readonly property real buttonRadius: _val('greeter.buttonRadius', 999)
    readonly property real avatarRadius: _val('greeter.avatarRadius', 16)

    // Wallpaper posterisation
    readonly property bool posterizeEnabled: _val('greeter.posterizeEnabled', true)
    // Dithering strategy: "bayer" | "blueNoise" | "yliluoma"
    readonly property string posterizeMode: _val('greeter.posterizeMode', "yliluoma")
    readonly property real posterizeModeValue: posterizeMode === "bayer" ? 0 : (posterizeMode === "blueNoise" ? 1 : 2)
    readonly property real posterizeMaskScale: _val('greeter.posterizeMaskScale', 1.0)
    readonly property real posterizeChroma: _val('greeter.posterizeChroma', 1.35)
    readonly property real posterizeDither: _val('greeter.posterizeDither', 0.85)
    readonly property real posterizeCell: _val('greeter.posterizeCell', 2)
    readonly property real posterizeGamma: _val('greeter.posterizeGamma', 1.0)
    readonly property real posterizeMix: _val('greeter.posterizeMix', 0.15)
    readonly property string posterizeTint: _val('greeter.posterizeTint', "")

    // CRT pass over the whole screen
    readonly property bool crtEnabled: _val('greeter.crtEnabled', true)
    readonly property real crtLineSpacing: _val('greeter.crtLineSpacing', 3)
    readonly property real crtScanStrength: _val('greeter.crtScanStrength', 0.13)
    readonly property real crtUiLines: _val('greeter.crtUiLines', 0)
    readonly property real crtMaskStrength: _val('greeter.crtMaskStrength', 0.05)
    readonly property real crtAberration: _val('greeter.crtAberration', 0.6)
    readonly property real crtBarrel: _val('greeter.crtBarrel', 0.008)
    readonly property real crtBloom: _val('greeter.crtBloom', 0.35)
    readonly property real crtVignette: _val('greeter.crtVignette', 0.35)
    readonly property real crtRollStrength: _val('greeter.crtRollStrength', 0)
    readonly property int crtRollMs: _val('greeter.crtRollMs', 9000)
    readonly property color cardOutline: _val('greeter.cardOutline', "#3dffffff")
    readonly property color accentColor: _val('greeter.accentColor', "#7fd6ff")
    readonly property color dangerColor: _val('greeter.dangerColor', "#ff9b9b")
    readonly property color textColor: _val('greeter.textColor', "#f2f6fa")
    readonly property color textMutedColor: _val('greeter.textMutedColor', "#c3d2e0")
    readonly property color avatarColor: _val('greeter.avatarColor', "#3d7fd6ff")

    // Timing tokens
    readonly property int lockAnimationMs: _val('greeter.lockAnimationMs', 500)
    readonly property int slideshowDurationMs: _val('greeter.slideshowDurationMs', 3000)
    readonly property int contextTimerMs: _val('greeter.contextTimerMs', 300)
    readonly property int animFastMs: _val('greeter.animFastMs', 150)
    readonly property int animMediumMs: _val('greeter.animMediumMs', 250)
    readonly property int animSlowMs: _val('greeter.animSlowMs', 500)
    readonly property int appearMs: _val('greeter.appearMs', 420)
}
