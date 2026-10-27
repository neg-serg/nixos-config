#!/usr/bin/env python3
"""A tray item with a nested menu, for checking that the bar's menu walks submenus.

Nothing on this host nests: the tray items it carries answer one flat list, so the
port's `open_tray_menu` could drop `children` and no window would ever show it. This
serves a real `org.kde.StatusNotifierItem` whose `com.canonical.dbusmenu` has a parent
with children, a separator inside it, a checkable leaf and one plain action, then
registers with the watcher the engine is.

Every activation is printed as `event <id> <event-id>` on stdout, so a run can prove
that a leaf of the submenu reached the application it belongs to.

    files/pleamar/scripts/fixtures/tray-nested.py            # serves until killed
    files/pleamar/scripts/fixtures/tray-nested.py --once     # exits after the first click

The bar draws this item like any other tray icon: a right press opens its menu, and
the submenu's rows are there under their parent.
"""

import argparse
import ctypes
import sys

import dbus
import dbus.service
import dbus.mainloop.glib

ITEM_NAME = "org.kde.StatusNotifierItem-stub"
ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"
WATCHER = "org.kde.StatusNotifierWatcher"
WATCHER_PATH = "/StatusNotifierWatcher"

# The menu: 1 is a parent whose children are only reachable through it.
# 0 is the root, which is never drawn (the engine takes its children).
LAYOUT = {
    0: {"label": "", "children": [1, 2, 3]},
    1: {"label": "Nested parent", "children": [11, 12, 13, 14]},
    2: {"label": "", "type": "separator", "children": []},
    3: {"label": "Plain action", "children": []},
    11: {"label": "Leaf one", "children": []},
    12: {"label": "Leaf two", "children": []},
    13: {"label": "", "type": "separator", "children": []},
    14: {
        "label": "Leaf checked",
        "toggle-type": "checkmark",
        "toggle-state": 1,
        "children": [],
    },
}

INTROSPECT = """<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.kde.StatusNotifierItem">
    <property name="Category" type="s" access="read"/>
    <property name="Id" type="s" access="read"/>
    <property name="Title" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="WindowId" type="i" access="read"/>
    <property name="IconName" type="s" access="read"/>
    <property name="IconPixmap" type="a(iiay)" access="read"/>
    <property name="IconThemePath" type="s" access="read"/>
    <property name="OverlayIconName" type="s" access="read"/>
    <property name="AttentionIconName" type="s" access="read"/>
    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    <property name="ItemIsMenu" type="b" access="read"/>
    <property name="Menu" type="o" access="read"/>
    <method name="ContextMenu"><arg direction="in" type="i"/><arg direction="in" type="i"/></method>
    <method name="Activate"><arg direction="in" type="i"/><arg direction="in" type="i"/></method>
    <method name="SecondaryActivate"><arg direction="in" type="i"/><arg direction="in" type="i"/></method>
    <method name="Scroll"><arg direction="in" type="i"/><arg direction="in" type="s"/></method>
  </interface>
  <interface name="com.canonical.dbusmenu">
    <method name="GetLayout">
      <arg direction="in" type="i"/><arg direction="in" type="i"/><arg direction="in" type="as"/>
      <arg direction="out" type="u"/><arg direction="out" type="(ia{sv}av)"/>
    </method>
    <method name="GetGroupProperties">
      <arg direction="in" type="ai"/><arg direction="in" type="as"/>
      <arg direction="out" type="a(ia{sv})"/>
    </method>
    <method name="AboutToShow"><arg direction="in" type="i"/><arg direction="out" type="b"/></method>
    <method name="Event">
      <arg direction="in" type="i"/><arg direction="in" type="s"/>
      <arg direction="in" type="v"/><arg direction="in" type="u"/>
    </method>
    <property name="Version" type="u" access="read"/>
    <property name="TextDirection" type="s" access="read"/>
    <property name="Status" type="s" access="read"/>
    <property name="IconThemePath" type="as" access="read"/>
    <signal name="ItemsPropertiesUpdated"><arg type="a(ia{sv})"/><arg type="a(ias)"/></signal>
    <signal name="LayoutUpdated"><arg type="u"/><arg type="i"/></signal>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="out" type="v"/></method>
    <method name="GetAll"><arg direction="in" type="s"/><arg direction="out" type="a{sv}"/></method>
    <method name="Set"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="in" type="v"/></method>
  </interface>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect"><arg direction="out" type="s"/></method>
  </interface>
</node>
"""


def props_of(item):
    out = {}
    for key in ("label", "type", "toggle-type", "toggle-state"):
        if key in item:
            value = item[key]
            out[key] = (
                dbus.Int32(value)
                if isinstance(value, int)
                else dbus.String(value)
            )
    out["enabled"] = dbus.Boolean(True)
    out["visible"] = dbus.Boolean(True)
    return dbus.Dictionary(out, signature="sv")


def node(item_id, depth):
    item = LAYOUT[item_id]
    children = dbus.Array(
        [node(c, depth - 1) for c in item["children"]], signature="v"
    )
    return dbus.Struct(
        (dbus.Int32(item_id), props_of(item), children),
        signature="ia{sv}av",
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--once", action="store_true", help="exit after the first activation"
    )
    args = ap.parse_args()

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    glib = ctypes.CDLL("libglib-2.0.so.0")
    glib.g_main_loop_new.restype = ctypes.c_void_p
    glib.g_main_loop_new.argtypes = [ctypes.c_void_p, ctypes.c_int]
    glib.g_main_loop_run.argtypes = [ctypes.c_void_p]

    bus = dbus.SessionBus()
    # Kept in a variable: a BusName that nothing references releases the name on GC.
    busname = dbus.service.BusName(ITEM_NAME, bus)  # noqa: F841

    class Item(dbus.service.Object):
        @dbus.service.method(
            "org.freedesktop.DBus.Properties",
            in_signature="ss",
            out_signature="v",
        )
        def Get(self, iface, prop):
            if iface == "com.canonical.dbusmenu":
                return {
                    "Version": dbus.UInt32(3),
                    "TextDirection": dbus.String("ltr"),
                    "Status": dbus.String("normal"),
                    "IconThemePath": dbus.Array([], signature="s"),
                }[prop]
            return {
                "Category": dbus.String("ApplicationStatus"),
                "Id": dbus.String("stub-nested"),
                "Title": dbus.String("Nested tray stub"),
                "Status": dbus.String("Active"),
                "WindowId": dbus.Int32(0),
                "IconName": dbus.String("applications-system"),
                "IconPixmap": dbus.Array([], signature="(iiay)"),
                "IconThemePath": dbus.String(""),
                "OverlayIconName": dbus.String(""),
                "AttentionIconName": dbus.String(""),
                "ToolTip": dbus.Struct(
                    (
                        dbus.String(""),
                        dbus.Array([], signature="(iiay)"),
                        dbus.String("Nested tray stub"),
                        dbus.String("a parent and its children"),
                    ),
                    signature="sa(iiay)ss",
                ),
                "ItemIsMenu": dbus.Boolean(True),
                "Menu": dbus.ObjectPath(MENU_PATH),
            }[prop]

        @dbus.service.method(
            "org.freedesktop.DBus.Properties",
            in_signature="s",
            out_signature="a{sv}",
        )
        def GetAll(self, iface):
            names = {
                "com.canonical.dbusmenu": (
                    "Version",
                    "TextDirection",
                    "Status",
                    "IconThemePath",
                ),
            }.get(
                iface,
                (
                    "Category",
                    "Id",
                    "Title",
                    "Status",
                    "WindowId",
                    "IconName",
                    "IconPixmap",
                    "IconThemePath",
                    "OverlayIconName",
                    "AttentionIconName",
                    "ToolTip",
                    "ItemIsMenu",
                    "Menu",
                ),
            )
            return dbus.Dictionary(
                {n: self.Get(iface, n) for n in names}, signature="sv"
            )

        @dbus.service.method(
            "org.freedesktop.DBus.Properties", in_signature="ssv"
        )
        def Set(self, iface, prop, value):
            pass

        @dbus.service.method(
            "org.freedesktop.DBus.Introspectable", out_signature="s"
        )
        def Introspect(self):
            return INTROSPECT

        @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
        def Activate(self, x, y):
            print("event 0 activated", flush=True)

        @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
        def SecondaryActivate(self, x, y):
            pass

        @dbus.service.method("org.kde.StatusNotifierItem", in_signature="ii")
        def ContextMenu(self, x, y):
            pass

        @dbus.service.method("org.kde.StatusNotifierItem", in_signature="is")
        def Scroll(self, delta, orientation):
            pass

        @dbus.service.method(
            "com.canonical.dbusmenu",
            in_signature="iias",
            out_signature="u(ia{sv}av)",
        )
        def GetLayout(self, parent_id, depth, names):
            return dbus.UInt32(1), node(int(parent_id), int(depth))

        @dbus.service.method(
            "com.canonical.dbusmenu",
            in_signature="aias",
            out_signature="a(ia{sv})",
        )
        def GetGroupProperties(self, ids, names):
            return dbus.Array(
                [
                    dbus.Struct(
                        (dbus.Int32(int(i)), props_of(LAYOUT[int(i)])),
                        signature="ia{sv}",
                    )
                    for i in ids
                ],
                signature="(ia{sv})",
            )

        @dbus.service.method(
            "com.canonical.dbusmenu", in_signature="i", out_signature="b"
        )
        def AboutToShow(self, item_id):
            return False

        @dbus.service.method("com.canonical.dbusmenu", in_signature="isvu")
        def Event(self, item_id, event_id, data, timestamp):
            print(f"event {int(item_id)} {event_id}", flush=True)
            if args.once and event_id in ("clicked", "activated"):
                loop.quit()

    # One object on two paths: the item and its menu are two interfaces of one node.
    Item(bus, ITEM_PATH)
    Item(bus, MENU_PATH)

    watcher = dbus.Interface(bus.get_object(WATCHER, WATCHER_PATH), WATCHER)
    watcher.RegisterStatusNotifierItem(ITEM_NAME)
    print(
        f"serving {ITEM_NAME}{ITEM_PATH} · menu {MENU_PATH} · parent 1 has 4 children",
        flush=True,
    )

    loop = glib.g_main_loop_new(None, 0)
    glib.g_main_loop_run(loop)
    return 0


if __name__ == "__main__":
    sys.exit(main())
