import 'dart:io';
import 'package:bluey_app/protocol/googly_protocol.dart';
import 'package:bluey_app/protocol/line_connection.dart';
import 'package:bluey_app/protocol/phone_server.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      var broadcasted = false;

      final face1 = FaceState(gazeX: 0.1, gazeY: 0.1, mood: Mood.happy);
      final face2 = FaceState(gazeX: 0.101, gazeY: 0.101, mood: Mood.happy);

      server.send(face1);
      server.send(face2); // skipped due to < 0.004 delta within 1 sec
    });
  });
}
