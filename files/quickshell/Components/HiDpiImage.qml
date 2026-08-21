import QtQuick
import "../Helpers/ScreenUtil.js" as ScreenUtil

// HiDpiImage — Image with auto-calculated sourceSize for crisp rendering
// Usage: HiDpiImage { anchors.fill: parent; source: url; fillMode: Image.PreserveAspectCrop }
Image {
    id: root
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true

    sourceSize: Qt.size(
        Math.round(width  * ScreenUtil.dpr(root)),
        Math.round(height * ScreenUtil.dpr(root))
    )
}

