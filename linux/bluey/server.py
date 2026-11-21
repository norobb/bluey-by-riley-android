"""Phone server (Mac PhoneServer.swift): DNS-SD `_googly._tcp` with TXT `bluey-id`, authenticated phones, broadcasts."""
from __future__ import annotations

import asyncio
import os
import subprocess
from typing import Awaitable, Callable

from .config import STATE
from .proto import SERVICE_TYPE, LineConnection, PairingRecord


def load_pairing(name: str) -> PairingRecord:
    """Private file like the Mac's support file (0600 in a 0700 dir). Created once per installation."""
    path = STATE / "pairing.json"
    try:
        r = PairingRecord.parse(path.read_text().strip())
        if r:
            return r
    except FileNotFoundError:
        pass
    r = PairingRecord.new(name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(r.qr_text)
    return r


class PhoneServer:
    def __init__(self, record: PairingRecord, name: str):
        self.record, self.name = record, name
        self.phones: dict[LineConnection, str | None] = {}
        self.on_request: Callable[[dict, Callable[[dict], None]], Awaitable[None] | None] | None = None
        self.on_phones_changed: Callable[[list[str]], None] | None = None
        self.last_face: dict | None = None
        self.last_face_at = 0.0
        self.avahi: subprocess.Popen | None = None
        self.port = 0

    @property
    def names(self) -> list[str]:
        return [n or "Phone" for n in self.phones.values()]

    def broadcast(self, packet: dict) -> None:
        for link in list(self.phones):
            link.send(packet)

    def send_face(self, face: dict, now: float) -> None:
        """Skips changes too small to see, but resends every second so the phone knows the host still drives."""
        last = self.last_face
        if last and now - self.last_face_at < 1 and last["mood"] == face["mood"] and abs(last["gazeX"] - face["gazeX"]) < 0.004 \
                and abs(last["gazeY"] - face["gazeY"]) < 0.004 and abs(last["talk"] - face["talk"]) < 0.02:
            return
        self.last_face, self.last_face_at = face, now
        self.broadcast({"face": face})

    def _changed(self):
        if self.on_phones_changed:
            self.on_phones_changed(self.names)

    async def _accept(self, reader, writer) -> None:
        link = LineConnection(reader, writer, self.record.key, server=True)

        def authenticated():
            self.phones[link] = None
            link.send({"hello": self.name})
            if self.last_face:
                link.send({"face": self.last_face})
            self._changed()

        async def packet(p: dict):
            if link not in self.phones:
                return
            if "hello" in p:
                self.phones[link] = p["hello"]
                self._changed()
            if "command" in p and self.on_request:
                r = self.on_request(p, link.send)
                if asyncio.iscoroutine(r):
                    asyncio.ensure_future(r)  # long requests (tools, tokens) must not block the reader

        link.on_authenticated, link.on_packet = authenticated, packet
        await link.run()
        if self.phones.pop(link, "absent") != "absent":
            self._changed()

    async def start(self, port: int = 0, mdns_host: str | None = None) -> None:
        self.tcp = await asyncio.start_server(self._accept, host=None, port=port)
        self.port = self.tcp.sockets[0].getsockname()[1]
        host = ["-H", mdns_host] if mdns_host else []
        # avahi-publish keeps the record alive while it runs; avahi-daemon is the system mDNS responder.
        self.avahi = subprocess.Popen(["avahi-publish", "-s", *host, self.name, SERVICE_TYPE, str(self.port),
                                       f"bluey-id={self.record.identifier}"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def stop(self):
        if self.avahi:
            self.avahi.terminate()
        for link in list(self.phones):
            link.close()
