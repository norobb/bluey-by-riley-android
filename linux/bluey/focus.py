"""Host-authoritative focus (Shared/FocusSession.swift + Mac FocusCompanion.swift), Swift-Codable JSON shape."""
from __future__ import annotations

import asyncio
import json
import math
import time
import uuid
from pathlib import Path
from typing import Awaitable, Callable

from .config import read_json, write_private

APPLE_EPOCH = 978_307_200.0  # Swift Date's Codable form is seconds since 2001-01-01
FALLBACK_NUDGE = "Are you sure you're on task right now?"


def apple_now() -> float:
    return time.time() - APPLE_EPOCH


def clock(seconds: float) -> str:
    n = max(0, math.ceil(seconds))
    return f"{n // 60:02d}:{n % 60:02d}"


def new_id() -> str:
    return str(uuid.uuid4()).upper()


class FocusSession:
    def __init__(self, task: str, duration: float = 1800, developer_mode: bool = False):
        self.d = {
            "id": new_id(), "task": task[:500], "duration": min(14400, max(60, duration)),
            "startedAt": apple_now(), "elapsed": 0.0, "status": "running", "detail": "", "checks": [],
            "developerMode": developer_mode, "usedDeveloperMode": developer_mode, "realElapsed": 0.0,
        }
        self.d["detail"] = f"First check in {int(self.check_interval)} seconds"

    dev = property(lambda s: s.d.get("developerMode") is True)
    clock_rate = property(lambda s: 4.0 if s.dev else 1.0)
    check_interval = property(lambda s: 10.0 if s.dev else 30.0)
    observation = property(lambda s: s.check_interval * s.clock_rate)
    real_active = property(lambda s: s.d.get("realElapsed", s.d["elapsed"]))
    remaining = property(lambda s: max(0.0, s.d["duration"] - s.d["elapsed"]))
    status = property(lambda s: s.d["status"])

    def advance(self, seconds: float) -> None:
        if self.status != "running" or not math.isfinite(seconds) or seconds <= 0:
            return
        self.d["realElapsed"] = self.real_active + min(seconds, self.remaining / self.clock_rate)
        self.d["elapsed"] = min(self.d["duration"], self.d["elapsed"] + seconds * self.clock_rate)
        if self.d["elapsed"] >= self.d["duration"]:
            self.d["status"], self.d["detail"] = "ended", "Time's up. Lovely bit of focus."

    def pause(self, reason: str) -> None:
        if self.status != "running":
            return
        self.d["status"], self.d["detail"] = "paused", reason
        self.d["checks"].append(check(self.d["elapsed"], "paused"))

    def resume(self) -> None:
        if self.status == "paused":
            self.d["status"], self.d["detail"] = "running", f"Resumed. Next check in {int(self.check_interval)} seconds"

    def set_developer_mode(self, enabled: bool) -> None:
        self.d["developerMode"] = enabled
        if enabled:
            self.d["usedDeveloperMode"] = True

    def end(self) -> None:
        self.d["status"], self.d["detail"] = "ended", "Session finished"


def check(elapsed, activity, probability=0.0, confidence=0.0, probabilities=None, sample=None) -> dict:
    c = {"id": new_id(), "elapsed": elapsed, "activity": activity, "probability": probability,
         "confidence": confidence, "nudged": False}
    if probabilities is not None:
        c["probabilities"] = probabilities
    if sample is not None:
        c["sampleDuration"] = sample
    return c


class NudgePolicy:
    """FocusNudgePolicy: consecutive fresh majority off-task checks over a probability-scaled span."""

    def __init__(self, maximum_gap: float = 45, developer_mode: bool = False):
        self.run: list[dict] = []
        self.last_nudge = -math.inf
        self.maximum_gap, self.developer_mode = maximum_gap, developer_mode

    def reset(self):
        self.run = []

    def observe(self, c: dict, age: float) -> bool:
        p, conf, e = c["probability"], c["confidence"], c["elapsed"]
        if not (0 <= age <= 20 and math.isfinite(e) and c["activity"] == "off_task" and math.isfinite(p)
                and math.isfinite(conf) and 0.5 <= p <= 1 and 0 <= conf <= 1):
            self.reset()
            return False
        if self.run:
            if e <= self.run[-1]["elapsed"]:
                self.reset()
                return False
            if e - self.run[-1]["elapsed"] > self.maximum_gap:
                self.reset()
        self.run.append(c)
        strength = sum(x["probability"] for x in self.run) / len(self.run)
        lo, hi = (40.0, 80.0) if self.developer_mode else (120.0, 240.0)
        required = lo if strength >= 0.95 else hi - max(0, strength - 0.5) / 0.45 * (hi - lo)
        if len(self.run) < 2 or e - self.run[0]["elapsed"] < max(lo, required) or e - self.last_nudge < 120:
            return False
        self.last_nudge = e
        self.reset()
        return True


Capture = Callable[[], Awaitable[dict]]  # {"jpeg", "app", "text", "targets", "find(id, quote)"}


class FocusCompanion:
    """The host owns the clock, check cadence and cancellation. Generations discard late results."""

    def __init__(self, state_dir: Path, settings, now: Callable[[], float] = time.monotonic,
                 capture: Capture | None = None, classify=None, prepare_nudge=None,
                 idle: Callable[[], Awaitable[float]] | None = None, has_key: Callable[[], bool] = lambda: True):
        self.now, self.settings = now, settings
        self.capture, self.classify, self.prepare_nudge, self.idle, self.has_key = capture, classify, prepare_nudge, idle, has_key
        self.file = state_dir / "focus-history.json"
        self.current: FocusSession | None = None
        self.history: list[dict] = read_json(self.file) or []
        self.revision = 0
        self.connected = False
        self.locked = False
        self.last_ping = -math.inf
        self.last_tick = now()
        self.last_check = 0.0
        self.generation = 0
        self.work: asyncio.Task | None = None
        self.developer_mode = bool(settings["focusDeveloperMode"])
        self.policy = NudgePolicy()
        self.on_change: Callable[[str], None] | None = None
        self.on_nudge: Callable[[str, dict | None], None] | None = None
        self.on_publish: Callable[["FocusSession | None"], None] | None = None

    fresh = property(lambda s: s.connected and s.now() - s.last_ping < 5)
    has_session = property(lambda s: s.current is not None and s.current.status != "ended")
    monitoring = property(lambda s: s.current is not None and s.current.status == "running")
    allowed = property(lambda s: s.monitoring and s.fresh and not s.locked)

    def heartbeat(self) -> None:
        self.last_ping = self.now()
        self.connected = True
        if not self.monitoring:
            self.publish()

    def disconnected(self) -> None:
        self.connected = False
        self.pause("Phone disconnected. Reconnect, then resume.")

    def _cancel(self):
        self.generation += 1
        if self.work:
            self.work.cancel()
        self.work = None

    def _advance(self) -> None:
        t = self.now()
        delta, self.last_tick = t - self.last_tick, t
        if self.current and delta <= 3:  # a suspended loop is not evidence of active focus time
            self.current.advance(delta)

    def tick(self) -> None:
        """Call once a second."""
        if not self.monitoring:
            return
        if not self.fresh:
            self.pause("Phone disconnected. Reconnect, then resume.")
            return
        if self.locked:
            self.pause("Computer locked. Resume when ready.")
            return
        if self.now() - self.last_tick > 3:
            self.pause("Computer was inactive. Resume when ready.")
            return
        self._advance()
        if self.current.status == "ended":
            self._finish()
            return
        self.publish()
        s = self.current
        if s.d["elapsed"] - self.last_check >= s.observation and self.work is None and self.capture:
            self.last_check = s.d["elapsed"]
            self.work = asyncio.ensure_future(self._check(self.generation, json.loads(json.dumps(s.d)), s.observation))

    async def _check(self, token: int, session: dict, observation: float) -> None:
        began = self.now()
        live = lambda: self.allowed and self.generation == token  # noqa: E731
        try:
            if not live():
                return
            screen = await self.capture()
            if not live():
                return
            idle = await self.idle() if self.idle else 0.0
            answer = await self.classify(screen["jpeg"], session, idle, screen.get("app"), screen.get("text", ""))
            if not live():
                return
            age = self.now() - began
            fresh = age <= 20
            c = check(session["elapsed"], answer["activity"] if fresh else "unavailable", answer["probability"],
                      answer["confidence"], answer["probabilities"] if fresh else None, observation)
            nudge = self.policy.observe(c, age)
            self.current.d["detail"] = ("Last check was stale; skipped" if not fresh else "Not enough context to judge"
                                        if answer["activity"] == "uncertain" else "On task" if answer["activity"] == "on_task"
                                        else "Off task · checking again before nudging")
            self.current.d["checks"].append(c)
            self.publish(); self.persist()
            if nudge:
                await self._nudge(token, session["task"], c, live)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            if not live():
                return
            self.policy.reset()
            self.current.d["checks"].append(check(session["elapsed"], "unavailable", sample=observation))
            self.current.d["detail"] = f"Check unavailable: {str(e)[:180]}"
            self.publish(); self.persist()
            from .ai import Failure  # auth/permission issues need the user, not repeated paid calls
            if isinstance(e, Failure):
                self.pause(self.current.d["detail"])
        finally:
            if self.generation == token:
                self.work = None

    async def _nudge(self, token, task, c, live) -> None:
        message, target = FALLBACK_NUDGE, None
        self.current.d["detail"] = "Off task · preparing a gentle nudge"
        self.publish()
        try:
            fresh = await self.capture()
            if not live():
                return
            captured = self.now()
            message, tid, quote = await self.prepare_nudge(fresh["jpeg"], task, fresh.get("targets", ""))
            if tid and quote and self.now() - captured < 15:
                # Re-read to reject a stale target after a tab, scroll or layout change.
                found = fresh["find"](tid, quote)
                verify = await self.capture() if found else None
                target = verify["find"](tid, quote) if verify else None
                if target and found and (abs(target["x"] - found["x"]) >= 10 or abs(target["y"] - found["y"]) >= 10):
                    target = None
        except Exception:
            self.current.d["detail"] = "Off task · using a gentle reminder"
        if not live():
            return
        if self.on_nudge:
            self.on_nudge(message, target)
        self.current.d["detail"] = "Off task · Bluey nudged you"
        c["nudged"] = True
        self.publish(); self.persist()

    def start(self, task: str, minutes: float = 30) -> str:
        task = task.strip()
        if not task:
            return "Tell me the task first."
        if not math.isfinite(minutes):
            return "Use a duration between 1 and 240 minutes."
        if self.has_session:
            return "There's already a focus session. End it before starting another."
        if not self.fresh:
            return "Connect the paired phone first."
        if not self.has_key():
            return "Add your Gemini key in Bluey's menu."
        self._cancel()
        m = min(240, max(1, minutes))
        self.current = FocusSession(task, m * 60, self.developer_mode)
        self.policy = NudgePolicy(self.current.observation * 1.5, self.developer_mode)
        self.last_tick, self.last_check = self.now(), 0.0
        self.publish(); self.persist()
        return f"Focus started: {task}, {int(m)} minutes."

    def pause(self, reason: str = "Paused") -> str:
        if not self.monitoring:
            return "Focus is already paused or ended."
        self._advance(); self.current.pause(reason); self._cancel(); self.policy.reset(); self.publish(); self.persist()
        return "Focus paused."

    def resume(self) -> str:
        if not (self.current and self.current.status == "paused"):
            return "There's no paused focus session."
        if not self.fresh:
            return "Reconnect the paired phone before resuming."
        self.current.resume(); self.policy.reset(); self._cancel()
        self.last_tick, self.last_check = self.now(), self.current.d["elapsed"]
        self.publish(); self.persist()
        return "Focus resumed."

    def end(self) -> str:
        if not self.has_session:
            return "There's no running focus session."
        self._advance(); self.current.end(); self._finish()
        return "Focus finished. Your timeline is on the phone."

    def test_nudge(self) -> str:
        if not (self.developer_mode and self.fresh):
            return "Enable Developer Mode and connect the phone first."
        if self.on_nudge:
            self.on_nudge("Oi, back to the mission. This is your test nudge.", None)
        return "Test nudge sent to the computer and phone."

    def set_developer_mode(self, enabled: bool) -> str:
        if enabled == self.developer_mode:
            return f"Developer Mode is already {'on' if enabled else 'off'}."
        if self.monitoring:
            self._advance()
        self._cancel()
        self.developer_mode = enabled
        self.settings["focusDeveloperMode"] = enabled
        if self.has_session:
            self.current.set_developer_mode(enabled)
            self.current.d["detail"] = "Developer Mode: clock 4×, next check in 10 seconds" if enabled else "Normal speed. Next check in 30 seconds"
        self.policy = NudgePolicy((self.current.observation if self.current else (40 if enabled else 30)) * 1.5, enabled)
        self.last_tick = self.now()
        self.last_check = self.current.d["elapsed"] if self.current else 0.0
        if self.current and self.current.status == "ended":
            self._finish()
        else:
            self.publish(); self.persist()
        return "Developer Mode on: clock 4×, checks every 10 seconds." if enabled else "Developer Mode off: normal clock, checks every 30 seconds."

    def _finish(self) -> None:
        self._cancel(); self.policy.reset()
        if self.current:
            self.history = [h for h in self.history if h["id"] != self.current.d["id"]]
            self.history.insert(0, dict(self.current.d))
            self.history = self.history[:30]
        self.publish(); self.persist()

    def persist(self) -> None:
        saved = list(self.history)
        if self.current and self.current.status != "ended":
            s = dict(self.current.d, status="ended", detail="App closed or restarted")
            saved = [h for h in saved if h["id"] != s["id"]]
            saved.insert(0, s)
        write_private(self.file, saved[:30])

    def sync_text(self) -> str:
        return json.dumps({"current": self.current.d if self.current else None, "history": self.history,
                           "revision": self.revision, "sentAt": apple_now(), "developerMode": self.developer_mode},
                          separators=(",", ":"))

    def publish(self) -> None:
        self.revision += 1
        if self.on_publish:
            self.on_publish(self.current)
        if self.on_change:
            self.on_change(self.sync_text())

    def status_line(self) -> str:
        s = self.current
        if not s:
            return "No focus session yet."
        return f"Task: {s.d['task']}. {s.status}, {clock(s.remaining)} remaining. {s.d['detail']}"

    def handle(self, command: str, args: dict) -> str:
        self.heartbeat()
        if command == "focusStart":
            m = args.get("minutes", 30)
            task = args.get("task", "")
            return self.start(task if isinstance(task, str) else "",
                              float(m) if isinstance(m, (int, float)) and not isinstance(m, bool) else 30)
        if command == "focusPause":
            return self.pause()
        if command == "focusResume":
            return self.resume()
        if command == "focusEnd":
            return self.end()
        if command == "focusTestNudge":
            return self.test_nudge()
        if command == "focusDeveloperMode":
            v = args.get("developerMode")
            return self.set_developer_mode(v) if isinstance(v, bool) else "Specify whether Developer Mode is on or off."
        if command == "focusSync":
            self.publish()
        return ""
