import QtQuick
import qs.Settings
import qs.Components
import "../Helpers/CapsuleMetrics.js" as Capsule
import "../Helpers/WidgetBg.js" as WidgetBg
import "../Helpers/Color.js" as ColorHelpers

Rectangle {
    id: root

    property var screen: null
    property string backgroundKey: ""
    property color fallbackColor: Theme.surface
    property color backgroundColorOverride: "transparent"
    property bool hoverEnabled: true
    property bool borderVisible: true
    property color borderColorOverride: "transparent"
    property real paddingScale: 1.0
    property real minPadding: 4
    property real verticalPaddingScale: 0.6
    property real verticalPaddingMin: 2
    property bool forceHeightFromMetrics: true
    property bool centerContent: true
    property real cornerRadius: Theme.cornerRadiusSmall
    property real cornerRadiusOverride: -1
    property real borderWidthOverride: -1
    property real contentYOffset: 0
    property int cursorShape: Qt.ArrowCursor

    // Triangle overlays (extend beyond capsule bounds into layout spacing)
    property bool rightTriangleVisible: false
    property bool leftTriangleVisible: false
    property real rightTriangleWidthFactor: 0.75
    property real leftTriangleWidthFactor: 0.75
    property color triangleColor: "transparent"
    property bool triangleHighlightEnabled: false
    property color triangleHighlightColor: Theme.accentPrimary
    property real triangleHighlightWidth: 2

    readonly property int _triangleWidth: Math.max(1, Math.round(capsuleScale * Theme.panelSeparatorWidthFactor * Math.max(1, Theme.uiBorderWidth) * 16))
    readonly property color _triangleFillColor: triangleColor.a > 0 ? triangleColor : _baseColor

    readonly property real _scale: Theme.scale(screen || Screen)
    readonly property var _metrics: Capsule.metrics(Theme, _scale)
    readonly property var capsuleMetrics: _metrics
    readonly property real capsuleScale: _scale
    readonly property int capsulePadding: _metrics.padding
    readonly property int capsuleInner: _metrics.inner
    readonly property int capsuleHeight: _metrics.height
    readonly property int uniformCapsuleHeight: Math.max(
        _metrics.height,
        Math.round(Theme.panelHeight * 0.55 * _scale)
    )
    readonly property color _baseColor: backgroundColorOverride.a > 0
            ? backgroundColorOverride
            : WidgetBg.color(Settings.settings, backgroundKey, fallbackColor)
    readonly property int horizontalPadding: Math.max(minPadding, Math.round(_metrics.padding * paddingScale))
    readonly property int verticalPadding: Math.max(verticalPaddingMin, Math.round(_metrics.padding * verticalPaddingScale))
    readonly property real _borderWidth: borderWidthOverride >= 0
            ? borderWidthOverride
            : Theme.panelCapsuleBorderWidth
    readonly property color _borderColorTheme: Theme.panelCapsuleBorderColor
    readonly property color _borderColor: borderColorOverride.a > 0
            ? borderColorOverride
            : (_borderColorTheme.a > 0
                ? _borderColorTheme
                : ColorHelpers.withAlpha(Theme.textPrimary, Theme.panelCapsuleBorderOpacity))

    implicitWidth: 0
    implicitHeight: forceHeightFromMetrics ? uniformCapsuleHeight : 0
    width: implicitWidth
    height: implicitHeight

    radius: 0
    topLeftRadius: leftTriangleVisible ? 0 : (cornerRadiusOverride >= 0 ? cornerRadiusOverride : cornerRadius)
    topRightRadius: rightTriangleVisible ? 0 : (cornerRadiusOverride >= 0 ? cornerRadiusOverride : cornerRadius)
    bottomLeftRadius: leftTriangleVisible ? 0 : (cornerRadiusOverride >= 0 ? cornerRadiusOverride : cornerRadius)
    bottomRightRadius: rightTriangleVisible ? 0 : (cornerRadiusOverride >= 0 ? cornerRadiusOverride : cornerRadius)
    antialiasing: true
    border.width: 0
    border.color: "transparent"
    color: _baseColor
    Behavior on color {
        enabled: Theme._themeLoaded && Theme.animationsEnabled
        ColorFastInOutBehavior {}
    }

    HoverHandler {
        id: hoverTracker
        enabled: root.hoverEnabled
        acceptedDevices: PointerDevice.Mouse | PointerDevice.Stylus | PointerDevice.TouchPad
        cursorShape: root.cursorShape
    }
    readonly property bool hovered: hoverTracker.hovered

    Item {
        id: contentArea
        anchors {
            fill: parent
            leftMargin: horizontalPadding
            rightMargin: horizontalPadding
            topMargin: verticalPadding
            bottomMargin: verticalPadding
        }

        Item {
            id: centerHost
            anchors {
                left: parent.left
                right: parent.right
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: contentYOffset
            }
            height: parent.height
        }
    }

    OverlayFrame {
        anchorTarget: root
        inset: Theme.panelCapsuleBorderInset
        baseTopLeftRadius: root.topLeftRadius
        baseTopRightRadius: root.topRightRadius
        baseBottomLeftRadius: root.bottomLeftRadius
        baseBottomRightRadius: root.bottomRightRadius
        strokeWidth: borderVisible ? _borderWidth : 0
        strokeColor: borderVisible ? _borderColor : "transparent"
        enabled: borderVisible
        zIndex: root.z + 1
    }

    // Right-side triangle overlay (extends past capsule right edge into spacing)
    TriangleOverlay {
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width
        width: parent._triangleWidth
        height: parent.height
        color: parent._triangleFillColor
        flipX: false
        flipY: true
        xCoverage: parent.rightTriangleWidthFactor
        visible: parent.rightTriangleVisible
        z: parent.z + 0.5
        highlightEnabled: parent.triangleHighlightEnabled
        highlightColor: parent.triangleHighlightColor
        highlightWidth: parent.triangleHighlightWidth
    }

    // Left-side triangle overlay (extends past capsule left edge into spacing)
    TriangleOverlay {
        anchors.verticalCenter: parent.verticalCenter
        x: -parent._triangleWidth
        width: parent._triangleWidth
        height: parent.height
        color: parent._triangleFillColor
        flipX: true
        flipY: false
        xCoverage: parent.leftTriangleWidthFactor
        visible: parent.leftTriangleVisible
        z: parent.z + 0.5
        highlightEnabled: parent.triangleHighlightEnabled
        highlightColor: parent.triangleHighlightColor
        highlightWidth: parent.triangleHighlightWidth
    }

    default property alias content: centerHost.data

    function paddingScaleFor(paddingPx) {
        if (!_metrics || !_metrics.padding) return 1;
        return paddingPx / _metrics.padding;
    }
}
