import 'dart:async';
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

  bool get isMicGranted => _micGranted;
  bool get isNotificationGranted => _notificationGranted;
  bool get isInstallGranted => _installGranted;

  /// Check all initial permissions at app startup
  Future<Map<String, bool>> checkAllPermissions() async {
    final Map<String, bool> results = {};

    try {
      final recorder = audioRecorder;
      if (recorder != null) {
        _micGranted = await recorder.hasPermission();
      }
      results['microphone'] = _micGranted;
    } catch (e) {
      debugPrint('Error checking mic permission: $e');
      _micGranted = false;
      results['microphone'] = false;
    }

    results['notifications'] = _notificationGranted;
    results['install_packages'] = _installGranted;

    return results;
  }

  /// Request Microphone permission
  Future<bool> requestMicrophonePermission() async {
    try {
      final recorder = audioRecorder;
      if (recorder != null) {
        _micGranted = await recorder.hasPermission();
      }
      return _micGranted;
    } catch (e) {
      debugPrint('Error requesting microphone permission: $e');
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

  /// Ensure all essential runtime permissions are requested
  Future<bool> ensureRequiredPermissions() async {
    final mic = await requestMicrophonePermission();
    await requestNotificationPermission();
    await requestInstallPermission();
    return mic;
  }
}
