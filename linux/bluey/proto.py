"""Wire protocol shared with the original iOS/Mac apps (Shared/SecurePairing.swift, Shared/GooglyLink.swift).

Byte-compatible: newline-delimited lines; plaintext JSON handshake, then base64(AES-GCM combined) records
of JSON {"sequence": n, "packet": {...}} with HKDF-SHA256 direction keys. Never log the pairing secret.
"""
from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import json
import os
from dataclasses import dataclass
from typing import Awaitable, Callable

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

SERVICE_TYPE = "_googly._tcp"
AUTH_TIMEOUT = 8.0
MAX_BUFFER = 16 * 1024 * 1024
MOODS = {"listening", "resting", "thinking", "talking", "pointing", "happy", "sleepy"}
PACKET_FIELDS = ("face", "hello", "volume", "command", "audio", "speech", "callID", "tool", "text", "image")


@dataclass
class PairingRecord:
    service: str
    secret: str  # base64 of 32 bytes
    version: int = 1

    @property
    def key(self) -> bytes | None:
        try:
            k = base64.b64decode(self.secret, validate=True)
        except Exception:
            return None
        return k if len(k) == 32 else None

    @property
    def identifier(self) -> str:
        k = self.key
        return hashlib.sha256(k).digest()[:12].hex() if k else "invalid"

    def to_json(self) -> dict:
        return {"version": self.version, "service": self.service, "secret": self.secret}

    @property
    def qr_text(self) -> str:
        return "bluey-pair:" + base64.b64encode(json.dumps(self.to_json()).encode()).decode()

    @classmethod
    def new(cls, service: str) -> "PairingRecord":
        return cls(service, base64.b64encode(os.urandom(32)).decode())

    @classmethod
    def parse(cls, text: str) -> "PairingRecord | None":
        if not text.startswith("bluey-pair:") or len(text) >= 2048:
            return None
        try:
            j = json.loads(base64.b64decode(text[11:], validate=True))
            r = cls(j["service"], j["secret"], j["version"])
        except Exception:
            return None
        if type(r.version) is not int or r.version != 1 or not isinstance(r.service, str) or not r.service or r.key is None:
            return None
        return r

    def __repr__(self) -> str:  # keep the secret out of logs
        return f"PairingRecord(service={self.service!r})"


def hkdf(secret: bytes, salt: bytes, info: bytes) -> bytes:
    return HKDF(hashes.SHA256(), 32, salt, info).derive(secret)


def proof(secret: bytes, challenge: bytes) -> bytes:
    return hmac.new(secret, b"bluey-pair-v1" + challenge, hashlib.sha256).digest()


def verifies(p: bytes, secret: bytes, challenge: bytes) -> bool:
    return hmac.compare_digest(p, proof(secret, challenge))


class ChannelError(Exception):
    pass


def validate_packet(p: object) -> dict:
    """Same acceptance as Swift's synthesized Packet decoder."""
    if not isinstance(p, dict):
        raise ChannelError
    for k in ("hello", "command", "audio", "callID", "tool", "text", "image"):
        if p.get(k) is not None and not isinstance(p[k], str):
            raise ChannelError
    if p.get("speech") is not None and (type(p["speech"]) is not int):
        raise ChannelError
    if p.get("volume") is not None and not isinstance(p["volume"], (int, float)):
        raise ChannelError
    f = p.get("face")
    if f is not None:
        if not isinstance(f, dict) or f.get("mood") not in MOODS or not all(isinstance(f.get(k), (int, float)) for k in ("gazeX", "gazeY", "talk")):
            raise ChannelError
    return {k: p[k] for k in PACKET_FIELDS if p.get(k) is not None}


class SecureChannel:
    def __init__(self, secret: bytes, challenge: bytes, server: bool):
        m2p = AESGCM(hkdf(secret, challenge, b"bluey-v1-mac-to-phone"))
        p2m = AESGCM(hkdf(secret, challenge, b"bluey-v1-phone-to-mac"))
        self._send, self._recv = (m2p, p2m) if server else (p2m, m2p)
        self.sent = 0
        self.received = 0

    def seal(self, packet: dict) -> bytes:
        record = json.dumps({"sequence": self.sent, "packet": {k: v for k, v in packet.items() if v is not None}},
                            separators=(",", ":")).encode()
        nonce = os.urandom(12)
        self.sent += 1
        return base64.b64encode(nonce + self._send.encrypt(nonce, record, None))  # CryptoKit `combined`

    def open(self, line: bytes) -> dict:
        try:
            data = base64.b64decode(line, validate=True)
            record = json.loads(self._recv.decrypt(data[:12], data[12:], None))
            seq = record["sequence"]
            packet = validate_packet(record["packet"])
        except ChannelError:
            raise
        except Exception as e:
            raise ChannelError from e
        if type(seq) is not int or seq != self.received:
            raise ChannelError
        self.received += 1
        return packet


class LineConnection:
    """One TCP peer. server=True is the Mac/Linux side; server=False is the phone side (used by tests)."""

    def __init__(self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter, secret: bytes, server: bool):
        self.reader, self.writer, self.secret, self.server = reader, writer, secret, server
        self.channel: SecureChannel | None = None
        self.challenge: bytes | None = None
        self.authenticated = False
        self.closed = False
        self.on_packet: Callable[[dict], Awaitable[None] | None] | None = None
        self.on_authenticated: Callable[[], Awaitable[None] | None] | None = None

    def send(self, packet: dict) -> None:
        if not self.authenticated or self.channel is None or self.closed:
            return
        self._write(self.channel.seal(packet))

    def _write(self, data: bytes) -> None:
        try:
            self.writer.write(data + b"\n")
        except Exception:
            self.close()

    def _handshake(self, fields: dict) -> None:
        self._write(json.dumps(fields, separators=(",", ":")).encode())

    def close(self) -> None:
        if not self.closed:
            self.closed = True
            self.writer.close()

    async def run(self) -> None:
        if self.server:
            self.challenge = os.urandom(32)
            self._handshake({"challenge": base64.b64encode(self.challenge).decode()})
        timeout = asyncio.get_running_loop().call_later(AUTH_TIMEOUT, lambda: None if self.authenticated else self.close())
        buffer = b""
        try:
            while not self.closed:
                chunk = await self.reader.read(1024 * 1024)
                if not chunk:
                    break
                buffer += chunk
                if len(buffer) > MAX_BUFFER:
                    break
                while b"\n" in buffer and not self.closed:
                    line, buffer = buffer.split(b"\n", 1)
                    if not await self._accept(line):
                        self.close()
                        return
        except (ConnectionError, OSError):
            pass
        finally:
            timeout.cancel()
            self.close()

    async def _call(self, fn, *args):
        if fn:
            r = fn(*args)
            if asyncio.iscoroutine(r):
                await r

    async def _accept(self, line: bytes) -> bool:
        if self.channel is not None:
            try:
                packet = self.channel.open(line)
            except ChannelError:
                return False
            if not self.authenticated:
                if self.server or packet.get("command") != "paired":
                    return False
                self.authenticated = True
                await self._call(self.on_authenticated)
            else:
                await self._call(self.on_packet, packet)
            return True
        try:
            j = json.loads(line)
        except Exception:
            return False
        if not isinstance(j, dict) or not all(isinstance(v, str) for v in j.values()):
            return False
        try:
            if self.server:
                p = base64.b64decode(j["proof"], validate=True)
                if not verifies(p, self.secret, self.challenge):
                    return False
                self.channel = SecureChannel(self.secret, self.challenge, server=True)
                self.authenticated = True
                self.send({"command": "paired"})
                await self._call(self.on_authenticated)
            else:
                c = base64.b64decode(j["challenge"], validate=True)
                if len(c) != 32:
                    return False
                self.channel = SecureChannel(self.secret, c, server=False)
                self._handshake({"proof": base64.b64encode(proof(self.secret, c)).decode()})
        except Exception:
            return False
        return True
