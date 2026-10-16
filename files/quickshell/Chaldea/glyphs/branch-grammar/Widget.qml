// SPDX-License-Identifier: 0BSD
import QtQuick

GlyphWidget {
    designName: "Branch grammar"
    property int duration: 100
    property int red: 100
    property bool motion: true
    transitionTime: duration
    emphasis: red
    animationEnabled: motion
}
