"""Local speech-to-text with Parakeet through an existing Voxtype install (`engine = "parakeet"` and its GGUF
model configured in ~/.config/voxtype/config.toml). Audio never leaves the PC."""
from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
import wave
from pathlib import Path

VOXTYPE = shutil.which("voxtype") or str(Path.home() / ".local/bin/voxtype")
RATE = 16_000
MAX_SECONDS = 60


def available() -> bool:
    return os.access(VOXTYPE, os.X_OK)


def parse(stdout: str) -> str:
    """`voxtype transcribe` prints status lines, a blank line, then the text."""
    lines = stdout.splitlines()
    start = next((i + 1 for i, l in enumerate(lines) if l.startswith("Processing ")), 0)
    return " ".join(l.strip() for l in lines[start:] if l.strip())


async def transcribe(pcm: bytes) -> str:
    """16 kHz mono PCM16 → text. Raises ValueError for unusable audio, RuntimeError if Voxtype fails."""
    if len(pcm) % 2 or not 3200 <= len(pcm) <= RATE * 2 * MAX_SECONDS:
        raise ValueError("audio must be 0.1–60 s of 16 kHz PCM16")
    # Private file on tmpfs, deleted right after; Voxtype only reads WAV files.
    fd, path = tempfile.mkstemp(prefix="bluey-", suffix=".wav", dir=os.environ.get("XDG_RUNTIME_DIR"))
    try:
        with os.fdopen(fd, "wb") as f, wave.open(f, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(pcm)
        proc = await asyncio.create_subprocess_exec(VOXTYPE, "-q", "transcribe", "--engine", "parakeet", path,
                                                    stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL)
        out, _ = await asyncio.wait_for(proc.communicate(), 30)
        if proc.returncode:
            raise RuntimeError("Voxtype couldn't transcribe")
        return parse(out.decode(errors="replace"))
    finally:
        os.unlink(path)
