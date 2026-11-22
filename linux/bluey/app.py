"""Bluey host for Linux (GNOME/Wayland): the Mac app's AppDelegate. Run: python3 -m bluey.app [--pair] [--port N]"""
from __future__ import annotations

import argparse
import asyncio
import json
import socket
import sys
import time
import warnings

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.events import GLibEventLoopPolicy  # noqa: E402
from gi.repository import Adw, Gio  # noqa: E402

from . import ai, screen, ui  # noqa: E402
from .codex import Codex  # noqa: E402
from .config import STATE, settings  # noqa: E402
from .focus import FocusCompanion  # noqa: E402
from .host import Host, focus_countdown  # noqa: E402
from .overlay import Overlay, face  # noqa: E402
from .server import PhoneServer, load_pairing  # noqa: E402


class App:
    def __init__(self, gtk: Adw.Application, args):
        self.gtk, self.args = gtk, args
        self.record = load_pairing(args.name)
        self.server = PhoneServer(self.record, args.name)
        self.overlay = Overlay()
        self.codex = Codex()
        self.reports = ui.ReportCard(gtk)

        async def capture():
            await self.overlay.refresh()
            shot = await screen.snapshot(self.overlay.stage, self.overlay.app,
                                         self.overlay.hidden if self.overlay.available else None)
            return shot.as_capture()

        self.focus = FocusCompanion(STATE, settings, capture=capture, classify=ai.classify,
                                    prepare_nudge=ai.nudge, idle=screen.idle_seconds,
                                    has_key=lambda: ai.api_key() is not None)
        self.host = Host(self.overlay, self.focus, self.codex, self.reports.show)
        self.focus.on_change = lambda text: self.server.broadcast({"command": "focusState", "text": text})
        self.focus.on_nudge = self._nudge
        self.focus.on_publish = lambda s: asyncio.ensure_future(self.overlay.countdown(focus_countdown(s)))
        self.server.on_request = self._request
        self.server.on_phones_changed = self._phones_changed
        self.codex.on_event = self._codex_event
        self.overlay.on_action = self._action
        self.host.on_change = self._menu

    # MARK: Wiring (AppDelegate.swift)

    def _nudge(self, message: str, target):
        asyncio.ensure_future(self.host.focus_nudge(message, target))
        self.server.broadcast({"command": "focusChirp", "text": message})

    async def _request(self, p: dict, reply):
        cmd = p["command"]
        if cmd.startswith("focus"):
            try:
                args = json.loads(p.get("text") or "{}")
            except ValueError:
                args = {}
            result = self.focus.handle(cmd, args if isinstance(args, dict) else {})
            reply({"command": "focusReply", "callID": p.get("callID"), "text": result})
        else:
            await self.host.handle(p, reply)

    def _phones_changed(self, names):
        if not names:
            self.focus.disconnected()
            if self.host.awake:
                self.host.set_awake(False)
        self._menu()

    def _codex_event(self, note: str, line: str):
        if self.host.awake and self.server.phones:
            self.server.broadcast({"command": "codexNote", "text": note})
            return

        async def tell():
            text = await ai.codex_line(note) if not line.startswith("Codex wouldn't") else None
            await self.host.show_reply(text or line)
            self.server.broadcast({"command": "codexChirp", "text": text or line})
        asyncio.ensure_future(tell())

    def _action(self, action: str):
        f, h = self.focus, self.host
        if action == "stop":  # also pauses focus, like ⌃⌥S on the Mac
            asyncio.ensure_future(h.stop_actions())
            f.pause("Stopped from the keyboard.")
            asyncio.ensure_future(self.codex.stop())
        elif action == "toggleAwake":
            self.server.broadcast({"command": "sleep" if h.awake else "wake"})
        elif action == "pointHere":
            h.point(*self.overlay.pointer)
        elif action == "toggleFollow":
            settings["followMouse"] = not settings["followMouse"]
            asyncio.ensure_future(h.go_home())
        elif action == "dock":
            asyncio.ensure_future(h.go_home())
        elif action == "toggleHide":
            self.hidden = not getattr(self, "hidden", False)
            asyncio.ensure_future(self.overlay.hidden(self.hidden))
        elif action in ("focusPause", "focusResume", "focusEnd"):
            {"focusPause": f.pause, "focusResume": f.resume, "focusEnd": f.end}[action]()
        elif action == "toggleDeveloperMode":
            f.set_developer_mode(not f.developer_mode)
        elif action == "toggleComputerControl":
            settings["computerControl"] = not settings["computerControl"]
        elif action == "pair":
            ui.pairing(self.gtk, self.record.qr_text)
        elif action == "editKey":
            ui.edit_key(self.gtk, self._menu)
        elif action == "editPersonality":
            ui.edit_personality(self.gtk)
        elif action == "quit":
            self.gtk.quit()
        self._menu()

    def _menu(self):
        s = self.focus.current
        phones = ", ".join(self.server.names) or "no phone"
        status = f"Bluey · {phones}" + ("" if ai.api_key() else " · no Gemini key")
        asyncio.ensure_future(self.overlay.menu({
            "status": status, "focus": s.status if s and s.status != "ended" else "none",
            "developerMode": self.focus.developer_mode, "computerControl": settings["computerControl"],
            "followMouse": settings["followMouse"]}))

    def _watch_lock_and_sleep(self):
        """Lock or suspend pauses monitoring; unlocking never resumes it."""
        session = Gio.bus_get_sync(Gio.BusType.SESSION)

        def locked(*a):
            active = a[5].unpack()[0]
            self.focus.locked = active
            if active:
                self.focus.pause("Computer locked. Resume when you're ready.")
        session.signal_subscribe("org.gnome.ScreenSaver", "org.gnome.ScreenSaver", "ActiveChanged", "/org/gnome/ScreenSaver",
                                 None, 0, locked)
        system = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        system.signal_subscribe("org.freedesktop.login1", "org.freedesktop.login1.Manager", "PrepareForSleep",
                                "/org/freedesktop/login1", None, 0,
                                lambda *a: a[5].unpack()[0] and self.focus.pause("Computer sleeping. Resume when you're ready."))

    # MARK: Loops

    async def run(self):
        await self.server.start(self.args.port, self.args.mdns_host)
        print(f"Advertising {self.args.name!r} on port {self.server.port}, bluey-id {self.record.identifier}", flush=True)
        self._watch_lock_and_sleep()
        self.codex.warm_up()
        if not await self.overlay.refresh():
            print("GNOME Shell extension bluey@googly-eyes isn't running: no overlay, pointer or menu.", flush=True)
        self._menu()
        if self.args.pair:
            ui.pairing(self.gtk, self.record.qr_text)
        if not ai.api_key():
            ui.edit_key(self.gtk, self._menu)
        last_tick = 0.0
        while True:
            now = time.monotonic()
            if now - last_tick >= 1:
                last_tick = now
                self.focus.tick()
            if await self.overlay.refresh():
                h = self.host
                f = face(self.overlay.stage, self.overlay.pointer, h.cursor, settings["followMouse"] and h.cursor is None,
                         h.awake, None, h.speaking, settings["phonePosition"], now - self.overlay.last_move, now)
                self.server.send_face(f, now)
            await self.host.choreograph()
            await asyncio.sleep(1 / 30)


def main():
    if sys.argv[1:2] == ["setup"]:
        from .setup import run
        sys.exit(run())
    ap = argparse.ArgumentParser(description="Bluey host for Linux. `bluey setup` enables the extension and autostart.")
    ap.add_argument("--pair", action="store_true", help="show the pairing QR")
    ap.add_argument("--port", type=int, default=47321, help="TCP port (fixed so a firewall rule can allow it)")
    ap.add_argument("--name", default=socket.gethostname())
    ap.add_argument("--mdns-host", help="advertise this mDNS host name (testing over adb reverse)")
    args = ap.parse_args()
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        asyncio.set_event_loop_policy(GLibEventLoopPolicy())
    gtk = Adw.Application(application_id="co.visionairy.googly.linux", flags=Gio.ApplicationFlags.NON_UNIQUE)
    state = {}

    def activate(a):
        a.hold()  # no main window: the panel menu and overlay are the UI
        app = App(a, args)
        state["app"] = app
        state["task"] = asyncio.ensure_future(app.run())
        state["task"].add_done_callback(lambda t: t.cancelled() or (t.exception() and (print(t.exception(), file=sys.stderr), a.quit())))

    gtk.connect("activate", activate)
    try:
        gtk.run([])
    finally:
        if "app" in state:
            state["app"].server.stop()
            state["app"].codex.shutdown()
            state["app"].focus.persist()


if __name__ == "__main__":
    main()
