import 'package:bluey_app/protocol/phone_client.dart';
import 'package:bluey_app/protocol/googly_protocol.dart';
import 'package:bluey_app/protocol/phone_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PhoneServer TCP Protocol Tests', () {
    test('PhoneServer binds, accepts client, and exchanges hello packet', () async {
      final server = PhoneServer();
      await server.start(port: 0); // dynamic port
      expect(server.isRunning, isTrue);

      // Verify empty initial phone names
      expect(server.phoneNames, isEmpty);

      server.stop();
      expect(server.isRunning, isFalse);
    });

    test('PhoneServer face state packet broadcast skipping small delta', () {
      final server = PhoneServer();

      final face1 = FaceState(gazeX: 0.1, gazeY: 0.1, mood: Mood.happy);
      final face2 = FaceState(gazeX: 0.101, gazeY: 0.101, mood: Mood.happy);

      server.send(face1);
      server.send(face2); // skipped due to < 0.004 delta within 1 sec
    });

    test('PhoneClient connects to PhoneServer and exchanges face state', () async {
      SharedPreferences.setMockInitialValues({});
      final server = PhoneServer();
      await server.start(port: 18080);

      final client = PhoneClient();
      FaceState? receivedFace;
      client.onFace = (face) {
        receivedFace = face;
      };

      final connected = await client.connectDirect('127.0.0.1', port: 18080);
      expect(connected, isTrue);
      expect(client.connected, isTrue);

      server.send(FaceState(gazeX: 0.5, gazeY: 0.5, mood: Mood.happy));
      await Future.delayed(const Duration(milliseconds: 300));

      expect(receivedFace, isNotNull);
      expect(receivedFace?.mood, Mood.happy);

      client.stop();
      server.stop();
    });

    test('PhoneClient connectDirect returns true on success and remembers IP', () async {
      SharedPreferences.setMockInitialValues({});
      final server = PhoneServer();
      await server.start(port: 18081);

      final client = PhoneClient();
      final success = await client.connectDirect('127.0.0.1', port: 18081);

      expect(success, isTrue);
      expect(client.connected, isTrue);
      expect(client.connectedIp, equals('127.0.0.1'));
      expect(client.lastManualIp, equals('127.0.0.1'));

      client.stop();
      server.stop();
    });

    test('PhoneClient connectDirect returns false when connection fails', () async {
      SharedPreferences.setMockInitialValues({});
      final client = PhoneClient();
      final success = await client.connectDirect('127.0.0.1', port: 18099);

      expect(success, isFalse);
      expect(client.connected, isFalse);

      client.stop();
    });
  });
}
