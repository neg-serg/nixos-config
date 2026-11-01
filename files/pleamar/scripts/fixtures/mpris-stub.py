#!/usr/bin/env python3
"""A minimal MPRIS player on the session bus, for checking what a scene does with a
player that cannot skip.

Nothing on this host answers `CanGoNext: false` while it plays — `mpd` reports `true`
even at the end of its queue — so the transport's dimmed button had no way to be seen
or re-checked. This serves a real player whose answers are arguments:

    files/pleamar/scripts/fixtures/mpris-stub.py --can-go-next false   # the dimmed one
    files/pleamar/scripts/fixtures/mpris-stub.py --can-go-next true    # the plain one
    files/pleamar/scripts/fixtures/mpris-stub.py --can-go-prev false --can-play false --can-pause false

It owns an `org.mpris.MediaPlayer2.stub` name, so the engine's `media` service follows
it as the most recent player (the bar's own priority rules prefer an mpd that plays,
and mpd is stopped). `pleamar --say bar "get media.can_go_next"` answers what it says,
and `pleamar --say bar describe` names the transport's zone by the value.

Why GLib through ctypes: the dbus-python here has no main loop of its own and PyGObject
is not in the closure, so the loop is `g_main_loop_run` straight from libglib.
"""

import argparse
import ctypes
import sys

import dbus
import dbus.service
import dbus.mainloop.glib

INTROSPECT = """<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/>
    <method name="PlayPause"/><method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" type="x"/></method>
    <method name="SetPosition"><arg direction="in" type="o"/><arg direction="in" type="x"/></method>
    <method name="OpenUri"><arg direction="in" type="s"/></method>
    <signal name="Seeked"><arg type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
  <interface name="org.freedesktop.DBus.Properties">
    <method name="Get"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="out" type="v"/></method>
    <method name="GetAll"><arg direction="in" type="s"/><arg direction="out" type="a{sv}"/></method>
    <method name="Set"><arg direction="in" type="s"/><arg direction="in" type="s"/><arg direction="in" type="v"/></method>
    <signal name="PropertiesChanged"><arg type="s"/><arg type="a{sv}"/><arg type="as"/></signal>
  </interface>
  <interface name="org.freedesktop.DBus.Introspectable">
    <method name="Introspect"><arg direction="out" type="s"/></method>
  </interface>
</node>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="org.mpris.MediaPlayer2.stub")
    ap.add_argument("--title", default="Stub track")
    ap.add_argument("--artist", default="Stub artist")
    # The cover the resolver is handed. A path or a URL: the cover plugin
    # treats `file://`, a bare path and an http(s) URL differently
    # (`CoverResolver.qml:163-168`).
    ap.add_argument("--art", default="file:///tmp/stub-cover.jpg")
    # The track's own file. The media tooltip's quality line reads it with ffprobe
    # (`lib/plugins/meta` does the same for the sidebar rows).
    ap.add_argument("--url", default="")
    ap.add_argument("--status", default="Playing")
    ap.add_argument(
        "--can-go-next", choices=("true", "false"), default="false"
    )
    ap.add_argument("--can-go-prev", choices=("true", "false"), default="true")
    ap.add_argument("--can-play", choices=("true", "false"), default="true")
    ap.add_argument("--can-pause", choices=("true", "false"), default="true")
    args = ap.parse_args()
    can_next = args.can_go_next == "true"
    can_prev = args.can_go_prev == "true"
    can_play = args.can_play == "true"
    can_pause = args.can_pause == "true"
    track = "/org/stub/Track/1"

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    glib = ctypes.CDLL("libglib-2.0.so.0")
    glib.g_main_loop_new.restype = ctypes.c_void_p
    glib.g_main_loop_new.argtypes = [ctypes.c_void_p, ctypes.c_int]
    glib.g_main_loop_run.argtypes = [ctypes.c_void_p]

    bus = dbus.SessionBus()
    # Kept in a variable: a BusName that nothing references releases the name on GC.
    busname = dbus.service.BusName(args.name, bus)  # noqa: F841

    def metadata():
        return dbus.Dictionary(
            {
                "mpris:trackid": dbus.ObjectPath(track),
                "xesam:title": dbus.String(args.title),
                "xesam:artist": dbus.Array([args.artist], signature="s"),
                "mpris:artUrl": dbus.String(args.art),
                **({"xesam:url": dbus.String(args.url)} if args.url else {}),
            },
            signature="sv",
        )

    props = {
        "org.mpris.MediaPlayer2": {
            "Identity": dbus.String("stub"),
            "DesktopEntry": dbus.String("stub"),
            "CanQuit": dbus.Boolean(False),
            "CanRaise": dbus.Boolean(False),
            "HasTrackList": dbus.Boolean(False),
            "SupportedUriSchemes": dbus.Array([], signature="s"),
            "SupportedMimeTypes": dbus.Array([], signature="s"),
        },
        "org.mpris.MediaPlayer2.Player": {
            "PlaybackStatus": dbus.String(args.status),
            "LoopStatus": dbus.String("None"),
            "Rate": dbus.Double(1.0),
            "Shuffle": dbus.Boolean(False),
            "Metadata": metadata(),
            "Volume": dbus.Double(1.0),
            "Position": dbus.Int64(0),
            "MinimumRate": dbus.Double(1.0),
            "MaximumRate": dbus.Double(1.0),
            "CanGoNext": dbus.Boolean(can_next),
            "CanGoPrevious": dbus.Boolean(can_prev),
            "CanPlay": dbus.Boolean(can_play),
            "CanPause": dbus.Boolean(can_pause),
            "CanSeek": dbus.Boolean(False),
            "CanControl": dbus.Boolean(True),
        },
    }

    class Player(dbus.service.Object):
        @dbus.service.method(
            "org.freedesktop.DBus.Properties",
            in_signature="ss",
            out_signature="v",
        )
        def Get(self, iface, prop):
            return props[iface][prop]

        @dbus.service.method(
            "org.freedesktop.DBus.Properties",
            in_signature="s",
            out_signature="a{sv}",
        )
        def GetAll(self, iface):
            return dbus.Dictionary(props.get(iface, {}), signature="sv")

        @dbus.service.method(
            "org.freedesktop.DBus.Properties", in_signature="ssv"
        )
        def Set(self, iface, prop, value):
            if iface in props and prop in props[iface]:
                props[iface][prop] = value

        @dbus.service.method(
            "org.freedesktop.DBus.Introspectable", out_signature="s"
        )
        def Introspect(self):
            return INTROSPECT

        @dbus.service.method("org.mpris.MediaPlayer2")
        def Raise(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2")
        def Quit(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Next(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Previous(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def PlayPause(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Play(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Pause(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player")
        def Stop(self):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="x")
        def Seek(self, offset):
            pass

        @dbus.service.method(
            "org.mpris.MediaPlayer2.Player", in_signature="ox"
        )
        def SetPosition(self, track_id, position):
            pass

        @dbus.service.method("org.mpris.MediaPlayer2.Player", in_signature="s")
        def OpenUri(self, uri):
            pass

        @dbus.service.signal("org.mpris.MediaPlayer2.Player", signature="x")
        def Seeked(self, position):
            pass

    Player(bus, "/org/mpris/MediaPlayer2")
    print(
        f"serving {args.name} · status {args.status} · can_go_next {can_next}",
        flush=True,
    )
    glib.g_main_loop_run(glib.g_main_loop_new(None, 0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
