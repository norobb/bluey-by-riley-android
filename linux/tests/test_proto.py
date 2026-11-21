"""Run: cd linux && python3 -m unittest discover -s tests. Same vectors as the Android ProtocolTest."""
import asyncio
import base64
import tempfile
import unittest
from pathlib import Path

from bluey.focus import FocusCompanion, FocusSession, NudgePolicy, clock
from bluey.proto import ChannelError, LineConnection, PairingRecord, SecureChannel, hkdf, proof

SECRET = bytes([17]) * 32
CHALLENGE = bytes(range(32))


class Proto(unittest.TestCase):
    def test_vectors(self):
        self.assertEqual(hkdf(SECRET, CHALLENGE, b"bluey-v1-mac-to-phone").hex(),
                         "ccfe489505023244ff17fcfc3cd8f74bb38d98b031e5fb0c39f8760c96b9ab2e")
        self.assertEqual(base64.b64encode(proof(SECRET, CHALLENGE)).decode(), "A5pzRo8ci6dkYIBJyff+7PGWIxFVMriqV5ZUC7IVydc=")
        phone = SecureChannel(SECRET, CHALLENGE, server=False)
        line = b"BwcHBwcHBwcHBwcH+MwwoIczKG+gXWxSbcJr9nMB5mwcT5+bzic06n6BDNCYBAmVlIKFqQP88c8EI3xN8Dndyg9GFYZRCcQr"
        self.assertEqual(phone.open(line), {"command": "paired"})
        self.assertEqual(PairingRecord(service="m", secret=base64.b64encode(SECRET).decode()).identifier, "02d449a31fbb267c8f352e99")

    def test_sequence_and_tamper(self):
        mac, phone = SecureChannel(SECRET, CHALLENGE, True), SecureChannel(SECRET, CHALLENGE, False)
        a, b = mac.seal({"command": "a"}), mac.seal({"command": "b", "text": None})
        self.assertRaises(ChannelError, SecureChannel(SECRET, CHALLENGE, False).open, b)
        self.assertEqual(phone.open(a)["command"], "a")
        self.assertRaises(ChannelError, phone.open, a)
        self.assertEqual(phone.open(b), {"command": "b"})
        bad = SecureChannel(SECRET, CHALLENGE, True)
        x = bytearray(base64.b64decode(bad.seal({"command": "x"}))); x[20] ^= 1
        self.assertRaises(ChannelError, SecureChannel(SECRET, CHALLENGE, False).open, base64.b64encode(bytes(x)))

    def test_pairing_parse(self):
        r = PairingRecord.new("Linux")
        self.assertEqual(PairingRecord.parse(r.qr_text).service, "Linux")
        self.assertNotIn(r.secret, repr(r))
        for bad in ["nope", "bluey-pair:%%", "bluey-pair:" + "A" * 2040,
                    "bluey-pair:" + base64.b64encode(b'{"version":2,"service":"m","secret":"' + r.secret.encode() + b'"}').decode()]:
            self.assertIsNone(PairingRecord.parse(bad))

    def test_loopback(self):
        async def run():
            got = asyncio.Event()

            async def serve(reader, writer):
                link = LineConnection(reader, writer, SECRET, server=True)
                link.on_packet = lambda p: got.set() if p.get("command") == "focusStart" else None
                await link.run()

            srv = await asyncio.start_server(serve, "127.0.0.1", 0)
            r, w = await asyncio.open_connection("127.0.0.1", srv.sockets[0].getsockname()[1])
            phone = LineConnection(r, w, SECRET, server=False)
            phone.on_authenticated = lambda: phone.send({"command": "focusStart", "text": "x"})
            task = asyncio.create_task(phone.run())
            await asyncio.wait_for(got.wait(), 8)
            self.assertTrue(phone.authenticated)
            phone.close(); srv.close(); await task
        asyncio.run(run())


class Focus(unittest.TestCase):
    def test_clock_matches_swift(self):
        s = FocusSession("Test Bluey", 60, developer_mode=True)
        s.advance(1); self.assertEqual((s.d["elapsed"], s.real_active), (4, 1))
        s.pause("x"); s.advance(100); self.assertEqual(s.d["elapsed"], 4)
        s.resume(); s.advance(20)
        self.assertEqual((s.status, s.d["elapsed"], s.real_active), ("ended", 60, 15))
        self.assertEqual(clock(1739.2), "29:00")

    def test_companion_commands(self):
        t = [100.0]
        with tempfile.TemporaryDirectory() as d:
            f = FocusCompanion(Path(d), {"focusDeveloperMode": False}, now=lambda: t[0])
            self.assertEqual(f.handle("focusStart", {"task": "Docs", "minutes": 1}), "Focus started: Docs, 1 minutes.")
            for _ in range(30):  # phone pings every second
                t[0] += 1; f.heartbeat(); f.tick()
            self.assertEqual(f.current.d["elapsed"], 30)
            self.assertEqual(f.handle("focusPause", {}), "Focus paused.")
            self.assertEqual(f.handle("focusDeveloperMode", {"developerMode": True})[:18], "Developer Mode on:")
            self.assertEqual(f.handle("focusEnd", {}), "Focus finished. Your timeline is on the phone.")
            self.assertEqual(len(f.history), 1)
            f.handle("focusStart", {"task": "Again"}); t[0] += 10; f.tick()
            self.assertEqual(f.current.status, "paused")  # lost heartbeat pauses monitoring
            self.assertIn('"revision"', f.sync_text())


class Policy(unittest.TestCase):
    """Ports of FocusTests.swift nudge cases."""
    def off(self, t, p=0.99):
        return {"elapsed": t, "activity": "off_task", "probability": p, "confidence": p}

    def test_minimum_cooldown_and_resets(self):
        n = NudgePolicy()
        for t in range(30, 121, 30):
            self.assertFalse(n.observe(self.off(t), 1))
        self.assertTrue(n.observe(self.off(150), 1))
        m = NudgePolicy()
        for t in range(0, 181, 30):
            self.assertFalse(m.observe(self.off(t, 0.65), 2))
        self.assertTrue(m.observe(self.off(210, 0.65), 2))
        d = NudgePolicy(60, developer_mode=True)
        self.assertFalse(d.observe(self.off(40), 1)); self.assertTrue(d.observe(self.off(80), 1))
        self.assertFalse(d.observe(self.off(120), 1)); self.assertFalse(d.observe(self.off(160), 1))
        self.assertTrue(d.observe(self.off(200), 1)); self.assertFalse(d.observe(self.off(240), 21))

    def test_decision_decode(self):
        from bluey.ai import decode_decision
        ok = {"answers": [{"name": "activity", "type": "choice", "choice": "off_task", "confidence": 0.8, "probabilities": [
            {"value": "on_task", "probability": 0.1}, {"value": "off_task", "probability": 0.85}, {"value": "uncertain", "probability": 0.05}]}]}
        self.assertEqual(decode_decision(ok)["probability"], 0.85)
        import copy
        bad = copy.deepcopy(ok); bad["answers"][0]["probabilities"][1]["probability"] = 0.5
        self.assertRaises(ValueError, decode_decision, bad)
        bad = copy.deepcopy(ok); bad["answers"][0]["choice"] = "paused"
        self.assertRaises(ValueError, decode_decision, bad)


class LocalSpeech(unittest.TestCase):
    def test_parse_voxtype_output(self):
        from bluey.stt import parse
        out = 'Loading audio file: "/run/x.wav"\nAudio format: 16000 Hz, 1 channel(s), Int\nProcessing 32000 samples (2.00s)...\n\nIch arbeite an den Docs.\n'
        self.assertEqual(parse(out), "Ich arbeite an den Docs.")
        self.assertEqual(parse(out.split("\n\n")[0] + "\n\n\n"), "")

    def test_parakeet_runs_locally(self):
        from bluey import stt
        if not stt.available():
            self.skipTest("voxtype not installed")
        import math, struct
        tone = b"".join(struct.pack("<h", int(800 * math.sin(i / 16000 * 2 * math.pi * 220))) for i in range(16000))
        self.assertIsInstance(asyncio.run(stt.transcribe(tone)), str)
        self.assertRaises(ValueError, asyncio.run, stt.transcribe(b"\x00" * 10))


class Keys(unittest.TestCase):
    def test_rejects_pasted_commands(self):
        from bluey.ai import valid_key
        self.assertTrue(valid_key("AIza" + "x" * 35))
        self.assertTrue(valid_key("AQ.Ab8RN6" + "x" * 40))  # newer formats without AIza
        self.assertFalse(valid_key("cd ~/Projects/googly-eyes/linux && python3 -m bluey.app --pair"))
        self.assertFalse(valid_key("GEMINI_API_KEY=\"AIza" + "x" * 35 + "\""))
        self.assertFalse(valid_key(""))


class Monitoring(unittest.TestCase):
    def test_check_then_nudge_with_fake_api(self):
        """Developer Mode: two off-task checks 40 focus-seconds apart nudge once."""
        async def run():
            t = [0.0]
            nudges = []
            async def capture():
                return {"jpeg": b"x", "app": "Firefox", "text": "", "targets": "", "find": lambda i, q: None}
            async def classify(*a):
                return {"activity": "off_task", "probability": 0.99, "confidence": 0.9,
                        "probabilities": {"on_task": 0.005, "off_task": 0.99, "uncertain": 0.005}}
            async def nudge(*a):
                return ("Hey, this doesn't look like docs.", None, None)
            with tempfile.TemporaryDirectory() as d:
                f = FocusCompanion(Path(d), {"focusDeveloperMode": True}, now=lambda: t[0], capture=capture,
                                   classify=classify, prepare_nudge=nudge)
                f.developer_mode = True
                f.on_nudge = lambda m, target: nudges.append(m)
                f.heartbeat(); f.start("Write docs", 5)
                for _ in range(25):
                    t[0] += 1; f.heartbeat(); f.tick()
                    await asyncio.sleep(0)
                    await asyncio.sleep(0)
                checks = [c for c in f.current.d["checks"] if c["activity"] == "off_task"]
                self.assertEqual(len(checks), 2)
                self.assertEqual(nudges, ["Hey, this doesn't look like docs."])
                self.assertTrue(checks[-1]["nudged"])
        asyncio.run(run())


if __name__ == "__main__":
    unittest.main()
