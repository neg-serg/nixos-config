pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Helpers

Singleton {
    property string shellName: "quickshell"
    property string settingsDir: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/" + shellName + "/"
    property string settingsFile: (settingsDir + "Settings.json")
    property string themeFile: (settingsDir + "Theme/.theme.json")
    property var settings: settingAdapter

    Item {
        Component.onCompleted: {
            Quickshell.execDetached(["mkdir", "-p", settingsDir]);
        }
    }

    GuardedFileView {
        id: settingFileView
        path: settingsFile
        onLoadFailed: function (error) {
            settingAdapter = {};
            writeAdapter();
            settingFileView._loading = false;
        }
        JsonAdapter {
            id: settingAdapter
            // Bar / Panel visuals
            // Panel background transparency controls:
            // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha. Example: 0.2 ≈ five times more transparent.
            property real panelBgAlphaScale: 0.2

            // Enable wedge clip ShaderEffect path (env vars can override in debug)
            // Per-window hyprglass overrides, edited in the Glass panel
            // (win+shift+g) and turned into custom presets + window-rule tags by
            // hyprglass-apply. Shape: [{ class, enabled, blurStrength,
            // glassOpacity, adaptiveDim, tint }] — tint is RRGGBBAA or "" to
            // inherit, and a missing field means "inherit the global value".
            property var glassWindowOverrides: []

            property bool enableWedgeClipShader: false
            // Recolor the bar content through a live FBO tint pass. The tint shader
            // is a descendant of the content it samples, so the feedback keeps the
            // scene dirty on every frame: the bar renders at ~480 fps instead of
            // redrawing on change only. Measured idle cost with it ON: ~15.8% of a
            // core at ~480 fps; with it OFF: ~0.6-1.8% at ~1 fps (8-15x depending on
            // what else wakes the shell). The original "~5-6% of a core" estimate is
            // too low.
            //
            // Turning it off is NOT visually neutral. The tint also draws a
            // near-opaque copy of the panel content over itself, which flattens the
            // panel's own glow/seam rendering. Without it that glow shows at full
            // strength and the bar reads as "doubled"/busier (measured 13.9% RMSE in
            // the seam area, 3.8% across the whole strip). Re-enable this if the look
            // matters more than the CPU cost.
            property bool panelTintEnabled: false

            // Glass (hyprglass) values, driven by the Glass panel
            // (Widgets/Glass/GlassPanel.qml). The panel writes them through to
            // ~/.config/hypr/hyprglass.json, and hyprglass-apply turns that into
            // the plugin's config, pushes it and verifies it; the shipped defaults
            // live in files/gui/hypr/hyprglass.lua.
            property real glassBlurStrength: 6
            property int glassBlurIterations: 5
            property real glassVibrancy: 0.5
            property real glassOpacity: 0.65
            property real glassRefraction: 0.5
            property real glassChromatic: 0.3
            property real glassFresnel: 0.3
            property real glassSpecular: 0.1
            property real glassAdaptiveDim: 0.5
            // Frosted tint against the light theme: the panel's switch for it.
            property bool glassLightFrost: false
            // Per-class tints of the scratchpad terminals (warm for rebuilds, cold
            // blue for downloads, green for the VPN, ...). Off = plain kitty
            // background for every pane, which is what the Glass panel's switch
            // flips. The rmpc pane is black either way (see kitty-glass).
            property bool scratchpadTint: true
            property string weatherCity: "Saint Petersburg"
            property string userAgent: "NegPanel"
            // Unified logging toggle for low-importance debug logs
            property bool debugLogs: false
            property bool debugNetwork: false
            property bool strictThemeTokens: false
            // Accessibility: disable all non-essential animations
            property bool reducedMotion: false
            property bool useFahrenheit: false
            property bool showMediaInBar: false
            property string mediaIconStretchMode: "compact"
            property int mediaIconMinWidthPx: 0
            property int mediaIconMaxWidthPx: 0
            property int mediaIconPreferredWidthPx: 0
            property real mediaIconStretchShare: 1.0
            property int mediaIconOverlayPaddingPx: 0
            property int mediaIconPanelOverlayPaddingPx: 12
            property real mediaIconPanelOverlayWidthShare: 0.45
            property real mediaIconPanelOverlayBgOpacity: 0.65
            // Separator shown between media track title and artist
            property string mediaTitleSeparator: "—"
            // Weather button in bar
            property bool showWeatherInBar: true
            property bool reverseDayMonth: false
            property bool use12HourClock: false
            property real fontSizeMultiplier: 1.0  // Font size multiplier (1.0 = normal, 1.2 = 20% larger, 0.8 = 20% smaller)

            // Show audio level (volume/mic/Genelec dB) when the cursor hovers
            // the capsule — delayed reveal via the existing pill/tooltip timers
            property bool showVolumeOnHover: true

            // Media time brackets styling
            property string timeBracketStyle: "round"

            // Displays
            property var barMonitors: []
            // `({})` and not `{}`: the analyzer reads a bare empty block as an
            // accidental one, which has to be spelled out for an object literal here.
            property var monitorScaleOverrides: ({})

            property bool collapseSystemTray: true
            property string collapsedTrayIcon: "expand_more"
            property string trayFallbackIcon: "broken_image"
            // Hide the inline tray capsule while keeping hover-based menu access
            property bool hideSystemTrayCapsule: true
            // Align inline tray contents flush with capsule edges (true by default)
            property bool systemTrayTightSpacing: true
            // Render media capsule without borders/contrasting background
            property bool mediaIconBorderless: false
            // Remove panel-mode play/pause button border
            property bool mediaPanelButtonBorderless: true
            // Prefer enlarged borderless button in panel mode
            property bool mediaPanelButtonLargerIcon: true

            // Global contrast
            property real contrastThreshold: 0.5
            property real contrastWarnRatio: 4.5

            // Music player selection
            property var pinnedPlayers: []
            property var ignoredPlayers: []
            // NOTE: lastActivePlayers moved to StateCache.qml (runtime state in ~/.cache)

            // Player selection priority
            property var playerSelectionPriority: ["mpdPlaying", "anyPlaying", "mpdRecent", "recent", "manual", "first"]
            property string playerSelectionPreset: "default"

            // Music popup sizing
            property int musicPopupWidth: 840     // logical px, scaled
            property int musicPopupHeight: 250    // logical px, scaled (used when content height unknown)
            property int musicPopupPadding: 12    // logical px, scaled (inner content padding)
            property int musicPopupEdgeMargin: 4  // logical px, scaled (distance from screen edge/panel)
            property bool musicPopupColoredProgress: true   // progress bar in cover accent colour
            property real musicPopupProgressHeight: 3       // logical px, scaled (progress line thickness)


            property int networkPingIntervalMs: 30000
            property string networkPingTarget: "8.8.8.8"
            property string networkNoInternetColor: "#FF6E00"
            property string networkNoLinkColor: "#D81B60"

            // Panel layout: ordered widget identifiers per section
            property var panelLayout: ({
                    left: ["clock", "workspaces", "keyboard", "network", "weather"],
                    right: ["media", "mpdFlags", "sysmon", "pill", "systray", "microphone", "volume", "genelec", "nixbuild"]
                })

            // Startup gate: at login the panel shows only the widgets listed in
            // startupCleanWidgets and keeps everything else hidden until the first
            // real window appears (see Bar/Bar.qml and Docs/Config.md). Hidden
            // daemon windows and, with startupCleanIgnoreSpecial, windows on special
            // workspaces (the scratchpads pre-launched at login) do not count; the
            // clean look is held for at least startupCleanMinMs. The gate arms only
            // when the panel starts together with the session, so a panel restart in
            // the middle of work never strips the bar.
            property bool startupCleanBar: true
            property var startupCleanWidgets: ["clock", "weather"]
            property int startupCleanMinMs: 10000
            property bool startupCleanIgnoreSpecial: true

            // Panel side edge margin in logical px; matches Theme.panelSideMargin when absent
            property int panelSideMarginPx: 4

            // System monitor capsule / monitor bar tuning
            property bool showCpuMonitor: true        // Show CPU metric in the system monitor capsule
            property bool showRamMonitor: true        // Show RAM metric
            property bool showIoMonitor: true         // Show disk I/O metric
            property bool showGpuMonitor: true        // Show GPU metric (when available)
            property bool showTempMonitor: true       // Show CPU temperature metric
            property bool showSwapMonitor: true       // Show swap metric (when active)
            property bool systemMonitorHideIdle: true // Dim metrics that are below the idle threshold
            property real systemMonitorIconScale: 0.85 // Icon scale factor inside the capsule
            property real systemMonitorIdleThreshold: 0.03 // Idle cutoff (0..1) for dimming
            property int systemMonitorSpacing: 3      // Gap between metric groups, logical px
            property real systemMonitorWarnThreshold: 0.5 // Warn color threshold (0..1)
            property real systemMonitorCritThreshold: 0.8 // Critical color threshold (0..1)
            property real systemMonitorSwapShowThreshold: 0.4 // Minimum swap usage to show the swap metric
            property int systemMonitorBarWidth: 3      // Per-metric vertical bar width, logical px
            property int systemMonitorPollMs: 2000     // Poll interval for system metrics, ms
            property real systemMonitorIoMaxMiBps: 500 // I/O full-scale normalization, MiB/s

            // Weather/geocoding API base URLs (configurable for proxies/firewalls)
            property string weatherApiBaseUrl: "https://api.open-meteo.com/v1"
            property string weatherGeocodingBaseUrl: "https://geocoding-api.open-meteo.com/v1"
            // Direct coordinates as an alternative to city geocoding; (0,0) = geocode weatherCity
            property real weatherLatitude: 0.0
            property real weatherLongitude: 0.0

            // Pill tracker reminder deadline (HH:MM format)
            property string pillReminderDeadline: "12:00"

            // Audio off reminder cooldown override in milliseconds.
            // -1 means: use Theme.panelVolumeOffReminderCooldownMs.
            property int audioOffReminderCooldownMs: -1

            // Wallpaper accent extraction
            property bool wallpaperAccent: true

            // Genelec SAM hardware volume cap (dB, negative). Raise above -35 at own risk.
            property int genelecMaxVolume: -35
        }
    }
}
