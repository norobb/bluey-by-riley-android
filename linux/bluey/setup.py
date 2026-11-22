"""`bluey setup`: the per-user steps a package can't do (pacman runs as root and doesn't know the user)."""
from __future__ import annotations

import ast
import os
import shutil
import subprocess

UUID = "bluey@googly-eyes"


def with_extension(gsettings_value: str) -> list[str] | None:
    """`gsettings get` output ("['a']" or "@as []") → list with Bluey added, or None if it's already there."""
    current = ast.literal_eval(gsettings_value.strip().removeprefix("@as").strip() or "[]")
    return None if UUID in current else [*current, UUID]


def _run(*cmd: str) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


def _step(ok: bool, text: str) -> bool:
    print(("  ✓ " if ok else "  ✗ ") + text)
    return ok


def run() -> int:
    if os.geteuid() == 0:
        print("Run `bluey setup` as your normal user, not with sudo.")
        return 1
    print("Setting up Bluey for this user:")
    ok = True

    # Written straight to GSettings so it also works before the shell has seen a freshly installed extension.
    got = _run("gsettings", "get", "org.gnome.shell", "enabled-extensions")
    if got.returncode:
        ok &= _step(False, "GNOME Shell extension: gsettings isn't available (is this a GNOME session?)")
    else:
        new = with_extension(got.stdout)
        if new is not None:
            got = _run("gsettings", "set", "org.gnome.shell", "enabled-extensions", str(new))
        ok &= _step(got.returncode == 0, "GNOME Shell extension enabled (active after logging out and back in)")

    if shutil.which("ydotool"):
        r = _run("systemctl", "--user", "enable", "--now", "ydotool.service")
        ok &= _step(r.returncode == 0, "ydotool running (Bluey can click, type and scroll)" if r.returncode == 0
                    else f"ydotool: {r.stderr.strip() or 'could not start'}")
    else:
        _step(False, "ydotool not installed: computer control stays off (install the ydotool package)")

    r = _run("systemctl", "--user", "enable", "--now", "bluey.service")
    ok &= _step(r.returncode == 0, "Bluey starts with your session and is running now" if r.returncode == 0
                else f"autostart: {r.stderr.strip() or 'bluey.service not found'}")

    print("\nNext:\n"
          "  1. Log out and back in once, so GNOME loads the extension (Bluey's menu appears in the top bar).\n"
          "  2. In that menu choose \"Pair phone\" (or run `bluey --pair`) and scan the code with the phone app.\n"
          "  3. Firewall: the phone connects to TCP 47321. With ufw, for example:\n"
          "     sudo ufw allow from 192.168.0.0/16 to any port 47321 proto tcp")
    return 0 if ok else 1
