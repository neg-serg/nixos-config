pragma ComponentBehavior: Bound
import QtQuick
import qs.Components
import qs.Settings

// Top-level tray menu: the shared SubmenuHost surface, sized for the root menu.
// It owns the component factory that builds nested submenus and destroys the
// whole submenu tree when the menu is hidden.
SubmenuHost {
    id: trayMenu
    implicitWidth: Theme.panelMenuWidth
    destroySubmenusOnHide: true

    // Submenu host component passed into delegates
    Component { id: submenuHostComp; SubmenuHost { submenuHostComponent: submenuHostComp } }
    submenuHostComponent: submenuHostComp
}
