"""Private state in ~/.config/bluey-linux (0700 dir, 0600 files), like the Mac's support folder."""
from __future__ import annotations

import json
import os
from pathlib import Path

STATE = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "bluey-linux"
STATE.mkdir(mode=0o700, parents=True, exist_ok=True)


def read_json(path: Path):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return None


def write_private(path: Path, value) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(value, f)
    os.replace(tmp, path)


class Settings:
    """Menu choices kept between launches (Mac Settings.swift)."""
    DEFAULTS = {"followMouse": True, "computerControl": True, "captions": True, "phonePosition": 0.5,
                "focusDeveloperMode": False, "personality": "", "codexFolders": []}

    def __init__(self):
        self.path = STATE / "settings.json"
        self.values = {**self.DEFAULTS, **(read_json(self.path) or {})}

    def __getitem__(self, key):
        return self.values[key]

    def __setitem__(self, key, value):
        self.values[key] = value
        write_private(self.path, self.values)


settings = Settings()
