import QtQuick
import qs.Settings
import "." as LocalComponents

LocalComponents.WidgetCapsule {
    id: root

    // Defaults tailored for inline SystemTray usage, but overridable.
    property color inlineBackground: Theme.surface
    property color inlineBorder: Theme.borderSubtle
    property real inlinePaddingScale: 1
    property real inlineVerticalPaddingScale: 1

    backgroundKey: "systemTray"
    hoverEnabled: false
    backgroundColorOverride: inlineBackground
    borderColorOverride: inlineBorder
    borderWidthOverride: Theme.uiBorderWidth
    minPadding: Settings.settings.systemTrayTightSpacing !== false ? 0 : 4
    paddingScale: inlinePaddingScale
    verticalPaddingScale: inlineVerticalPaddingScale
    centerContent: false
    contentYOffset: 0
    clip: true
}
