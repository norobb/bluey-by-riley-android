"""The host's half of live voice (Mac RealtimeHost.swift): short-lived keys, tools, pointing and captions.

The phone runs the Realtime session; this side mints its key, runs its tools in order, and shows captions.
"""
from __future__ import annotations

import asyncio
import base64
import json
import time
from typing import Callable

from . import ai, control, notes, stt
from .codex import Codex
from .config import settings
from .focus import FocusCompanion, clock
from .overlay import Overlay
from .screen import Snapshot, snapshot

REPORT_MARKER = "\n---REPORT---\n"
ACTIONS = {"move_mouse", "click", "type_text", "press_keys", "scroll", "drag", "open_app", "open_url"}
MIN_HOLD, IDLE_HOME = 2.2, 5.0


def _num(v):
    if isinstance(v, bool):
        return None
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


class Host:
    def __init__(self, overlay: Overlay, focus: FocusCompanion, codex: Codex, show_report: Callable[[dict | str, bool], None]):
        self.overlay, self.focus, self.codex, self.show_report = overlay, focus, codex, show_report
        self.snap: Snapshot | None = None
        self.awake = False
        self.speaking = False
        self.cursor: tuple[float, float] | None = None  # where his cursor is pinned; None = home
        self.queue: list[tuple[float, float]] = []
        self.hold_until = 0.0
        self.home_requested = False
        self.quiet_since = 0.0
        self.stopped_until = 0.0
        self.tool_chain: asyncio.Future | None = None
        self.reading_done: asyncio.TimerHandle | None = None
        self.on_change: Callable[[], None] | None = None

    # MARK: Requests from the phone

    async def handle(self, p: dict, reply: Callable[[dict], None]) -> None:
        cmd, call = p.get("command"), p.get("callID")
        if cmd == "realtimeToken":
            s = self.focus.current
            extra = f"Current focus task: {s.d['task']}. State: {s.status}." if s and s.status != "ended" else None
            try:
                token = await ai.mint_token(extra, Codex.installed(), settings["computerControl"], stt.available())
                reply({"command": "realtimeToken", "callID": call, "text": token})
            except Exception as e:
                reply({"command": "realtimeToken", "callID": call})
                await self.overlay.flash(str(e)[:160])
        elif cmd == "hear":
            # A held voice turn (16 kHz PCM16) transcribed locally with Parakeet; only the text goes to Gemini.
            try:
                text = await stt.transcribe(base64.b64decode(p.get("audio") or "", validate=True))
            except Exception:
                text = None
            reply({"command": "heard", "callID": call, "text": text})
        elif cmd == "transcribe":
            try:
                meta = json.loads(p.get("text") or "")
                audio = base64.b64decode(p["audio"], validate=True)
                segs, folder = await notes.transcribe(audio, meta["session"], int(meta["index"]), float(meta["sessionStarted"]))
                reply({"command": "transcribed", "callID": call, "text": json.dumps(
                    {"segments": [{"speaker": s["speaker"], "start": s["start"], "text": s["text"]} for s in segs], "notesPath": str(folder)})})
            except Exception:
                reply({"command": "transcribed", "callID": call})
        elif cmd == "notes":
            try:
                folder = notes.write(json.loads(p.get("text") or ""))
            except ValueError:
                folder = None
            reply({"command": "notes", "callID": call, "text": str(folder) if folder else None})
        elif cmd == "awake":
            self.set_awake(True)
        elif cmd == "asleep":
            self.set_awake(False)
        elif cmd == "caption":
            text = (p.get("text") or "").strip()
            self._cancel_reading()
            await self.overlay.caption(text)
            if text:
                self.set_speaking(True)
        elif cmd == "captionDone":
            await self.show_reply(p.get("text") or "")
        elif cmd == "tool":
            previous = self.tool_chain

            async def run():
                if previous:
                    await asyncio.shield(previous)
                text, image = await self.run_tool(p.get("tool") or "", p.get("text") or "{}")
                reply({"command": "toolResult", "callID": call, "text": text, "image": image})
            self.tool_chain = asyncio.ensure_future(run())

    # MARK: Bubble

    def _cancel_reading(self):
        if self.reading_done:
            self.reading_done.cancel()
            self.reading_done = None

    async def show_reply(self, text: str) -> None:
        if text:
            await self.overlay.caption(text)
        words = len(text.split())
        read = min(max(2.8, 1.2 + words * 0.32), 12) + 3
        self._cancel_reading()

        def done():
            self.set_speaking(False)
            asyncio.ensure_future(self.overlay.caption(""))
        self.reading_done = asyncio.get_running_loop().call_later(read, done)

    async def focus_nudge(self, message: str, target: dict | None) -> None:
        if target:
            self.point(target["x"], target["y"] + target["rect"][3] / 2 + 3)
        else:
            await self.go_home()
        self.set_speaking(True)
        await self.show_reply(message)

    def set_speaking(self, on: bool):
        if self.speaking and not on:
            self.quiet_since = time.monotonic()
        self.speaking = on

    def set_awake(self, on: bool):
        self.awake = on
        if not on:
            self.queue = []
            asyncio.ensure_future(self.go_home())
            asyncio.ensure_future(self.overlay.caption(""))
        if self.on_change:
            self.on_change()

    async def stop_actions(self):
        self.stopped_until = time.monotonic() + 6
        self.queue = []
        await self.go_home()
        await self.overlay.flash("Stopped")

    # MARK: Pointing choreography: each spot gets a flight and a hold; home once he's done talking.

    def point(self, x: float, y: float):
        self.queue.append((x, y))
        self.home_requested = False

    async def go_home(self):
        self.cursor = None
        self.queue = []
        self.home_requested = False
        await self.overlay.home()

    async def choreograph(self):
        """Called ~30×/s by the app loop."""
        now = time.monotonic()
        if now >= self.hold_until and self.queue:
            x, y = self.queue.pop(0)
            self.cursor = (x, y)
            if not self.speaking:
                self.quiet_since = now
            await self.overlay.fly(x, y)
            self.hold_until = now + 1.0 + MIN_HOLD
            return
        if self.queue or now < self.hold_until or self.cursor is None:
            return
        quiet = 0 if self.speaking else now - self.quiet_since
        if (self.home_requested and quiet > 1.2) or quiet > IDLE_HOME:
            await self.go_home()

    # MARK: Tools

    def _size(self):
        return self.snap.size if self.snap else self.overlay.stage or (1920.0, 1080.0)

    def _grid(self, x, y):
        w, h = self._size()
        return min(max(x, 0), 1000) / 1000 * w, min(max(y, 0), 1000) / 1000 * h

    def _spot(self, args, id_key, x_key, y_key):
        tid = args.get(id_key)
        if isinstance(tid, str) and tid and self.snap and (t := self.snap.target(tid)):
            return (t["x"] + t["w"] / 2, t["y"] + t["h"] / 2), t["text"]
        x, y = _num(args.get(x_key)), _num(args.get(y_key))
        if x is not None and y is not None:
            return self._grid(x, y), "that spot"
        return None

    async def look(self, prefix: str | None = None) -> tuple[str, str | None]:
        try:
            await self.overlay.refresh()
            shot = await snapshot(self.overlay.stage, self.overlay.app, self.overlay.hidden if self.overlay.available else None)
        except Exception:
            problem = "I can't see the screen. The screenshot permission is off for Bluey."
            return (f"{prefix} {problem}" if prefix else problem), None
        self.snap = shot
        text = shot.target_list
        if self.overlay.available:
            mx, my = self.overlay.pointer
            w, h = shot.size
            text += f"\nThe user's mouse pointer is at @{int(min(max(mx / w, 0), 1) * 1000)},{int(min(max(my / h, 0), 1) * 1000)}"
            under = shot.target_near(mx, my)
            if under:
                text += f", on {under['id']} \"{under['text']}\""
            text += ". When they say \"this\", \"that\" or \"here\", they mean what's at their mouse pointer."
        if prefix:
            text = prefix + "\nHere's the screen now (ids have changed):\n" + text
        return text, base64.b64encode(shot.jpeg).decode()

    async def run_tool(self, name: str, arguments: str) -> tuple[str, str | None]:
        try:
            args = json.loads(arguments)
            args = args if isinstance(args, dict) else {}
        except ValueError:
            args = {}
        if name in ACTIONS:
            refusal = self._refusal()
            if refusal:
                return refusal, None
            try:
                return await self._action(name, args)
            except control.ControlError as e:
                return str(e), None
        f = self.focus
        if name == "look_at_screen":
            return await self.look()
        if name == "point_at":
            tid = str(args.get("target_id", "")).strip()
            if not self.snap:
                return "Call look_at_screen first.", None
            t = self.snap.target(tid)
            if not t:
                return f"No target {tid}. Use an id from the last look_at_screen.", None
            self.point(t["x"] + t["w"] / 2, t["y"] + t["h"] + 3)
            return (f"Queued: your cursor will point at \"{t['text']}\" after the earlier spots." if len(self.queue) > 1
                    else f"Pointing at \"{t['text']}\"."), None
        if name == "point_at_spot":
            x, y = _num(args.get("x")), _num(args.get("y"))
            if x is None or y is None:
                return "Give x and y.", None
            self.point(*self._grid(x, y))
            return "Pointing there.", None
        if name == "stop_pointing":
            self.home_requested = True
            return "Your cursor will head home once you finish talking.", None
        if name == "web_research":
            q = str(args.get("question", "")).strip()
            if not q:
                return "What should I research?", None
            self.show_report(q, True)
            try:
                context = " / ".join(line["text"] for line, _ in self.snap.lines[:40]) if self.snap else None
                report = await ai.research(q, context)
                self.show_report(report, False)
                plain = "\n\n".join([report["title"], *report["paragraphs"]])
                return ("The full report is now in a card on the user's screen. Reply with ONE short line: the key takeaway in your own words. Don't repeat the report."
                        + REPORT_MARKER + plain), None
            except Exception as e:
                self.show_report(f"Research failed: {e}", False)
                return f"Research failed: {e}. Tell the user in a few words.", None
        if name == "focus_start":
            m = _num(args.get("minutes"))
            return f.start(str(args.get("task", "")), m if m is not None else 30), None
        if name == "focus_pause":
            return f.pause(), None
        if name == "focus_resume":
            return f.resume(), None
        if name == "focus_end":
            return f.end(), None
        if name == "focus_status":
            return f.status_line(), None
        if name == "codex_start":
            return self.codex.start(args.get("project") if isinstance(args.get("project"), str) else None, str(args.get("prompt", ""))), None
        if name == "codex_follow_up":
            return await self.codex.follow_up(args.get("job"), str(args.get("message", ""))), None
        if name == "codex_status":
            return self.codex.status(), None
        if name == "codex_stop":
            return await self.codex.stop(args.get("job")), None
        if name == "codex_open":
            return self.codex.open(args.get("job")), None
        if name == "go_to_sleep":
            return "Going to sleep. Say a very short goodbye.", None
        return f"Unknown tool {name}.", None

    def _refusal(self) -> str | None:
        if not settings["computerControl"]:
            return "The user has turned off computer control in the menu. You can still look and point."
        if time.monotonic() < self.stopped_until:
            return "The user pressed stop. Don't do anything else until they ask again."
        if not self.overlay.available:
            return "Computer control needs the Bluey GNOME Shell extension, which isn't running. Tell the user."
        why = control.sanity()
        return f"I can't use the keyboard and mouse: {why}" if why else None

    async def _aim(self, x, y) -> None:
        """Warp and confirm: the user's own mouse can move the pointer between warp and click."""
        for _ in range(3):
            await self.overlay.warp(x, y)
            await asyncio.sleep(0.03)
            await self.overlay.refresh()
            px, py = self.overlay.pointer
            if abs(px - x) <= 2 and abs(py - y) <= 2:
                return
        raise control.ControlError("The pointer kept moving while I aimed, so I didn't click. Ask the user to keep the mouse still.")

    async def _fly(self, x, y):
        """His cursor flies there and the real mouse pointer glides along with it (and stays there)."""
        self.queue, self.cursor = [], (x, y)
        await self.overlay.refresh()
        sx, sy = self.overlay.pointer
        wait = await self.overlay.fly(x, y)
        steps = max(int(wait / 0.016), 1)
        for i in range(1, steps + 1):
            await self.overlay.warp(sx + (x - sx) * i / steps, sy + (y - sy) * i / steps)
            await asyncio.sleep(wait / steps)
        await asyncio.sleep(0.05)

    async def _action(self, name: str, args: dict) -> tuple[str, str | None]:
        try:
            if name == "move_mouse":
                spot = self._spot(args, "target_id", "x", "y")
                if not spot:
                    return "Tell me where to move the mouse: a target id from look_at_screen, or x and y.", None
                (x, y), label = spot
                await self._fly(x, y)
                await self._aim(x, y)
                await asyncio.sleep(0.3)
                return await self.look(f"Moved the mouse to {'that spot' if label == 'that spot' else repr(label)}.")
            if name == "click":
                spot = self._spot(args, "target_id", "x", "y")
                if not spot:
                    return "Tell me what to click: a target id from look_at_screen, or x and y.", None
                (x, y), label = spot
                right, count = bool(args.get("right")), 2 if args.get("double") else 1
                await self._fly(x, y)
                await self._aim(x, y)
                await asyncio.sleep(0.09)
                await control.click(right, count)
                await asyncio.sleep(0.44)
                verb = "Right-clicked" if right else "Double-clicked" if count == 2 else "Clicked"
                return await self.look(f"{verb} {'there' if label == 'that spot' else repr(label)}.")
            if name == "type_text":
                text = str(args.get("text", ""))
                if not text:
                    return "Nothing to type.", None
                # shortcut: no AT-SPI password-field check yet; the model is told never to type secrets.
                await control.type_text(text)
                if args.get("press_return"):
                    await asyncio.sleep(0.12)
                    await control.press("return")
                    await self.overlay.flash("↩")
                    await asyncio.sleep(0.55)
                    return await self.look("Typed it and pressed Return.")
                return "Typed it.", None
            if name == "press_keys":
                keys = str(args.get("keys", "")).strip()
                label = await control.press(keys)
                await self.overlay.flash(label)
                await asyncio.sleep(0.38)
                return await self.look(f"Pressed {keys}.")
            if name == "scroll":
                d = str(args.get("direction", "down")).lower()
                amount = min(max(_num(args.get("amount")) or 3, 1), 10)
                spot = self._spot(args, "target_id", "x", "y")
                w, h = self._size()
                x, y = spot[0] if spot else (w / 2, h / 2)
                px = int(amount * 120)
                dx, dy, arrow = {"up": (0, -px, "↑"), "left": (-px, 0, "←"), "right": (px, 0, "→")}.get(d, (0, px, "↓"))
                await self._fly(x, y)
                await self._aim(x, y)
                await self.overlay.flash(arrow)
                await control.scroll(dx, dy)
                await asyncio.sleep(0.28)
                return await self.look(f"Scrolled {d}.")
            if name == "drag":
                a = self._spot(args, "from_id", "from_x", "from_y")
                b = self._spot(args, "to_id", "to_x", "to_y")
                if not a or not b:
                    return "Tell me where to drag from and to (ids or x and y).", None
                (fx, fy), (tx, ty) = a[0], b[0]
                await self._fly(fx, fy)
                await self._aim(fx, fy)
                await control.button(True)
                await asyncio.sleep(0.12)
                for i in range(1, 21):  # the real drag follows the visible path
                    await self.overlay.warp(fx + (tx - fx) * i / 20, fy + (ty - fy) * i / 20)
                    await asyncio.sleep(0.016)
                await self.overlay.fly(tx, ty)
                await asyncio.sleep(0.08)
                await control.button(False)
                self.cursor = (tx, ty)
                await asyncio.sleep(0.34)
                return await self.look("Dragged it.")
            if name == "open_app":
                app = str(args.get("name", "")).strip()
                if not app:
                    return "Which app?", None
                await self.overlay.flash(f"Opening {app}")
                result = control.open_app(app)
                await asyncio.sleep(0.9)
                return await self.look(result)
            if name == "open_url":
                result = control.open_url(str(args.get("url", "")))
                await self.overlay.flash(result[7:-1] if result.startswith("Opened ") else "Hmm")
                await asyncio.sleep(1.1)
                return await self.look(result)
            return f"Unknown action {name}.", None
        finally:
            self.hold_until = time.monotonic() + 1.5
            if not self.speaking:
                self.quiet_since = time.monotonic()


def focus_countdown(session) -> str:
    if not session or session.status == "ended":
        return ""
    return ("Ⅱ " if session.status == "paused" else "") + clock(session.remaining) + ("  4×" if session.dev else "")
