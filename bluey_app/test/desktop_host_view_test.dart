import 'package:bluey_app/main.dart';
import 'package:bluey_app/storage/session_store.dart';
import 'package:bluey_app/ui/desktop_host_view.dart';
import 'package:bluey_app/ui/pairing_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopHostView Widget & Platform Routing Tests', () {
    test('BlueyApp.isDesktop correctly evaluates desktop platforms', () {
      expect(BlueyApp.isDesktop, isTrue);
    });

    testWidgets('DesktopHostView renders macOS control bar items and action buttons',
        (WidgetTester tester) async {
      final store = SessionStore();

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopHostView(store: store, enableAnimation: false, enableServer: false),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Verify connection banner
      expect(find.textContaining('Waiting for phone app'), findsOneWidget);

      // Verify computer control chip
      expect(find.text('Let Him Use Computer'), findsOneWidget);

      // Verify emergency stop button
      expect(find.textContaining('Stop Him'), findsOneWidget);

      // Verify mood, size, trail popups exist
      expect(find.textContaining('Mood:'), findsOneWidget);
      expect(find.textContaining('Size:'), findsOneWidget);
      expect(find.textContaining('Trail:'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('DesktopHostView displays server IP port in connection banner when enabled',
        (WidgetTester tester) async {
      final store = SessionStore();

      await tester.pumpWidget(
        MaterialApp(
          home: DesktopHostView(store: store, enableAnimation: false, enableServer: true),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('IP:'), findsOneWidget);
      expect(find.textContaining(':8080'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('PairingView renders manual coupling button and opens ManualPairingDialog',
        (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PairingView(onPlay: () {}),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // Find "Manuell koppeln" button
      final manualBtn = find.text('Manuell koppeln');
      expect(manualBtn, findsOneWidget);

      // Tap manual connect button
      await tester.tap(manualBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Verify dialog is shown with IP-Adresse field and Verbinden button
      expect(find.text('IP-Adresse'), findsOneWidget);
      expect(find.text('Verbinden'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
