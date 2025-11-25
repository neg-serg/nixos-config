import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects as GE
import qs.Bar.Modules
import qs.Components
import "Modules" as LocalMods
import qs.Services
import qs.Settings
import qs.Widgets.SidePanel
import "../Helpers/Color.js" as Color
import "../Helpers/WidgetBg.js" as WidgetBg

Scope {
    id: rootScope
    property var shell
    property alias visible: barRootItem.visible
    property real barHeight: 0 // Expose current bar height for other components (e.g. window mirroring)
    function mixColor(a, b, t) {
        return Qt.rgba(a.r * (1 - t) + b.r * t,
                       a.g * (1 - t) + b.g * t,
                       a.b * (1 - t) + b.b * t,
                       a.a * (1 - t) + b.a * t);
    }
    function grayOf(c) {
        const y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return Qt.rgba(y, y, y, c.a);
    }
    function desaturateColor(c, amount) {
        const clamped = Math.min(1, Math.max(0, amount || 0));
        return mixColor(c, grayOf(c), clamped);
    }
    function vpnAccentColor() {
        const boost = Theme.vpnAccentSaturateBoost || 0;
        const desat = Theme.vpnDesaturateAmount || 0;
        const base = Color.saturate(Theme.accentPrimary, boost);
        return desaturateColor(base, desat);
    }
    readonly property real _defaultPanelAlphaScale: 0.2
    function panelBgAlphaScale() {
        const raw = Settings.settings ? Settings.settings.panelBgAlphaScale : undefined;
        let val = Number(raw);
        if (!isFinite(val))
            val = _defaultPanelAlphaScale;
        return Math.max(0.0, Math.min(1.0, val));
    }
    function panelBgColor(baseColor) {
        const scale = panelBgAlphaScale();
        const hsl = Color.toHsl(baseColor);
        const baseAlpha = (hsl && hsl.a !== undefined) ? hsl.a : 1.0;
        return Color.withAlpha(baseColor, baseAlpha * scale);
    }

    component TriangleOverlay : Canvas {
        property color color: Theme.background
        property bool flipX: false
        property bool flipY: false
        property real xCoverage: 1.0

        antialiasing: true
        enabled: visible
        contextType: "2d"

        onPaint: {
            var ctx = getContext("2d");
            var w = width;
            var h = height;
            ctx.clearRect(0, 0, w, h);
            if (w <= 0 || h <= 0) {
                return;
            }
            var coverage = Math.max(0.0, Math.min(1.0, xCoverage));
            var span = Math.max(1, w * coverage);
            span = Math.min(span, w);
            var xBase = flipX ? w : 0;
            var xEdge = flipX ? Math.max(0, w - span) : span;
            var yBase = flipY ? 0 : h;
            var yOpp = flipY ? h : 0;
            ctx.lineWidth = 0;
            ctx.lineJoin = "miter";
            ctx.lineCap = "butt";
            ctx.beginPath();
            ctx.moveTo(xBase, yBase);
            ctx.lineTo(xBase, yOpp);
            ctx.lineTo(xEdge, yBase);
            ctx.closePath();
            ctx.fillStyle = color;
            ctx.fill();
        }

        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onColorChanged: requestPaint()
        onFlipXChanged: requestPaint()
        onFlipYChanged: requestPaint()
        onXCoverageChanged: requestPaint()
        Component.onCompleted: requestPaint()
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
        property color fallbackColor: Qt.rgba(0, 0, 0, 1)
        property color backgroundColorOverride: "transparent"
        property color triangleColor: backgroundColorOverride.a > 0
            ? backgroundColorOverride
            : WidgetBg.color(Settings.settings, backgroundKey, fallbackColor)
        property real triangleWidthFactor: 1.0
        property bool mirrorTriangle: false
        property real mirrorTriangleWidthFactor: triangleWidthFactor
        property real widthScale: 1.0
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
        width: Math.max(1, Math.round(widthScale * Theme.panelSeparatorWidthFactor * scaleFactor * Math.max(1, Theme.uiBorderWidth) * 16))
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
                                                        && !(useMirrorTriangleOnly && !usePrimaryTriangleOnly))
        readonly property bool mirrorTriangleEnabled: (triangleEnabled && mirrorTriangle && visible
                                                        && !(usePrimaryTriangleOnly && !useMirrorTriangleOnly)
                                                        && !_preferPrimary)
        readonly property bool primaryFlipX: flipAcrossVerticalAxis ? !triangleFlipX : triangleFlipX
        readonly property bool mirrorFlipX: flipAcrossVerticalAxis ? triangleFlipX : !triangleFlipX
        radius: 0
        color: Color.withAlpha(Theme.textPrimary, alpha)
        opacity: 1.0
        Layout.alignment: Qt.AlignVCenter
        visible: panelActive && userVisible


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
                var cov = Math.max(0.0, Math.min(1.0, coverage));
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
        readonly property color pillColor: Theme.panelPillColor
        backgroundColorOverride: pillColor
        fallbackColor: pillColor
        color: pillColor
        alpha: pillColor.a
    }

    Item {
        id: barRootItem
        anchors.fill: parent

        Variants {
            model: Quickshell.screens

            Item {
                property var modelData // 'modelData' comes from Variants
                readonly property bool monitorEnabled: (Settings.settings.barMonitors.includes(modelData.name)
                                                        || (Settings.settings.barMonitors.length === 0))

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
                    id: shadowPanel
                    screen: modelData
                    color: "transparent"
                    WlrLayershell.namespace: "quickshell-bar-shadow"
                    readonly property bool _forceOverlay: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                                             || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                    WlrLayershell.layer: shadowPanel._forceOverlay ? WlrLayer.Overlay : WlrLayer.Bottom
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true
                    visible: monitorEnabled
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    // flag unavailable; keep default
                    property real s: Theme.scale(shadowPanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)
                    implicitHeight: barHeightPx
                    Component.onCompleted: { if (contentItem) contentItem.enabled = false }

                    Item {
                        anchors.fill: parent

                        ShaderEffect {
                            anchors.fill: parent
                            visible: shadowPanel.visible
                            property color baseColor: Theme.panelPillColor
                            property color accentColor: Theme.panelPillColor
                            property vector4d params0: Qt.vector4d(0.0, 0.0, 0.0, 0.0)
                            property vector4d params1: Qt.vector4d(0.0, 0.0, 0.93, 0.0)
                            fragmentShader: Qt.resolvedUrl("../shaders/diag.frag.qsb")
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
                    WlrLayershell.namespace: "quickshell-bar-left"
                    // Debug/testing: put bars on Overlay when wedge debug or shader-test enabled
                    WlrLayershell.layer: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                          || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                        ? WlrLayer.Overlay : WlrLayer.Top
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: false
                    implicitWidth: leftPanel.screen ? Math.round(leftPanel.screen.width / 2) : 960
                    visible: monitorEnabled
                    onVisibleChanged: {}
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
                    // Provide extra spacing between widgets now that decorative separators are gone
                    property int interWidgetSpacing: Math.max(widgetSpacing, Math.round(widgetSpacing * 1.35))
                    property int seamWidth: Math.max(8, Math.round(widgetSpacing * 0.85))
                    // Panel background transparency is configurable via Settings:
                    // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha
                    property color barBgColor: "transparent"
                    property real seamTaperTop: 0.25
                    property real seamTaperBottom: 0.9
                    property real seamOpacity: 0.55
                    readonly property real seamTiltSign: 1.0
                    readonly property real seamTaperTopClamped: Math.max(0.0, Math.min(1.0, seamTaperTop))
                    readonly property real seamTaperBottomClamped: Math.max(0.0, Math.min(1.0, seamTaperBottom))
                    readonly property real seamEdgeBaseTop: (seamTiltSign > 0)
                        ? (1.0 - seamTaperTopClamped)
                        : seamTaperTopClamped
                    readonly property real seamEdgeSlope: ((seamTiltSign > 0)
                        ? (1.0 - seamTaperBottomClamped)
                        : seamTaperBottomClamped) - seamEdgeBaseTop
                    property color seamFillColor: Color.withAlpha(
                        Color.mix(Theme.surfaceVariant, Theme.background, 0.45),
                        seamOpacity
                    )
                    readonly property real seamSlackWidth: Math.max(0, leftBarBackground.width - leftBarFill.width)
                    property bool panelTintEnabled: true
                    property color panelTintColor: Color.withAlpha("#ff2a36", 0.75)
                    property real panelTintStrength: 1.0
                    property real panelTintFeatherTop: 0.08
                    property real panelTintFeatherBottom: 0.35
                    readonly property real contentWidth: Math.max(
                        leftWidgetsRow.width,
                        leftWidgetsRow.implicitWidth || leftWidgetsRow.width || 0
                    ) + leftPanel.interWidgetSpacing

                        Item {
                            id: leftPanelContent
                            anchors.fill: parent

                    Rectangle {
                        id: leftBarBackdrop
                        width: Math.max(1, leftPanel.width)
                        height: leftPanel.barHeightPx
                        color: "#000000"
                        opacity: 0.65
                        anchors.top: parent.top
                        anchors.left: parent.left
                        z: -1
                    }
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
                                    // QS_WEDGE_WIDTH_PCT override; otherwise use panel seamWidth capped to 35% of face.
                                    (function(){
                                        var ww = Number(Quickshell.env("QS_WEDGE_WIDTH_PCT") || "");
                                        if (isFinite(ww) && ww > 0) return Math.max(0.0, Math.min(1.0, ww/100.0));
                                        var faceW = Math.max(1, leftBarFill.width);
                                        var targetPx = Math.max(1, Math.round(leftPanel.seamWidth));
                                        var capPx = Math.round(faceW * 0.35);
                                        var wpx = Math.min(targetPx, capPx);
                                        return Math.max(0.02, Math.min(0.98, wpx / faceW));
                                    })(),
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
                            active: ((Quickshell.env("QS_ENABLE_WEDGE_CLIP") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1")
                                    || (Settings.settings.enableWedgeClipShader === true)
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                // Clip the base face (pure fill color) to subtract the wedge
                                property var sourceSampler: leftBarFillSource
                                // params0: x=wNorm, y=slopeUp, z=side(+1 right edge), w=unused
                                property vector4d params0: Qt.vector4d(
                                    (function(){
                                        var ww = Number(Quickshell.env("QS_WEDGE_WIDTH_PCT") || "");
                                        if (isFinite(ww) && ww > 0) return Math.max(0.0, Math.min(1.0, ww/100.0));
                                        var faceW = Math.max(1, leftBarFill.width);
                                        var targetPx = Math.max(1, Math.round(leftPanel.seamWidth));
                                        var capPx = Math.round(faceW * 0.35);
                                        var wpx = Math.min(targetPx, capPx);
                                        return Math.max(0.02, Math.min(0.98, wpx / faceW));
                                    })(),
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

                        Item {
                            id: leftSeamFill
                            width: Math.min(leftBarBackground.width, leftPanel.seamWidth)
                            height: leftBarBackground.height
                            anchors.bottom: leftBarBackground.bottom
                            anchors.right: leftBarBackground.right
                            z: 1000
                            // Draw local seam wedge only when the shader path is active,
                            // and hide it while QS_WEDGE_DEBUG is enabled so the shader's
                            // magenta overlay remains visible for validation.
                            visible: leftFaceClipLoader.active === true && ((Quickshell.env("QS_WEDGE_DEBUG") || "") !== "1")
                            ShaderEffect {
                                id: leftSeamFX
                                anchors.fill: parent
                                fragmentShader: Qt.resolvedUrl("../shaders/seam.frag.qsb")
                                property color baseColor: leftPanel.seamFillColor
                                // params0: edgeBase, edgeSlope, tilt, opacity
                                property vector4d params0: Qt.vector4d(leftPanel.seamEdgeBaseTop, leftPanel.seamEdgeSlope, leftPanel.seamTiltSign, leftPanel.seamOpacity)
                                blending: true
                            }
                        }

                        // Mask the left seam fill so its visible area becomes a triangle
                        // matching the wedge; this prevents rectangular seam blocks.
                        ShaderEffectSource {
                            id: leftSeamSource
                            anchors.fill: leftSeamFill
                            sourceItem: leftSeamFX
                            hideSource: true
                            live: true
                            recursive: true
                        }
                        Canvas {
                            id: leftSeamMask
                            anchors.fill: leftSeamFill
                            visible: false
                            onPaint: {
                                var ctx = getContext('2d');
                                ctx.reset();
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = '#ffffffff';
                                ctx.fillRect(0, 0, width, height);
                                // Cut triangle adjacent to the seam boundary (x = 0 in this local space)
                                ctx.fillStyle = '#000000ff';
                                ctx.beginPath();
                                // Default orientation: bottom-left → top-right
                                ctx.moveTo(0, height);
                                ctx.lineTo(width, 0);
                                ctx.lineTo(width, height);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                        GE.OpacityMask {
                            anchors.fill: leftSeamFill
                            source: leftSeamSource
                            maskSource: leftSeamMask
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
                            ClockWidget { Layout.alignment: Qt.AlignVCenter }
                            WsIndicator {
                                id: wsindicator
                                Layout.alignment: Qt.AlignVCenter
                                workspaceGlyphDetached: true
                                showSubmapIcon: false
                                showLabel: true
                            }
                            PanelSeparator {
                                scaleFactor: leftPanel.s
                                panelHeightPx: leftPanel.barHeightPx
                                triangleEnabled: true
                                triangleWidthFactor: 0.75
                                mirrorTriangle: true
                                widthScale: 2.0
                                backgroundKey: "workspaces"
                            }
                            RowLayout {
                                id: kbCluster
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
                            PanelSeparator {
                                scaleFactor: leftPanel.s
                                panelHeightPx: leftPanel.barHeightPx
                                userVisible: netCluster.visible
                                triangleEnabled: netCluster.visible
                                triangleWidthFactor: 0.75
                                mirrorTriangle: netCluster.visible
                                widthScale: 2.0
                                highlightHypotenuse: netCluster.visible
                                highlightMirror: true
                                highlightColor: Color.towardsBlack(Color.saturate(Color.towardsBlack(Color.saturate(rootScope.vpnAccentColor(), 0.2), 0.3), 0.2), 0.3)
                                highlightWidth: Math.max(2, Math.round(leftPanel.s * 3))
                                backgroundKey: "keyboard"
                            }
                            Row {
                                id: netCluster
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
                            PanelSeparator {
                                scaleFactor: leftPanel.s
                                panelHeightPx: leftPanel.barHeightPx
                                triangleEnabled: true
                                triangleWidthFactor: 0.75
                                mirrorTriangle: false
                                widthScale: 2.0
                                backgroundKey: "network"
                            }
                            LocalMods.WeatherButton {
                                id: weatherButton
                                visible: Settings.settings.showWeatherInBar === true
                                Layout.alignment: Qt.AlignVCenter
                            }
                        }
                    }

                    ShaderEffectSource {
                        id: leftPanelSource
                        anchors.fill: parent
                        sourceItem: leftPanelContent
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
                    WlrLayershell.namespace: "quickshell-bar-right"
                    // Debug/testing: put bars on Overlay when wedge debug or shader-test enabled
                    WlrLayershell.layer: (((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                          || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1"))
                        ? WlrLayer.Overlay : WlrLayer.Top
                    anchors.bottom: true
                    anchors.right: true
                    anchors.left: false
                    implicitWidth: rightPanel.screen ? Math.round(rightPanel.screen.width / 2) : 960
                    visible: monitorEnabled
                    onVisibleChanged: {}
                    implicitHeight: rightBarBackground.height
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    property real s: Theme.scale(rightPanel.screen)
                    property int barHeightPx: Math.round(Theme.panelHeight * s)
                    readonly property bool _mediaSlotVisible: !!(mediaModule && mediaModule.visible)
                    readonly property bool _mediaOverlayVisible: !!(mediaOverlayHost && mediaOverlayHost.visible)
                    readonly property bool _mpdFlagsVisible: !!(mpdFlagsBar && mpdFlagsBar.visible)
                    readonly property bool _trayVisible: !!(systemTrayWrapper && systemTrayWrapper.trayVisible)
                    readonly property bool _microphoneVisible: !!(widgetsMicrophone && widgetsMicrophone.visible)
                    readonly property bool _volumeVisible: !!(widgetsVolume && widgetsVolume.visible)
                    readonly property bool _hasPanelContent: (
                        _mediaSlotVisible
                        || _mediaOverlayVisible
                        || _mpdFlagsVisible
                        || _trayVisible
                        || _microphoneVisible
                        || _volumeVisible
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
                    property int interWidgetSpacing: Math.max(widgetSpacing, Math.round(widgetSpacing * 1.35))
                    property int seamWidth: Math.max(8, Math.round(widgetSpacing * 0.85))
                    // Panel background transparency is configurable via Settings:
                    // - panelBgAlphaScale: 0..1 multiplier applied to the base theme alpha
                    property color barBgColor: "transparent"
                    property real seamTaperTop: 0.25
                    property real seamTaperBottom: 0.9
                    property real seamOpacity: 0.55
                    readonly property real seamTiltSign: -1.0
                    readonly property real seamTaperTopClamped: Math.max(0.0, Math.min(1.0, seamTaperTop))
                    readonly property real seamTaperBottomClamped: Math.max(0.0, Math.min(1.0, seamTaperBottom))
                    readonly property real seamEdgeBaseTop: (seamTiltSign > 0)
                        ? (1.0 - seamTaperTopClamped)
                        : seamTaperTopClamped
                    readonly property real seamEdgeSlope: ((seamTiltSign > 0)
                        ? (1.0 - seamTaperBottomClamped)
                        : seamTaperBottomClamped) - seamEdgeBaseTop
                    property color seamFillColor: Color.withAlpha(
                        Color.mix(Theme.surfaceVariant, Theme.background, 0.45),
                        seamOpacity
                    )
                    readonly property real seamSlackWidth: Math.max(0, rightBarBackground.width - rightBarFill.width)
                    property bool panelTintEnabled: true
                    property color panelTintColor: Color.withAlpha("#ff2a36", 0.75)
                    property real panelTintStrength: 1.0
                    property real panelTintFeatherTop: 0.08
                    property real panelTintFeatherBottom: 0.35

                    readonly property real contentWidth: Math.max(
                        rightWidgetsRow.width,
                        rightWidgetsRow.implicitWidth || rightWidgetsRow.width || 0
                    ) + rightPanel.interWidgetSpacing

                        Item {
                            id: rightPanelContent
                            anchors.fill: parent

                    Rectangle {
                        id: rightBarBackdrop
                        width: Math.max(1, rightPanel.width)
                        height: rightPanel.barHeightPx
                        color: "#000000"
                        opacity: 0.65
                        anchors.top: parent.top
                        anchors.right: parent.right
                        z: -1
                        visible: rightPanel.baseFillVisible
                    }
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
                                    (function(){
                                        var ww = Number(Quickshell.env("QS_WEDGE_WIDTH_PCT") || "");
                                        if (isFinite(ww) && ww > 0) return Math.max(0.0, Math.min(1.0, ww/100.0));
                                        var faceW = Math.max(1, rightBarFill.width);
                                        var targetPx = Math.max(1, Math.round(rightPanel.seamWidth));
                                        var capPx = Math.round(faceW * 0.35);
                                        var wpx = Math.min(targetPx, capPx);
                                        return Math.max(0.02, Math.min(0.98, wpx / faceW));
                                    })(),
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
                                    ((Quickshell.env("QS_ENABLE_WEDGE_CLIP") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_DEBUG") || "") === "1")
                                    || ((Quickshell.env("QS_WEDGE_SHADER_TEST") || "") === "1")
                                    || (Settings.settings.enableWedgeClipShader === true)
                            )
                            sourceComponent: ShaderEffect {
                                fragmentShader: Qt.resolvedUrl("../shaders/wedge_clip.frag.qsb")
                                // Clip the base face (pure fill color) to subtract the wedge
                                property var sourceSampler: rightBarFillSource
                                // params0: x=wNorm, y=slopeUp, z=side(-1 left edge), w=unused
                                property vector4d params0: Qt.vector4d(
                                    (function(){
                                        var ww = Number(Quickshell.env("QS_WEDGE_WIDTH_PCT") || "");
                                        if (isFinite(ww) && ww > 0) return Math.max(0.0, Math.min(1.0, ww/100.0));
                                        var faceW = Math.max(1, rightBarFill.width);
                                        var targetPx = Math.max(1, Math.round(rightPanel.seamWidth));
                                        var capPx = Math.round(faceW * 0.35);
                                        var wpx = Math.min(targetPx, capPx);
                                        return Math.max(0.02, Math.min(0.98, wpx / faceW));
                                    })(),
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

                        // (old right Canvas triangle overlay removed)
                        Item {
                            id: rightSeamFill
                            width: Math.min(rightBarBackground.width, rightPanel.seamWidth)
                            height: rightBarBackground.height
                            anchors.bottom: rightBarBackground.bottom
                            anchors.left: rightBarBackground.left
                            z: 1000
                            // Draw local seam wedge only when the shader path is active,
                            // and hide it while QS_WEDGE_DEBUG is enabled so the shader's
                            // magenta overlay remains visible for validation.
                            visible: rightPanel.renderActive
                                && rightFaceClipLoader.active === true
                                && ((Quickshell.env("QS_WEDGE_DEBUG") || "") !== "1")
                            ShaderEffect {
                                id: rightSeamFX
                                anchors.fill: parent
                                fragmentShader: Qt.resolvedUrl("../shaders/seam.frag.qsb")
                                property color baseColor: rightPanel.seamFillColor
                                // params0: edgeBase, edgeSlope, tilt, opacity
                                property vector4d params0: Qt.vector4d(rightPanel.seamEdgeBaseTop, rightPanel.seamEdgeSlope, rightPanel.seamTiltSign, rightPanel.seamOpacity)
                                blending: true
                            }
                        }

                        // Mask the right seam fill similarly to form a triangular visible area.
                        ShaderEffectSource {
                            id: rightSeamSource
                            anchors.fill: rightSeamFill
                            sourceItem: rightSeamFX
                            hideSource: true
                            live: true
                            recursive: true
                        }
                        Canvas {
                            id: rightSeamMask
                            anchors.fill: rightSeamFill
                            visible: false
                            onPaint: {
                                var ctx = getContext('2d');
                                ctx.reset();
                                ctx.clearRect(0, 0, width, height);
                                ctx.fillStyle = '#ffffffff';
                                ctx.fillRect(0, 0, width, height);
                                // Cut triangle adjacent to the seam boundary (x = width in this local space)
                                ctx.fillStyle = '#000000ff';
                                ctx.beginPath();
                                // Default orientation: bottom-left → top-right (seam edge on the right)
                                ctx.moveTo(width, height);
                                ctx.lineTo(0, 0);
                                ctx.lineTo(0, height);
                                ctx.closePath();
                                ctx.fill();
                            }
                        }
                        GE.OpacityMask {
                            anchors.fill: rightSeamFill
                            source: rightSeamSource
                            maskSource: rightSeamMask
                        }

                        RowLayout {
                            id: rightWidgetsRow
                            anchors.verticalCenter: rightBarBackground.verticalCenter
                            anchors.right: rightBarBackground.right
                            anchors.rightMargin: rightPanel.sideMargin
                            spacing: 0
                            PanelSeparator {
                                id: mediaLeadingSeparator
                                scaleFactor: rightPanel.s
                                panelHeightPx: rightPanel.barHeightPx
                                panelActive: rightPanel.renderActive
                                triangleEnabled: true
                                triangleWidthFactor: 0.95
                                mirrorTriangle: false
                                widthScale: 1.0
                                flipAcrossVerticalAxis: true
                                highlightHypotenuse: true
                                highlightColor: Color.towardsBlack(Color.saturate(Color.towardsBlack(Color.saturate(rootScope.vpnAccentColor(), 0.2), 0.3), 0.2), 0.3)
                                highlightWidth: Math.max(2, Math.round(rightPanel.s * 3))
                            }
                            PillSeparator {
                                scaleFactor: rightPanel.s
                                panelHeightPx: rightPanel.barHeightPx
                                panelActive: rightPanel.renderActive
                                triangleEnabled: false
                                widthScale: 0.5
                            }
                            Item {
                                id: mediaRowSlot
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.preferredWidth: implicitWidth
                                implicitWidth: mediaModule.parent === mediaRowSlot ? Math.max(mediaModule.implicitWidth, 1) : 0
                                implicitHeight: mediaModule.parent === mediaRowSlot ? Math.max(mediaModule.implicitHeight, 1) : 0
                                visible: mediaModule.parent === mediaRowSlot

                                Media {
                                    id: mediaModule
                                    anchors.fill: parent
                                    sidePanelPopup: sidebarPopup
                                }
                            }
                            LocalMods.MpdFlags {
                                id: mpdFlagsBar
                                Layout.alignment: Qt.AlignVCenter
                                property bool _mediaVisible: (
                                    Settings.settings.showMediaInBar
                                    && MusicManager.currentPlayer
                                    && !MusicManager.isStopped
                                    && (MusicManager.isPlaying || MusicManager.isPaused || (MusicManager.trackTitle && MusicManager.trackTitle.length > 0))
                                )
                                enabled: _mediaVisible && MusicManager.isCurrentMpdPlayer()
                                iconPx: Math.round(Theme.fontSizeSmall * Theme.scale(rightPanel.screen))
                                iconColor: Theme.textPrimary
                            }
                            Item {
                                id: systemTrayWrapper
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillHeight: true
                                Layout.preferredHeight: rightPanel.barHeightPx
                                readonly property bool trayCapsuleHidden: Settings.settings.hideSystemTrayCapsule === true
                                readonly property bool trayVisible: (!trayCapsuleHidden || systemTrayModule.expanded)
                                readonly property bool tightSpacing: Settings.settings.systemTrayTightSpacing !== false
                                readonly property int horizontalPadding: tightSpacing ? 0 : Math.max(4, Math.round(Theme.panelTrayInlinePadding * rightPanel.s * 0.75))
                                readonly property color capsuleColor: WidgetBg.color(Settings.settings, "systemTray", Theme.background)
                                readonly property real trayContentHeight: (
                                    systemTrayModule.capsuleHeight !== undefined
                                        ? systemTrayModule.capsuleHeight
                                        : (systemTrayModule.implicitHeight || systemTrayModule.height || 0)
                                )
                                readonly property int capsuleWidth: Math.max(1, systemTrayModule.implicitWidth) + systemTrayWrapper.horizontalPadding * 2
                                readonly property int capsuleHeight: rightPanel.barHeightPx
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
                                Layout.alignment: Qt.AlignVCenter
                            }
                            Volume {
                                id: widgetsVolume
                                Layout.alignment: Qt.AlignVCenter
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
                            if (MusicManager.isStopped) return;
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

                PanelLayer {
                    id: seamPanel
                    screen: modelData
                    color: "transparent"
                    anchors.bottom: true
                    anchors.left: true
                    anchors.right: true
                    // Ensure the seam window has a real height; without this the window
                    // collapses to 0px and shaders never render (stays invisible).
                    implicitHeight: seamPanel.seamHeightPx
                    // Readiness filter: when enabled, only show seam once geometry stabilizes.
                    // Prevents early full-width flash while rows are still measuring.
                    property bool useReadinessFilter: true
                    property bool rightPanelActive: rightPanel.renderActive
                    visible: monitorEnabled && seamPanel.rightPanelActive && (
                        !seamPanel.useReadinessFilter
                        ? (seamPanel.rawGapWidth > 0)
                        : (seamPanel.geometryReady)
                    )
                    // flag unavailable; keep default
                    onVisibleChanged: {}
                    exclusionMode: ExclusionMode.Ignore
                    exclusiveZone: 0
                    WlrLayershell.namespace: "quickshell-bar-seam"
                    // Place seam below panel elements so debug fill shows through the center gap only
                    WlrLayershell.layer: WlrLayer.Bottom
                    property real s: Theme.scale(seamPanel.screen)
                    property int seamHeightPx: Math.round(Theme.panelHeight * s)
                    property real seamTaperTop: 0.12
                    property real seamTaperBottom: 0.65
                    property real seamEffectOpacity: 0.85
                    property color seamFillColor: Color.mix(Theme.surfaceVariant, Theme.background, 0.35)
                    property bool seamTintEnabled: true
                    // Use theme accent for seam tint to avoid hardcoded red
                    property color seamTintColor: Theme.accentPrimary
                    property real seamTintOpacity: 0.9
                    property color seamBaseColor: Theme.background
                    property real seamBaseOpacityTop: 0.5
                    property real seamBaseOpacityBottom: 0.65
                    function seamClamp01(v) { return Math.max(0.0, Math.min(1.0, v)); }
                    function seamEdgeBaseForTilt(tiltSign, frac) {
                        var f = seamClamp01(frac);
                        return (tiltSign > 0) ? (1.0 - f) : f;
                    }
                    function seamEdgeParamsFor(tiltSign) {
                        var topEdge = seamEdgeBaseForTilt(tiltSign, seamTaperTop);
                        var bottomEdge = seamEdgeBaseForTilt(tiltSign, seamTaperBottom);
                        return ({ base: topEdge, slope: (bottomEdge - topEdge) });
                    }
                    readonly property var seamEdgeLeft: seamEdgeParamsFor(-1)
                    readonly property var seamEdgeRight: seamEdgeParamsFor(1)
                    property real seamTintTopInsetPx: Math.round(Theme.panelWidgetSpacing * 0.55 * s)
                    property real seamTintBottomInsetPx: Math.round(Theme.panelWidgetSpacing * 0.2 * s)
                    property real seamTintFeatherPx: Math.max(1, Math.round(Theme.uiRadiusSmall * 0.35 * s))
                    readonly property real monitorWidth: seamPanel.screen ? seamPanel.screen.width : seamPanel.width
                    // Consider geometry "ready" only when left/right fills are measured and gap is sane
                    readonly property bool leftReady: _leftFillWidth > Math.max(8, leftPanel.sideMargin + leftPanel.widgetSpacing)
                    readonly property bool rightReady: _rightFillWidth > Math.max(8, rightPanel.sideMargin + rightPanel.widgetSpacing)
                    readonly property bool gapSane: rawGapWidth < (monitorWidth * 0.98)
                    readonly property bool geometryReady: leftReady && rightReady && gapSane

                    readonly property real _leftFillWidth: leftBarFill ? leftBarFill.width : seamPanel.monitorWidth / 2
                    readonly property real _rightFillWidth: rightBarFill ? rightBarFill.width : seamPanel.monitorWidth / 2
                    readonly property real _leftVisibleEdge: Math.max(
                        0,
                        Math.min(seamPanel.monitorWidth, _leftFillWidth - Math.max(0, leftPanel.seamWidth || 0))
                    )
                    readonly property real _rightFillVisibleWidth: Math.max(0, _rightFillWidth - Math.max(0, rightPanel.seamWidth || 0))
                    readonly property real _rightVisibleEdge: Math.max(
                        _leftVisibleEdge,
                        seamPanel.monitorWidth - Math.min(seamPanel.monitorWidth, _rightFillVisibleWidth)
                    )
                    readonly property real gapStart: _leftVisibleEdge
                    readonly property real gapEnd: _rightVisibleEdge
                    readonly property real rawGapWidth: Math.max(0, gapEnd - gapStart)
                    readonly property real seamWidthPx: Math.min(
                        seamPanel.monitorWidth,
                        Math.max(Math.round(Theme.panelWidgetSpacing * seamPanel.s * 2.4), rawGapWidth)
                    )
                    readonly property real seamLeftMargin: Math.max(
                        0,
                        Math.min(
                            seamPanel.monitorWidth - seamPanel.seamWidthPx,
                            gapStart - Math.max(0, (seamPanel.seamWidthPx - rawGapWidth) / 2)
                        )
                    )
                    readonly property real seamTintLeftTop: seamPanel._normalizedInset(seamPanel.seamTintTopInsetPx)
                    readonly property real seamTintLeftBottom: seamPanel._normalizedInset(seamPanel.seamTintBottomInsetPx)
                    readonly property real seamTintRightTop: 1 - seamPanel.seamTintLeftTop
                    readonly property real seamTintRightBottom: 1 - seamPanel.seamTintLeftBottom
                    readonly property real seamTintFeatherLeft: seamPanel._normalizedFeather(seamPanel.seamTintFeatherPx)
                    readonly property real seamTintFeatherRight: seamPanel.seamTintFeatherLeft

                    function _normalizedInset(px) {
                        const width = Math.max(1, seamPanel.seamWidthPx);
                        return Math.min(0.49, Math.max(0, px / width));
                    }

                    function _normalizedFeather(px) {
                        const width = Math.max(1, seamPanel.seamWidthPx);
                        return Math.min(0.25, Math.max(0.005, px / width));
                    }

                    Item {
                        // Render shader content only after geometry stabilizes
                        visible: seamPanel.geometryReady
                        width: seamPanel.seamWidthPx + 2
                        height: seamPanel.seamHeightPx
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.leftMargin: Math.max(0, seamPanel.seamLeftMargin - 1)

                        // Hidden visuals (used as source for mask)
                        Item {
                            id: seamVisuals
                            anchors.fill: parent
                            visible: false
                            ShaderEffect {
                                z: 0
                                anchors.fill: parent
                                fragmentShader: Qt.resolvedUrl("../shaders/seam_fill.frag.qsb")
                                property color baseColor: seamPanel.seamBaseColor
                                property vector4d params0: Qt.vector4d(
                                    seamPanel.seamBaseOpacityTop,
                                    seamPanel.seamBaseOpacityBottom - seamPanel.seamBaseOpacityTop,
                                    0,
                                    0
                                )
                            }
                            ShaderEffect {
                                z: 50
                                visible: seamPanel.seamTintEnabled
                                anchors.fill: parent
                                fragmentShader: Qt.resolvedUrl("../shaders/seam_tint.frag.qsb")
                                property color tintColor: seamPanel.seamTintColor
                                property vector4d params0: Qt.vector4d(
                                    seamPanel.seamTintLeftTop,
                                    seamPanel.seamTintLeftBottom,
                                    seamPanel.seamTintRightTop,
                                    seamPanel.seamTintRightBottom
                                )
                                property vector4d params1: Qt.vector4d(
                                    seamPanel.seamTintFeatherLeft,
                                    seamPanel.seamTintFeatherRight,
                                    seamPanel.seamTintOpacity,
                                    0
                                )
                                property color baseColor: seamPanel.seamBaseColor
                                blending: true
                            }
                            Row {
                                z: 10
                                anchors.fill: parent
                            ShaderEffect {
                                width: parent.width / 2
                                height: parent.height
                                fragmentShader: Qt.resolvedUrl("../shaders/seam.frag.qsb")
                                property color baseColor: seamPanel.seamFillColor
                                property vector4d params0: Qt.vector4d(seamPanel.seamEdgeLeft.base, seamPanel.seamEdgeLeft.slope, -1, seamPanel.seamEffectOpacity)
                                blending: true
                            }
                            ShaderEffect {
                                width: parent.width / 2
                                height: parent.height
                                fragmentShader: Qt.resolvedUrl("../shaders/seam.frag.qsb")
                                property color baseColor: seamPanel.seamFillColor
                                property vector4d params0: Qt.vector4d(seamPanel.seamEdgeRight.base, seamPanel.seamEdgeRight.slope, 1, seamPanel.seamEffectOpacity)
                                blending: true
                            }
                            }
                        }

                        // (removed) Previously we punched holes in the seam visuals.
                        // The new approach is to mask panel fills instead, so the seam
                        // remains intact and shows through the wedges.
                    }

                    // (debug logging removed)
                }

            }
        }
    }
}
