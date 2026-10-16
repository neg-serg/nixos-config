// SPDX-License-Identifier: 0BSD
import QtQuick

GlyphWidget {
    designName: "Stencil assembly"
    property int duration: 100
    property int red: 100
    property bool motion: true
    transitionTime: duration
    emphasis: red
    animationEnabled: motion
}
