# Bluey / GooglyEyes – protocol notes and port status

Source of truth: `bluey-by-riley/` (Unlicense). Ports: `android/` (phone client, replaces iOS) and `linux/` (host, replaces Mac).

## Discovery
- DNS-SD service `_googly._tcp`, instance name = host name. TXT `bluey-id` = hex(SHA-256(secret)[0:12]), lowercase.
- Phone connects only to the instance whose `bluey-id` matches its stored pairing.

## Pairing QR
`bluey-pair:` + base64(JSON `{"version":1,"service":"<host name>","secret":"<base64 32 bytes>"}`). Total < 2048 chars,
version must be 1, service non-empty, secret must decode to exactly 32 bytes. The secret is a credential; never log it.

## Transport
Plain TCP (no TLS), lines terminated by `0x0A`, receive buffer cap 16 MiB, 8 s to authenticate or close.
1. Server → `{"challenge":"<base64 32 random bytes>"}`
2. Client (challenge must be 32 bytes) → `{"proof":"<base64 HMAC-SHA256(secret, "bluey-pair-v1" ‖ challenge)>"}`
3. Server verifies (constant time), then sends encrypted `{command:"paired"}`; client requires that as its first record.
Handshake objects must contain only string values (Swift casts to `[String:String]`).

Encrypted records: base64(nonce(12) ‖ ciphertext ‖ tag(16)) of JSON `{"sequence":n,"packet":{…}}`, AES-256-GCM.
Keys: HKDF-SHA256(ikm=secret, salt=challenge, info=`bluey-v1-mac-to-phone` / `bluey-v1-phone-to-mac`, 32 bytes).
Sequence starts at 0 per direction and must match exactly; any failure closes the connection.

## Packet
All optional: `face{gazeX,gazeY,mood,talk}`, `hello`, `volume`, `command`, `audio`, `speech`(int), `callID`, `tool`, `text`, `image`.
Moods: listening, resting, thinking, talking, pointing, happy, sleepy. Nil fields are omitted.
Swift `Date` = seconds since 2001-01-01 (Unix − 978307200); `UUID` = uppercase string.

## Commands
| Direction | Command | Notes |
|---|---|---|
| phone→host | `hello` field | after auth |
| phone→host | `focusSync`, `focusPing` (1/s), `focusStart/Pause/Resume/End/TestNudge/DeveloperMode` | text = JSON `{task, minutes, developerMode?}`; reply `focusReply` same callID |
| phone→host | `realtimeToken` | reply `realtimeToken`, text = ephemeral key or nil |
| phone→host | `tool` (+`tool`, text = args JSON) | reply `toolResult` (+ optional JPEG `image`) |
| phone→host | `notes` (session JSON, Unix-second times) | reply `notes`, text = folder path |
| phone→host | `transcribe` (m4a base64) | reply `transcribed`; iOS never records chunks in this build, so unused |
| phone→host | `caption`, `captionDone`, `awake`, `asleep` | events, no reply |
| host→phone | `face`, `hello`, `focusState` (text = FocusSync JSON, revision increases), `focusChirp`, `wake`, `sleep`, `codexNote`, `codexChirp` | |
Requests time out after 12 s on the phone.

## AI provider (changed 2026-11-21: Gemini instead of OpenAI)
The Linux host and the Android app use the Google Gemini API. `realtimeToken` replies now carry JSON text
`{"provider":"gemini","token":<auth_tokens name>,"url":<Live WSS BidiGenerateContentConstrained>,"setup":{…}}`;
the phone connects with `?access_token=`, sends `{"setup": …}`, frames held speech with `realtimeInput.activityStart/
activityEnd` (16 kHz PCM16), shows `outputTranscription` as the caption (Live models only answer with audio, which is
discarded), answers `toolCall` with `toolResponse` and sends screenshots as `realtimeInput.video` JPEG frames.
Consequence: the original iPhone app gets no voice from the Linux host (it expects an OpenAI client secret and
reports "Voice could not connect"); pairing, focus and everything else stay compatible. The Android app no longer
does OpenAI Realtime, so against the original Mac it has no voice either.
Focus checks use `generateContent` with a JSON schema (choice, self-reported probabilities and confidence) instead
of the Decisions API; the same validation (`decode_decision`) applies. Model ids live in `linux/bluey/ai.py`.

Local speech (2026-11-21): when the host has Voxtype + Parakeet Ultra, the token JSON carries `"speech":"local"`.
The phone then keeps a held turn (≤20 s, 16 kHz PCM16), sends it as `{command:"hear", audio:<base64>}` and gets
`{command:"heard", text}` back (null on failure); only that text goes to Gemini Live as a `clientContent` turn.
Audio never leaves the PC. Otherwise (`"speech":"live"`) audio streams to Gemini as before.

## Focus
Host is authoritative (clock, checks, nudges); phone renders snapshots and is "fresh" only if a snapshot arrived in the last 5 s.
Missing heartbeat > 5 s, disconnect, lock or backgrounding pauses. Developer Mode: 4× clock, 10 s checks, 40–80 s evidence, 120 s cooldown.
Nudge policy and Decisions decoding: `Shared/FocusSession.swift`, ported 1:1 in `android/.../proto/Focus.kt`.

## Android port (`android/`)
Kotlin + Compose, minSdk 26, target 35. Build: `JAVA_HOME=/opt/android-studio/jbr ./gradlew :app:assembleDebug :app:testDebugUnitTest`
(Gradle 9.1.0, AGP 8.13.2, Kotlin 2.1.20). Deps fetched from Maven: okhttp (Realtime WebSocket), zxing-android-embedded (QR).
Differences from iOS: NsdManager instead of NWBrowser; pairing encrypted with an Android Keystore AES key (no backup);
AudioRecord VOICE_COMMUNICATION at 24 kHz PCM16 instead of AVAudioEngine voice processing; backgrounding = `onStop`
(iOS also pauses on "inactive"); no diagnostics JSON files; debug builds accept `--es pair 'bluey-pair:…'` for testing.

## Linux host (`linux/`, Python 3 + GTK 4 + GNOME Shell extension)
Port of the Mac app; see `linux/README.md` for the mapping. `python3 -m bluey.app --pair`.
Ported: phone server, handshake/crypto, focus (clock, checks via XDG screenshot portal + Decisions API, nudge policy,
nudge wording via Responses, lock/sleep pause), Realtime client secrets with the same instructions and tools,
look/point/research/computer-control tools, meeting notes, Codex app-server jobs, pairing/key/personality windows,
panel menu, overlay cursor + bubble + countdown, hotkeys.
Differences: no Accessibility control ids; OCR only with Tesseract; Ctrl+Alt instead of Option shortcuts; no
password-field check before typing; the overlay is simpler than the Mac's animated cursor (no trails or squish).

## Test status
- Unit: Android 14 tests (vectors cross-checked with Python `cryptography`, RFC 5869, loopback handshake, wrong secret,
  sequence/replay/tamper, PairingRecord, Packet, FocusSync, nudge policy, Decisions decode); Linux 9 tests (protocol, focus clock, nudge policy, Decisions decode, monitoring with a fake API).
- On device (Nothing phone, 2026-11-21): app runs; NSD discovery + TXT match + handshake + hello against the Linux
  host verified (over `adb reverse`, because of the firewall).
- Not tested: pairing against the original Mac or iPhone, QR scanning with the camera, Realtime voice, focus UI round trip on device.
