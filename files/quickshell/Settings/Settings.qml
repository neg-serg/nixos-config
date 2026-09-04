pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

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

    FileView {
        id: settingFileView
        path: settingsFile
        watchChanges: true
        property bool _reloadPending: false
        property bool _loading: false
        onFileChanged: {
            if (!settingFileView._reloadPending) {
                settingFileView._reloadPending = true;
                Qt.callLater(function () {
                    settingFileView._reloadPending = false;
                    settingFileView._reload();
                });
            }
        }
        onAdapterUpdated: {
            // A reload applying file changes must not write back to the file
            // (that would trigger onFileChanged -> reload -> onAdapterUpdated loop).
            if (settingFileView._loading) {
                settingFileView._loading = false;
                return;
            }
            writeAdapter();
        }
        Component.onCompleted: function () {
            _reload();
        }
        onLoadFailed: function (error) {
            settingAdapter = {};
            writeAdapter();
            settingFileView._loading = false;
        }
        // Wrap reload() so adapter updates caused by it are not echoed back to disk.
        function _reload() {
            settingFileView._loading = true;
            settingFileView.reload();
        }
        JsonAdapter {
            id: settingAdapter
            // Bar / Panel visuals
            // Panel background transparency controls:
            // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha. Example: 0.2 ≈ five times more transparent.
            property real panelBgAlphaScale: 0.2

            // Enable wedge clip ShaderEffect path (env vars can override in debug)
            property bool enableWedgeClipShader: false
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

            // Media spectrum / CAVA
            property int cavaBars: 86
            // CAVA tuning
            property int cavaFramerate: 24
            property bool cavaMonstercat: false
            property int cavaGravity: 150000
            property int cavaNoiseReduction: 12
            property bool spectrumUseGradient: false
            property bool spectrumMirror: false
            property bool showSpectrumTopHalf: false
            // Spectrum frequency band: full scale (0..spectrumMaxHz) and the
            // highlighted (coloured) band inside it.
            property int spectrumMinHz: 0
            property int spectrumMaxHz: 40000
            property int spectrumColorMinHz: 15000
            property int spectrumColorMaxHz: 25000
            property real spectrumDimOpacity: 0.18
            // Show audio level (volume/mic/Genelec dB) when the cursor hovers
            // the capsule — delayed reveal via the existing pill/tooltip timers
            property bool showVolumeOnHover: true
            property real spectrumFillOpacity: 0.35
            property real spectrumHeightFactor: 1.2
            property real spectrumOverlapFactor: 0.2
            property real spectrumBarGap: 1.0
            property real spectrumVerticalRaise: 0.75

            property string activeVisualizerProfile: "classic"
            property var visualizerProfiles: ({
                    classic: {
                        cavaBars: 86,
                        cavaFramerate: 24,
                        cavaMonstercat: false,
                        cavaGravity: 150000,
                        cavaNoiseReduction: 12,
                        spectrumFillOpacity: 0.35,
                        spectrumHeightFactor: 1.2,
                        spectrumOverlapFactor: 0.2,
                        spectrumBarGap: 1.0,
                        spectrumVerticalRaise: 0.75
                    }
                })

            // Media time brackets styling
            property string timeBracketStyle: "round"

            // Displays
            property var barMonitors: []
            property var monitorScaleOverrides: {}

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

            // Media visualizer (CAVA/LinearSpectrum) toggle
            property bool showMediaVisualizer: false

            // iPhone-style visualizer beside album art in bar
            property bool showIphoneVisualizer: false

            // Player selection priority
            property var playerSelectionPriority: ["mpdPlaying", "anyPlaying", "mpdRecent", "recent", "manual", "first"]
            property string playerSelectionPreset: "default"

            // Music popup sizing
            property int musicPopupWidth: 840     // logical px, scaled
            property int musicPopupHeight: 250    // logical px, scaled (used when content height unknown)
            property int musicPopupPadding: 12    // logical px, scaled (inner content padding)
            property int musicPopupEdgeMargin: 4  // logical px, scaled (distance from screen edge/panel)
            // Toast extras
            property bool musicPopupSpectrum: true          // show spectrum analyzer behind progress
            property bool musicPopupColoredProgress: true   // progress bar in cover accent colour
            property real musicPopupProgressHeight: 5       // logical px, scaled (progress line thickness)

            // Small bar analyser (left of the bar album art)
            property bool barAnalyserMirror: false          // false = one-sided
            property int barAnalyserBars: 5
            property string barAnalyserStyle: "neon-cyan"   // neon-cyan | neon-violet | analog-amber | analog-rose
            // Large toast analyser (behind the popup progress bar)
            property bool toastAnalyserMirror: false        // false = one-sided
            property int toastAnalyserBars: 64
            property string toastAnalyserStyle: "neon-cyan" // neon-cyan | neon-violet | analog-amber | analog-rose

            property int networkPingIntervalMs: 30000
            property string networkPingTarget: "8.8.8.8"
            property string networkNoInternetColor: "#FF6E00"
            property string networkNoLinkColor: "#D81B60"

            // Panel layout: ordered widget identifiers per section
            property var panelLayout: ({
                    left: ["clock", "workspaces", "keyboard", "network", "weather"],
                    right: ["media", "mpdFlags", "sysmon", "pill", "systray", "microphone", "volume", "genelec"]
                })

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
