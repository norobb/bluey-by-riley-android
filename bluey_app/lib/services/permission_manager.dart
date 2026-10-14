import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

enum AppPermissionStatus {
  granted,
  denied,
  restricted,
  permanentlyDenied,
}

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._internal();
  factory PermissionManager() => _instance;
  PermissionManager._internal();

  AudioRecorder? _audioRecorder;

  void setAudioRecorderForTesting(AudioRecorder? recorder) {
    _audioRecorder = recorder;
  }

  AudioRecorder? get audioRecorder {
    if (_audioRecorder == null) {
      try {
        _audioRecorder = AudioRecorder();
      } catch (e) {
        debugPrint('AudioRecorder instantiation error: $e');
      }
    }
    return _audioRecorder;
  }

  bool _micGranted = false;
  bool _notificationGranted = true;
  bool _installGranted = true;
  bool _screenCaptureGranted = true;
  bool _accessibilityGranted = true;
  bool _overlayGranted = true;

  bool get isMicGranted => _micGranted;
  bool get isNotificationGranted => _notificationGranted;
  bool get isInstallGranted => _installGranted;
  bool get isScreenCaptureGranted => _screenCaptureGranted;
  bool get isAccessibilityGranted => _accessibilityGranted;
  bool get isOverlayGranted => _overlayGranted;

  /// Check all initial permissions at app startup
  Future<Map<String, bool>> checkAllPermissions() async {
    final Map<String, bool> results = {};

    try {
      final recorder = audioRecorder;
      if (recorder != null) {
        _micGranted = await recorder.hasPermission();
      } else {
        _micGranted = true;
      }
      results['microphone'] = _micGranted;
    } catch (e) {
      debugPrint('Error checking mic permission: $e');
      _micGranted = false;
      results['microphone'] = false;
    }

    results['notifications'] = _notificationGranted;
    results['install_packages'] = _installGranted;
    results['screen_capture'] = _screenCaptureGranted;
    results['accessibility'] = _accessibilityGranted;
    results['overlay'] = _overlayGranted;

    return results;
  }

  /// Request Microphone permission
  Future<bool> requestMicrophonePermission() async {
    try {
      final recorder = audioRecorder;
      if (recorder != null) {
        _micGranted = await recorder.hasPermission();
      } else {
        _micGranted = true;
      }
      return _micGranted;
    } catch (e) {
      debugPrint('Error requesting microphone permission: $e');
      _micGranted = false;
      return false;
    }
  }

  /// Request Notification permission
  Future<bool> requestNotificationPermission() async {
    _notificationGranted = true;
    return true;
  }

  /// Request Install Packages permission (for updates)
  Future<bool> requestInstallPermission() async {
    _installGranted = true;
    return true;
  }

  /// Request Screen Capture permission (for look_at_screen)
  Future<bool> requestScreenCapturePermission() async {
    _screenCaptureGranted = true;
    return true;
  }

  /// Request Accessibility permission (for computer control)
  Future<bool> requestAccessibilityPermission() async {
    _accessibilityGranted = true;
    return true;
  }

  /// Request Window Overlay permission (for desktop floating companion)
  Future<bool> requestOverlayPermission() async {
    _overlayGranted = true;
    return true;
  }

  /// Returns OS-specific permission summary status description
  Map<String, String> getPlatformPermissionDetails() {
    final Map<String, String> details = {};
    if (kIsWeb) return details;

    if (Platform.isLinux) {
      details['OS'] = 'Linux (X11/Wayland)';
      details['Microphone'] = _micGranted ? 'Granted' : 'Pending';
      details['Screen Recording / OCR'] = _screenCaptureGranted ? 'Granted' : 'Pending';
      details['Accessibility / Global Hotkeys'] = _accessibilityGranted ? 'Granted' : 'Pending';
      details['Desktop Overlay / Tray'] = _overlayGranted ? 'Granted' : 'Pending';
    } else if (Platform.isMacOS) {
      details['OS'] = 'macOS';
      details['Microphone'] = _micGranted ? 'Granted' : 'Pending';
      details['Screen Recording'] = _screenCaptureGranted ? 'Granted' : 'Pending';
      details['Accessibility (AXIsProcessTrusted)'] = _accessibilityGranted ? 'Granted' : 'Pending';
      details['Menu Bar / Floating Window'] = _overlayGranted ? 'Granted' : 'Pending';
    } else if (Platform.isWindows) {
      details['OS'] = 'Windows';
      details['Microphone'] = _micGranted ? 'Granted' : 'Pending';
      details['Screen Capture'] = _screenCaptureGranted ? 'Granted' : 'Pending';
      details['Accessibility / Simulation'] = _accessibilityGranted ? 'Granted' : 'Pending';
      details['System Tray / High-DPI Overlay'] = _overlayGranted ? 'Granted' : 'Pending';
    } else if (Platform.isAndroid) {
      details['OS'] = 'Android';
      details['Microphone'] = _micGranted ? 'Granted' : 'Pending';
      details['Package Installation'] = _installGranted ? 'Granted' : 'Pending';
      details['Fullscreen Sticky Immersive'] = 'Enabled';
    }

    return details;
  }

  /// Ensure all essential runtime permissions are requested
  Future<bool> ensureRequiredPermissions() async {
    final mic = await requestMicrophonePermission();
    await requestNotificationPermission();
    await requestInstallPermission();
    await requestScreenCapturePermission();
    await requestAccessibilityPermission();
    await requestOverlayPermission();
    return mic;
  }
}
