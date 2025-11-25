import QtQuick
import qs.Settings
import "../Helpers/CapsuleMetrics.js" as Capsule
import "../Helpers/WidgetBg.js" as WidgetBg
import "../Helpers/Color.js" as ColorHelpers

Rectangle {
    id: root

    property var screen: null
    property string backgroundKey: ""
    property color fallbackColor: "#000000"
    property color backgroundColorOverride: "transparent"
    property bool hoverEnabled: true
    property color hoverColorOverride: "transparent"
    property real hoverMixAmount: 0
    property color hoverMixColor: Qt.rgba(1, 1, 1, 1)
    property bool borderVisible: true
    property color borderColorOverride: "transparent"
    property real borderOpacity: Theme.panelCapsuleBorderOpacity
    property real paddingScale: 1.0
    property real minPadding: 4
    property real verticalPaddingScale: 0.6
    property real verticalPaddingMin: 2
    property bool forceHeightFromMetrics: true
    property bool centerContent: true
    property real cornerRadiusOverride: -1
    property real borderWidthOverride: -1
    property real borderInset: Theme.panelCapsuleBorderInset
    property real contentYOffset: 0
    property int cursorShape: Qt.ArrowCursor

    readonly property real _scale: Theme.scale(screen || Screen)
    readonly property var _metrics: Capsule.metrics(Theme, _scale)
    readonly property var capsuleMetrics: _metrics
    readonly property real capsuleScale: _scale
    readonly property int capsulePadding: _metrics.padding
    readonly property int capsuleInner: _metrics.inner
    readonly property int capsuleHeight: _metrics.height
    readonly property color _baseColor: backgroundColorOverride.a > 0
            ? backgroundColorOverride
            : WidgetBg.color(Settings.settings, backgroundKey, fallbackColor)
    readonly property int horizontalPadding: Math.max(minPadding, Math.round(_metrics.padding * paddingScale))
    readonly property int verticalPadding: Math.max(verticalPaddingMin, Math.round(_metrics.padding * verticalPaddingScale))
    readonly property color _hoverColor: ColorHelpers.mix(_baseColor, hoverMixColor, hoverMixAmount)
    readonly property real _borderWidth: borderWidthOverride >= 0
            ? borderWidthOverride
            : Theme.panelCapsuleBorderWidth
    readonly property color _borderColorTheme: Theme.panelCapsuleBorderColor
    readonly property color _borderColor: borderColorOverride.a > 0
            ? borderColorOverride
            : (_borderColorTheme.a > 0
                ? _borderColorTheme
                : ColorHelpers.withAlpha(Theme.textPrimary, borderOpacity))

    implicitWidth: 0
    implicitHeight: forceHeightFromMetrics ? _metrics.height : 0
    width: implicitWidth
    height: implicitHeight

    radius: cornerRadiusOverride >= 0 ? cornerRadiusOverride : Theme.cornerRadiusSmall
    antialiasing: true
    border.width: 0
    border.color: "transparent"
    color: hoverEnabled && hoverTracker.hovered
        ? (hoverColorOverride.a > 0 ? hoverColorOverride : _hoverColor)
        : _baseColor

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
        inset: borderInset
        baseRadius: root.radius
        strokeWidth: borderVisible ? _borderWidth : 0
        strokeColor: borderVisible ? _borderColor : "transparent"
        enabled: borderVisible
        zIndex: root.z + 1
    }

    default property alias content: centerHost.data

    function paddingScaleFor(paddingPx) {
        if (!_metrics || !_metrics.padding) return 1;
        return paddingPx / _metrics.padding;
    }
}
