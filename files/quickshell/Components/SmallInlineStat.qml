import QtQuick
import QtQuick.Controls
import qs.Components
import qs.Settings
import "../Helpers/Utils.js" as Utils
import "." as LocalComponents

LocalComponents.CenteredCapsuleRow {
    id: root
    property int desiredHeight: 28
    property int fontPixelSize: 0
    property int textPadding: Theme.panelRowSpacingSmall
    property int iconSpacing: Theme.panelRowSpacingSmall
    property string iconMode: "glyph"
    property string iconGlyph: ""
    property string iconFontFamily: ""
    property string iconStyleName: ""
    property string materialIconName: ""
    property bool materialIconRounded: false
    property int iconVAdjust: 0
    property bool iconAutoTune: true
    property color iconColor: Theme.textSecondary
    property bool centerContent: false
    property bool labelVisible: true
    property string labelText: ""
    property color labelColor: Theme.textPrimary
    property string labelFontFamily: Theme.fontFamily
    property bool labelIsRichText: false
    property var screen: null
    property color bgColor: "transparent"
    property int centerOffset: 0

    desiredInnerHeight: desiredHeight
    textPadding: root.textPadding
    iconSpacing: root.iconSpacing
    iconMode: root.iconMode
    iconGlyph: root.iconGlyph
    iconFontFamily: root.iconFontFamily
    iconStyleName: root.iconStyleName
    materialIconName: root.materialIconName
    materialIconRounded: root.materialIconRounded
    iconVAdjust: root.iconVAdjust
    iconAutoTune: root.iconAutoTune
    iconColor: root.iconColor
    centerRow: root.centerContent
    labelVisible: root.labelVisible
    labelText: root.labelText
    labelColor: root.labelColor
    labelFontFamily: root.labelFontFamily
    labelIsRichText: root.labelIsRichText
    screen: root.screen
    backgroundKey: ""
    backgroundColorOverride: root.bgColor
    contentYOffset: root.centerOffset
    interactive: false
    hoverEnabled: false

    property int computedFontPx: fontPixelSize > 0
        ? fontPixelSize
        : Utils.computedInlineFontPx(desiredHeight, textPadding, Theme.panelComputedFontScale)
    fontPixelSize: computedFontPx
}
