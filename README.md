# Bluey Cross-Platform

A friendly blueberry companion character who lives on your phone or desktop screen, follows your cursor, points at UI elements, and provides real-time AI context and computer control capabilities.

---

## Supported Platforms & Feature Matrix

| Platform | Role / App Type | Core Capabilities |
| --- | --- | --- |
| **Android** | Mobile Client (`bluey_app`) | Fullscreen sticky immersive mode (hidden status bar), double-tap wake/sleep, press-and-hold AI response, cute audio chirps, session history management, responsive layout, and automatic Bonjour discovery/pairing over Wi-Fi. |
| **macOS** | Native Desktop (`Mac/`) & Cross-Platform Desktop (`bluey_app`) | Menu bar controls, transparent floating overlay, background animation physics loop, global shortcuts (⌃⌥P, ⌃⌥F, ⌥Space, ⌃⌥S, etc.), ScreenCaptureKit + Vision OCR element target identification, safety-guardrailed computer automation, and session audio note transcription. |
| **Windows** | Desktop Overlay (`bluey_app`) | System tray support, cursor-following teardrop graphics, pointer trails, global hotkeys, high-DPI scaling support, computer control automation with refusal guardrails, and audio response playback. |
| **Linux (X11 / Wayland)** | Desktop Overlay (`bluey_app`) | Native GTK system tray integration, smooth spring physics background loop, custom cursor graphics, global keyboard shortcuts, and network pairing with mobile clients over `_googly._tcp`. |

---

## 📱 & 💻 Verbindungsanleitung & Netzwerkopplung (Detailed Connection Guide)

### 📌 Voraussetzungen / Prerequisites
1. **Gemeinsames WLAN / Same Local Network**: Phone (Android) and Desktop (Linux / macOS / Windows) must be connected to the **same local Wi-Fi or LAN router**.
2. **AP-Isolation Deaktiviert**: Ensure "AP Isolation" or "Client Isolation" is turned off in your Wi-Fi router settings (so local devices can talk to each other).

---

### 🚀 Schritt-für-Schritt Verbindungsanleitung / Step-by-Step Instructions

#### Schritt 1: Desktop-App starten
- Start the Desktop application on Linux, macOS, or Windows.
- The Desktop app starts the server automatically listening on TCP socket port `52431` and registers the Bonjour service `_googly._tcp`.
- The top bar will show: `Waiting for phone app...` or connected phone list.

#### Schritt 2: Mobile App starten & koppeln
- Open the Mobile App on Android.
- If not connected, tap the **"Pairing" / "Verbinden"** overlay button.
- The mobile app scans local network for `_googly._tcp` service instances automatically.
- Select your desktop computer name from the list (e.g. `My Computer`).

#### Schritt 3: Manueller IP-Verbindungsaufbau (Fallback)
If your Wi-Fi router blocks mDNS/Bonjour service discovery, use manual IP connection:
1. Find your computer's local IP address:
   - **Linux / macOS**: Open terminal and run `hostname -I` or `ifconfig` (e.g. `192.168.1.120`).
   - **Windows**: Open Command Prompt (`cmd`) and run `ipconfig` (look for IPv4 address).
2. On Android App, tap **"Manual IP Connect"**.
3. Enter `192.168.1.120` and Port `52431`, then tap **Connect**.

---

### 🛡️ Firewall & Netzwerkeinstellungen / Firewall Rules

Make sure TCP Port `52431` and mDNS UDP Port `5353` are allowed through your firewall:

- **Linux (ufw)**:
  ```bash
  sudo ufw allow 52431/tcp comment 'Bluey TCP Port'
  sudo ufw allow 5353/udp comment 'mDNS Service Discovery'
  ```
- **macOS**:
  - Open **System Settings** -> **Network** -> **Firewall**.
  - Ensure `bluey_app` is allowed to accept incoming network connections.
- **Windows Firewall**:
  - Run Command Prompt as Administrator:
  ```cmd
  netsh advfirewall firewall add rule name="Bluey_Desktop_Port" dir=in action=allow protocol=TCP localport=52431
  ```

---

### ❓ Fehlerbehebung & FAQ / Troubleshooting FAQ

- **Animation stops when desktop window is closed/minimized?**
  - Fixed! The app runs a background 60 FPS physics and animation loop (`Timer.periodic`) that keeps cursor movements, speech bubbles, and phone synchronization alive even when minimized or closed to system tray.
- **Status bar visible on Android?**
  - The Android app operates in **Sticky Immersive Fullscreen Mode** (`SystemUiMode.immersiveSticky`). Swipe down from the top edge if you need to briefly reveal system bar.
- **Desktop Companion Cursor graphics don't match preview images?**
  - Hand-drawn googly eyes, gradient shader, pupil catchlights, comet particle decay, and elastic tether curves are updated to match all visual previews in `docs/previews/`.

---

## Project Structure & Architecture

```
bluey-by-riley-android/
├── Shared/                 # Swift protocol models, colors, and shared assets for native macOS/iOS
├── Mac/                    # Native macOS menu bar application (GooglyMac Swift target)
├── iOS/                    # Original SwiftUI iPhone application
├── bluey_app/              # Multiplatform Flutter application (Android, Windows, Linux, macOS)
│   ├── lib/
│   │   ├── ai/             # AI Provider interfaces (Gemini models: gemini-3.7-flash, gemini-3.8-flash, Live API)
│   │   ├── audio/          # Chirp synthesizer and procedural audio generation
│   │   ├── graphics/       # Blob shape drawing, spring dynamics, face animator, cursor overlays
│   │   ├── models/         # Session data models and serialization
│   │   ├── platform/       # Hotkeys, computer control guardrails, and screen capture analysis
│   │   ├── protocol/       # Googly protocol implementation (Bonjour service _googly._tcp, newline JSON)
│   │   ├── services/       # PermissionManager (Linux, macOS, Windows, Android) & UpdateManager
│   │   ├── storage/        # Local persistent session storage and markdown export generator
│   │   └── ui/             # Flutter screens: face screen, pairing view, sound button, session history
│   ├── android/            # Native Android platform configuration and permissions
│   ├── linux/              # Native Linux CMake runner and dependencies
│   ├── windows/            # Native Windows C++ runner
│   └── test/               # Comprehensive unit and integration test suite
├── .github/workflows/      # Consolidated GitHub CI/CD build workflows
└── scripts/
    └── build-mac.sh        # Build script for native macOS app (GooglyMac)
```

---

## Reproducible Build Instructions

### 1. Flutter App (`bluey_app`) - Android, Linux, Windows, macOS

#### Prerequisites
- Flutter SDK (3.x stable)
- Java JDK 17 (for Android build)
- Native toolchains:
  - **Linux**: `sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev lld`
  - **Windows**: Visual Studio 2022 with C++ desktop development workload.
  - **macOS**: Xcode 15+ and Xcode Command Line Tools.

#### Running Tests & Code Analysis
```bash
cd bluey_app
flutter pub get
flutter analyze
flutter test
```

#### Building Release Packages
- **Android APK:**
  ```bash
  cd bluey_app
  flutter build apk --release
  # Output: bluey_app/build/app/outputs/flutter-apk/app-release.apk
  ```
- **Linux Desktop Bundle:**
  ```bash
  cd bluey_app
  flutter build linux --release
  # Output: bluey_app/build/linux/x64/release/bundle/
  ```
- **Windows Desktop Bundle:**
  ```bash
  cd bluey_app
  flutter build windows --release
  # Output: bluey_app/build/windows/x64/runner/Release/
  ```
- **macOS Desktop Bundle:**
  ```bash
  cd bluey_app
  flutter build macos --release
  # Output: bluey_app/build/macos/Build/Products/Release/bluey_app.app
  ```

---

### 2. Native macOS Menu Bar App (`Mac/`)

Build the standalone native Swift macOS menu bar application using:
```bash
./scripts/build-mac.sh
open "build/Bluey.app"
```

---

## Communication Protocol & Network Pairing

Mobile and Desktop applications discover each other on the local Wi-Fi network using Bonjour service discovery:
- **Service Type:** `_googly._tcp`
- **Transport:** TCP socket with newline-delimited (`\n`) JSON packets.
- **Packet Structure:** Encodes face state, gaze coordinates (`gazeX`, `gazeY`), mood (`listening`, `talking`, `pointing`, `thinking`, `happy`, `resting`, `sleepy`), speech volume, and tool commands (`look_at_screen`, `point_at`, `click`, etc.).

---

## Native Permissions & Safety Guardrails

### Required Permissions
- **Microphone**: For voice input during AI sessions and audio note recording.
- **Screen Recording / Capture**: For `look_at_screen` functionality and UI element coordinate analysis.
- **Accessibility / Overlay**: For executing requested computer control interactions (clicks, typing, shortcut invocation) and desktop floating companion display.

### Built-in Guardrails & Emergency Stop
- **Emergency Stop Hotkey**: Pressing **⌃⌥S** instantly halts all computer control automation for 6 seconds.
- **Sensitive Data Protection**: Refuses to type text containing password or secret keywords.
- **Dangerous Action Refusal**: Hard-coded refusal of system logout, force quit, lock screen, and reboot keyboard shortcuts (`cmd+shift+q`, `ctrl+alt+del`, etc.).
- **User Confirmation Out Loud**: Requires explicit user intent before performing actions that are difficult to undo.

---

## CI/CD Workflows & Build Artifacts

Automated GitHub Actions workflows run on all pushes and pull requests targeting key platform files:

- **`android.yml`**: Builds and verifies the Android release APK artifact (`bluey-app-android-apk`).
- **`linux.yml`**: Installs GStreamer and GTK3 native dependencies, runs analysis and tests, and builds the Linux x64 bundle (`bluey-app-linux`).
- **`windows.yml`**: Runs Flutter tests and builds the Windows release binary bundle (`bluey-app-windows`).
- **`macos.yml`**: Builds the native macOS app bundle via `./scripts/build-mac.sh` and tests the Flutter cross-platform target (`bluey-native-mac-app`).
