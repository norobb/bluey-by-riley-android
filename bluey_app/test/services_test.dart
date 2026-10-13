import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/services/permission_manager.dart';
import 'package:bluey_app/services/update_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      (MethodCall methodCall) async {
        if (methodCall.method == 'create') {
          return null;
        }
        if (methodCall.method == 'hasPermission') {
          return true;
        }
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('com.llfbandit.record/messages'),
      null,
    );
  });

  group('PermissionManager & UpdateManager Verification', () {
    test('PermissionManager initial status checks', () async {
      final pm = PermissionManager();
      final permissions = await pm.checkAllPermissions();

      expect(permissions.containsKey('microphone'), isTrue);
      expect(permissions.containsKey('notifications'), isTrue);
      expect(permissions.containsKey('install_packages'), isTrue);
      expect(pm.isNotificationGranted, isTrue);
      expect(pm.isInstallGranted, isTrue);
    });

    test('PermissionManager ensure required permissions', () async {
      final pm = PermissionManager();
      final mic = await pm.ensureRequiredPermissions();
      expect(pm.isNotificationGranted, isTrue);
      expect(pm.isInstallGranted, isTrue);
      expect(mic, isA<bool>());
    });

    test('UpdateManager version checking', () async {
      final um = UpdateManager();
      expect(UpdateManager.currentVersion, equals("1.0.0"));
      expect(UpdateManager.currentBuildNumber, equals(1));

      final updateInfo = await um.checkForUpdates();
      expect(updateInfo, isNull);
      expect(um.statusMessage, contains("1.0.0"));
    });

    test('UpdateManager local APK install handling', () async {
      final um = UpdateManager();
      final result = await um.installLocalApk("non_existent_path.apk");
      expect(result, isFalse);
      expect(um.statusMessage, contains("not found"));
    });
  });
}
