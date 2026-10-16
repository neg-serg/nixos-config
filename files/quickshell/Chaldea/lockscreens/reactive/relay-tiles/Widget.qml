// SPDX-License-Identifier: 0BSD
import QtQuick

LockScreen {
    property int s0Duration: 100
    property int s1Red: 100
    property bool s2Motion: true
    transitionTime: s0Duration
    emphasis: s1Red
    animationEnabled: s2Motion
}
