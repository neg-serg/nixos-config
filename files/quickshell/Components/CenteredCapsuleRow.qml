import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "." as LocalComponents
import qs.Settings
import "../Helpers/Utils.js" as Utils

LocalComponents.CapsuleButton {
    id: root

    // Layout + sizing
    property int desiredInnerHeight: capsuleMetrics.inner
    property int fontPixelSize: 0
    property int textPadding: Theme.panelRowSpacingSmall
    property int iconSpacing: Theme.panelRowSpacingSmall
    property real centerOffset: 0
    property bool centerRow: true
    property bool labelVisible: true
    property bool iconVisible: true
    property int iconPadding: 0
    property int minContentWidth: 0
    property int maxContentWidth: 0
    property int contentWidth: 0
    property int labelMaxWidth: 0
    property int labelLeftPaddingOverride: -1
    property int labelRightPaddingOverride: -1
    property int labelElideMode: Text.ElideRight

    // Label configuration
    property string labelText: ""
    property color labelColor: Theme.textPrimary
    property string labelFontFamily: Theme.fontFamily
    property int labelFontWeight: Font.Medium
    property bool labelIsRichText: false
    property int labelBaselineAdjust: 0

    // Icon configuration
    property string iconMode: "material" // "material", "glyph"
    property string iconGlyph: ""
    property string iconFontFamily: ""
    property string iconStyleName: ""
    property string materialIconName: ""
    property bool materialIconRounded: false
    property int iconVAdjust: 0
    property bool iconAutoTune: true
    property color iconColor: Theme.textSecondary

    // Accessors
    readonly property alias row: lineBox
    readonly property alias iconItem: baselineIcon
    readonly property alias labelItem: label

    readonly property int computedFontPx: fontPixelSize > 0
        ? fontPixelSize
        : Utils.computedInlineFontPx(desiredInnerHeight, textPadding, Theme.panelComputedFontScale)

    centerContent: centerRow
    contentYOffset: centerOffset
    interactive: false

    readonly property int _naturalWidth: Math.max(0, rowLayout.implicitWidth || 0)
    readonly property int _contentWidth: (function() {
        var width = Math.max(minContentWidth, _naturalWidth);
        if (contentWidth > 0) width = contentWidth;
        if (maxContentWidth > 0) width = Math.min(width, maxContentWidth);
        return width;
    })()
    readonly property bool _isClamped: _contentWidth < _naturalWidth || (contentWidth > 0) || (maxContentWidth > 0) || (labelMaxWidth > 0)

    Item {
        id: lineBox
        width: _contentWidth
        height: rowLayout.implicitHeight
        implicitWidth: width
        implicitHeight: height
        clip: _isClamped
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        RowLayout {
            id: rowLayout
            anchors.fill: parent
            spacing: iconSpacing
            layoutDirection: Qt.LeftToRight

            LocalComponents.BaselineAlignedIcon {
                id: baselineIcon
                visible: root.iconVisible
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: root.iconVisible ? implicitWidth : 0
                Layout.minimumWidth: root.iconVisible ? implicitWidth : 0
                Layout.maximumWidth: root.iconVisible ? implicitWidth : 0
                Layout.preferredHeight: root.desiredInnerHeight
                implicitHeight: root.desiredInnerHeight
                labelRef: label
                mode: root.iconMode === "material" ? "material" : "text"
                alignMode: root.labelVisible ? "baseline" : "optical"
                alignTarget: root.labelVisible ? label : null
                text: root.iconGlyph
                fontFamily: root.iconFontFamily
                fontStyleName: root.iconStyleName
                color: root.iconColor
                icon: root.materialIconName
                rounded: root.materialIconRounded
                screen: root.screen
                autoTune: root.iconAutoTune
                baselineAdjust: root.iconVAdjust
                padding: root.iconPadding
            }

            Item {
                id: leadingSlot
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: childrenRect.width
                Layout.preferredHeight: childrenRect.height
                Layout.minimumWidth: 0
                Layout.maximumWidth: childrenRect.width
            }

            Label {
                id: label
                visible: root.labelVisible
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                Layout.minimumWidth: 0
                Layout.maximumWidth: (root.labelMaxWidth > 0) ? root.labelMaxWidth : Number.POSITIVE_INFINITY
                textFormat: root.labelIsRichText ? Text.RichText : Text.PlainText
                text: root.labelText
                color: root.labelColor
                font.family: root.labelFontFamily
                font.weight: root.labelFontWeight
                font.pixelSize: root.computedFontPx
                padding: 0
                leftPadding: root.labelLeftPaddingOverride !== -1 ? root.labelLeftPaddingOverride : root.textPadding
                rightPadding: root.labelRightPaddingOverride !== -1 ? root.labelRightPaddingOverride : root.textPadding
                verticalAlignment: Text.AlignVCenter
                baselineOffset: labelMetrics.ascent + root.labelBaselineAdjust
                elide: root.labelElideMode
                clip: true
                maximumLineCount: 1
            }

            FontMetrics {
                id: labelMetrics
                font: label.font
            }

            Item {
                id: tailSlot
                Layout.preferredWidth: childrenRect.width
                Layout.preferredHeight: childrenRect.height
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
            }
        }
    }
    default property alias tailContent: tailSlot.data
    property alias leadingContent: leadingSlot.data

    implicitWidth: root.horizontalPadding * 2 + lineBox.width
    implicitHeight: root.forceHeightFromMetrics
        ? Math.max(root.capsuleMetrics.height, lineBox.implicitHeight + root.verticalPadding * 2)
        : lineBox.implicitHeight + root.verticalPadding * 2
}
