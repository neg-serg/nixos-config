import QtQuick

/*!
 * OverlayFrame draws a border as a separate overlay rectangle, allowing the
 * stroke to extend inside (positive inset) or outside (negative inset) the
 * target item without affecting its layout.
 */
Rectangle {
    id: frame

    // Item to follow. Defaults to the parent.
    property Item anchorTarget: parent
    // Positive inset draws the border inside, negative grows it outward.
    property real inset: 0
    // Base radius from the target geometry; OverlayFrame adjusts relative to inset.
    property real baseRadius: 0
    property color strokeColor: "transparent"
    property real strokeWidth: 0
    property bool enabled: true
    // Allows callers to fine-tune stacking relative to siblings.
    property real zIndex: 10

    anchors.fill: anchorTarget ? anchorTarget : parent
    anchors.margins: inset
    radius: Math.max(0, baseRadius - inset)
    color: "transparent"
    border.width: enabled ? strokeWidth : 0
    border.color: enabled ? strokeColor : "transparent"
    antialiasing: true
    visible: enabled && border.width > 0 && border.color.a > 0
    z: zIndex
}
