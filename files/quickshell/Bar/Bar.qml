import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Bar.Modules
import qs.Components
import "Modules" as LocalMods
import qs.Services
import qs.Settings
import qs.Widgets.SidePanel
import "../Helpers/Color.js" as Color
import "../Helpers/Utils.js" as Utils
import "../Helpers/WidgetBg.js" as WidgetBg

Scope {
    id: rootScope
    property var shell
    property alias visible: barRootItem.visible
    property real barHeight: 0 // Expose current bar height for other components (e.g. window mirroring)
    function vpnAccentColor() {
        const boost = Theme.vpnAccentSaturateBoost || 0;
        const desat = Theme.vpnDesaturateAmount || 0;
        const base = Color.saturate(Theme.accentPrimary, boost);
        return Color.desaturate(base, desat);
    }
    readonly property real _defaultPanelAlphaScale: 0.2
    function panelBgAlphaScale() {
        const raw = Settings.settings ? Settings.settings.panelBgAlphaScale : undefined;
        let val = Number(raw);
        if (!isFinite(val))
            val = _defaultPanelAlphaScale;
        return Utils.clamp01(val);
    }
    function wedgeWidthNorm(faceWidth, seamWidth) {
        var ww = Number(Quickshell.env("QS_WEDGE_WIDTH_PCT") || "");
        if (isFinite(ww) && ww > 0) return Utils.clamp01(ww/100.0);
        var faceW = Math.max(1, faceWidth);
        var targetPx = Math.max(1, Math.round(seamWidth));
        var capPx = Math.round(faceW * 0.35);
        var wpx = Math.min(targetPx, capPx);
        return Math.max(0.02, Math.min(0.98, wpx / faceW));
    }

    // Env toggles to hard-disable expensive paths during perf triage
    readonly property bool wedgeClipAllowed: ((Quickshell.env("QS_DISABLE_WEDGE") || "") !== "1")
    readonly property bool trianglesAllowed: ((Quickshell.env("QS_DISABLE_TRIANGLES") || "") !== "1")

    // Terminal workspace detection — makes seam gap fully transparent on non-terminal workspaces
    readonly property var _terminalIcons: ["\uf120", "\ue795", "\ue7a2"]
    property bool isTerminalWs: false

    function _recalcTerminalWs() {
        const name = HyprlandWatcher.activeWorkspaceName || "";
        let glyph = "";
        let rest = name;
        if (name.length > 0) {
            const cp = name.codePointAt(0);
            if (cp >= 0xE000 && cp <= 0xF8FF) {
                const skip = (cp > 0xFFFF) ? 2 : 1;
                glyph = String.fromCodePoint(cp);
                rest = name.substring(skip).replace(/^\s+/, "");
            }
        }
        const rn = rest.toLowerCase().trim();
        let terminal = false;
        if (glyph && _terminalIcons.indexOf(glyph) !== -1) { terminal = true; }
        else if (rn.startsWith("term")) { terminal = true; }
        else if (rn.endsWith("term")) { terminal = true; }
        isTerminalWs = terminal;
        if (Settings.settings && Settings.settings.debugLogs)
            console.debug('[Bar] workspace:', JSON.stringify(name), 'glyph:', JSON.stringify(glyph), 'rest:', JSON.stringify(rest), 'rn:', JSON.stringify(rn), 'isTerminalWs:', terminal);
    }

    Connections {
        target: HyprlandWatcher
        function onActiveWorkspaceNameChanged() { rootScope._recalcTerminalWs(); }
        function onActiveWorkspaceIdChanged() { rootScope._recalcTerminalWs(); }
    }

    Component.onCompleted: {
        // Force WallpaperAccent singleton to instantiate
        var wa = WallpaperAccent;
        _recalcTerminalWs();
    }

    function makeTriangleVariant(widthPx, heightPx, variantSelector) {
        const w = Math.max(1, Math.round(widthPx || 0));
        const h = Math.max(1, Math.round(heightPx || 0));
        const variants = [
            { key: "identity", flipX: false, flipY: false },
            { key: "flipX", flipX: true, flipY: false },
            { key: "flipY", flipX: false, flipY: true },
            { key: "flipXY", flipX: true, flipY: true }
        ];
        let idx = 0;
        if (typeof variantSelector === "string") {
            const lowered = variantSelector.trim().toLowerCase();
            const nameToIdx = { identity: 0, normal: 0, flipx: 1, flipy: 2, flipxy: 3, rotate: 3 };
            idx = nameToIdx[lowered] !== undefined ? nameToIdx[lowered] : 0;
        } else if (variantSelector !== undefined && variantSelector !== null && variantSelector !== "") {
            const numeric = Number(variantSelector);
            if (isFinite(numeric)) {
                idx = Math.floor(numeric) % variants.length;
                if (idx < 0)
                    idx += variants.length;
            }
        }
        const transform = variants[idx] || variants[0];
        const baseVerts = [
            Qt.point(0, h),
            Qt.point(0, 0),
            Qt.point(w, 0)
        ];
        const mapPoint = (pt) => Qt.point(
            transform.flipX ? (w - pt.x) : pt.x,
            transform.flipY ? (h - pt.y) : pt.y
        );
        return {
            key: transform.key,
            flipX: transform.flipX,
            flipY: transform.flipY,
            vertices: baseVerts.map(mapPoint)
        };
    }

    function makeTriangleVariantSet(widthPx, heightPx) {
        const out = [];
        for (let i = 0; i < 4; i++) {
            out.push(makeTriangleVariant(widthPx, heightPx, i));
        }
        return out;
    }

    component PanelSeparator : Rectangle {
        id: panelSeparator
        required property real scaleFactor
        required property int panelHeightPx
        // Control overall visibility: panelActive is toggled by parent panel,
        // while userVisible lets callers add per-instance conditions.
        property bool panelActive: true
        property bool userVisible: true
        property real alpha: 0.0
        property bool triangleEnabled: false
        property string backgroundKey: ""
        property color fallbackColor: Theme.surface
        property color backgroundColorOverride: "transparent"
        property color triangleColor: backgroundColorOverride.a > 0
            ? backgroundColorOverride
            : WidgetBg.color(Settings.settings, backgroundKey, fallbackColor)
        property real triangleWidthFactor: 1.0
        property bool mirrorTriangle: false
        property real mirrorTriangleWidthFactor: triangleWidthFactor
        property real widthScale: 1.0
        property Item snapLeft: null
        property Item snapRight: null
        property real snapWidth: 0
        property real snapInset: 0

        readonly property bool _snapLeftVisible: snapLeft ? snapLeft.visible : true
        readonly property bool _snapRightVisible: snapRight ? snapRight.visible : true
        readonly property bool _snapGated: {
            if (!snapLeft && !snapRight) return true;
            if (snapRight) return snapRight.visible;
            return snapLeft.visible;
        }
        readonly property bool _snapPrimaryEnabled: snapLeft ? snapLeft.visible : true
        readonly property bool _snapMirrorEnabled: snapRight ? snapRight.visible : true
        readonly property real _heightRaw: panelHeightPx
        readonly property int triangleHeightPx: Math.max(2, Math.round(_heightRaw))
        property bool highlightHypotenuse: false
        property bool highlightMirror: false
        property color highlightColor: Theme.accentPrimary
        property real highlightWidth: Math.max(1, Math.round(scaleFactor * 2))
        // Advanced controls to toggle which wedges render and whether they should flip horizontally.
        property bool useMirrorTriangleOnly: false
        property bool usePrimaryTriangleOnly: false
        property bool flipAcrossVerticalAxis: false
        width: snapWidth > 0
            ? Math.max(1, Math.round(snapWidth))
            : Math.max(1, Math.round(widthScale * Theme.panelSeparatorWidthFactor * scaleFactor * Math.max(1, Theme.uiBorderWidth) * 16))
        height: triangleHeightPx
        implicitHeight: triangleHeightPx
        Layout.preferredHeight: triangleHeightPx
        property var triangleVariant: "flipY"
        readonly property var triangleVariantSpec: rootScope.makeTriangleVariant(width, height, triangleVariant)
        readonly property bool triangleFlipX: triangleVariantSpec.flipX
        readonly property bool triangleFlipY: triangleVariantSpec.flipY
        readonly property var triangleVertices: triangleVariantSpec.vertices
        readonly property var triangleVariants: rootScope.makeTriangleVariantSet(width, height)
        readonly property bool _preferPrimary: usePrimaryTriangleOnly && useMirrorTriangleOnly
        readonly property bool primaryTriangleEnabled: (triangleEnabled && visible
                                                        && !(useMirrorTriangleOnly && !usePrimaryTriangleOnly)
                                                        && _snapPrimaryEnabled)
        readonly property bool mirrorTriangleEnabled: (triangleEnabled && mirrorTriangle && visible
                                                        && !(usePrimaryTriangleOnly && !useMirrorTriangleOnly)
                                                        && !_preferPrimary
                                                        && _snapMirrorEnabled)
        readonly property bool primaryFlipX: flipAcrossVerticalAxis ? !triangleFlipX : triangleFlipX
        readonly property bool mirrorFlipX: flipAcrossVerticalAxis ? triangleFlipX : !triangleFlipX
        radius: 0
        color: Color.withAlpha(Theme.textPrimary, alpha)
        opacity: 1.0
        Layout.alignment: Qt.AlignVCenter
        Layout.leftMargin: snapInset > 0 ? -Math.round(snapInset) : 0
        Layout.rightMargin: snapInset > 0 ? -Math.round(snapInset) : 0
        visible: panelActive && userVisible && rootScope.trianglesAllowed && _snapGated


        TriangleOverlay {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: (parent.primaryFlipX ? undefined : parent.left)
            anchors.right: (parent.primaryFlipX ? parent.right : undefined)
            width: parent.width
            height: parent.height
            color: parent.triangleColor
            flipX: parent.primaryFlipX
            flipY: parent.triangleFlipY
            xCoverage: parent.triangleWidthFactor
            z: parent.z + 0.5
            visible: parent.primaryTriangleEnabled && !parent.useMirrorTriangleOnly
        }

        TriangleOverlay {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: (!parent.mirrorFlipX ? undefined : parent.left)
            anchors.right: (!parent.mirrorFlipX ? parent.right : undefined)
            width: parent.width
            height: parent.height
            color: parent.triangleColor
            flipX: parent.mirrorFlipX
            flipY: !parent.triangleFlipY
            xCoverage: parent.mirrorTriangleWidthFactor
            z: parent.z + 0.5
            visible: parent.mirrorTriangleEnabled && !parent.usePrimaryTriangleOnly
        }

        Canvas {
            id: hypotenuseStroke
            anchors.fill: parent
            visible: parent.highlightHypotenuse && (parent.primaryTriangleEnabled || parent.mirrorTriangleEnabled)
            z: parent.z + 1
            antialiasing: true

            function drawHypotenuse(flipX, flipY, coverage, useMirror) {
                var w = width;
                var h = height;
                if (w <= 0 || h <= 0)
                    return;
                var cov = Utils.clamp01(coverage);
                var span = Math.max(1, Math.min(w, w * cov));
                var drawFlipX = useMirror ? parent.mirrorFlipX : parent.primaryFlipX;
                var drawFlipY = useMirror ? !parent.triangleFlipY : parent.triangleFlipY;
                var xBase = drawFlipX ? w : 0;
                var xEdge = drawFlipX ? Math.max(0, w - span) : span;
                var yBase = drawFlipY ? 0 : h;
                var yOpp = drawFlipY ? h : 0;
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, w, h);
                ctx.lineWidth = Math.max(1, parent.highlightWidth);
                ctx.lineCap = "round";
                ctx.lineJoin = "round";
                ctx.strokeStyle = parent.highlightColor;
                ctx.beginPath();
                ctx.moveTo(xEdge, yBase);
                ctx.lineTo(xBase, yOpp);
                ctx.stroke();
            }

            onPaint: {
                var targetMirror = parent.highlightMirror || (!parent.primaryTriangleEnabled && parent.mirrorTriangleEnabled);
                var span = targetMirror ? parent.mirrorTriangleWidthFactor : parent.triangleWidthFactor;
                var canDraw = targetMirror ? parent.mirrorTriangleEnabled : parent.primaryTriangleEnabled;
                if (!canDraw) {
                    var ctx = getContext("2d");
                    ctx.clearRect(0, 0, width, height);
                    return;
                }
                drawHypotenuse(parent.triangleFlipX, parent.triangleFlipY, span, targetMirror);
            }
            onVisibleChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        onTriangleWidthFactorChanged: hypotenuseStroke.requestPaint()
        onMirrorTriangleWidthFactorChanged: hypotenuseStroke.requestPaint()
        onTriangleFlipXChanged: hypotenuseStroke.requestPaint()
        onTriangleFlipYChanged: hypotenuseStroke.requestPaint()
        onHighlightColorChanged: hypotenuseStroke.requestPaint()
        onHighlightWidthChanged: hypotenuseStroke.requestPaint()
        onHighlightMirrorChanged: hypotenuseStroke.requestPaint()
        onUseMirrorTriangleOnlyChanged: hypotenuseStroke.requestPaint()
        onUsePrimaryTriangleOnlyChanged: hypotenuseStroke.requestPaint()
        onFlipAcrossVerticalAxisChanged: hypotenuseStroke.requestPaint()
    }

    component PillSeparator : PanelSeparator {
        readonly property color pillColor: Theme.surface
        backgroundColorOverride: pillColor
        fallbackColor: pillColor
        color: pillColor
        alpha: pillColor.a
    }

    // Workaround: Hyprland skips wallpaper render behind transparent bar
    // on first workspace (term). Brief opacity toggle forces a full repaint.
    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            barRootItem.opacity = 0.99
            Qt.callLater(function() { barRootItem.opacity = 1.0 })
        }
    }

    Item {
        id: barRootItem
        anchors.fill: parent

        Variants {
            id: barVariants
            model: Quickshell.screens

            Item {
                id: monitorItem
                property var modelData // 'modelData' comes from Variants
                readonly property bool monitorEnabled: (Settings.settings.barMonitors.includes(modelData.name)
                                                        || (Settings.settings.barMonitors.length === 0))

                // --- Whole-bar slide-up entrance animation (clip reveal) ---
                property real barSlideProgress: 1.0
                property bool barSlideAnimating: false
                property bool _barSlideInitDone: false
                NumberFadeBehavior {
                    id: barSlideAnim
                    target: monitorItem
                    property: "barSlideProgress"
                    duration: Theme.panelSlideMs || 350
                    easing.type: Theme.uiEasingStdOut || Easing.OutCubic
                    onStopped: { monitorItem.barSlideAnimating = false }
                }
                Timer {
                    id: barSlideTimer
                    interval: Theme.panelSlideTimerTickMs
                    repeat: false
                    onTriggered: {
                        monitorItem.barSlideProgress = 0;
                        monitorItem.barSlideAnimating = true;
                        barSlideAnim.from = 0;
                        barSlideAnim.to = 1;
                        barSlideAnim.start();
                    }
                }
                Component.onCompleted: {
                    if (monitorEnabled && Theme.animationsEnabled) {
                        _barSlideInitDone = true;
                        barSlideProgress = 0;
                        barSlideTimer.start();
                    }
                }

                PanelLayer {
                    id: reservePanel
                    screen: modelData
                    color: "transparent"
                    WlrLayershell.layer: WlrLayer.Bottom
                    WlrLayershell.namespace: "quickshell-bar-reserve"
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true
                    visible: monitorEnabled
                    implicitHeight: reserveBackground.height
                    exclusionMode: ExclusionMode.Normal
                    exclusiveZone: barHeightPx
                    // Qt.WindowTransparentForInput isn’t available in this build; skip flag tweak.
                    property real s: Theme.scale(reservePanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)

                    Item {
                        anchors.fill: parent

                        Rectangle {
                            id: reserveBackground
                            width: parent.width
                            height: reservePanel.barHeightPx
                            color: "transparent"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: false
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                PanelLayer {
                    id: backdropPanel
                    screen: modelData
                    color: "transparent"
                    WlrLayershell.namespace: "qs-panel"
                    readonly property bool _forceOverlay: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                                             || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                    WlrLayershell.layer: backdropPanel._forceOverlay ? WlrLayer.Overlay : WlrLayer.Bottom
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true
                    visible: monitorEnabled
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    property real s: Theme.scale(backdropPanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)
                    property real nonTerminalOpacity: 0.5
                    implicitHeight: barHeightPx

                    Item {
                        anchors.fill: parent
                        transform: Translate { y: backdropPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }

                        Canvas {
                            id: sharedBarBackdrop
                            anchors.fill: parent
                            readonly property color bgColor: Theme.panelBackdropColor
                            readonly property real baseOpacity: Theme.panelSeamOpacity
                            readonly property real effectiveOpacity: rootScope.isTerminalWs
                                ? baseOpacity
                                : baseOpacity * backdropPanel.nonTerminalOpacity

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = bgColor.toString();
                                ctx.globalAlpha = effectiveOpacity;
                                ctx.fillRect(0, 0, width, height);
                            }

                            onWidthChanged: requestPaint()
                            onHeightChanged: requestPaint()
                            onBgColorChanged: requestPaint()
                            onEffectiveOpacityChanged: requestPaint()
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: false
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }

                PanelLayer {
                    id: leftPanel
                    screen: modelData
                    color: "transparent"
                    property bool panelHovering: false
                    WlrLayershell.namespace: "qs-content-left"
                    // Debug/testing: put bars on Overlay when wedge debug or shader-test enabled
                    WlrLayershell.layer: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                          || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                        ? WlrLayer.Overlay : WlrLayer.Top
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: false
                    implicitWidth: leftPanel.screen ? Math.round(leftPanel.screen.width / 2) : 960
                    visible: monitorEnabled
                    implicitHeight: leftBarBackground.height
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    property real s: Theme.scale(leftPanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)
                    readonly property real _sideMarginBase: (
                        Settings.settings.panelSideMarginPx !== undefined
                        && Settings.settings.panelSideMarginPx !== null
                        && isFinite(Settings.settings.panelSideMarginPx)
                    ) ? Settings.settings.panelSideMarginPx : Theme.panelSideMargin
                    property int sideMargin: Math.round(_sideMarginBase * s)
                    property int widgetSpacing: Math.round(Theme.panelWidgetSpacing * s)
                    property int interWidgetSpacing: Math.max(widgetSpacing, Math.round(widgetSpacing * Theme.panelInterWidgetRatio))
                    property int seamWidth: Math.max(Theme.panelSeamMinPx, Math.round(widgetSpacing * Theme.panelSeamWidthRatio))
                    // Panel background transparency is configurable via Settings:
                    // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha
                    property color barBgColor: "transparent"
                    property bool panelTintEnabled: true
                    property color panelTintColor: Color.withAlpha(Theme.panelTintColor, Theme.panelTintAlpha)
                    Behavior on panelTintColor {
                        enabled: Theme._themeLoaded
                        ColorAnimation { duration: Theme.panelAnimFastMs }
                    }
                    property real panelTintStrength: Theme.panelTintStrength
                    property real panelTintFeatherTop: Theme.panelTintFeatherTop
                    property real panelTintFeatherBottom: Theme.panelTintFeatherBottom
                    readonly property real contentWidth: Math.max(
                        leftWidgetsRow.width,
                        leftWidgetsRow.implicitWidth || leftWidgetsRow.width || 0
                    ) + leftPanel.interWidgetSpacing

                        Item {
                            id: leftPanelContent
                            anchors.fill: parent
                            transform: Translate { y: leftPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }

                    Rectangle {
                        id: leftBarBackground
                        width: Math.max(1, leftPanel.width)
                        height: leftPanel.barHeightPx
                        color: "transparent"
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                            Rectangle {
                                id: leftBarFill
                                width: Math.min(leftBarBackground.width, Math.ceil(leftPanel.sideMargin + leftPanel.contentWidth))
                                height: leftBarBackground.height
                                color: leftPanel.barBgColor
                                topLeftRadius: Theme.cornerRadius
                                bottomLeftRadius: Theme.cornerRadius
                                topRightRadius: 0
                                bottomRightRadius: 0
                                anchors.top: leftBarBackground.top
                            anchors.left: leftBarBackground.left
                            // Keep visible; ShaderEffectSource will hide it from the scene
                            // only when the shader clip is active (via hideSource binding).
                        }
                        // Cut a triangular window from the right edge of leftBarFill
                        // so the underlying seam (in seamPanel) shows through exactly.
                        ShaderEffectSource {
                            id: leftBarFillSource
                            anchors.fill: leftBarFill
                            sourceItem: leftBarFill
                            // Hide the source item only when we are actually using
                            // the shader clip. Otherwise allow the base fill to draw.
                            hideSource: leftFaceClipLoader.active === true
                            live: true
                            recursive: true
                        }
                        // Legacy Canvas/OpacityMask fallback removed — shader path only
                        // Panel tint (left) drawn and masked within leftPanelContent so anchors are valid siblings
                        ShaderEffect {
                            id: leftPanelTintFX
                            anchors.fill: leftBarFill
                            // Keep the tint effect enabled when panelTintEnabled.
                            // ShaderEffectSource below hides it from the scene when the
                            // clipped-tint path is active.
                            visible: leftPanel.panelTintEnabled
                            fragmentShader: Qt.resolvedUrl("../shaders/panel_tint_mix.frag.qsb")
                            property var sourceSampler: leftPanelSource
                            property color tintColor: leftPanel.panelTintColor
                            property vector4d params0: Qt.vector4d(
                                leftPanel.panelTintStrength,
                                leftPanel.panelTintFeatherTop,
                                leftPanel.panelTintFeatherBottom,
                                0
                            )
                            blending: true
                        }
                        ShaderEffectSource {
                            id: leftPanelTintSource
                            anchors.fill: leftBarFill
                            sourceItem: leftPanelTintFX
                            // Hide the tint effect when the clipped tint path is active.
                            hideSource: leftTintClipLoader.active === true
                            live: true
                            recursive: true
                        }
                        // Legacy tint mask fallback removed — shader path only
                        // Shader-based subtractive wedge for the tint overlay (enabled with the same flag)
                        Loader {
                            id: leftTintClipLoader
                            anchors.fill: leftBarFill
                            z: 2
                            active: leftPanel.panelTintEnabled && leftFaceClipLoader.active === true
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                property var sourceSampler: leftPanelTintSource
                                property vector4d params0: Qt.vector4d(
                                    rootScope.wedgeWidthNorm(leftBarFill.width, leftPanel.seamWidth),
                                    1,
                                    1,
                                    0
                                )
                                property vector4d params1: Qt.vector4d(
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.uiRadiusSmall * 0.5 * leftPanel.s)) / Math.max(1, leftBarFill.width)))) ,
                                    0,0,0
                                )
                                // In shader-test mode, force visible magenta overlay for tint path as well
                                property vector4d params2: Qt.vector4d(
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 0.6 : 0.0,
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 1.0 : 0.0,
                                    0,0)
                                blending: true
                            }
                        }
                        // Subtractive wedge using a shader clip over the base face (lazy-loaded)
                        Loader {
                            id: leftFaceClipLoader
                            anchors.fill: leftBarFill
                            // Raise above base content; seam remains higher.
                            z: 50
                            // Force-activate in debug/test modes to guarantee visibility
                            active: (((Quickshell.env("QS_ENABLE_WEDGE_CLIP") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1")
                                    || (Settings.settings.enableWedgeClipShader === true))
                                    && rootScope.wedgeClipAllowed
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                // Clip the base face (pure fill color) to subtract the wedge
                                property var sourceSampler: leftBarFillSource
                                // params0: x=wNorm, y=slopeUp, z=side(+1 right edge), w=unused
                                property vector4d params0: Qt.vector4d(
                                    rootScope.wedgeWidthNorm(leftBarFill.width, leftPanel.seamWidth),
                                    1,
                                    1,
                                    0
                                )
                                // params1: x=feather
                                property vector4d params1: Qt.vector4d(
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.uiRadiusSmall * 0.5 * leftPanel.s)) / Math.max(1, leftBarFill.width)))) ,
                                    0,0,0
                                )
                                // Enable magenta wedge overlay when QS_WEDGE_DEBUG=1
                                property vector4d params2: Qt.vector4d(
                                    ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1") ? 0.6 : 0.0,
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 1.0 : 0.0,
                                    0, 0)
                                blending: true
                            }
                        }

                        Component.onCompleted: rootScope.barHeight = leftBarBackground.height
                        Connections {
                            target: leftBarBackground
                            function onHeightChanged() { rootScope.barHeight = leftBarBackground.height }
                        }

                        RowLayout {
                            id: leftWidgetsRow
                            anchors.verticalCenter: leftBarBackground.verticalCenter
                            anchors.left: leftBarBackground.left
                            anchors.leftMargin: leftPanel.sideMargin
                            spacing: leftPanel.interWidgetSpacing
                            ClockWidget { Layout.alignment: Qt.AlignVCenter; visible: WidgetRegistry.isVisible("clock") }
                            WsIndicator {
                                id: wsindicator
                                visible: WidgetRegistry.isVisible("workspaces")
                                Layout.alignment: Qt.AlignVCenter
                                workspaceGlyphDetached: true
                                showSubmapIcon: false
                                showLabel: true
                            }
                            RowLayout {
                                id: kbCluster
                                visible: WidgetRegistry.isVisible("keyboard")
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Math.round(Theme.panelNetClusterSpacing * leftPanel.s)

                                KeyboardLayoutHypr {
                                    id: kbIndicator
                                    Layout.alignment: Qt.AlignVCenter
                                    showKeyboardIcon: true
                                    showLayoutLabel: true
                                    iconSquare: false
                                }
                            }
                            Row {
                                id: netCluster
                                visible: WidgetRegistry.isVisible("network")
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Math.round(Theme.panelNetClusterSpacing * leftPanel.s)
                                LocalMods.NetClusterCapsule {
                                        id: netCapsule
                                        Layout.alignment: Qt.AlignVCenter
                                        screen: leftPanel.screen
                                        vpnIconRounded: true
                                        throughputText: ConnectivityState.throughputText
                                }
                            }
                            LocalMods.SystemMonitorCapsule {
                                id: systemMonitorCapsule
                                visible: WidgetRegistry.isVisible("sysmon")
                                Layout.alignment: Qt.AlignVCenter
                                screen: modelData
                            }
                            LocalMods.WeatherButton {
                                id: weatherButton
                                visible: WidgetRegistry.isVisible("weather") && Settings.settings.showWeatherInBar === true
                                Layout.alignment: Qt.AlignVCenter
                                capsule.rightTriangleVisible: true
                                capsule.rightTriangleWidthFactor: 0.75
                                capsule.triangleHighlightEnabled: true
                                capsule.triangleHighlightColor: Color.towardsBlack(Color.saturate(Color.towardsBlack(Color.saturate(rootScope.vpnAccentColor(), 0.2), 0.3), 0.2), 0.3)
                                capsule.triangleHighlightWidth: Math.max(2, Math.round(leftPanel.s * 3))
                            }
                        }
                    }

                    ShaderEffectSource {
                        id: leftPanelSource
                        anchors.fill: parent
                        sourceItem: leftPanelContent
                        transform: Translate { y: leftPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }
                        hideSource: false
                        live: true
                        recursive: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: false
                        acceptedButtons: Qt.NoButton
                    }

                    // (old Canvas triangle overlay removed to avoid blue tint overlay)
                }

                PanelLayer {
                    id: rightPanel
                    screen: modelData
                    color: "transparent"
                    property bool panelHovering: false
                    WlrLayershell.namespace: "qs-content-right"
                    // Debug/testing: put bars on Overlay when wedge debug or shader-test enabled
                    WlrLayershell.layer: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                          || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                        ? WlrLayer.Overlay : WlrLayer.Top
                    anchors.bottom: true
                    anchors.right: true
                    anchors.left: false
                    implicitWidth: rightPanel.screen ? Math.round(rightPanel.screen.width / 2) : 960
                    visible: monitorEnabled
                    implicitHeight: rightBarBackground.height
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    property real s: Theme.scale(rightPanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)
                    readonly property bool _mediaSlotVisible: !!(mediaModule && mediaModule.visible)
                    readonly property bool _mediaOverlayVisible: !!(mediaOverlayHost && mediaOverlayHost.visible && mediaModule && mediaModule.visible)
                    readonly property bool _mpdFlagsVisible: !!(mpdFlagsBar && mpdFlagsBar.visible)
                    readonly property bool _trayVisible: !!(systemTrayWrapper && systemTrayWrapper.trayVisible)
                    readonly property bool _microphoneVisible: !!(widgetsMicrophone && widgetsMicrophone.visible)
                    readonly property bool _volumeVisible: !!(widgetsVolume && widgetsVolume.visible)
                    readonly property bool _hasPanelContent: (
                        _mediaSlotVisible
                        || _mediaOverlayVisible
                        || _mpdFlagsVisible
                        || _trayVisible
                    )
                    readonly property bool baseFillVisible: monitorEnabled
                    readonly property bool renderActive: baseFillVisible && _hasPanelContent
                    readonly property real _sideMarginBase: (
                        Settings.settings.panelSideMarginPx !== undefined
                        && Settings.settings.panelSideMarginPx !== null
                        && isFinite(Settings.settings.panelSideMarginPx)
                    ) ? Settings.settings.panelSideMarginPx : Theme.panelSideMargin
                    property int sideMargin: Math.round(_sideMarginBase * s)
                    property int widgetSpacing: Math.round(Theme.panelWidgetSpacing * s)
                    property int interWidgetSpacing: Math.max(widgetSpacing, Math.round(widgetSpacing * Theme.panelInterWidgetRatio))
                    property int seamWidth: Math.max(Theme.panelSeamMinPx, Math.round(widgetSpacing * Theme.panelSeamWidthRatio))
                    // Panel background transparency is configurable via Settings:
                    // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha
                    property color barBgColor: "transparent"
                    property bool panelTintEnabled: true
                    property color panelTintColor: Color.withAlpha(Theme.panelTintColor, Theme.panelTintAlpha)
                    Behavior on panelTintColor {
                        enabled: Theme._themeLoaded
                        ColorAnimation { duration: Theme.panelAnimFastMs }
                    }
                    property real panelTintStrength: Theme.panelTintStrength
                    property real panelTintFeatherTop: Theme.panelTintFeatherTop
                    property real panelTintFeatherBottom: Theme.panelTintFeatherBottom

                    readonly property real contentWidth: Math.max(
                        rightWidgetsRow.width,
                        rightWidgetsRow.implicitWidth || rightWidgetsRow.width || 0
                    ) + rightPanel.interWidgetSpacing

                        Item {
                            id: rightPanelContent
                            anchors.fill: parent
                            transform: Translate { y: rightPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }
    
                    Rectangle {
                        id: rightBarBackground
                        width: Math.max(1, rightPanel.width)
                        height: rightPanel.barHeightPx
                        color: "transparent"
                        anchors.top: parent.top
                        anchors.right: parent.right
                        visible: rightPanel.baseFillVisible
                    }
                            Rectangle {
                                id: rightBarFill
                                width: Math.min(rightBarBackground.width, Math.ceil(rightPanel.sideMargin + rightPanel.contentWidth))
                                height: rightBarBackground.height
                                color: rightPanel.barBgColor
                                topRightRadius: Theme.cornerRadius
                                bottomRightRadius: Theme.cornerRadius
                                topLeftRadius: 0
                                bottomLeftRadius: 0
                            anchors.top: rightBarBackground.top
                            anchors.right: rightBarBackground.right
                            // Keep visible; ShaderEffectSource will hide it from the scene
                            // only when the shader clip is active (via hideSource binding).
                            visible: rightPanel.baseFillVisible
                        }
                        // Cut a triangular window from the left edge of rightBarFill
                        // so the underlying seam (in seamPanel) shows through exactly.
                        ShaderEffectSource {
                            id: rightBarFillSource
                            anchors.fill: rightBarFill
                            sourceItem: rightBarFill
                            // Hide the source item only when we are actually using the shader
                            // clip. Otherwise allow the base fill to draw.
                            hideSource: rightFaceClipLoader.active === true
                            live: true
                            recursive: true
                        }
                        // Legacy Canvas/OpacityMask fallback removed — shader path only
                        // Panel tint (right) drawn and masked within rightPanelContent so anchors are valid siblings
                        ShaderEffect {
                            id: rightPanelTintFX
                            anchors.fill: rightBarFill
                            // Keep the tint effect enabled when panelTintEnabled. The
                            // ShaderEffectSource below hides it when the clipped-tint path
                            // is active.
                            visible: rightPanel.baseFillVisible && rightPanel.panelTintEnabled
                            fragmentShader: Qt.resolvedUrl("../shaders/panel_tint_mix.frag.qsb")
                            property var sourceSampler: rightPanelSource
                            property color tintColor: rightPanel.panelTintColor
                            property vector4d params0: Qt.vector4d(
                                rightPanel.panelTintStrength,
                                rightPanel.panelTintFeatherTop,
                                rightPanel.panelTintFeatherBottom,
                                0
                            )
                            blending: true
                        }
                        ShaderEffectSource {
                            id: rightPanelTintSource
                            anchors.fill: rightBarFill
                            sourceItem: rightPanelTintFX
                            // Hide the tint effect when the clipped tint path is active.
                            hideSource: rightTintClipLoader.active === true
                            live: true
                            recursive: true
                        }
                        // Legacy tint mask fallback removed — shader path only
                        // Shader-based subtractive wedge for the tint overlay (enabled with the same flag)
                        Loader {
                            id: rightTintClipLoader
                            anchors.fill: rightBarFill
                            z: 2
                            active: rightPanel.panelTintEnabled && rightFaceClipLoader.active === true
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                property var sourceSampler: rightPanelTintSource
                                property vector4d params0: Qt.vector4d(
                                    rootScope.wedgeWidthNorm(rightBarFill.width, rightPanel.seamWidth),
                                    1,
                                    -1,
                                    0
                                )
                                property vector4d params1: Qt.vector4d(
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.uiRadiusSmall * 0.5 * rightPanel.s)) / Math.max(1, rightBarFill.width)))) ,
                                    0,0,0
                                )
                                // In shader-test mode, force visible magenta overlay for tint path as well
                                property vector4d params2: Qt.vector4d(
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 0.6 : 0.0,
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 1.0 : 0.0,
                                    0,0)
                                blending: true
                            }
                        }
                        // Subtractive wedge using a shader clip over the base face (lazy-loaded)
                        Loader {
                            id: rightFaceClipLoader
                            anchors.fill: rightBarFill
                            z: 50
                            active: rightPanel.renderActive && (
                                    (((Quickshell.env("QS_ENABLE_WEDGE_CLIP") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1")
                                    || (Settings.settings.enableWedgeClipShader === true))
                                    && rootScope.wedgeClipAllowed
                            )
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                // Clip the base face (pure fill color) to subtract the wedge
                                property var sourceSampler: rightBarFillSource
                                // params0: x=wNorm, y=slopeUp, z=side(-1 left edge), w=unused
                                property vector4d params0: Qt.vector4d(
                                    rootScope.wedgeWidthNorm(rightBarFill.width, rightPanel.seamWidth),
                                    1,
                                    -1,
                                    0
                                )
                                // params1: x=feather
                                property vector4d params1: Qt.vector4d(
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.uiRadiusSmall * 0.5 * rightPanel.s)) / Math.max(1, rightBarFill.width)))) ,
                                    0,0,0
                                )
                                // Enable magenta wedge overlay when QS_WEDGE_DEBUG=1
                                property vector4d params2: Qt.vector4d(
                                    ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1") ? 0.6 : 0.0,
                                    ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1") ? 1.0 : 0.0,
                                    0, 0)
                                blending: true
                            }
                        }

                        RowLayout {
                            id: rightWidgetsRow
                            anchors.verticalCenter: rightBarBackground.verticalCenter
                            anchors.right: rightBarBackground.right
                            anchors.rightMargin: rightPanel.sideMargin
                            spacing: 0
                            Item {
                                id: mediaRowSlot
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: implicitWidth
                                implicitWidth: mediaModule.parent === mediaRowSlot ? Math.max(mediaModule.implicitWidth, 1) : 0
                                implicitHeight: mediaModule.parent === mediaRowSlot ? Math.max(mediaModule.implicitHeight, 1) : 0
                                visible: WidgetRegistry.isVisible("media") && mediaModule.parent === mediaRowSlot && Settings.settings.showMediaInBar && MusicManager.hasPlayer && (MusicManager.isPlaying || MusicManager.isPaused)

                                Media {
                                    id: mediaModule
                                    anchors.fill: parent
                                    sidePanelPopup: sidebarPopup
                                }
                            }
                            LocalMods.MpdFlags {
                                id: mpdFlagsBar
                                visible: WidgetRegistry.isVisible("mpdFlags") && _mediaVisible && activeFlags.length > 0
                                Layout.alignment: Qt.AlignVCenter
                                property bool _mediaVisible: Settings.settings.showMediaInBar && MusicManager.hasPlayer
                                enabled: _mediaVisible && MusicManager.isCurrentMpdPlayer()
                                iconPx: Math.round(Theme.fontSizeSmall * Theme.scale(rightPanel.screen))
                                iconColor: Theme.textPrimary
                            }
                            LocalMods.PillCapsule {
                                id: pillCapsule
                                visible: WidgetRegistry.isVisible("pills")
                                Layout.alignment: Qt.AlignVCenter
                                screen: modelData
                            }
                            Item {
                                id: systemTrayWrapper
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillHeight: true
                                Layout.preferredHeight: pillCapsule.capsule.uniformCapsuleHeight
                                readonly property bool trayCapsuleHidden: Settings.settings.hideSystemTrayCapsule === true
                                readonly property bool trayVisible: WidgetRegistry.isVisible("systray") && (!trayCapsuleHidden || systemTrayModule.expanded)
                                readonly property bool tightSpacing: Settings.settings.systemTrayTightSpacing !== false
                                readonly property int horizontalPadding: tightSpacing ? 0 : Math.max(4, Math.round(Theme.panelTrayInlinePadding * rightPanel.s * 0.75))
                                readonly property color capsuleColor: WidgetBg.color(Settings.settings, "systemTray", Theme.surface)
                                readonly property real trayContentHeight: (
                                    systemTrayModule.capsuleHeight !== undefined
                                        ? systemTrayModule.capsuleHeight
                                        : (systemTrayModule.implicitHeight || systemTrayModule.height || 0)
                                )
                                readonly property int capsuleWidth: Math.max(1, systemTrayModule.implicitWidth) + systemTrayWrapper.horizontalPadding * 2
                                readonly property int capsuleHeight: pillCapsule.capsule.uniformCapsuleHeight
                                implicitWidth: trayVisible ? capsuleWidth : 0
                                implicitHeight: trayVisible ? capsuleHeight : 0
                                Layout.preferredWidth: implicitWidth
                                Layout.minimumWidth: implicitWidth
                                Layout.maximumWidth: implicitWidth

                                Rectangle {
                                    id: systemTrayBackground
                                    visible: systemTrayWrapper.trayVisible
                                    radius: 0
                                    color: systemTrayWrapper.capsuleColor
                                    width: systemTrayWrapper.capsuleWidth
                                    height: systemTrayWrapper.capsuleHeight
                                    border.width: 0
                                    border.color: "transparent"
                                    antialiasing: true
                                }

                                SystemTray {
                                    id: systemTrayModule
                                    shell: rootScope.shell
                                    screen: modelData
                                    trayMenu: externalTrayMenu
                                    anchors.centerIn: systemTrayWrapper.trayVisible ? systemTrayBackground : systemTrayWrapper
                                    inlineBgColor: Theme.background
                                    inlineBorderColor: "transparent"
                                    opacity: systemTrayWrapper.trayVisible ? 1 : 0
                                }
                            }
                            CustomTrayMenu { id: externalTrayMenu }
                            Microphone {
                                id: widgetsMicrophone
                                visible: WidgetRegistry.isVisible("microphone")
                                Layout.alignment: Qt.AlignVCenter
                                panelHovering: rightPanel.panelHovering
                            }
                            Volume {
                                id: widgetsVolume
                                visible: WidgetRegistry.isVisible("volume")
                                Layout.alignment: Qt.AlignVCenter
                                panelHovering: rightPanel.panelHovering
                            }
                        }

                        // Wallpaper accent sampler — inside visible panel so Canvas can paint
                        Item {
                            id: _wpSampler
                            opacity: 0
                            property int _accentRetryCount: 0

                            property string _wpPath: WallpaperAccent.currentWallpaperPath
                            on_WpPathChanged: {
                                if (_wpPath.length > 0) {
                                    _accentRetryCount = 0;
                                    _wpImage.source = "file://" + _wpPath;
                                    _wpDebounce.restart();
                                }
                            }
                            Component.onCompleted: {
                                var p = WallpaperAccent.currentWallpaperPath || _wpPath;
                                if (p.length > 0) {
                                    _accentRetryCount = 0;
                                    _wpImage.source = "file://" + p;
                                    _wpDebounce.restart();
                                }
                            }

                            Image {
                                id: _wpImage
                                opacity: 0
                                width: 48; height: 48
                                sourceSize.width: 48; sourceSize.height: 48
                                asynchronous: true
                                onStatusChanged: {
                                    if (status === Image.Ready)
                                        _wpDebounce.restart();
                                }
                            }

                            Timer {
                                id: _wpDebounce
                                interval: 50
                                repeat: false
                                onTriggered: {
                                    if (_wpImage.status === Image.Ready) {
                                        _wpRetry.stop();
                                        _wpCanvas.requestPaint();
                                    } else {
                                        _wpRetry.restart();
                                    }
                                }
                            }

                            Timer {
                                id: _wpRetry
                                interval: 200
                                repeat: true
                                onTriggered: {
                                    if (++_wpSampler._accentRetryCount > 10) {
                                        stop();
                                        Theme._wpHasAccent = false;
                                        return;
                                    }
                                    if (_wpImage.status === Image.Ready) {
                                        _wpRetry.stop();
                                        _wpCanvas.requestPaint();
                                    }
                                }
                            }

                            function _sampleAccent(imageData) {
                                if (!imageData || !imageData.data) return null;
                                var data = imageData.data;
                                var len = data.length;
                                var satMin = 10, lumMin = 20, lumMax = 235;
                                var satRelax = 8, lumRelaxMin = 20, lumRelaxMax = 240;
                                var rs = 0, gs = 0, bs = 0, n = 0;
                                for (var i = 0; i < len; i += 4) {
                                    var a = data[i + 3]; if (a < 128) continue;
                                    var r = data[i], g = data[i + 1], b = data[i + 2];
                                    var maxv = Math.max(r, g, b), minv = Math.min(r, g, b);
                                    var sat = maxv - minv; if (sat < satMin) continue;
                                    var lum = (r + g + b) / 3; if (lum < lumMin || lum > lumMax) continue;
                                    rs += r; gs += g; bs += b; ++n;
                                }
                                if (n === 0) {
                                    rs = 0; gs = 0; bs = 0; n = 0;
                                    for (var j = 0; j < len; j += 4) {
                                        var a2 = data[j + 3]; if (a2 < 128) continue;
                                        var r2 = data[j], g2 = data[j + 1], b2 = data[j + 2];
                                        var max2 = Math.max(r2, g2, b2), min2 = Math.min(r2, g2, b2);
                                        var sat2 = max2 - min2; if (sat2 < satRelax) continue;
                                        var lum2 = (r2 + g2 + b2) / 3; if (lum2 < lumRelaxMin || lum2 > lumRelaxMax) continue;
                                        rs += r2; gs += g2; bs += b2; ++n;
                                    }
                                }
                                if (n > 0) return { r: Math.min(255, Math.round(rs / n)), g: Math.min(255, Math.round(gs / n)), b: Math.min(255, Math.round(bs / n)) };
                                // Ultimate fallback: average all non-transparent pixels (handles dark grayscale images)
                                rs = 0; gs = 0; bs = 0; n = 0;
                                for (var k = 0; k < len; k += 4) {
                                    var a3 = data[k + 3]; if (a3 < 128) continue;
                                    rs += data[k]; gs += data[k + 1]; bs += data[k + 2]; ++n;
                                }
                                if (n > 0) return { r: Math.min(255, Math.round(rs / n)), g: Math.min(255, Math.round(gs / n)), b: Math.min(255, Math.round(bs / n)) };
                                return null;
                            }

                            Canvas {
                                id: _wpCanvas
                                width: 48
                                height: 48
                                opacity: 0
                                renderStrategy: Canvas.Cooperative
                                onPaint: {
                                    var ctx = getContext('2d');
                                    if (_wpImage.status !== Image.Ready) return;
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.drawImage(_wpImage, 0, 0, width, height);
                                    var img = ctx.getImageData(0, 0, width, height);
                                    var rgb = _wpSampler._sampleAccent(img);
                                    if (!rgb) {
                                        _wpRetry.restart();
                                        return;
                                    }
                                    Theme._wpAccent = Qt.rgba(rgb.r / 255.0, rgb.g / 255.0, rgb.b / 255.0, 1);
                                    Theme._wpHasAccent = true;
                                }
                            }
                        }

                        Item {
                            id: mediaOverlayHost
                            anchors.fill: rightBarBackground
                            visible: mediaModule.panelMode
                            z: -1
                            clip: false
                        }

                        MusicPopup {
                            id: sidebarPopup
                            anchorWindow: rightPanel
                            panelEdge: "bottom"
                        }

                        states: [
                            State {
                                name: "mediaPanelOverlayActive"
                                when: mediaModule.panelMode
                                ParentChange { target: mediaModule; parent: mediaOverlayHost }
                            },
                            State {
                                name: "mediaPanelOverlayInactive"
                                when: !mediaModule.panelMode
                                ParentChange { target: mediaModule; parent: mediaRowSlot }
                            }
                        ]
                    }

                    ShaderEffectSource {
                        id: rightPanelSource
                        anchors.fill: parent
                        sourceItem: rightPanelContent
                        transform: Translate { y: rightPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }
                        hideSource: false
                        live: true
                        recursive: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: false
                        acceptedButtons: Qt.NoButton
                    }

                    property string _lastAlbum: ""
                    function maybeShowOnAlbumChange() {
                        try {
                            if (!rightPanel.visible) return;
                            if (!MusicManager.hasPlayer) return;
                            const album = String(MusicManager.trackAlbum || "");
                            if (!album || album.length === 0) return;
                            if (album !== rightPanel._lastAlbum) {
                                if (MusicManager.trackTitle || MusicManager.trackArtist) sidebarPopup.showAt();
                                rightPanel._lastAlbum = album;
                            }
                        } catch (e) { /* ignore */ }
                    }
                    
                    Connections {
                        target: MusicManager
                        function onTrackAlbumChanged()  { rightPanel.maybeShowOnAlbumChange(); }
                    }

                    MouseArea {
                        id: trayHotZone
                        anchors.right: rightPanelContent.right
                        anchors.bottom: rightPanelContent.bottom
                        width: Math.round(Theme.panelHotzoneWidth * rightPanel.s)
                        height: Math.round(Theme.panelHotzoneHeight * rightPanel.s)
                        anchors.rightMargin: Math.round(width * Theme.panelHotzoneRightShift)
                        anchors.bottomMargin: Theme.uiMarginNone
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        z: 10001
                        onEntered: {
                            systemTrayModule.hotHover = true
                            systemTrayModule.expanded = true
                        }
                        onExited: {
                            systemTrayModule.hotHover = false
                        }
                        cursorShape: Qt.ArrowCursor
                    }

                    MouseArea {
                        id: barHoverTracker
                        anchors.fill: rightPanelContent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        propagateComposedEvents: true
                        z: 10000
                        onEntered: {
                            systemTrayModule.panelHover = true; rightPanel.panelHovering = true
                        }
                        onExited: {
                            systemTrayModule.panelHover = false
                            rightPanel.panelHovering = false
                            const menuOpen = systemTrayModule.trayMenu && systemTrayModule.trayMenu.visible
                            if (!systemTrayModule.hotHover && !systemTrayModule.holdOpen && !systemTrayModule.shortHoldActive && !menuOpen) {
                                systemTrayModule.expanded = false
                            }
                        }
                        visible: rightPanel.renderActive
                        Rectangle { visible: false }
                    }

                }

            }
        }
    }
}
