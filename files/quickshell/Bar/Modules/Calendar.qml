pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Components
import qs.Settings
import "../Widgets/SidePanel" as SidePanel

// Calendar capsule button — opens the medieval CalendarPopup overlay.
OverlayToggleCapsule {
    id: root
    visible: false
    capsuleVisible: false
    autoToggleOnTap: false

    // Wire to the CalendarPopup instance (must be set by Bar.qml or parent)
    property var calendarPopup: null

    onTapped: {
        if (calendarPopup) {
            if (calendarPopup.visible)
                calendarPopup.hidePopup()
            else
                calendarPopup.showAt()
        }
    }

    // The CalendarPopup is a WlrLayershell window — instantiate here as overlay child
    overlayChildren: [
        Item {
            id: popupHost
            // This Item exists so OverlayToggleCapsule has children.
            // The actual CalendarPopup is a WlrLayershell window managed externally.
        }
    ]
}
