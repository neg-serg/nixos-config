pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Settings
import "../../Helpers/Color.js" as Color

// Glass panel: live tuning for the hyprglass settings.
//
// The values live in Settings.json (so they survive restarts and the shell's own
// persistence handles them) and are written through to
// ~/.config/hypr/hyprglass-user.lua on every change. `hyprglass-apply` picks that
// file up through the hyprglass-config path unit, which is what pushes the values
// into the running compositor — the panel never talks to hyprctl itself, so there
// is exactly one place that knows how the plugin wants its config.
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

    // ── Writing the plugin's file ────────────────────────────────────────────
    // hyprglass takes plain config keys (its own Lua API aborts the compositor),
    // so the panel emits exactly that call. Values are pushed through the path
    // unit, not from here.
    readonly property string _home: {
        var h = Quickshell.env("HOME");
        return (h && h !== "") ? h : "/tmp";
    }
    readonly property string userFile: _home + "/.config/hypr/hyprglass-user.lua"

    function luaText() {
        var s = Settings.settings;
        var light = s.glassLightFrost ? s.glassVibrancy : -1;
        return "-- Written by the quickshell Glass panel — edit it in the panel, not here.\n"
            + "hl.config({ plugin = { hyprglass = {\n"
            + "  blur_strength = " + Number(s.glassBlurStrength).toFixed(1) + ",\n"
            + "  blur_iterations = " + Math.round(Number(s.glassBlurIterations)) + ",\n"
            + "  vibrancy = " + Number(s.glassVibrancy).toFixed(2) + ",\n"
            + "  glass_opacity = " + Number(s.glassOpacity).toFixed(2) + ",\n"
            + "  refraction_strength = " + Number(s.glassRefraction).toFixed(2) + ",\n"
            + "  chromatic_aberration = " + Number(s.glassChromatic).toFixed(2) + ",\n"
            + "  fresnel_strength = " + Number(s.glassFresnel).toFixed(2) + ",\n"
            + "  specular_strength = " + Number(s.glassSpecular).toFixed(2) + ",\n"
            + "  adaptive_dim = " + Number(s.glassAdaptiveDim).toFixed(2) + ",\n"
            + "  light = { vibrancy = " + light + " },\n"
            + "} } })\n";
    }

    FileView {
        id: userFileView
        path: toast.userFile
        blockWrites: false
    }
    // Debounced: a slider drag fires dozens of changes, and each one would start
    // the apply service.
    Timer {
        id: writeDebounce
        interval: 200
        repeat: false
        onTriggered: userFileView.setText(toast.luaText())
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

            Text {
                Layout.fillWidth: true
                Layout.topMargin: Math.round(2 * Theme.scale(Screen))
                text: "Применяется сразу — через hyprglass-apply"
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
