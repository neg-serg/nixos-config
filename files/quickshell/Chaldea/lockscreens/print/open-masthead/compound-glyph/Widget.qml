// SPDX-License-Identifier: 0BSD
import QtQuick

LockScreen {
    property int s0Duration: 100
    property bool s1Motion: true

    transitionTime: s0Duration
    animationEnabled: s1Motion
    designName: "Open masthead"
    wallOpacity: 0
    minimumHeight: 790
    mainPaddingWide: 56
    mainPaddingMedium: 44
    mainPaddingNarrow: 32
    showShipTag: false
    footerRule: true
    compactBadge: true
}
