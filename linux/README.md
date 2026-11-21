# Bluey host for Linux (GNOME/Wayland)

Port of the Mac app (`../bluey-by-riley/Mac`). Wire-compatible with the original iPhone app and with `../android`.

## Run

```sh
cd ~/Projects/googly-eyes/linux
python3 -m bluey.app --pair        # first time: shows the pairing QR
python3 -m bluey.app               # afterwards
python3 -m unittest discover -s tests
```

Autostart: user unit `~/.config/systemd/user/bluey.service` (enabled for `graphical-session.target`).
`systemctl --user restart bluey`, logs with `journalctl --user -u bluey -f`.

Needs: Python 3 with PyGObject (GTK 4, libadwaita), `python-cryptography`, avahi-daemon + `avahi-publish`, `qrencode`,
a Google Gemini API key (entered in the app, stored in `~/.config/bluey-linux/keys.json`),
xdg-desktop-portal (GNOME), `ydotool` with a running `ydotoold` (computer control), optional `codex` and `tesseract`.
The GNOME Shell extension in `gnome-extension/bluey@googly-eyes` (symlinked into `~/.local/share/gnome-shell/extensions`)
loads after logging out and back in.

Firewall: the phone connects to TCP port 47321 (fixed, `--port`). With ufw's default "deny incoming" you need
`sudo ufw allow from 192.168.0.0/16 to any port 47321 proto tcp` (adjust to your LAN).

## What maps to what

| Mac | Linux |
|---|---|
| NWListener + Bonjour | asyncio TCP + `avahi-publish` |
| Menu bar item | Panel menu from the extension |
| Cursor overlay, speech bubble, countdown | Extension (St/Clutter actors in the shell) |
| `NSEvent.mouseLocation`, frontmost app | Extension `GetState` |
| ScreenCaptureKit | XDG portal Screenshot (non-interactive; the file is deleted right after reading) |
| Vision OCR | Tesseract if installed, otherwise none (the model points by grid) |
| CGEvent click/keys/scroll | Extension `Warp` for position + `ydotool` for buttons, keys, wheel, typing |
| Accessibility controls (C ids) | Not ported (AT-SPI on Wayland gives no reliable screen coordinates) |
| OpenAI Decisions/Responses/Realtime/transcription | Gemini `generateContent` (JSON schema, Google Search grounding, audio) and Live API tokens (`ai.py`) |
| (voice turns streamed to OpenAI) | Held speech transcribed locally by Parakeet Ultra via `voxtype transcribe` (`stt.py`), only text goes to Gemini |
| Keychain / support files | `~/.config/bluey-linux/` (0700 dir, 0600 files) |
| ⌥Space, ⌃⌥P/F/D/H/S | Ctrl+Alt+Space, Ctrl+Alt+P/F/D/H/S (Alt+Space is GNOME's window menu) |
| Codex app deep links | Opens the job folder (no Codex desktop app on Linux) |
| Lock / sleep notifications | `org.gnome.ScreenSaver.ActiveChanged`, logind `PrepareForSleep` |

The extension's D-Bus methods (pointer, focused app, warp) are reachable by any process of the same user on the
session bus. It never clicks, types or captures the screen itself.

Codex runs like on the Mac: `danger-full-access`, no approvals, started by voice. Set `"codexFullAccess": false`
in `~/.config/bluey-linux/settings.json` to use `workspace-write` instead.
