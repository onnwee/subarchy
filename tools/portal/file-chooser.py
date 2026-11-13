#!/usr/bin/python3
"""Ask the desktop portal for files; print one path per line.

Installed as /usr/lib/subcult/file-chooser for scripts such as
`subcult tailscale send` (ADR 0058). The portal shows the dialog
(xdg-desktop-portal-gtk on Subarchy), so it looks like any other app's.

Usage: file-chooser [--title TEXT] [--multiple]
Exit status: 0 with the paths, 1 when the dialog was closed without a
choice, 2 when the portal could not be asked.
"""

import argparse
import os
import sys

PORTAL = "org.freedesktop.portal.Desktop"
PATH = "/org/freedesktop/portal/desktop"
REQUEST = "org.freedesktop.portal.Request"


def request_path(unique_name: str, token: str) -> str:
    """The object path the portal answers on, from the caller's bus name."""
    sender = unique_name.lstrip(":").replace(".", "_")
    return f"/org/freedesktop/portal/desktop/request/{sender}/{token}"


def local_paths(uris) -> list[str]:
    """The file:// URIs as paths; anything else is left out."""
    from gi.repository import Gio

    paths = []
    for uri in uris:
        path = Gio.File.new_for_uri(uri).get_path() if uri.startswith("file://") else None
        if path:
            paths.append(path)
    return paths


def choose(title: str, multiple: bool) -> tuple[int, list[str]]:
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    token = f"subcult{os.getpid()}"
    loop = GLib.MainLoop()
    answer = {"code": 2, "uris": []}

    def on_response(_conn, _sender, _path, _iface, _signal, params, _data):
        code, results = params.unpack()
        answer["code"] = code
        answer["uris"] = results.get("uris", [])
        loop.quit()

    def subscribe(path):
        bus.signal_subscribe(PORTAL, REQUEST, "Response", path, None, Gio.DBusSignalFlags.NONE, on_response, None)

    # Subscribe before asking, so a quick answer is not missed.
    expected = request_path(bus.get_unique_name(), token)
    subscribe(expected)
    options = {"handle_token": GLib.Variant("s", token), "multiple": GLib.Variant("b", multiple)}
    handle = bus.call_sync(PORTAL, PATH, "org.freedesktop.portal.FileChooser", "OpenFile",
                           GLib.Variant("(ssa{sv})", ("", title, options)), None, Gio.DBusCallFlags.NONE,
                           10000, None).unpack()[0]
    # A portal that ignores the token answers on the path it returns.
    if handle != expected:
        subscribe(handle)
    loop.run()
    return answer["code"], local_paths(answer["uris"])


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Pick files through the desktop portal.")
    parser.add_argument("--title", default="Choose files")
    parser.add_argument("--multiple", action="store_true")
    args = parser.parse_args(argv)
    try:
        code, paths = choose(args.title, args.multiple)
    except Exception as e:  # GLib.Error and import failures alike
        print(f"file-chooser: {e}", file=sys.stderr)
        return 2
    if code == 0 and paths:
        print("\n".join(paths))
        return 0
    # 1: cancelled; 2: the dialog ended some other way.
    return 1 if code in (0, 1) else 2


if __name__ == "__main__":
    sys.exit(main())
