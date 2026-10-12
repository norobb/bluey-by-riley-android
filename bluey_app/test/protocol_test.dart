import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/protocol/googly_protocol.dart';

void main() {
  group('Googly Protocol Tests', () {
    test('GooglyService service type matches swift _googly._tcp', () {
      expect(GooglyService.type, equals('_googly._tcp'));
    });

    test('Mood enum cases and title parsing', () {
      expect(Mood.listening.title, equals('Listening'));
      expect(Mood.resting.title, equals('Resting'));
      expect(Mood.thinking.title, equals('Thinking'));
      expect(Mood.talking.title, equals('Talking'));
      expect(Mood.pointing.title, equals('Pointing'));
      expect(Mood.happy.title, equals('Happy'));
      expect(Mood.sleepy.title, equals('Sleepy'));

      expect(Mood.fromString('HAPPY'), equals(Mood.happy));
      expect(Mood.fromString('unknown'), equals(Mood.listening));
    });

    test('FaceState JSON encoding and decoding parity', () {
      final face = FaceState(
        gazeX: -0.5,
        gazeY: 0.75,
        mood: Mood.happy,
        talk: 0.8,
      );

      final json = face.toJson();
      expect(json['gazeX'], equals(-0.5));
      expect(json['gazeY'], equals(0.75));
      expect(json['mood'], equals('happy'));
      expect(json['talk'], equals(0.8));

      final decoded = FaceState.fromJson(json);
      expect(decoded, equals(face));
    });

    test('Packet JSON encoding and decoding parity', () {
      final face = FaceState(gazeX: 0.1, gazeY: -0.2, mood: Mood.thinking, talk: 0.3);
      final packet = Packet(
        hello: 'TestMac',
        face: face,
        volume: 0.9,
        command: 'wake',
        callID: 'call123',
        tool: 'look_at_screen',
        text: '{"arg":"val"}',
      );

      final jsonMap = packet.toJson();
      final jsonString = jsonEncode(jsonMap);
      final decodedMap = jsonDecode(jsonString) as Map<String, dynamic>;
      final decodedPacket = Packet.fromJson(decodedMap);

      expect(decodedPacket.hello, equals('TestMac'));
      expect(decodedPacket.volume, equals(0.9));
      expect(decodedPacket.command, equals('wake'));
      expect(decodedPacket.callID, equals('call123'));
      expect(decodedPacket.tool, equals('look_at_screen'));
      expect(decodedPacket.text, equals('{"arg":"val"}'));
      expect(decodedPacket.face?.mood, equals(Mood.thinking));
    });

    test('Palette hex colors match original Swift design palette', () {
      expect(Palette.berry1, equals(0xA9BCFF));
      expect(Palette.berry2, equals(0x6C86F5));
      expect(Palette.berry3, equals(0x4254D6));
      expect(Palette.berry4, equals(0x2B2F8F));
      expect(Palette.nose, equals(0x1C1F66));
      expect(Palette.ink, equals(0x17151F));
      expect(Palette.inkSoft, equals(0xB9B2CC));
      expect(Palette.panel, equals(0x1E1B29));

      final color1 = Palette.color(Palette.berry1);
      expect(color1.a, equals(1.0));
      expect((color1.r * 255).round(), equals(0xA9));
      expect((color1.g * 255).round(), equals(0xBC));
      expect((color1.b * 255).round(), equals(0xFF));
    });
  });
}
