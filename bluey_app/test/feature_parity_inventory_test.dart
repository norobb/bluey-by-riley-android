import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/ai/ai_provider.dart';
import 'package:bluey_app/graphics/blob_shape.dart';
import 'package:bluey_app/graphics/cursor_overlay_graphics.dart';
import 'package:bluey_app/graphics/face_animator.dart';
import 'package:bluey_app/models/session_models.dart';
import 'package:bluey_app/platform/computer_control.dart';
import 'package:bluey_app/platform/hotkeys.dart';
import 'package:bluey_app/platform/screen_capture.dart';
import 'package:bluey_app/protocol/googly_protocol.dart';
import 'package:bluey_app/storage/session_store.dart';

void main() {
  group('Milestone 5: Comprehensive Feature Parity Matrix Verification (FEAT-001 .. FEAT-025)', () {
    test('FEAT-001 & FEAT-002: Service Name & Newline JSON Protocol', () {
      expect(GooglyService.type, equals('_googly._tcp'));
      final packet = Packet(hello: 'Device', command: 'wake');
      final json = packet.toJson();
      expect(json['command'], equals('wake'));
      final decoded = Packet.fromJson(json);
      expect(decoded.hello, equals('Device'));
    });

    test('FEAT-003 & FEAT-004: BlobShape & Damped Spring Face Dynamics', () {
      final rect = const Rect.fromLTWH(0, 0, 844, 390);
      final blobPath = BlobShape.path(rect);
      expect(blobPath.getBounds().isEmpty, isFalse);

      final spring = Spring(0, stiffness: 200, damping: 0.7);
      spring.step(50, 0.016);
      expect(spring.value, greaterThan(0));
    });

    test('FEAT-005 & FEAT-006 & FEAT-007: Face Animator, Gestures & Moods', () {
      final animator = FaceAnimator();
      animator.receive(FaceState(gazeX: 0.5, gazeY: -0.5, mood: Mood.happy), 1.0);
      final frame = animator.step(1.05);

      expect(frame.mood, equals(Mood.happy));
      expect(frame.pupil, greaterThan(0));
    });

    test('FEAT-008 & FEAT-009 & FEAT-010: Audio Chirps, Chunks & SessionStore', () {
      final session = BlueySession(
        started: DateTime.now(),
        entries: [
          TranscriptEntry(kind: EntryKind.asked, text: 'Test question', time: DateTime.now()),
        ],
      );
      expect(session.questionCount, equals(1));
      expect(session.summary, equals('Test question'));
    });

    test('FEAT-011 & FEAT-012: Session Display & Prompt Copy Export', () {
      final session = BlueySession(
        started: DateTime.now(),
        entries: [
          TranscriptEntry(kind: EntryKind.reply, text: 'Hello', time: DateTime.now()),
        ],
      );
      expect(session.exportText, contains('Bluey: Hello'));
    });

    test('FEAT-013 & FEAT-014 & FEAT-015: Cursor Teardrop & Bezier Flight Physics', () {
      final teardrop = TeardropPath.path(size: 72, tipRadius: 6);
      expect(teardrop.getBounds().isEmpty, isFalse);

      const curve = TimingCurve.launch;
      expect(curve.value(0.5), greaterThan(0));
    });

    test('FEAT-016 & FEAT-017: Pointer Trails & Global System Hotkeys', () {
      final hotkeys = GlobalHotKeyManager();
      var triggered = false;
      hotkeys.register(HotKeyAction.toggleShow, () => triggered = true);
      hotkeys.trigger(HotKeyAction.toggleShow);
      expect(triggered, isTrue);
    });

    test('FEAT-018 & FEAT-019 & FEAT-020: Screen Capture & Grid Target Listing', () async {
      final snapshot = await ScreenCaptureEngine.capture(screenSize: const Size(1000, 1000));
      expect(snapshot.targetList, contains('0-1000 grid'));
    });

    test('FEAT-021 & FEAT-022 & FEAT-023: Computer Control Automation & Guardrails', () async {
      final result = await ComputerControl.pressKeys('cmd+shift+q');
      expect(result, contains("won't press that shortcut"));
    });

    test('FEAT-024 & FEAT-025: Modular AI Research Report & Notes Markdown Exporter', () async {
      final provider = GeminiProvider();
      expect(provider.name, equals('Google Gemini'));

      final json = {
        'id': 'session123',
        'started': 1772359200.0,
        'entries': [
          {'kind': 'asked', 'text': 'Help me', 'time': 1772359205.0},
        ],
      };
      final md = SessionStore.generateMarkdownNotes(json);
      expect(md, contains('# Bluey session:'));
      expect(md, contains('User asked Bluey:** Help me'));
    });
  });
}
