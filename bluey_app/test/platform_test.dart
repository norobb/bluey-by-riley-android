import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/platform/computer_control.dart';
import 'package:bluey_app/platform/hotkeys.dart';
import 'package:bluey_app/platform/screen_capture.dart';

void main() {
  group('Platform Integration & Automation Tests', () {
    test('GlobalHotKeyManager triggers registered handlers', () {
      final manager = GlobalHotKeyManager();
      var triggered = false;

      manager.register(HotKeyAction.toggleAwake, () {
        triggered = true;
      });

      manager.trigger(HotKeyAction.toggleAwake);
      expect(triggered, isTrue);
    });

    test('ComputerControl safety guardrails refuse dangerous shortcuts', () async {
      final result = await ComputerControl.pressKeys('cmd+option+esc');
      expect(result, contains("won't press that shortcut"));
    });

    test('ComputerControl stop signal halts actions', () async {
      ComputerControl.stopActions();
      final clickResult = await ComputerControl.click(const Offset(100, 100));
      expect(clickResult, contains("user pressed stop"));
    });

    test('ScreenSnapshot formats target list with 0-1000 grid coordinates', () {
      final snapshot = ScreenSnapshot(
        jpegBytes: [],
        controls: [
          Target(id: 'C1', text: 'Submit', rect: const Rect.fromLTWH(500, 450, 100, 50)),
        ],
        lines: [
          Target(id: 'L1', text: 'Search Google', rect: const Rect.fromLTWH(500, 225, 200, 30)),
        ],
        words: [],
        size: const Size(1000, 900),
        appName: 'Browser',
      );

      final listStr = snapshot.targetList;
      expect(listStr, contains('Frontmost app: Browser'));
      expect(listStr, contains('C1 control @550,528 "Submit"'));
      expect(listStr, contains('L1 @600,267 "Search Google"'));
    });
  });
}
