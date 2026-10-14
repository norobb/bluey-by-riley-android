import 'package:bluey_app/main.dart';
import 'package:bluey_app/storage/session_store.dart';
import 'package:bluey_app/ui/desktop_host_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      await tester.pumpAndSettle();

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
  });
}
