"""Meeting notes as plain files any agent can read: ~/Documents/Bluey Notes/<date> <id>/ (Mac MeetingNotes.swift)."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

from . import ai

ROOT = Path.home() / "Documents" / "Bluey Notes"
README = """# Bluey Notes

Meeting notes recorded by the Bluey app (the blueberry on the phone). One folder per listening session, named by start time.

In each session folder:
- `notes.md`: the full transcript with timestamps and speaker labels, plus your questions to Bluey, Bluey's replies and any research reports, in time order. Start here.
- `session.json`: the same data, structured.
- `audio/`: the raw recording, as five-minute AAC chunks.

Speaker letters (A, B, …) are assigned per five-minute chunk, so the same letter can mean different people in different chunks. Lines marked "(live)" are a rough live transcript for audio that hasn't been fully transcribed yet.
"""


def folder(session: str, started: float) -> Path:
    ROOT.mkdir(parents=True, exist_ok=True)
    if not (ROOT / "README.md").exists():
        (ROOT / "README.md").write_text(README)
    tag = session[:8].lower()
    existing = next((p for p in ROOT.iterdir() if p.is_dir() and p.name.endswith(tag)), None)
    if existing:
        return existing
    path = ROOT / f"{datetime.fromtimestamp(started).strftime('%Y-%m-%d %H.%M')} {tag}"
    (path / "audio").mkdir(parents=True, exist_ok=True)
    return path


def _clock(t: float) -> str:
    return datetime.fromtimestamp(t).strftime("%H:%M:%S")


def markdown(j: dict) -> str:
    started = j["started"]
    out = [f"# Bluey session: {datetime.fromtimestamp(started).strftime('%Y-%m-%d %H:%M')}", ""]
    ended = j.get("ended")
    if isinstance(ended, (int, float)):
        minutes = int((ended - started) / 60)
        out.append(f"Ended {_clock(ended)} ({minutes // 60}h {minutes % 60}m).")
    else:
        out.append("Still recording.")
    pending = j.get("transcribing", 0)
    if isinstance(pending, int) and pending > 0:
        out.append(f"{pending} recording chunk(s) still being transcribed; this file updates when they're done.")
    entries = [e for e in j.get("entries", []) if isinstance(e, dict)]
    asked = sum(1 for e in entries if e.get("kind") == "asked")
    if asked:
        out.append(f"You asked Bluey {asked} question(s); they're marked inline below.")
    out += ["", "## Transcript", ""]
    for e in entries:
        text = str(e.get("text", "")).strip()
        if not text:
            continue
        t = _clock(e["time"]) if isinstance(e.get("time"), (int, float)) else ""
        kind = e.get("kind")
        if kind == "transcript":
            out.append(f"**[{t}] Speaker {e.get('speaker', '?')}:** {text}")
        elif kind == "heard":
            out.append(f"[{t}] (live) {text}")
        elif kind == "asked":
            out.append(f"> **[{t}] You asked Bluey:** {text}")
        elif kind == "reply":
            out.append(f"> **Bluey:** {text}")
        elif kind == "codex":
            out.append(f"> **[{t}] Codex:** {text}")
        elif kind == "report":
            out.append("> **Research report:**\n" + "\n".join("> " + line for line in text.split("\n")))
        else:
            out.append(f"[{t}] {text}")
        out.append("")
    return "\n".join(out)


def write(j: dict) -> Path | None:
    if not isinstance(j, dict) or not isinstance(j.get("id"), str) or not isinstance(j.get("started"), (int, float)):
        return None
    # The id names a folder: keep it to the UUID alphabet so it can't escape ROOT.
    if not all(c.isalnum() or c == "-" for c in j["id"]):
        return None
    path = folder(j["id"], j["started"])
    (path / "session.json").write_text(json.dumps(j, indent=2, sort_keys=True))
    (path / "notes.md").write_text(markdown(j))
    return path


async def transcribe(audio: bytes, session: str, index: int, session_started: float) -> tuple[list[dict], Path]:
    if not all(c.isalnum() or c == "-" for c in session):
        raise ValueError("bad session id")
    path = folder(session, session_started)
    (path / "audio").mkdir(exist_ok=True)
    (path / "audio" / f"chunk-{index:03d}.m4a").write_bytes(audio)
    raw = await ai.transcribe(audio)
    turns: list[dict] = []
    for seg in raw:  # join one speaker's consecutive pieces into a single turn
        if turns and turns[-1]["speaker"] == seg["speaker"] and seg["start"] - turns[-1]["end"] < 2.5:
            turns[-1]["text"] += " " + seg["text"]
            turns[-1]["end"] = seg["end"]
        else:
            turns.append(dict(seg))
    return turns, path
