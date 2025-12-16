import QtQuick
import qs.Settings
import "." as LocalComponents

LocalComponents.WidgetCapsule {
    id: root

    // Defaults tailored for inline SystemTray usage, but overridable.
    property color inlineBackground: Theme.background
    property color inlineBorder: Theme.borderSubtle
    property string inlineBackgroundKey: "systemTray"
    property real inlinePaddingScale: 1
    property real inlineVerticalPaddingScale: 1
    property bool clipContents: true

    backgroundKey: inlineBackgroundKey
    hoverEnabled: false
    backgroundColorOverride: inlineBackground
    borderColorOverride: inlineBorder
    borderWidthOverride: Theme.uiBorderWidth
    minPadding: Settings.settings.systemTrayTightSpacing !== false ? 0 : 4
    paddingScale: inlinePaddingScale
    verticalPaddingScale: inlineVerticalPaddingScale
    centerContent: false
    contentYOffset: 0
    clip: clipContents
}
