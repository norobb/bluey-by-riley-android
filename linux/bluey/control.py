"""Using the computer for the user (Mac ComputerControl.swift).

Pointer position and precise warps come from the GNOME Shell extension (Wayland gives normal apps neither);
clicks, keys, typing and wheel go through the user's existing ydotoold (uinput, socket 0600).
"""
from __future__ import annotations

import asyncio
import shutil
import subprocess

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402

# Linux evdev key codes (input-event-codes.h).
KEYS = {
    "esc": 1, "escape": 1, "1": 2, "2": 3, "3": 4, "4": 5, "5": 6, "6": 7, "7": 8, "8": 9, "9": 10, "0": 11,
    "minus": 12, "-": 12, "equal": 13, "=": 13, "backspace": 14, "delete": 111, "tab": 15,
    "q": 16, "w": 17, "e": 18, "r": 19, "t": 20, "y": 21, "u": 22, "i": 23, "o": 24, "p": 25, "[": 26, "]": 27,
    "return": 28, "enter": 28, "ctrl": 29, "control": 29, "a": 30, "s": 31, "d": 32, "f": 33, "g": 34, "h": 35,
    "j": 36, "k": 37, "l": 38, ";": 39, "'": 40, "`": 41, "shift": 42, "\\": 43, "z": 44, "x": 45, "c": 46,
    "v": 47, "b": 48, "n": 49, "m": 50, ",": 51, ".": 52, "/": 53, "alt": 56, "option": 56, "space": 57,
    "capslock": 58, "f1": 59, "f2": 60, "f3": 61, "f4": 62, "f5": 63, "f6": 64, "f7": 65, "f8": 66, "f9": 67,
    "f10": 68, "f11": 87, "f12": 88, "home": 102, "up": 103, "pageup": 104, "left": 105, "right": 106,
    "end": 107, "down": 108, "pagedown": 109, "insert": 110, "super": 125, "meta": 125, "win": 125,
}
MODIFIERS = {"ctrl", "control", "shift", "alt", "option", "super", "meta", "win"}
ALIASES = {"cmd": "ctrl", "command": "ctrl", "opt": "alt", "del": "delete", "pgup": "pageup", "pgdn": "pagedown",
           "arrowup": "up", "arrowdown": "down", "arrowleft": "left", "arrowright": "right"}
# Shortcuts that log out, lock, power off or kill the session are left to the user.
REFUSED = {"ctrl+alt+delete", "ctrl+alt+backspace", "super+l", "ctrl+alt+l", "alt+f4+ctrl", "ctrl+alt+f1", "ctrl+alt+f2",
           "ctrl+alt+f3", "ctrl+alt+f4", "ctrl+alt+f5", "ctrl+alt+f6", "alt+sysrq"}


class ControlError(Exception):
    pass


def available() -> bool:
    return shutil.which("ydotool") is not None


async def _ydotool(*args: str) -> None:
    proc = await asyncio.create_subprocess_exec("ydotool", *args, stdout=asyncio.subprocess.DEVNULL,
                                                stderr=asyncio.subprocess.PIPE)
    _, err = await proc.communicate()
    if proc.returncode:
        raise ControlError("I can't use the keyboard and mouse: ydotoold isn't running. "
                           "Start it with: systemctl --user start ydotool")


def normalize(keys: str) -> str:
    parts = [ALIASES.get(p, p) for p in keys.lower().replace(" ", "").split("+") if p]
    return "+".join(parts)


async def press(keys: str) -> str:
    combo = normalize(keys)
    parts = combo.split("+")
    if combo in REFUSED or ("ctrl" in parts and "alt" in parts and ("delete" in parts or "backspace" in parts)):
        raise ControlError("I won't press that one (it logs out, locks or kills the session). Ask the user to do it.")
    codes = []
    for p in parts:
        if p not in KEYS:
            raise ControlError(f"I don't know the key \"{p}\".")
        codes.append(KEYS[p])
    seq = [f"{c}:1" for c in codes] + [f"{c}:0" for c in reversed(codes)]
    await _ydotool("key", *seq)
    return "+".join(p.capitalize() if len(p) > 1 else p.upper() for p in parts)


async def type_text(text: str) -> None:
    # A newline presses Return, as on the Mac.
    for i, chunk in enumerate(text.split("\n")):
        if i:
            await _ydotool("key", "28:1", "28:0")
        if chunk:
            await _ydotool("type", "--key-delay", "6", "--", chunk)


async def click(right: bool = False, count: int = 1) -> None:
    code = "0xC1" if right else "0xC0"  # button down+up
    await _ydotool("click", "--repeat", str(count), "--next-delay", "80", code)


async def button(down: bool) -> None:
    await _ydotool("click", "0x40" if down else "0x80")


async def scroll(dx: int, dy: int) -> None:
    # Wheel clicks: one notch ≈ 120 px on the Mac's pixel deltas.
    steps_y, steps_x = round(dy / 120), round(dx / 120)
    if steps_y:
        await _ydotool("mousemove", "--wheel", "--", "0", str(-steps_y))
    if steps_x:
        await _ydotool("mousemove", "--wheel", "--", str(steps_x), "0")


def open_url(url: str) -> str:
    url = url.strip()
    if not url:
        return "Which website?"
    if "://" not in url:
        url = "https://" + url
    if not url.startswith(("http://", "https://")):
        return "I only open web links."
    Gio.AppInfo.launch_default_for_uri(url, None)
    return f"Opened {url}."


def open_app(name: str) -> str:
    want = name.strip().lower()
    apps = [a for a in Gio.AppInfo.get_all() if a.should_show()]
    match = (next((a for a in apps if a.get_display_name().lower() == want), None)
             or next((a for a in apps if want in a.get_display_name().lower()), None)
             or next((a for a in apps if want in (a.get_id() or "").lower()), None))
    if not match:
        return f"Couldn't find an app called {name}."
    match.launch([], None)
    return f"Opened {match.get_display_name()}."


def sanity() -> str | None:
    """None when ydotoold answers; otherwise why not."""
    if not available():
        return "ydotool isn't installed."
    r = subprocess.run(["systemctl", "--user", "is-active", "ydotool"], capture_output=True, text=True)
    return None if r.stdout.strip() == "active" else "ydotoold isn't running."
