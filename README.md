# Bluey Cross-Platform

A friendly blueberry companion character who lives on your phone or desktop screen, follows your cursor, points at UI elements, and provides real-time AI context and computer control capabilities.

---

## Supported Platforms & Feature Matrix

| Platform | Role / App Type | Core Capabilities |
| --- | --- | --- |
| **Android** | Mobile Client (`bluey_app`) | Faithful reproduction of original iOS app: double-tap wake/sleep, press-and-hold AI response, cute audio chirps, session history management, responsive layout with system inset padding, and Bonjour discovery/pairing over Wi-Fi. |
| **macOS** | Native Desktop (`Mac/`) & Cross-Platform Desktop (`bluey_app`) | Menu bar controls, transparent floating overlay, global shortcuts (⌃⌥P, ⌃⌥F, ⌥Space, ⌃⌥S, etc.), ScreenCaptureKit + Vision OCR element target identification, safety-guardrailed computer automation, and session audio note transcription. |
| **Windows** | Desktop Overlay (`bluey_app`) | System tray support, cursor-following teardrop graphics, pointer trails, global hotkeys, high-DPI scaling support, computer control automation with refusal guardrails, and audio response playback. |
| **Linux (X11 / Wayland)** | Desktop Overlay (`bluey_app`) | Native GTK system tray integration, smooth spring physics animations, custom cursor graphics, global keyboard shortcuts, and network pairing with mobile clients over `_googly._tcp`. |

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
│   │   ├── storage/        # Local persistent session storage and markdown export generator
│   │   └── ui/             # Flutter screens: face screen, pairing view, sound button, session history
│   ├── android/            # Native Android platform configuration and permissions
│   ├── linux/              # Native Linux CMake runner and dependencies
│   ├── windows/            # Native Windows C++ runner
│   └── test/               # Comprehensive unit and integration test suite
├── .github/workflows/      # Consolidated GitHub CI/CD build workflows
│   ├── android.yml         # Android APK build and test workflow
│   ├── linux.yml           # Linux x64 bundle build and test workflow
│   ├── windows.yml         # Windows x64 release build and test workflow
│   └── macos.yml           # macOS native app and Flutter build workflow
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
- **Screen Recording**: For `look_at_screen` functionality and UI element coordinate analysis.
- **Accessibility**: For executing requested computer control interactions (clicks, typing, shortcut invocation).

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

---

## Known Limitations

- **Linux Display Servers**: On Wayland sessions without Xwayland accessibility extensions, global cursor warp and direct click simulation require explicit portal permissions or user input falling back to coordinate reporting.
- **Realtime Voice Live API**: On environments without direct Gemini Live WebSocket connectivity, voice turns fall back to text streaming with local chirp synthesis.
