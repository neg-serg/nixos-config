import QtQuick
import qs.Settings

/*!
 * PanelOverlaySurface standardizes the background chrome (radius, border,
 * color) for overlay popups launched from the panel. Consumers anchor this
 * surface and provide their content via the default slot.
 */
Rectangle {
    id: root

    // Optional screen binding for scale-aware radii
    property var screen: null
    // Provide a custom scale (e.g., capsuleScale) when available
    property real scaleHint: 0
    readonly property real overlayScale: scaleHint > 0
        ? scaleHint
        : Theme.scale(screen || Screen)

    property color backgroundColor: Theme.overlayWeak
    property color borderColor: Theme.borderSubtle
    property real borderWidth: Theme.uiBorderWidth
    property real borderInset: 0
    property real radiusBase: Theme.panelOverlayRadius
    property real cornerRadiusOverride: -1

    color: backgroundColor
    radius: cornerRadiusOverride >= 0
        ? cornerRadiusOverride
        : Math.round(radiusBase * overlayScale)

    implicitWidth: contentHost.implicitWidth
    implicitHeight: contentHost.implicitHeight
    width: implicitWidth
    height: implicitHeight

    Item {
        id: contentHost
        anchors.fill: parent
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    OverlayFrame {
        anchorTarget: root
        inset: borderInset
        baseRadius: root.radius
        strokeWidth: borderWidth
        strokeColor: borderColor
        enabled: borderWidth > 0 && borderColor.a > 0
        zIndex: root.z + 1
    }

    default property alias content: contentHost.data
}
