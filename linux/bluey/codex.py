"""Codex jobs via one `codex app-server` process (JSON-RPC over stdio). Port of Mac CodexController.swift.

Like the original: threads run in ~/Documents/Bluey with sandbox "danger-full-access" and approvalPolicy "never";
codex_stop and the stop hotkey are the brakes. Set settings["codexFullAccess"] = False for "workspace-write".
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Callable

from .config import settings

BLUEY = Path.home() / "Documents" / "Bluey"


def short(text: str, limit: int = 300) -> str:
    flat = text.replace("\n", " ").strip()
    return flat[:limit] + "…" if len(flat) > limit else flat


def key(text: str) -> str:
    return "".join(c for c in text.lower() if c.isalnum())


def projects() -> list[dict]:
    """Git repos two levels under ~/Documents and ~/Projects, plus folders added in settings."""
    found: list[str] = []

    def scan(d: Path, depth: int):
        try:
            children = [c for c in d.iterdir() if c.is_dir() and not c.name.startswith(".")]
        except OSError:
            return
        for c in children:
            if (c / ".git").is_dir():
                found.append(str(c))
            elif depth > 1:
                scan(c, depth - 1)

    for root in (Path.home() / "Documents", Path.home() / "Projects"):
        scan(root, 2)
    out = []
    for p in list(settings["codexFolders"]) + found:
        if p in [x["path"] for x in out]:
            continue
        aliases = []
        try:
            m = re.search(r"url = .*/([^/\s]+?)(\.git)?\s*$", (Path(p) / ".git" / "config").read_text(), re.M)
            if m:
                aliases.append(m.group(1))
        except OSError:
            pass
        out.append({"name": Path(p).name, "path": p, "aliases": aliases})
    return out


def resolve(query: str):
    q = key(query)
    if not q:
        return None
    ps = projects()
    exact = [p for p in ps if key(p["name"]) == q or any(key(a) == q for a in p["aliases"])]
    if len(exact) == 1:
        return exact[0]
    loose = [p for p in ps if any((k := key(n)) and (q in k or (len(k) >= 4 and k in q)) for n in [p["name"], *p["aliases"]])]
    if len(loose) == 1:
        return loose[0]
    if loose or exact:
        return [p["name"] for p in (loose or exact)]
    return None


def bluey_folder() -> Path:
    if not (BLUEY / ".git").exists():
        BLUEY.mkdir(parents=True, exist_ok=True)
        readme = BLUEY / "README.md"
        if not readme.exists():
            readme.write_text("# Bluey\n\nCodex jobs started by Bluey, the blueberry on your phone, run from here.\n")
        subprocess.run(["git", "init", "-q", str(BLUEY)], check=False)
    return BLUEY


class Codex:
    def __init__(self):
        self.jobs: list[dict] = []
        self.proc: asyncio.subprocess.Process | None = None
        self.next_id = 1
        self.waiting: dict[int, asyncio.Future] = {}
        self.ready: asyncio.Task | None = None
        self.loaded: set[str] = set()
        self.on_event: Callable[[str, str], None] | None = None  # (note for him, ready-made line)
        self.on_change: Callable[[], None] | None = None

    @staticmethod
    def installed() -> bool:
        return shutil.which("codex") is not None

    async def ensure_running(self) -> None:
        if self.ready and self.proc and self.proc.returncode is None:
            return await self.ready
        if not self.installed():
            raise RuntimeError("Codex isn't installed on this computer.")
        self.proc = await asyncio.create_subprocess_exec(
            shutil.which("codex"), "app-server", cwd=str(Path.home()), stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL, limit=16 * 1024 * 1024, env=os.environ.copy())
        self.loaded = set()
        asyncio.ensure_future(self._read(self.proc))

        async def init():
            await self.request("initialize", {"clientInfo": {"name": "bluey", "title": "Bluey", "version": "1.0"}})
            self._write({"jsonrpc": "2.0", "method": "initialized"})
        self.ready = asyncio.ensure_future(init())
        await self.ready

    def shutdown(self):
        if self.proc and self.proc.returncode is None:
            self.proc.terminate()

    def _write(self, obj: dict) -> None:
        if self.proc and self.proc.stdin:
            self.proc.stdin.write(json.dumps(obj).encode() + b"\n")

    async def request(self, method: str, params: dict) -> dict:
        i = self.next_id
        self.next_id += 1
        fut = asyncio.get_running_loop().create_future()
        self.waiting[i] = fut
        self._write({"jsonrpc": "2.0", "id": i, "method": method, "params": params})
        return await fut

    async def _read(self, proc) -> None:
        while True:
            line = await proc.stdout.readline()
            if not line:
                break
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            if isinstance(msg, dict):
                self._handle(msg)
        self._exited()

    def _exited(self):
        self.proc, self.ready, self.loaded = None, None, set()
        for f in self.waiting.values():
            if not f.done():
                f.set_exception(RuntimeError("Codex stopped unexpectedly."))
        self.waiting = {}
        for j in self.jobs:
            if j["status"] in ("starting", "working", "waiting for approval"):
                j["status"] = "stopped (Codex quit)"
        self._changed()

    def _changed(self):
        if self.on_change:
            self.on_change()

    def _handle(self, msg: dict) -> None:
        method = msg.get("method")
        if method is None and isinstance(msg.get("id"), int) and msg["id"] in self.waiting:
            fut = self.waiting.pop(msg["id"])
            if fut.done():
                return
            if "error" in msg:
                fut.set_exception(RuntimeError(f"Codex said: {short(str(msg['error'].get('message', 'error')), 200)}"))
            else:
                fut.set_result(msg.get("result") or {})
            return
        if not method:
            return
        params = msg.get("params") or {}
        if "id" in msg:
            self._server_request(msg["id"], method, params)
        else:
            self._notification(method, params)

    def _job(self, thread):
        return next((j for j in reversed(self.jobs) if j["thread"] == thread), None)

    def _notification(self, method: str, p: dict) -> None:
        job = self._job(p.get("threadId"))
        if not job:
            return
        if method == "turn/started":
            job["turn"] = (p.get("turn") or {}).get("id")
            job["status"] = "working"
            self._changed()
        elif method == "item/completed":
            item = p.get("item") or {}
            if item.get("type") == "agentMessage" and item.get("text"):
                job["last"] = item["text"]
        elif method == "turn/completed":
            turn = p.get("turn") or {}
            for item in turn.get("items") or []:
                if item.get("type") == "agentMessage" and item.get("text"):
                    job["last"] = item["text"]
            status = turn.get("status", "completed")
            if status == "interrupted":
                job["status"] = "stopped"
            elif status == "failed":
                job["status"] = "failed"
                why = short(str((turn.get("error") or {}).get("message", "no reason given")))
                self._event(f"Codex hit a problem in {job['project']} (job: \"{short(job['prompt'], 160)}\"). Error: {why}",
                            f"Codex tripped over something in {job['project']}. Have a look?")
            else:
                job["status"] = "done"
                summary = short(job["last"], 900) if job.get("last") else "(no summary)"
                self._event(f"Codex finished in {job['project']} (job: \"{short(job['prompt'], 160)}\"). Codex's own summary: {summary}",
                            f"Codex is done in {job['project']}.")
            self._changed()

    def _event(self, note: str, line: str):
        if self.on_event:
            self.on_event(note, line)

    def _server_request(self, id, method: str, p: dict) -> None:
        # Full access, never ask; if an approval comes anyway, say yes so Codex keeps going (as on the Mac).
        if method in ("item/commandExecution/requestApproval", "item/fileChange/requestApproval"):
            self._write({"jsonrpc": "2.0", "id": id, "result": {"decision": "acceptForSession"}})
        elif method in ("execCommandApproval", "applyPatchApproval"):
            self._write({"jsonrpc": "2.0", "id": id, "result": {"decision": "approved_for_session"}})
        elif method == "item/permissions/requestApproval":
            asked = {k: v for k, v in (p.get("permissions") or {}).items() if v is not None}
            self._write({"jsonrpc": "2.0", "id": id, "result": {"permissions": asked, "scope": "session"}})
        else:
            self._write({"jsonrpc": "2.0", "id": id, "error": {"code": -32601, "message": f"Bluey can't answer {method}."}})

    @staticmethod
    def _text(t: str) -> dict:
        return {"type": "text", "text": t, "text_elements": []}

    def warm_up(self):
        if self.installed():
            asyncio.ensure_future(self._quiet(self.ensure_running()))

    @staticmethod
    async def _quiet(coro):
        try:
            await coro
        except Exception:
            pass

    def start(self, project: str | None, prompt: str) -> str:
        prompt = prompt.strip()
        if not prompt:
            return "What should Codex do?"
        if not self.installed():
            return "Codex isn't installed on this computer."
        full, name = prompt, "Bluey"
        if project and project.strip():
            m = resolve(project)
            if isinstance(m, dict):
                full, name = f"The work is in the existing repo at {m['path']}.\n\n{prompt}", m["name"]
            elif isinstance(m, list):
                return f"Several projects match \"{project}\": {', '.join(m[:6])}. Ask the user which one in one short line."
            else:
                names = ", ".join(p["name"] for p in projects()[:20])
                return f"No project called \"{project}\". Projects: {names}. Ask which one, or leave the project out to work in the Bluey folder."

        async def run():
            try:
                folder = bluey_folder()
                await self.ensure_running()
                sandbox = "danger-full-access" if settings.values.get("codexFullAccess", True) else "workspace-write"
                r = await self.request("thread/start", {"cwd": str(folder), "sandbox": sandbox, "approvalPolicy": "never"})
                thread = (r.get("thread") or {}).get("id")
                if not thread:
                    raise RuntimeError("no thread")
                self.loaded.add(thread)
                self.jobs.append({"thread": thread, "project": name, "folder": str(folder), "prompt": prompt,
                                  "turn": None, "status": "starting", "last": None, "started": time.time()})
                self._changed()
                await self.request("turn/start", {"threadId": thread, "input": [self._text(full)]})
            except Exception as e:
                self._event(f"Codex couldn't start the job (\"{short(prompt, 120)}\"): {e}", f"Codex wouldn't start: {short(str(e), 80)}")
        asyncio.ensure_future(run())
        return f"Codex is on it ({name}). It'll ping you when it's done."

    def find(self, hint: str | None):
        hint = (hint or "").strip().lower()
        if not self.jobs:
            return None
        if not hint:
            return self.jobs[-1]
        k = key(hint)
        return (next((j for j in reversed(self.jobs) if k in key(j["project"]) or key(j["project"]) in k), None)
                or next((j for j in reversed(self.jobs) if hint in j["prompt"].lower()), None) or self.jobs[-1])

    async def follow_up(self, hint: str | None, message: str) -> str:
        job = self.find(hint)
        if not job:
            return "There's no Codex job yet. Start one with codex_start."
        try:
            await self.ensure_running()
            if job["status"] in ("working", "waiting for approval") and job.get("turn"):
                await self.request("turn/steer", {"threadId": job["thread"], "expectedTurnId": job["turn"], "input": [self._text(message)]})
                return f"Passed that to Codex in {job['project']} while it works."
            if job["thread"] not in self.loaded:
                await self.request("thread/resume", {"threadId": job["thread"]})
                self.loaded.add(job["thread"])
            job["status"] = "starting"
            self._changed()
            await self.request("turn/start", {"threadId": job["thread"], "input": [self._text(message)]})
            return f"Sent the follow-up to Codex in {job['project']}."
        except Exception as e:
            return f"Couldn't reach Codex: {e}"

    async def stop(self, hint: str | None = None) -> str:
        job = self.find(hint)
        if not job:
            return "No Codex job to stop."
        if not job.get("turn") or job["status"] not in ("working", "waiting for approval", "starting"):
            return f"Codex isn't working on anything in {job['project']} right now."
        try:
            await self.request("turn/interrupt", {"threadId": job["thread"], "turnId": job["turn"]})
            return f"Stopped Codex in {job['project']}."
        except Exception as e:
            return f"Couldn't stop it: {e}"

    def status(self) -> str:
        lines = []
        for j in reversed(self.jobs[-6:]):
            mins = int((time.time() - j["started"]) / 60)
            line = f"{j['project']}: {j['status']}, started {mins} min ago, job \"{short(j['prompt'], 100)}\""
            if j.get("last"):
                line += f". Latest from Codex: {short(j['last'], 300)}"
            lines.append(line)
        return "\n".join(lines) or "No Codex jobs yet."

    def open(self, hint: str | None) -> str:
        """No Codex desktop app on Linux: open the job's folder instead."""
        job = self.find(hint)
        path = job["folder"] if job else str(bluey_folder())
        from gi.repository import Gio
        Gio.AppInfo.launch_default_for_uri(Path(path).as_uri(), None)
        return f"Opened the {job['project'] if job else 'Bluey'} folder."
