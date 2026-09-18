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
import "../Helpers/BarLayout.js" as BarLayout
import "../Helpers/Color.js" as Color
import "../Helpers/WidgetBg.js" as WidgetBg
import "../Helpers/WorkspaceName.js" as WorkspaceName
import "../Helpers/AccentSampler.js" as AccentSampler

Scope {
    id: rootScope
    property var shell
    property alias visible: barRootItem.visible
    // Now-playing popup window, hoisted to a top-level Loader in shell.qml so its
    // PanelWindow maps as a real surface (nested PanelWindow does not map).
    // Anchored to the right panel once it exists.
    property var sidebarPopup: (shell && shell.musicPopup) ? shell.musicPopup : null
    // Panel widget visibility, resolved from Settings.panelLayout.
    // NOTE: the settings adapter applies Settings.json only after the bar has been
    // built and blocks change notifications while doing so (JsonAdapter::
    // changesBlocked), so this binding reflects the layout as it is when the object
    // is created. Settings.json edits need a panel restart to take effect.
    readonly property var panelWidgets: WidgetRegistry.visibleSetFor(
        Settings.settings ? Settings.settings.panelLayout : undefined)

    property real barHeight: 0 // Expose current bar height for other components (e.g. window mirroring)
    function vpnAccentColor() {
        const boost = Theme.vpnAccentSaturateBoost || 0;
        const desat = Theme.vpnDesaturateAmount || 0;
        const base = Color.saturate(Theme.accentPrimary, boost);
        return Color.desaturate(base, desat);
    }
    readonly property real _defaultPanelAlphaScale: 0.2
    // The arithmetic itself lives in Helpers/BarLayout.js (pure functions, tested
    // on their own); these stay as the scope-level names the panel tree calls.
    function panelBgAlphaScale() {
        return BarLayout.panelBgAlphaScale(Settings.settings, _defaultPanelAlphaScale);
    }
    function wedgeWidthNorm(faceWidth, seamWidth) {
        return BarLayout.wedgeWidthNorm(faceWidth, seamWidth, Quickshell.env);
    }

    // Env toggles to hard-disable expensive paths during perf triage
    readonly property bool wedgeClipAllowed: BarLayout.wedgeClipAllowed(Quickshell.env)
    readonly property bool trianglesAllowed: BarLayout.trianglesAllowed(Quickshell.env)

    // Terminal workspace detection — makes seam gap fully transparent on
    // non-terminal workspaces. The name parsing is shared with the workspace
    // indicator (Helpers/WorkspaceName.js) so the bar and its own indicator
    // cannot disagree about what a workspace is called.
    property bool isTerminalWs: false

    function _recalcTerminalWs() {
        isTerminalWs = WorkspaceName.isTerminal(HyprlandWatcher.activeWorkspaceName || "");
        if (Settings.settings && Settings.settings.debugLogs)
            console.debug('[Bar] workspace:', JSON.stringify(HyprlandWatcher.activeWorkspaceName || ""), 'isTerminalWs:', isTerminalWs);
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

                // --- Whole-bar entrance slide animation ---
                property real barSlideProgress: 1.0
                property bool barSlideAnimating: false

                NumberFadeBehavior {
                    id: barSlideAnim
                    target: monitorItem
                    property: "barSlideProgress"
                    duration: Theme.panelSlideMs || 350
                    easing.type: Theme.uiEasingStdOut || Easing.OutCubic
                    onStopped: {
                        monitorItem.barSlideAnimating = false;
                    }
                }
                Timer {
                    id: barSlideTimer
                    interval: Theme.panelSlideTimerTickMs
                    repeat: false
                    onTriggered: monitorItem._slideTo(0, 1)
                }

                // The bar is always visible (no games-workspace auto-hide);
                // it only slides in once at startup.
                function _slideTo(from, to) {
                    monitorItem.barSlideAnimating = true;
                    barSlideAnim.from = from;
                    barSlideAnim.to = to;
                    barSlideAnim.duration = Theme.panelSlideMs;
                    barSlideAnim.easing.type = Theme.uiEasingStdOut || Easing.OutCubic;
                    barSlideAnim.start();
                }

                Component.onCompleted: {
                    if (monitorEnabled && Theme.animationsEnabled) {
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
                    property real nonTerminalOpacity: 1.0
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
                    property bool panelTintEnabled: Settings.settings.panelTintEnabled
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
                            // leftBarFill is a plain static fill: re-render the clip
                            // texture only when the fill changes, not on every frame.
                            live: false
                            recursive: true
                            Component.onCompleted: scheduleUpdate()
                            Connections {
                                target: leftBarFill
                                function onWidthChanged() { leftBarFillSource.scheduleUpdate() }
                                function onHeightChanged() { leftBarFillSource.scheduleUpdate() }
                                function onColorChanged() { leftBarFillSource.scheduleUpdate() }
                                function onVisibleChanged() { leftBarFillSource.scheduleUpdate() }
                            }
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
                            visible: leftPanel.panelTintEnabled
                            // Hide the tint effect when the clipped tint path is active.
                            hideSource: leftTintClipLoader.active === true
                            live: leftPanel.panelTintEnabled && leftFaceClipLoader.active === true
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
                                    // Theme.uiRadiusSmall never existed: Math.round(undefined) is
                                    // NaN and the outer clamp turned that into 0, so the shader's
                                    // corner-radius parameter was silently disabled. The intended
                                    // radius is the small corner radius the theme does define.
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.cornerRadiusSmall * 0.5 * leftPanel.s)) / Math.max(1, leftBarFill.width)))) ,
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
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.cornerRadiusSmall * 0.5 * leftPanel.s)) / Math.max(1, leftBarFill.width)))) ,
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
                            // Clock + pill sit close together (tight internal gap).
                            // The pill capsule rides out/in smoothly via SlideReveal -
                            // no reserved slot, neighbours close up. When taken,
                            // hovering the left module row peeks it back.
                            RowLayout {
                                id: clockPillGroup
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Math.max(1, Math.round(2 * leftPanel.s))

                                ClockWidget {
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: rootScope.panelWidgets["clock"]
                                    screen: modelData
                                }

                                // Pill capsule rides out smoothly via SlideReveal
                                // instead of toggling visibility.
                                SlideReveal {
                                    id: pillReveal
                                    Layout.alignment: Qt.AlignVCenter
                                    revealed: rootScope.panelWidgets["pill"]
                                        && (PillTracker.reminderActive
                                            || (PillTracker.taken && pillRevealHover.hovered))

                                    LocalMods.PillCapsule {
                                        id: pillCapsule
                                        screen: modelData
                                    }
                                }
                            }
                            WsIndicator {
                                id: wsindicator
                                visible: rootScope.panelWidgets["workspaces"]
                                Layout.alignment: Qt.AlignVCenter
                                workspaceGlyphDetached: true
                                showSubmapIcon: false
                                showLabel: true
                            }
                            RowLayout {
                                id: kbCluster
                                visible: rootScope.panelWidgets["keyboard"]
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
                                visible: rootScope.panelWidgets["network"]
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Math.round(Theme.panelNetClusterSpacing * leftPanel.s)
                                LocalMods.NetFlowCapsule {
                                        id: netCapsule
                                        Layout.alignment: Qt.AlignVCenter
                                        screen: leftPanel.screen
                                        vpnIconRounded: true
                                        throughputText: ConnectivityState.throughputText
                                }
                            }
                            LocalMods.SystemMonitorCapsule {
                                id: systemMonitorCapsule
                                visible: rootScope.panelWidgets["sysmon"]
                                Layout.alignment: Qt.AlignVCenter
                                screen: modelData
                            }
                            LocalMods.WeatherButton {
                                id: weatherButton
                                visible: rootScope.panelWidgets["weather"] && Settings.settings.showWeatherInBar === true
                                Layout.alignment: Qt.AlignVCenter
                                screen: modelData
                                capsule.rightTriangleVisible: true
                                capsule.rightTriangleWidthFactor: 0.75
                                capsule.triangleHighlightEnabled: true
                                capsule.triangleHighlightColor: Color.towardsBlack(Color.saturate(Color.towardsBlack(Color.saturate(rootScope.vpnAccentColor(), 0.2), 0.3), 0.2), 0.3)
                                capsule.triangleHighlightWidth: Math.max(2, Math.round(leftPanel.s * 3))
                            }

                            // Passive hover zone covering the left module row: with the
                            // pill taken, hovering anywhere on the left side of the bar
                            // peeks the pill capsule back. HoverHandler does not steal
                            // hover from module tooltips/buttons.
                            HoverHandler {
                                id: pillRevealHover
                            }
                        }
                    }

                    ShaderEffectSource {
                        id: leftPanelSource
                        anchors.fill: parent
                        sourceItem: leftPanelContent
                        transform: Translate { y: leftPanel.barHeightPx * (1 - monitorItem.barSlideProgress) }
                        hideSource: false
                        // Texture provider for the panel tint only. Without this the
                        // panel content is drawn a second time as a frozen snapshot
                        // (doubled glyphs, stale values) - the visible "second panel".
                        visible: leftPanel.panelTintEnabled
                        live: leftPanel.panelTintEnabled
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
                    property bool panelTintEnabled: Settings.settings.panelTintEnabled
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
                            // rightBarFill is a plain static fill: re-render the clip
                            // texture only when the fill changes, not on every frame.
                            live: false
                            recursive: true
                            Component.onCompleted: scheduleUpdate()
                            Connections {
                                target: rightBarFill
                                function onWidthChanged() { rightBarFillSource.scheduleUpdate() }
                                function onHeightChanged() { rightBarFillSource.scheduleUpdate() }
                                function onColorChanged() { rightBarFillSource.scheduleUpdate() }
                                function onVisibleChanged() { rightBarFillSource.scheduleUpdate() }
                            }
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
                            visible: rightPanel.panelTintEnabled
                            // Hide the tint effect when the clipped tint path is active.
                            hideSource: rightTintClipLoader.active === true
                            live: rightPanel.panelTintEnabled && rightFaceClipLoader.active === true
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
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.cornerRadiusSmall * 0.5 * rightPanel.s)) / Math.max(1, rightBarFill.width)))) ,
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
                                    Math.max(0.0, Math.min(0.05, (Math.max(1, Math.round(Theme.cornerRadiusSmall * 0.5 * rightPanel.s)) / Math.max(1, rightBarFill.width)))) ,
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
                                visible: rootScope.panelWidgets["media"] && mediaModule.parent === mediaRowSlot && Settings.settings.showMediaInBar && MusicManager.hasPlayer && (MusicManager.isPlaying || MusicManager.isPaused)

                                Media {
                                    id: mediaModule
                                    anchors.fill: parent
                                    sidePanelPopup: rootScope.sidebarPopup
                                    panelHovering: rightPanel.panelHovering
                                }
                            }
                            LocalMods.MpdFlags {
                                id: mpdFlagsBar
                                visible: rootScope.panelWidgets["mpdFlags"] && _mediaVisible && activeFlags.length > 0
                                Layout.alignment: Qt.AlignVCenter
                                property bool _mediaVisible: Settings.settings.showMediaInBar && MusicManager.hasPlayer
                                enabled: _mediaVisible && MusicManager.isCurrentMpdPlayer()
                                iconPx: Math.round(Theme.fontSizeSmall * Theme.scale(rightPanel.screen))
                                iconColor: Theme.textPrimary
                            }
                            Item {
                                id: systemTrayWrapper
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillHeight: true
                                Layout.preferredHeight: pillCapsule.capsule.uniformCapsuleHeight
                                readonly property bool trayCapsuleHidden: Settings.settings.hideSystemTrayCapsule === true
                                readonly property bool trayVisible: rootScope.panelWidgets["systray"] && (!trayCapsuleHidden || systemTrayModule.expanded)
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
                                visible: rootScope.panelWidgets["microphone"]
                                Layout.alignment: Qt.AlignVCenter
                                panelHovering: rightPanel.panelHovering
                            }
                            Volume {
                                id: widgetsVolume
                                visible: rootScope.panelWidgets["volume"]
                                Layout.alignment: Qt.AlignVCenter
                                panelHovering: rightPanel.panelHovering
                            }
                            GenelecWidget {
                                id: widgetsGenelec
                                visible: true
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
                                    var rgb = AccentSampler.sampleAccent(img, { finalFallback: true });
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

                        // Popup window is hoisted to shell.qml (top-level Loader);
                        // see rootScope.sidebarPopup. Anchor it to this panel.
                        readonly property var _sidebarPopup: rootScope.sidebarPopup
                        function __anchorPopup() {
                            if (rootScope.sidebarPopup && rootScope.sidebarPopup.anchorWindow !== rightPanel) {
                                rootScope.sidebarPopup.anchorWindow = rightPanel;
                                rootScope.sidebarPopup.panelEdge = "bottom";
                            }
                        }
                        Component.onCompleted: { __anchorPopup(); }
                        on_SidebarPopupChanged: Qt.callLater(__anchorPopup)

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
                        // See leftPanelSource: never draw the copy itself.
                        visible: rightPanel.panelTintEnabled
                        live: rightPanel.panelTintEnabled
                        recursive: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: false
                        acceptedButtons: Qt.NoButton
                    }

                    property string _lastAlbum: ""
                    property string _lastTrackKey: ""
                    function maybeShowOnAlbumChange() {
                        try {
                            const dbg = Settings.settings && Settings.settings.debugLogs;
                            if (!MusicManager.hasPlayer) { if (dbg) console.debug("[qs-music] track-change: no player"); return; }
                            // Some tracks lack an album tag; derive a robust change
                            // key from album+title+artist so the popup still fires.
                            const album = String(MusicManager.trackAlbum || "");
                            const title = String(MusicManager.trackTitle || "");
                            const artist = String(MusicManager.trackArtist || "");
                            const key = (album + "|" + title + "|" + artist);
                            if (dbg) console.debug("[qs-music] track-change key='" + key + "' last='" + rightPanel._lastTrackKey + "' popup=" + (rootScope.sidebarPopup ? "yes" : "null"));
                            if (key === rightPanel._lastTrackKey) return;
                            if (!title && !artist) { if (dbg) console.debug("[qs-music] track-change: no metadata yet"); return; }
                            rightPanel._lastTrackKey = key;
                            // Show the toast only when the album (i.e. the cover
                            // art) actually changes — not on every track change
                            // within the same album.
                            const albumChanged = (album !== rightPanel._lastAlbum);
                            rightPanel._lastAlbum = album;
                            if (albumChanged && (MusicManager.trackTitle || MusicManager.trackArtist)) {
                                if (dbg) console.debug("[qs-music] track-change -> showAt (new album)");
                                if (rootScope.sidebarPopup) rootScope.sidebarPopup.showAt();
                            }
                        } catch (e) { /* ignore */ }
                    }
                    
                    Connections {
                        target: MusicManager
                        function onTrackAlbumChanged()  { rightPanel.maybeShowOnAlbumChange(); }
                        function onTrackTitleChanged()  { rightPanel.maybeShowOnAlbumChange(); }
                        function onTrackArtistChanged() { rightPanel.maybeShowOnAlbumChange(); }
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
                        // Hover-out grace: keep the bar widgets / tray visible for a
                        // short moment after the cursor leaves instead of snapping shut.
                        Timer {
                            id: hoverOutDelay
                            interval: 350
                            repeat: false
                            onTriggered: {
                                systemTrayModule.panelHover = false
                                rightPanel.panelHovering = false
                                const menuOpen = systemTrayModule.trayMenu && systemTrayModule.trayMenu.visible
                                if (!systemTrayModule.hotHover && !systemTrayModule.holdOpen && !systemTrayModule.shortHoldActive && !menuOpen) {
                                    systemTrayModule.expanded = false
                                }
                            }
                        }
                        onEntered: {
                            hoverOutDelay.stop();
                            systemTrayModule.panelHover = true; rightPanel.panelHovering = true
                        }
                        onExited: {
                            hoverOutDelay.restart();
                        }
                        visible: rightPanel.renderActive
                        Rectangle { visible: false }
                    }

                }

            }
        }
    }
}
