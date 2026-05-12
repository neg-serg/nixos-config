import QtQuick
import qs.Components
import qs.Settings

/*!
 * ConnectivityCapsule standardizes padding, font sizing, and capsule metrics for
 * network-related widgets that build on CenteredCapsuleRow.
 */
CenteredCapsuleRow {
    id: root

    property int labelPixelSize: Math.round(Theme.fontSizeSmall * capsuleScale)
    property int iconSpacingPx: Theme.networkCapsuleIconSpacing
    property int textPaddingPx: Theme.networkCapsuleLabelPadding
    property int minLabelGapPx: Theme.networkCapsuleMinLabelGap
    property color textColor: Theme.textPrimary
    // When true, treat the capsule as having leading glyph content (square icon slot)
    property bool glyphLeadingActive: iconVisible

    readonly property int _clampedLabelPadding: Math.max(0, textPaddingPx)
    readonly property int _clampedIconSpacing: Math.max(0, iconSpacingPx)
    readonly property int _clampedMinLabelGap: Math.max(0, minLabelGapPx)
    readonly property int _resolvedIconSpacing: glyphLeadingActive ? _clampedIconSpacing : Theme.uiSpacingNone
    readonly property int _resolvedLabelLeftPadding: glyphLeadingActive ? Math.max(_clampedLabelPadding, _clampedMinLabelGap - _clampedIconSpacing) : -1

    desiredInnerHeight: capsuleInner
    textPadding: _clampedLabelPadding
    iconSpacing: _resolvedIconSpacing
    fontPixelSize: labelPixelSize
    labelColor: textColor
    labelFontFamily: Theme.fontFamily
    labelLeftPaddingOverride: _resolvedLabelLeftPadding
}
