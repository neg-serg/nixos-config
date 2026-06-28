import QtQuick
import qs.Settings
import "../Helpers/Utils.js" as Utils

Canvas {
    property color color: Theme.background
    property bool flipX: false
    property bool flipY: false
    property real xCoverage: 1.0
    property bool highlightEnabled: false
    property color highlightColor: Theme.accentPrimary
    property real highlightWidth: 2

    antialiasing: true
    enabled: visible
    contextType: "2d"

    function _resolveVertices() {
        var w = width;
        var h = height;
        var coverage = Utils.clamp01(xCoverage);
        var span = Math.max(1, w * coverage);
        span = Math.min(span, w);
        return {
            xBase: flipX ? w : 0,
            xEdge: flipX ? Math.max(0, w - span) : span,
            yBase: flipY ? 0 : h,
            yOpp: flipY ? h : 0
        };
    }

    onPaint: {
        var ctx = getContext("2d");
        var w = width;
        var h = height;
        ctx.clearRect(0, 0, w, h);
        if (w <= 0 || h <= 0) return;

        var v = _resolveVertices();

        ctx.lineWidth = 0;
        ctx.lineJoin = "miter";
        ctx.lineCap = "butt";
        ctx.beginPath();
        ctx.moveTo(v.xBase, v.yBase);
        ctx.lineTo(v.xBase, v.yOpp);
        ctx.lineTo(v.xEdge, v.yBase);
        ctx.closePath();
        ctx.fillStyle = color;
        ctx.fill();

        if (highlightEnabled) {
            ctx.beginPath();
            ctx.moveTo(v.xEdge, v.yBase);
            ctx.lineTo(v.xBase, v.yOpp);
            ctx.lineWidth = highlightWidth;
            ctx.lineCap = "round";
            ctx.strokeStyle = highlightColor;
            ctx.stroke();
        }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()
    onFlipXChanged: requestPaint()
    onFlipYChanged: requestPaint()
    onXCoverageChanged: requestPaint()
    onHighlightEnabledChanged: requestPaint()
    onHighlightColorChanged: requestPaint()
    onHighlightWidthChanged: requestPaint()
    Component.onCompleted: requestPaint()
}
