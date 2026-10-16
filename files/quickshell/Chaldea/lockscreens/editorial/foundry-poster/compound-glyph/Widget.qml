// SPDX-License-Identifier: 0BSD
import QtQuick

LockScreen {
    property int s0Duration: 100
    property bool s1Motion: true

    transitionTime: s0Duration
    animationEnabled: s1Motion
    designName: "Foundry poster"
}
