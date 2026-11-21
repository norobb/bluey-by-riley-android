"""GTK 4 / libadwaita windows: pairing QR, Gemini key, personality, research report (Mac panels)."""
from __future__ import annotations

import shutil
import subprocess

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Adw, Gdk, GLib, Gtk  # noqa: E402

from . import ai  # noqa: E402
from .config import settings  # noqa: E402


def _window(app: Adw.Application, title: str, child: Gtk.Widget, width=460, height=-1) -> Adw.Window:
    view = Adw.ToolbarView()
    view.add_top_bar(Adw.HeaderBar())
    view.set_content(child)
    win = Adw.Window(application=app, title=title, default_width=width, default_height=height, content=view)
    win.present()
    return win


def _box(margin=24, spacing=14) -> Gtk.Box:
    return Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=spacing, margin_top=margin, margin_bottom=margin,
                   margin_start=margin, margin_end=margin)


def pairing(app, qr_text: str) -> None:
    box = _box()
    box.append(Gtk.Label(label="Pair your phone", css_classes=["title-2"], xalign=0))
    box.append(Gtk.Label(label="On the phone choose Pair Mac and scan this code. Keep phone and computer on the same network. "
                               "Treat this code as a private pairing credential.", wrap=True, xalign=0))
    if shutil.which("qrencode"):
        png = subprocess.run(["qrencode", "-o", "-", "-t", "PNG", "-s", "8", "-m", "2", qr_text], capture_output=True).stdout
        texture = Gdk.Texture.new_from_bytes(GLib.Bytes.new(png))
        box.append(Gtk.Picture(paintable=texture, can_shrink=True, height_request=320))
    else:
        box.append(Gtk.Label(label="Install qrencode to show the code as a QR.", wrap=True))
    _window(app, "Pair phone", box)


def edit_key(app, on_saved) -> None:
    box = _box()
    box.append(Gtk.Label(label="Your Gemini API key stays on this computer (~/.config/bluey-linux/keys.json, private). "
                               "The phone only ever gets short-lived voice keys.", wrap=True, xalign=0))
    group = Adw.PreferencesGroup()
    row = Adw.PasswordEntryRow(title="Gemini API key")
    group.add(row)
    box.append(group)
    button = Gtk.Button(label="Save", css_classes=["suggested-action", "pill"], halign=Gtk.Align.END)
    box.append(button)
    win = _window(app, "Gemini key", box)

    error = Gtk.Label(label="", css_classes=["error"], xalign=0, wrap=True)
    box.insert_child_after(error, group)

    def save(_):
        if not ai.valid_key(row.get_text()):
            error.set_label("That doesn't look like a Gemini API key. Paste only the key from aistudio.google.com/apikey, without spaces or quotes.")
            return
        ai.set_api_key(row.get_text())
        on_saved()
        win.close()
    button.connect("clicked", save)
    row.connect("entry-activated", save)


def edit_personality(app) -> None:
    box = _box()
    box.append(Gtk.Label(label="Who he is. Tool and safety rules are always added after this.", wrap=True, xalign=0))
    buf = Gtk.TextBuffer(text=ai.personality())
    view = Gtk.TextView(buffer=buf, wrap_mode=Gtk.WrapMode.WORD_CHAR, top_margin=8, bottom_margin=8, left_margin=8, right_margin=8)
    box.append(Gtk.ScrolledWindow(child=view, min_content_height=200, vexpand=True))
    row = Gtk.Box(spacing=8, halign=Gtk.Align.END)
    reset, save = Gtk.Button(label="Reset"), Gtk.Button(label="Save", css_classes=["suggested-action"])
    row.append(reset)
    row.append(save)
    box.append(row)
    win = _window(app, "Personality", box, 520, 380)
    reset.connect("clicked", lambda _: buf.set_text(ai.DEFAULT_PERSONALITY))

    def store(_):
        text = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), False).strip()
        settings["personality"] = "" if text == ai.DEFAULT_PERSONALITY else text
        win.close()
    save.connect("clicked", store)


class ReportCard:
    """One window reused for loading → report or error (Mac ReportPanel)."""

    def __init__(self, app):
        self.app, self.win = app, None

    def show(self, report, loading: bool) -> None:
        box = _box(spacing=10)
        if loading:
            box.append(Gtk.Label(label="Doing some research…", css_classes=["title-3"], xalign=0))
            box.append(Gtk.Label(label=str(report), wrap=True, xalign=0, css_classes=["dim-label"]))
            box.append(Gtk.Spinner(spinning=True, halign=Gtk.Align.START))
        elif isinstance(report, str):
            box.append(Gtk.Label(label=report, wrap=True, xalign=0))
        else:
            box.append(Gtk.Label(label=report["title"], css_classes=["title-2"], wrap=True, xalign=0))
            for p in report["paragraphs"]:
                box.append(Gtk.Label(label=p, wrap=True, xalign=0, selectable=True))
            for title, url in report["sources"]:
                box.append(Gtk.LinkButton(uri=url, label=title[:80], halign=Gtk.Align.START))
        scroll = Gtk.ScrolledWindow(child=box, propagate_natural_height=True, max_content_height=600)
        if self.win is None or not self.win.get_visible():
            self.win = _window(self.app, "Bluey research", scroll, 520)
        else:
            self.win.get_content().set_content(scroll)
            self.win.present()
