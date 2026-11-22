"""Screen capture and reading (Mac ScreenReader.swift).

Capture: XDG Desktop Portal Screenshot (non-interactive). The file the portal writes is read and deleted at once.
Text: Tesseract when installed. shortcut: without it, look_at_screen returns only the image, so the model
points by grid (point_at_spot); install `tesseract` + `tesseract-data-eng` to get L/W target ids.
Coordinates: everything is in logical stage pixels (what the overlay and pointer use).
"""
from __future__ import annotations

import asyncio
import shutil
from pathlib import Path
from urllib.parse import unquote, urlparse

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, Gio, GLib  # noqa: E402

_counter = 0


async def _portal_screenshot() -> str:
    global _counter
    _counter += 1
    bus = Gio.bus_get_sync(Gio.BusType.SESSION)
    token = f"bluey{_counter}"
    sender = bus.get_unique_name()[1:].replace(".", "_")
    path = f"/org/freedesktop/portal/desktop/request/{sender}/{token}"
    loop = asyncio.get_running_loop()
    fut = loop.create_future()

    def response(_c, _s, _p, _i, _sig, params):
        if not fut.done():
            fut.set_result(params.unpack())

    sid = bus.signal_subscribe(None, "org.freedesktop.portal.Request", "Response", path, None, 0, response)
    try:
        bus.call_sync("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Screenshot",
                      "Screenshot", GLib.Variant("(sa{sv})", ("", {"handle_token": GLib.Variant("s", token),
                                                                    "interactive": GLib.Variant("b", False)})),
                      None, 0, 10_000, None)
        code, results = await asyncio.wait_for(fut, 15)
    finally:
        bus.signal_unsubscribe(sid)
    if code != 0 or "uri" not in results:
        raise RuntimeError("I can't see the screen. The screenshot permission was refused.")
    return unquote(urlparse(results["uri"]).path)


def _read_and_delete(path: str) -> GdkPixbuf.Pixbuf:
    try:
        return GdkPixbuf.Pixbuf.new_from_file(path)
    finally:
        Gio.File.new_for_path(path).delete(None)  # the portal saves into ~/Pictures; screenshots must not persist


def _jpeg(pix: GdkPixbuf.Pixbuf, max_edge: int = 1100) -> bytes:
    w, h = pix.get_width(), pix.get_height()
    scale = min(1.0, max_edge / max(w, h))
    small = pix.scale_simple(max(1, round(w * scale)), max(1, round(h * scale)), GdkPixbuf.InterpType.HYPER)
    ok, data = small.save_to_bufferv("jpeg", ["quality"], ["72"])
    return bytes(data)


async def _ocr(pix: GdkPixbuf.Pixbuf, factor: float) -> list[tuple[dict, list[dict]]]:
    """Tesseract TSV → lines with words, in logical coordinates. Empty when Tesseract isn't installed."""
    if not shutil.which("tesseract"):
        return []
    ok, png = pix.save_to_bufferv("png", [], [])
    langs = ["-l", "deu+eng"] if Path("/usr/share/tessdata/deu.traineddata").exists() else []  # German UI text too
    proc = await asyncio.create_subprocess_exec("tesseract", "stdin", "stdout", *langs, "tsv", stdin=asyncio.subprocess.PIPE,
                                                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
    out, _ = await proc.communicate(bytes(png))
    lines: dict[tuple, list[dict]] = {}
    for row in out.decode(errors="replace").splitlines()[1:]:
        f = row.split("\t")
        if len(f) < 12 or f[0] != "5" or not f[11].strip() or float(f[10]) < 30:
            continue
        x, y, w, h = (int(v) / factor for v in f[6:10])
        lines.setdefault((f[2], f[3], f[4]), []).append({"text": f[11].strip(), "x": x, "y": y, "w": w, "h": h})
    result, words_total = [], 0
    for i, ws in enumerate(sorted(lines.values(), key=lambda ws: (round(ws[0]["y"] / 8), ws[0]["x"]))[:400]):
        x0, y0 = min(w["x"] for w in ws), min(w["y"] for w in ws)
        x1, y1 = max(w["x"] + w["w"] for w in ws), max(w["y"] + w["h"] for w in ws)
        line = {"id": f"L{i + 1}", "text": " ".join(w["text"] for w in ws), "x": x0, "y": y0, "w": x1 - x0, "h": y1 - y0}
        words = []
        if words_total < 600:
            for w in ws:
                words_total += 1
                words.append({**w, "id": f"W{words_total}"})
        result.append((line, words))
    return result


class Snapshot:
    def __init__(self, jpeg: bytes, lines, size: tuple[float, float], app: str | None):
        self.jpeg, self.lines, self.size, self.app = jpeg, lines, size, app

    def target(self, id: str) -> dict | None:
        id = id.strip().upper()
        for line, words in self.lines:
            if line["id"] == id:
                return line
            for w in words:
                if w["id"] == id:
                    return w
        return None

    def target_near(self, px: float, py: float) -> dict | None:
        cands = [t for line, words in self.lines for t in [line, *words]]
        hits = [t for t in cands if t["x"] - 6 <= px <= t["x"] + t["w"] + 6 and t["y"] - 6 <= py <= t["y"] + t["h"] + 6]
        if hits:
            return min(hits, key=lambda t: t["w"] * t["h"])

        def dist(t):
            return ((max(t["x"] - px, 0, px - t["x"] - t["w"])) ** 2 + (max(t["y"] - py, 0, py - t["y"] - t["h"])) ** 2) ** 0.5
        near = [t for t in cands if dist(t) < 60]
        return min(near, key=dist) if near else None

    def find(self, id: str, quote: str) -> dict | None:
        """Nudge target: an L line whose text matches exactly and lies on screen."""
        t = self.target(id) if id.upper().startswith("L") else None
        if t and t["text"] == quote and 0 <= t["x"] and t["x"] + t["w"] <= self.size[0] and 0 <= t["y"] and t["y"] + t["h"] <= self.size[1]:
            return {**t, "x": t["x"] + t["w"] / 2, "y": t["y"] + t["h"] / 2, "rect": (t["x"], t["y"], t["w"], t["h"])}
        return None

    @property
    def text(self) -> str:
        return "\n".join(line["text"] for line, _ in self.lines[:140])

    @property
    def target_list(self) -> str:
        W, H = self.size

        def grid(t):
            return f"@{int((t['x'] + t['w'] / 2) / W * 1000)},{int((t['y'] + t['h'] / 2) / H * 1000)}"
        out = [f"Frontmost app: {self.app}"] if self.app else []
        out.append("Text on screen (L = line, W = word, @x,y on a 0-1000 grid):")
        if not self.lines:
            out.append("(no text found: text reading isn't available on this computer, so use the screenshot and point_at_spot)")
        for line, words in self.lines:
            extra = " | " + " ".join(f"{w['id']}={w['text']}" for w in words) if len(words) > 1 else ""
            out.append(f"{line['id']} {grid(line)} \"{line['text']}\"{extra}")
        return "\n".join(out)

    def as_capture(self) -> dict:
        """The shape FocusCompanion expects."""
        return {"jpeg": self.jpeg, "app": self.app, "text": self.text, "targets": self.target_list, "find": self.find}


async def snapshot(stage_size: tuple[float, float] | None, app: str | None, hide_overlay=None) -> Snapshot:
    if hide_overlay:
        await hide_overlay(True)  # like the Mac, Bluey's own cursor and bubble aren't in the picture
    try:
        path = await _portal_screenshot()
    finally:
        if hide_overlay:
            await hide_overlay(False)
    pix = await asyncio.to_thread(_read_and_delete, path)
    size = stage_size or (float(pix.get_width()), float(pix.get_height()))
    factor = pix.get_width() / size[0]
    lines = await _ocr(pix, factor)
    return Snapshot(await asyncio.to_thread(_jpeg, pix), lines, size, app)


async def idle_seconds() -> float:
    """Mutter's idle monitor (CGEventSource idle time on the Mac)."""
    try:
        bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        r = bus.call_sync("org.gnome.Mutter.IdleMonitor", "/org/gnome/Mutter/IdleMonitor/Core", "org.gnome.Mutter.IdleMonitor",
                          "GetIdletime", None, GLib.VariantType("(t)"), 0, 2000, None)
        return r.unpack()[0] / 1000
    except GLib.Error:
        return 0.0
