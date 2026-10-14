pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import "NixieLab.js" as Lab

// The live nixie settings menu (qs.nixielab): sections of sliders, colour
// fields, toggles and one choice, a preset strip, and Save / Reset / Export.
//
// Editing is process-local: every widget writes the running value through
// GreeterTheme.setOverride ("greeter.nixie…"), so the preview follows the hand
// immediately and nothing is persisted until Save. Save merges only the keys
// that differ from what the user's part already says into
// ~/.config/quickshell/Theme/greeter.jsonc — written by a temp file + rename,
// like the shell's own theme merge, and never into .theme.json. Reset writes
// the repository defaults explicitly (the repo part when readable, the
// embedded map below otherwise). Export is a read-only snippet for the repo
// copy; this panel never touches /etc/nixos.
Rectangle {
    id: menu

    implicitWidth: 400
    implicitHeight: 640

    color: "#ee14161c"
    radius: 10
    border.width: 1
    border.color: "#333842"

    // ── Token metadata ──────────────────────────────────────────────────────
    // The order is also the export order and what Reset walks.
    readonly property var tokenOrder: [
        "nixieGlow", "nixieTempK", "nixieExposure", "nixieGlowColor", "nixieTint",
        "nixieTintWallpaper", "nixieGlassColor", "nixieCathodeColor", "nixieHighlight",
        "nixieWarmth", "nixieWire", "nixieStack", "nixieViewAngle", "nixieViewDistance",
        "nixieViewPitch", "nixieCameraFollow", "nixieCameraRange", "nixieDigitSize",
        "nixieTubeMargin", "nixieSpacing", "nixieFlicker", "nixieFlickerMs",
        "nixieShimmer", "nixieShimmerMs", "nixieJitter", "nixie24h", "nixieLeadingZero",
        "nixieQuality", "nixieAge", "nixieBase"
    ]

    // Fallback defaults, mirroring files/quickshell/Theme/greeter.jsonc. They
    // are used when the repository part cannot be read, so Reset still writes
    // explicit values on a login-like tree with no repo checkout.
    readonly property var fallbackDefaults: ({
        nixieGlow: 1.0, nixieTempK: 2100, nixieExposure: 2.5, nixieGlowColor: "#ff5a10",
        nixieTint: "#00000000", nixieTintWallpaper: 0.0, nixieGlassColor: "#4d120b06",
        nixieCathodeColor: "#aab6c4", nixieHighlight: 0.8, nixieWarmth: 0.45,
        nixieWire: 0.0440, nixieStack: 0.5, nixieViewAngle: 16.0, nixieViewDistance: 8.0,
        nixieViewPitch: 0.0, nixieCameraFollow: true, nixieCameraRange: 6.0,
        nixieDigitSize: 92, nixieTubeMargin: 16, nixieSpacing: 1.0,
        nixieFlicker: true, nixieFlickerMs: 320, nixieShimmer: 1.0, nixieShimmerMs: 66,
        nixieJitter: 1.0, nixie24h: true, nixieLeadingZero: false,
        nixieQuality: "full", nixieAge: 1.0, nixieBase: false
    })

    // Defaults read from the repository part (the commented source of truth).
    property var repoNixie: ({})

    // Values the tokens had before the menu touched them: the reference the
    // dirty check compares an override against.
    property var baseValues: ({})

    property string status: ""
    property bool exportOpen: false

    // Child processes run with an explicit environment (Quickshell's Process
    // replaces it), so the shell they run under needs a PATH of its own:
    // without it `mv` and `wl-copy` are simply not found and Save fails
    // silently with exit 127 while the panel reports it is verifying.
    readonly property string shellPath: "/run/current-system/sw/bin:/usr/bin:/bin"

    // ── Where the parts live ────────────────────────────────────────────────
    readonly property string userThemeDir: {
        var xdg = Quickshell.env("XDG_CONFIG_HOME");
        var home = Quickshell.env("HOME");
        var base = (xdg && xdg !== "") ? xdg : (home + "/.config");
        return base + "/quickshell/Theme";
    }
    readonly property string userPartPath: userThemeDir + "/greeter.jsonc"
    // Resolved from this module, so a harness started from /etc/nixos reads the
    // repository part; the deployed greeter symlink points at the same tree.
    readonly property string repoPartPath: String(Qt.resolvedUrl("../../Theme/greeter.jsonc")).replace("file://", "")

    // ── Value plumbing ──────────────────────────────────────────────────────
    function defaultFor(key) {
        return (menu.repoNixie[key] !== undefined) ? menu.repoNixie[key] : menu.fallbackDefaults[key];
    }

    function val(key) {
        return GreeterTheme.effective("greeter." + key, menu.defaultFor(key));
    }

    function set(key, value) {
        // Remember the pre-override value once, for the dirty comparison.
        if (menu.baseValues[key] === undefined) {
            var bv = Object.assign({}, menu.baseValues);
            bv[key] = GreeterTheme.effective("greeter." + key, menu.defaultFor(key));
            menu.baseValues = bv;
        }
        GreeterTheme.setOverride("greeter." + key, value);
    }

    function setColor(key, c) {
        menu.set(key, Lab.argbFromComponents(c.r, c.g, c.b, c.a));
    }

    // Numbers and booleans compare by identity; colour strings by their
    // #AARRGGBB components, so "#ff5a10" equals "#ffff5a10".
    function sameValue(a, b) {
        if (typeof a === "number" || typeof b === "number"
                || typeof a === "boolean" || typeof b === "boolean")
            return a === b;
        var ca = Lab.componentsFromArgb(a);
        var cb = Lab.componentsFromArgb(b);
        if (ca !== null && cb !== null)
            return ca.a === cb.a && ca.r === cb.r && ca.g === cb.g && ca.b === cb.b;
        return String(a) === String(b);
    }

    readonly property var dirtyKeys: {
        var out = [];
        var ov = GreeterTheme.overrides || ({});
        for (var path in ov) {
            if (path.indexOf("greeter.") !== 0)
                continue;
            var key = path.substring(8);
            if (menu.fallbackDefaults[key] === undefined)
                continue;
            if (!menu.sameValue(ov[path], menu.baseValues[key]))
                out.push(key);
        }
        out.sort();
        return out;
    }
    readonly property bool dirty: dirtyKeys.length > 0

    // ── Reading the parts ───────────────────────────────────────────────────
    property bool partReady: false
    property string partText: ""
    property string _queued: ""
    property string _mode: "save"
    property var _verify: null
    property var _pendingKeys: []
    property bool _saveArmed: false
    property bool _resetArmed: false

    function onPartLoaded() {
        menu.partText = partReader.text() || "";
        menu.partReady = true;
        menu.runQueued();
    }

    function onPartMissing() {
        menu.partText = "";
        menu.partReady = true;
        menu.runQueued();
    }

    function runQueued() {
        if (menu._queued === "" || !menu.partReady)
            return;
        var what = menu._queued;
        menu._queued = "";
        if (what === "save")
            menu.doSave();
        else if (what === "reset")
            menu.doReset();
    }

    // Compose the new part: the user's own JSON with only the given keys
    // replaced. Returns null when the file cannot be parsed — never a partial
    // file and never a rewrite of a part we do not understand.
    function compose(patch) {
        var data;
        try {
            data = Lab.parseJsonc(menu.partText);
        } catch (e) {
            return null;
        }
        if (data === null || typeof data !== "object" || Array.isArray(data))
            return null;
        var greeter = data.greeter;
        if (greeter === null || typeof greeter !== "object")
            greeter = {};
        for (var key in patch)
            greeter[key] = patch[key];
        data.greeter = greeter;
        var text = JSON.stringify(data, null, 2) + "\n";
        try {
            JSON.parse(text); // the parse check before anything reaches the disk
        } catch (e2) {
            return null;
        }
        return text;
    }

    // ── Save / Reset / Export ───────────────────────────────────────────────
    function requestSave() {
        menu.status = "";
        menu._queued = "save";
        menu._saveArmed = true;
    }

    function doSave() {
        if (!menu.dirty) {
            menu.status = "Нет изменений";
            return;
        }
        if (!menu.partReady)
            return; // stays queued; onPartLoaded runs it
        var ov = GreeterTheme.overrides || ({});
        var keys = menu.dirtyKeys.slice();
        var patch = {};
        for (var i = 0; i < keys.length; i++)
            patch[keys[i]] = ov["greeter." + keys[i]];
        var content = menu.compose(patch);
        if (content === null) {
            menu.status = "Ошибка: файл темы не разобран";
            return;
        }
        menu.writeContent(content, "save", patch);
    }

    function requestReset() {
        menu.status = "";
        // The picture goes to the repository defaults at once; the explicit
        // defaults are then written to the user's part like a Save. baseValues
        // is committed only after the write verifies, so the dirty marker
        // keeps meaning "this is not what the disk says yet".
        var keys = menu.tokenOrder;
        for (var i = 0; i < keys.length; i++)
            GreeterTheme.setOverride("greeter." + keys[i], menu.defaultFor(keys[i]));
        menu._queued = "reset";
        menu._resetArmed = true;
    }

    function doReset() {
        if (!menu.partReady)
            return;
        var patch = {};
        var keys = menu.tokenOrder;
        for (var i = 0; i < keys.length; i++)
            patch[keys[i]] = menu.defaultFor(keys[i]);
        var content = menu.compose(patch);
        if (content === null) {
            menu.status = "Ошибка: файл темы не разобран";
            return;
        }
        menu.writeContent(content, "reset", patch);
    }

    function writeContent(content, mode, verify) {
        menu._mode = mode;
        menu._verify = verify;
        var keys = [];
        for (var key in verify)
            keys.push(key);
        menu._pendingKeys = keys;
        writer.target = menu.userPartPath;
        writer.environment = ({ NIXIELAB_JSON: content, PATH: menu.shellPath });
        writer.running = true;
    }

    // The write is over; read the part back and check that parsing it yields
    // the values that were sent. baseValues is committed only then, so the
    // dirty marker means "matches the disk", not "the process exited".
    function onWriterStopped() {
        menu.status = "Проверяю…";
        verifier.reload();
    }

    function verifyText(text) {
        if (menu._verify === null)
            return;
        var expected = menu._verify;
        menu._verify = null;
        var ok = false;
        try {
            var data = Lab.parseJsonc(text);
            var greeter = (data && typeof data.greeter === "object" && data.greeter !== null)
                ? data.greeter : {};
            ok = true;
            for (var check in expected) {
                if (!menu.sameValue(greeter[check], expected[check])) {
                    ok = false;
                    break;
                }
            }
        } catch (e) {
            ok = false;
        }
        if (!ok) {
            menu.status = "Запись не проверена";
            menu._pendingKeys = [];
            return;
        }
        // The file just verified is the new base: composing the next save from
        // the stale pre-write snapshot would silently revert keys this menu is
        // not touching (e.g. after a Reset, whose whole point is the explicit
        // defaults on disk).
        menu.partText = text;
        var bv = Object.assign({}, menu.baseValues);
        var ov = GreeterTheme.overrides || ({});
        for (var i = 0; i < menu._pendingKeys.length; i++) {
            var key = menu._pendingKeys[i];
            if (ov["greeter." + key] !== undefined)
                bv[key] = ov["greeter." + key];
        }
        menu.baseValues = bv;
        menu._pendingKeys = [];
        menu.status = menu._mode === "reset" ? "Сброшено и проверено" : "Сохранено и проверено";
    }

    function onCopied(ok) {
        menu.status = ok ? "Скопировано в буфер" : "Буфер обмена недоступен";
    }

    function applyPreset(preset) {
        if (preset.reset) {
            menu.requestReset();
            return;
        }
        var values = preset.values || ({});
        for (var key in values)
            menu.set(key, values[key]);
        menu.status = "Пресет: " + preset.text;
    }

    // The repo-ready snippet: the current value of every menu token, comments
    // aside, exactly in the repo's #AARRGGBB style.
    function exportSnippet() {
        var lines = [];
        lines.push("// nixie tokens from the live menu (qs.nixielab) — paste into files/quickshell/Theme/greeter.jsonc");
        var keys = menu.tokenOrder;
        for (var i = 0; i < keys.length; i++) {
            var key = keys[i];
            var value = menu.val(key);
            var rendered = (typeof value === "string") ? JSON.stringify(value) : String(value);
            lines.push("    \"" + key + "\": " + rendered + (i < keys.length - 1 ? "," : ""));
        }
        return lines.join("\n") + "\n";
    }

    function copyExport() {
        clipboard.environment = ({ NIXIELAB_COPY: menu.exportSnippet(), PATH: menu.shellPath });
        clipboard.running = true;
    }

    // ── Reading and writing the parts ───────────────────────────────────────
    FileView {
        id: partReader
        path: menu.userPartPath
        preload: true
        printErrors: false
        onLoaded: menu.onPartLoaded()
        onLoadFailed: menu.onPartMissing()
    }

    FileView {
        id: repoPart
        path: menu.repoPartPath
        preload: true
        printErrors: false
        onLoaded: {
            try {
                var data = Lab.parseJsonc(repoPart.text());
                var greeter = (data && typeof data.greeter === "object" && data.greeter !== null)
                    ? data.greeter : {};
                var out = {};
                for (var i = 0; i < menu.tokenOrder.length; i++) {
                    var key = menu.tokenOrder[i];
                    if (greeter[key] !== undefined)
                        out[key] = greeter[key];
                }
                menu.repoNixie = out;
            } catch (e) {
                // The embedded map stays in charge.
            }
        }
    }

    Process {
        id: writer
        property string target: ""
        // Temp file and rename, the same shape as the shell's theme merge: the
        // part is either the old content or the new one, never half of either.
        command: ["/bin/sh", "-c", "printf '%s' \"$NIXIELAB_JSON\" > \"$0.new\" && mv -f \"$0.new\" \"$0\"", writer.target]
        Component.onCompleted: writer.environment = ({ NIXIELAB_JSON: "", PATH: menu.shellPath })
        onRunningChanged: {
            if (!writer.running)
                menu.onWriterStopped();
        }
    }

    // Reads the part as it landed on disk; parsing this text is the check that
    // the atomic write actually produced the values that were sent. A FileView
    // reload is used instead of spawning `cat`: the read has to happen after
    // the rename, and a process that exits immediately races the stdout
    // collector (the collector's streamFinished never arrived, so Save was
    // stuck on "Проверяю…" and every later save was not idempotent).
    FileView {
        id: verifier
        path: menu.userPartPath
        printErrors: false
        onLoaded: menu.verifyText(verifier.text())
        onLoadFailed: {
            if (menu._verify !== null) {
                menu._verify = null;
                menu._pendingKeys = [];
                menu.status = "Запись не проверена";
            }
        }
    }

    Process {
        id: clipboard
        command: ["/bin/sh", "-c", "printf '%s' \"$NIXIELAB_COPY\" | wl-copy && echo NIXIELAB_COPIED"]
        Component.onCompleted: clipboard.environment = ({ NIXIELAB_COPY: "", PATH: menu.shellPath })
        stdout: StdioCollector {
            id: clipboardOut
            waitForEnd: true
            onStreamFinished: menu.onCopied(clipboardOut.text.indexOf("NIXIELAB_COPIED") >= 0)
        }
    }

    // The 250 ms coalescing window of Save / Reset: a drag cannot produce one
    // write per frame, and a second click inside the window only re-arms it.
    Timer {
        interval: 250
        repeat: false
        running: menu._saveArmed
        onTriggered: {
            menu._saveArmed = false;
            menu.doSave();
        }
    }

    Timer {
        interval: 250
        repeat: false
        running: menu._resetArmed
        onTriggered: {
            menu._resetArmed = false;
            menu.doReset();
        }
    }

    // ── Panel ───────────────────────────────────────────────────────────────
    component MenuButton: Rectangle {
        id: button
        property string label: ""
        property bool primary: false
        signal activated()

        implicitHeight: 30
        radius: 6
        color: button.primary
            ? (buttonArea.containsMouse ? "#4f86a5" : "#3f6f8f")
            : (buttonArea.containsMouse ? "#232833" : "#1b1f27")
        border.width: 1
        border.color: button.primary ? "#63c8e8" : "#333842"

        Text {
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? "#eef7fc" : "#d5dae3"
            font.pixelSize: 12
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.activated()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Настройки никс"
                color: "#e8eaf0"
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            Text {
                text: menu.dirty ? "● не сохранено" : "✓ сохранено"
                color: menu.dirty ? "#e0b04b" : "#7fbf9f"
                font.pixelSize: 12
            }
        }

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: scroller.width
                spacing: 12

                NixieSection {
                    title: "Пресеты"
                    NixiePresetRow {
                        presets: [
                            { text: "Винтаж", values: { nixieTempK: 2100, nixieExposure: 2.5 } },
                            { text: "Амбра", values: { nixieTempK: 2400, nixieExposure: 1.5 } },
                            { text: "Циан", values: { nixieTint: "#cc66e0ff" } },
                            { text: "От обоев", values: { nixieTintWallpaper: 0.35 } },
                            { text: "Погасить", values: { nixieGlow: 0 } },
                            { text: "Сброс", reset: true }
                        ]
                        onChosen: preset => menu.applyPreset(preset)
                    }
                }

                NixieSection {
                    title: "Разряд"
                    NixieSlider {
                        label: "Яркость разряда"
                        value: menu.val("nixieGlow")
                        from: 0
                        to: 2.5
                        step: 0.05
                        onMoved: value => menu.set("nixieGlow", value)
                    }
                    NixieSlider {
                        label: "Температура"
                        unit: " K"
                        value: menu.val("nixieTempK")
                        from: 1600
                        to: 3200
                        step: 50
                        onMoved: value => menu.set("nixieTempK", value)
                    }
                    NixieSlider {
                        label: "Экспозиция"
                        value: menu.val("nixieExposure")
                        from: 0.5
                        to: 4.0
                        step: 0.05
                        onMoved: value => menu.set("nixieExposure", value)
                    }
                    NixieColorField {
                        label: "Цвет свечения"
                        value: menu.val("nixieGlowColor")
                        alpha: false
                        onPicked: value => menu.setColor("nixieGlowColor", value)
                    }
                    NixieColorField {
                        label: "Тонирование стекла"
                        value: menu.val("nixieTint")
                        alpha: true
                        onPicked: value => menu.setColor("nixieTint", value)
                    }
                    NixieSlider {
                        label: "Подхват цвета обоев"
                        value: menu.val("nixieTintWallpaper")
                        from: 0
                        to: 1
                        step: 0.05
                        onMoved: value => menu.set("nixieTintWallpaper", value)
                    }
                }

                NixieSection {
                    title: "Стекло"
                    NixieColorField {
                        label: "Цвет стекла"
                        value: menu.val("nixieGlassColor")
                        alpha: true
                        onPicked: value => menu.setColor("nixieGlassColor", value)
                    }
                    NixieColorField {
                        label: "Цвет катода"
                        value: menu.val("nixieCathodeColor")
                        alpha: false
                        onPicked: value => menu.setColor("nixieCathodeColor", value)
                    }
                    NixieSlider {
                        label: "Блик стекла"
                        value: menu.val("nixieHighlight")
                        from: 0
                        to: 2.5
                        step: 0.05
                        onMoved: value => menu.set("nixieHighlight", value)
                    }
                    NixieSlider {
                        label: "Тепло на стекле"
                        value: menu.val("nixieWarmth")
                        from: 0
                        to: 2.5
                        step: 0.05
                        onMoved: value => menu.set("nixieWarmth", value)
                    }
                    NixieSlider {
                        label: "Толщина нити"
                        value: menu.val("nixieWire")
                        from: 0.02
                        to: 0.08
                        step: 0.002
                        onMoved: value => menu.set("nixieWire", value)
                    }
                    NixieSlider {
                        label: "Металл"
                        value: menu.val("nixieStack")
                        from: 0
                        to: 1.5
                        step: 0.05
                        onMoved: value => menu.set("nixieStack", value)
                    }
                }

                NixieSection {
                    title: "Камера"
                    NixieSlider {
                        label: "Поворот"
                        unit: "°"
                        value: menu.val("nixieViewAngle")
                        from: -30
                        to: 30
                        step: 1
                        onMoved: value => menu.set("nixieViewAngle", value)
                    }
                    NixieSlider {
                        label: "Дистанция (0 = по умолчанию)"
                        value: menu.val("nixieViewDistance")
                        from: 0
                        to: 20
                        step: 0.5
                        onMoved: value => menu.set("nixieViewDistance", value)
                    }
                    NixieSlider {
                        label: "Наклон"
                        unit: "°"
                        value: menu.val("nixieViewPitch")
                        from: -20
                        to: 20
                        step: 1
                        onMoved: value => menu.set("nixieViewPitch", value)
                    }
                    NixieToggle {
                        label: "Следить за курсором"
                        value: menu.val("nixieCameraFollow")
                        onToggled: value => menu.set("nixieCameraFollow", value)
                    }
                    NixieSlider {
                        label: "Диапазон слежения"
                        unit: "°"
                        value: menu.val("nixieCameraRange")
                        from: 0
                        to: 15
                        step: 0.5
                        onMoved: value => menu.set("nixieCameraRange", value)
                    }
                }

                NixieSection {
                    title: "Ряд"
                    NixieSlider {
                        label: "Размер цифры"
                        unit: " px"
                        value: menu.val("nixieDigitSize")
                        from: 40
                        to: 200
                        step: 1
                        onMoved: value => menu.set("nixieDigitSize", value)
                    }
                    NixieSlider {
                        label: "Поле вокруг трубки"
                        unit: " px"
                        value: menu.val("nixieTubeMargin")
                        from: 0
                        to: 64
                        step: 1
                        onMoved: value => menu.set("nixieTubeMargin", value)
                    }
                    NixieSlider {
                        label: "Плотность ряда"
                        value: menu.val("nixieSpacing")
                        from: 0
                        to: 2
                        step: 0.01
                        onMoved: value => menu.set("nixieSpacing", value)
                    }
                }

                NixieSection {
                    title: "Движение"
                    NixieToggle {
                        label: "Перезажигание при смене"
                        value: menu.val("nixieFlicker")
                        onToggled: value => menu.set("nixieFlicker", value)
                    }
                    NixieSlider {
                        label: "Длительность перезажигания"
                        unit: " мс"
                        value: menu.val("nixieFlickerMs")
                        from: 0
                        to: 1500
                        step: 10
                        onMoved: value => menu.set("nixieFlickerMs", value)
                    }
                    NixieSlider {
                        label: "Мерцание"
                        value: menu.val("nixieShimmer")
                        from: 0
                        to: 1
                        step: 0.01
                        onMoved: value => menu.set("nixieShimmer", value)
                    }
                    NixieSlider {
                        label: "Период мерцания"
                        unit: " мс"
                        value: menu.val("nixieShimmerMs")
                        from: 33
                        to: 250
                        step: 1
                        onMoved: value => menu.set("nixieShimmerMs", value)
                    }
                    NixieSlider {
                        label: "Разброс трубок"
                        value: menu.val("nixieJitter")
                        from: 0
                        to: 1.5
                        step: 0.05
                        onMoved: value => menu.set("nixieJitter", value)
                    }
                }

                NixieSection {
                    title: "Формат"
                    NixieToggle {
                        label: "24-часовой формат"
                        value: menu.val("nixie24h")
                        onToggled: value => menu.set("nixie24h", value)
                    }
                    NixieToggle {
                        label: "Ведущий ноль"
                        value: menu.val("nixieLeadingZero")
                        onToggled: value => menu.set("nixieLeadingZero", value)
                    }
                }

                NixieSection {
                    title: "Качество"
                    NixieChoice {
                        label: "Путь шейдера"
                        options: [
                            { text: "Полное", value: "full" },
                            { text: "Среднее", value: "balanced" },
                            { text: "Лёгкое", value: "lite" }
                        ]
                        value: menu.val("nixieQuality")
                        onChosen: value => menu.set("nixieQuality", value)
                    }
                    NixieSlider {
                        label: "Старение"
                        value: menu.val("nixieAge")
                        from: 0
                        to: 2
                        step: 0.05
                        onMoved: value => menu.set("nixieAge", value)
                    }
                    NixieToggle {
                        label: "Цоколь с выводами"
                        value: menu.val("nixieBase")
                        onToggled: value => menu.set("nixieBase", value)
                    }
                }

                NixieSection {
                    title: "Действия"
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        MenuButton {
                            Layout.fillWidth: true
                            label: "Сохранить"
                            primary: true
                            onActivated: menu.requestSave()
                        }
                        MenuButton {
                            Layout.fillWidth: true
                            label: "Сбросить"
                            onActivated: menu.requestReset()
                        }
                        MenuButton {
                            Layout.fillWidth: true
                            label: "Экспорт"
                            onActivated: menu.exportOpen = true
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        visible: menu.status !== ""
                        text: menu.status
                        color: menu.status.indexOf("Ошибка") === 0 ? "#e0736b" : "#8f98a8"
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Сохранение — в ~/.config/quickshell/Theme/greeter.jsonc; репозиторий меню не меняет."
                        color: "#6f7888"
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 4
                }
            }
        }
    }

    // ── Export overlay (read-only) ─────────────────────────────────────────
    Rectangle {
        id: exportOverlay
        anchors.fill: parent
        anchors.margins: 1
        visible: menu.exportOpen
        color: "#f214161c"
        radius: menu.radius - 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8

            Text {
                Layout.fillWidth: true
                text: "Экспорт для репозитория"
                color: "#e8eaf0"
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }

            Text {
                Layout.fillWidth: true
                text: "Фрагмент вставляется в files/quickshell/Theme/greeter.jsonc вручную (или через nixie theme set). Меню файл репозитория не пишет."
                color: "#8f98a8"
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: exportText.implicitWidth
                contentHeight: exportText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                TextEdit {
                    id: exportText
                    text: menu.exportSnippet()
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.NoWrap
                    color: "#cfd6e0"
                    font.family: "monospace"
                    font.pixelSize: 11
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                MenuButton {
                    Layout.fillWidth: true
                    label: "Копировать"
                    primary: true
                    onActivated: menu.copyExport()
                }
                MenuButton {
                    Layout.fillWidth: true
                    label: "Закрыть"
                    onActivated: menu.exportOpen = false
                }
            }
        }
    }
}
