import QtQuick
import qs.Components
import qs.Settings

/*! ConnectivityIconCapsule combines ConnectivityCapsule with a standardized
    icon slot driven by Theme's network capsule tokens. Modules configure the
    icon while inheriting label padding/spacing from ConnectivityCapsule. */
ConnectivityCapsule {
    id: root

    // Control leading glyph behavior
    property bool iconActive: true
    property bool iconSquare: true
    property string iconMode: "material" // material, text, svg
    property string iconName: ""
    property string iconText: ""
    property bool iconRounded: false
    property color iconColor: Theme.textSecondary
    property bool iconFollowsLabel: true
    property var iconScreen: root.screen
    property real iconScaleToken: Theme.networkCapsuleIconScale
    property int iconBaselineToken: Theme.networkCapsuleIconBaselineOffset
    property string iconAlignModeToken: Theme.networkCapsuleIconAlignMode
    property int iconPadding: Theme.networkCapsuleIconPadding
    property int iconHorizontalMargin: Math.max(0, Theme.networkCapsuleIconHorizontalMargin)

    glyphLeadingActive: iconActive

    leadingContent: ConnectivityIconSlot {
        active: root.iconActive
        square: root.iconSquare
        box: root.desiredInnerHeight
        mode: root.iconMode
        icon: root.iconName
        text: root.iconText
        rounded: root.iconRounded
        color: root.iconColor
        screen: root.iconScreen
        scaleToken: root.iconScaleToken
        baselineToken: root.iconBaselineToken
        alignModeToken: root.iconAlignModeToken
        padding: root.iconPadding
        outerHorizontalMargin: root.iconHorizontalMargin
        labelRef: root.iconFollowsLabel ? root.labelItem : null
        alignTarget: root.iconFollowsLabel ? root.labelItem : null
    }
}
