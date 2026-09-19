pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Settings
import qs.Components
import "../../Helpers/Color.js" as Color

// Glass panel: live tuning for the hyprglass settings.
//
// The values live in Settings.json (the shell's own persistence) and are written
// as ~/.config/hypr/hyprglass.json, which `hyprglass-apply` turns into the
// plugin's config and then verifies against the running compositor. The panel
// never talks to hyprctl itself, and it polls the same check while it is open, so
// what the panel shows is what the compositor actually has.
PanelWindow {
    id: toast

    color: "transparent"
    visible: false
    WlrLayershell.namespace: "qs-glass"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    anchors.right: true
    anchors.top: true
    anchors.bottom: true

    function showAt() { toast.visible = true; }
    function hidePopup() { toast.visible = false; }
    function toggle() { if (toast.visible) toast.hidePopup(); else toast.showAt(); }

    implicitWidth: Math.max(1, Math.round(card.width + margin))

    readonly property real margin: Math.round(12 * Theme.scale(Screen))

    // Pointer input only on the card, so the rest of the surface stays clickless.
    mask: Region {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
    }

    // ── Values ───────────────────────────────────────────────────────────────
    // Slider bounds; the plugin's own defaults live in files/gui/hypr/hyprglass.lua.
    property var knobs: [
        { key: "glassBlurStrength",   label: "Блюр",        hint: "радиус = значение × 12 px",        min: 1,  max: 12, step: 0.5, digits: 1 },
        { key: "glassBlurIterations", label: "Проходов",    hint: "гауссовых проходов, максимум 5",   min: 1,  max: 5,  step: 1,   digits: 0 },
        { key: "glassVibrancy",       label: "Мороз",       hint: "морозный оттенок, −1 = выключен",  min: -1, max: 1,  step: 0.05, digits: 2 },
        { key: "glassOpacity",        label: "Плотность",   hint: "сколько стекла на поверхности",    min: 0,  max: 1,  step: 0.05, digits: 2 },
        { key: "glassRefraction",     label: "Преломление", hint: "толщина стеклянной плиты",         min: 0,  max: 1,  step: 0.05, digits: 2 },
        { key: "glassChromatic",      label: "Аберрация",   hint: "цветные каёмки на кромках",        min: 0,  max: 1,  step: 0.05, digits: 2 },
        { key: "glassFresnel",        label: "Френель",     hint: "подсветка кромки",                 min: 0,  max: 1,  step: 0.05, digits: 2 },
        { key: "glassSpecular",       label: "Блик",        hint: "зеркальный отблеск",               min: 0,  max: 1,  step: 0.05, digits: 2 },
        { key: "glassAdaptiveDim",    label: "Адаптация",   hint: "затемнение под светлым фоном",     min: 0,  max: 1,  step: 0.05, digits: 2 }
    ]

    // Presets: the three shapes worth having at hand, everything else is sliders.
    property var presets: [
        { label: "Стекло",   values: { glassBlurStrength: 6, glassBlurIterations: 5, glassVibrancy: 0.5, glassOpacity: 0.65, glassRefraction: 0.5, glassChromatic: 0.3, glassFresnel: 0.3, glassSpecular: 0.1, glassAdaptiveDim: 0.5 } },
        { label: "Плотнее",  values: { glassBlurStrength: 8, glassBlurIterations: 5, glassVibrancy: 0.7, glassOpacity: 0.75, glassRefraction: 0.6, glassChromatic: 0.4, glassFresnel: 0.35, glassSpecular: 0.15, glassAdaptiveDim: 0.6 } },
        { label: "Без фроста", values: { glassBlurStrength: 4, glassBlurIterations: 4, glassVibrancy: -1, glassOpacity: 0.45, glassRefraction: 0.4, glassChromatic: 0.2, glassFresnel: 0.25, glassSpecular: 0.1, glassAdaptiveDim: 0.4 } }
    ]

    function applyPreset(p) {
        for (var k in p.values) Settings.settings[k] = p.values[k];
    }

    // ── Handing the values over ─────────────────────────────────────────────
    // The panel writes one JSON file and nothing else: hyprglass-apply reads it,
    // generates the plugin's config from it and then *checks* that the running
    // plugin actually took the values. Keeping a single machine-readable source
    // is what makes the check possible at all — the placeholder version emitted
    // Lua by hand, had nothing to compare against, and quietly half-applied.
    readonly property string _home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/tmp";
    }
    readonly property string valuesFile: _home + "/.config/hypr/hyprglass.json"

    function valuesJson() {
        var s = Settings.settings;
        return JSON.stringify({
            blurStrength: Number(s.glassBlurStrength),
            blurIterations: Math.round(Number(s.glassBlurIterations)),
            vibrancy: Number(s.glassVibrancy),
            glassOpacity: Number(s.glassOpacity),
            refraction: Number(s.glassRefraction),
            chromatic: Number(s.glassChromatic),
            fresnel: Number(s.glassFresnel),
            specular: Number(s.glassSpecular),
            adaptiveDim: Number(s.glassAdaptiveDim),
            lightFrost: s.glassLightFrost === true
        }, null, 2) + "\n";
    }

    FileView {
        id: valuesFileView
        path: toast.valuesFile
        blockWrites: false
    }

    // Debounced: a drag fires dozens of changes and each write starts the apply.
    Timer {
        id: writeDebounce
        interval: 200
        repeat: false
        onTriggered: valuesFileView.setText(toast.valuesJson())
    }
    function scheduleWrite() { writeDebounce.restart(); }

    Connections {
        target: Settings.settings
        ignoreUnknownSignals: true
        function onGlassBlurStrengthChanged() { toast.scheduleWrite(); }
        function onGlassBlurIterationsChanged() { toast.scheduleWrite(); }
        function onGlassVibrancyChanged() { toast.scheduleWrite(); }
        function onGlassOpacityChanged() { toast.scheduleWrite(); }
        function onGlassRefractionChanged() { toast.scheduleWrite(); }
        function onGlassChromaticChanged() { toast.scheduleWrite(); }
        function onGlassFresnelChanged() { toast.scheduleWrite(); }
        function onGlassSpecularChanged() { toast.scheduleWrite(); }
        function onGlassAdaptiveDimChanged() { toast.scheduleWrite(); }
        function onGlassLightFrostChanged() { toast.scheduleWrite(); }
    }

    // ── Verification ────────────────────────────────────────────────────────
    // The plugin has been observed to keep some values and drop others, so the
    // panel does not assume: it polls the check while it is open and says what
    // the compositor actually reports. "Переприменить" pushes again.
    property bool inSync: true
    property var differences: []
    property bool checked: false

    ProcessRunner {
        id: verifyRunner
        cmd: ["hyprglass-apply", "--check", "--json"]
        intervalMs: 3000
        parseJson: true
        autoStart: toast.visible
        onJson: (obj) => {
            toast.checked = true;
            toast.inSync = obj && obj.inSync === true;
            toast.differences = (obj && obj.differences) ? obj.differences : [];
        }
    }

    ProcessRunner {
        id: applyRunner
        cmd: ["hyprglass-apply"]
        intervalMs: 0
        restartMode: "never"
        autoStart: false
        onLine: (l) => { /* the check that follows reports the outcome */ }
        onExited: verifyRunner.start()
    }

    function reapply() {
        toast.checked = false;
        applyRunner.start();
    }

    // ── Card ────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.right: parent.right
        anchors.rightMargin: toast.margin
        anchors.verticalCenter: parent.verticalCenter
        width: Math.round(360 * Theme.scale(Screen))
        height: content.implicitHeight + Math.round(24 * Theme.scale(Screen))
        radius: Math.round(Theme.sidePanelCornerRadius * Theme.scale(Screen))
        color: Color.withAlpha(Theme.surface, 0.94)
        border.width: Theme.uiBorderWidth
        border.color: Color.withAlpha(Theme.textPrimary, 0.08)

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Math.round(12 * Theme.scale(Screen))
            spacing: Math.round(Theme.sidePanelSpacingSmall * Theme.scale(Screen))

            Text {
                text: "Стекло"
                color: Theme.textPrimary
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * 1.1)
                font.weight: Font.DemiBold
            }

            Repeater {
                model: toast.knobs
                delegate: GlassSlider {
                    id: knob
                    required property var modelData
                    Layout.fillWidth: true
                    label: knob.modelData.label
                    from: knob.modelData.min
                    to: knob.modelData.max
                    stepSize: knob.modelData.step
                    decimals: knob.modelData.digits
                    value: Settings.settings[knob.modelData.key]
                    onMoved: (newValue) => Settings.settings[knob.modelData.key] = newValue
                }
            }

            // The frosted tint brightens whatever is behind the glass, which
            // washes the light theme out — hence a switch of its own.
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(4 * Theme.scale(Screen))
                spacing: Math.round(8 * Theme.scale(Screen))
                Text {
                    Layout.fillWidth: true
                    text: "Мороз в светлой теме"
                    color: Theme.textPrimary
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall * Theme.scale(Screen)
                }
                Rectangle {
                    id: lightSwitch
                    readonly property bool on: Settings.settings.glassLightFrost
                    implicitWidth: Math.round(34 * Theme.scale(Screen))
                    implicitHeight: Math.round(18 * Theme.scale(Screen))
                    radius: height / 2
                    color: on
                        ? Color.withAlpha(Theme.accentPrimary, 0.85)
                        : Color.withAlpha(Theme.textPrimary, 0.14)
                    Behavior on color { ColorAnimation { duration: 140 } }

                    Rectangle {
                        width: parent.height - Math.round(4 * Theme.scale(Screen))
                        height: width
                        radius: width / 2
                        y: Math.round(2 * Theme.scale(Screen))
                        x: lightSwitch.on
                            ? parent.width - width - Math.round(2 * Theme.scale(Screen))
                            : Math.round(2 * Theme.scale(Screen))
                        color: Theme.surface
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.settings.glassLightFrost = !Settings.settings.glassLightFrost
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(4 * Theme.scale(Screen))
                spacing: Math.round(8 * Theme.scale(Screen))
                Repeater {
                    model: toast.presets
                    delegate: Rectangle {
                        id: presetButton
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: Math.round(26 * Theme.scale(Screen))
                        radius: Math.round(Theme.cornerRadiusSmall * Theme.scale(Screen))
                        color: presetHover.containsMouse
                            ? Color.withAlpha(Theme.accentPrimary, 0.22)
                            : Color.withAlpha(Theme.textPrimary, 0.06)
                        Text {
                            anchors.centerIn: parent
                            text: presetButton.modelData.label
                            color: Theme.textPrimary
                            font.family: Theme.fontFamily
                            font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * 0.95)
                        }
                        MouseArea {
                            id: presetHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: toast.applyPreset(presetButton.modelData)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(4 * Theme.scale(Screen))
                spacing: Math.round(8 * Theme.scale(Screen))

                Text {
                    Layout.fillWidth: true
                    text: !toast.checked
                        ? "Проверяю…"
                        : (toast.inSync ? "Применено" : "Расходится: " + toast.differences.join(", "))
                    color: !toast.checked
                        ? Color.withAlpha(Theme.textPrimary, 0.5)
                        : (toast.inSync
                            ? Color.withAlpha(Theme.accentPrimary, 0.95)
                            : Color.withAlpha("#e8b04b", 0.95))
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * 0.85)
                    elide: Text.ElideRight
                    wrapMode: Text.NoWrap
                }

                Rectangle {
                    id: reapplyButton
                    implicitWidth: Math.round(96 * Theme.scale(Screen))
                    implicitHeight: Math.round(22 * Theme.scale(Screen))
                    radius: Math.round(Theme.cornerRadiusSmall * Theme.scale(Screen))
                    color: reapplyHover.containsMouse
                        ? Color.withAlpha(Theme.accentPrimary, 0.25)
                        : Color.withAlpha(Theme.textPrimary, 0.07)
                    Text {
                        anchors.centerIn: parent
                        text: "Переприменить"
                        color: Theme.textPrimary
                        font.family: Theme.fontFamily
                        font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * 0.8)
                    }
                    MouseArea {
                        id: reapplyHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toast.reapply()
                    }
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(2 * Theme.scale(Screen))
                text: "Значения — в ~/.config/hypr/hyprglass.json"
                color: Color.withAlpha(Theme.textPrimary, 0.5)
                font.family: Theme.fontFamily
                font.pixelSize: Math.round(Theme.fontSizeSmall * Theme.scale(Screen) * 0.85)
            }
        }
    }

    // Escape closes the panel; it is a tool, not a surface to hunt for.
    Shortcut {
        sequence: "Escape"
        enabled: toast.visible
        onActivated: toast.hidePopup()
    }
}
