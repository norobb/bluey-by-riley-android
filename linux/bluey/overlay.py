"""Client for the GNOME Shell extension (bluey@googly-eyes) and the face the phone shows (Mac CursorOverlay.face).

Without the extension the host still runs: no pointer, so the phone's eyes wander and pointing becomes
a caption-only reply.
"""
from __future__ import annotations

import asyncio
import json
import math
import time
from typing import Callable

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAME, PATH, IFACE = "co.visionairy.Bluey.Overlay", "/co/visionairy/Bluey/Overlay", "co.visionairy.Bluey.Overlay"


class Overlay:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        self.on_action: Callable[[str], None] | None = None
        self.bus.signal_subscribe(NAME, IFACE, "Action", PATH, None, 0,
                                  lambda *a: self.on_action and self.on_action(a[5].unpack()[0]))
        self.pointer = (0.0, 0.0)
        self.stage: tuple[float, float] | None = None
        self.app: str | None = None
        self.available = False
        self.last_move = time.monotonic()

    def _call(self, method: str, sig: str | None, args: tuple = (), reply: str | None = None):
        fut = asyncio.get_running_loop().create_future()

        def done(bus, res):
            try:
                v = bus.call_finish(res)
                fut.set_result(v.unpack() if v is not None else ())
            except GLib.Error as e:
                fut.set_exception(e)
        self.bus.call(NAME, PATH, IFACE, method, GLib.Variant(sig, args) if sig else None,
                      GLib.VariantType(reply) if reply else None, 0, 2000, None, done)
        return fut

    async def refresh(self) -> bool:
        try:
            x, y, w, h, app = await self._call("GetState", None, (), "(dddds)")
        except GLib.Error:
            self.available = False
            return False
        if (x, y) != self.pointer:
            self.last_move = time.monotonic()
        self.pointer, self.stage, self.app, self.available = (x, y), (w, h), app or None, True
        return True

    async def _fire(self, method, sig, *args, reply=None):
        try:
            return await self._call(method, sig, args, reply)
        except GLib.Error:
            return None

    async def fly(self, x: float, y: float) -> float:
        r = await self._fire("SetCursor", "(bdd)", True, float(x), float(y), reply="(d)")
        return r[0] if r else 0.0

    async def home(self):
        await self._fire("SetCursor", "(bdd)", False, 0.0, 0.0, reply="(d)")

    async def warp(self, x: float, y: float):
        await self._fire("Warp", "(dd)", float(x), float(y))

    async def caption(self, text: str):
        await self._fire("SetCaption", "(s)", text)

    async def flash(self, text: str):
        await self._fire("Flash", "(s)", text)

    async def countdown(self, text: str):
        await self._fire("SetCountdown", "(s)", text)

    async def hidden(self, on: bool):
        await self._fire("SetHidden", "(b)", on)

    async def menu(self, state: dict):
        await self._fire("SetMenu", "(s)", json.dumps(state))


def face(stage, pointer, cursor, following: bool, awake: bool, mood: str | None, speaking: bool,
         phone_position: float, idle: float, now: float) -> dict:
    """What the phone should look at: the cursor, or your mouse in follow mode."""
    w, h = stage
    phone = (w * phone_position, h + h * 0.18)
    cx, cy = pointer if following or cursor is None else cursor
    gx = max(-1.0, min(1.0, (cx - phone[0]) / (w * 0.5)))
    gy = -max(0.15, min(1.0, (phone[1] - cy) / (h * 1.1)))
    talk = 0.5 + 0.5 * math.sin(now * 19) * math.sin(now * 7.3) if speaking else 0.0
    m = mood or "listening"
    if mood is None and speaking:
        m = "talking"
    elif mood is None and cursor is not None and not following:
        m = "pointing"
    elif mood is None and following and not awake:
        # Your mouse sat still: drowsy after 5 seconds, dozing after 15.
        m = "resting" if idle > 15 else "sleepy" if idle > 5 else "listening"
    return {"gazeX": gx, "gazeY": gy, "mood": m, "talk": talk}
