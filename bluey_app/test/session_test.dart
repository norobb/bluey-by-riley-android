import 'package:flutter_test/flutter_test.dart';
import 'package:bluey_app/models/session_models.dart';
import 'package:bluey_app/storage/session_store.dart';

void main() {
  group('Session Models & Storage Tests', () {
    test('TranscriptEntry serialization and deserialization', () {
      final now = DateTime.now();
      final entry = TranscriptEntry(
        kind: EntryKind.asked,
        text: 'What is this on my screen?',
        time: now,
        itemID: 'item_101',
      );

      final json = entry.toJson();
      expect(json['kind'], equals('asked'));
      expect(json['text'], equals('What is this on my screen?'));
      expect(json['itemID'], equals('item_101'));

      final decoded = TranscriptEntry.fromJson(json);
      expect(decoded.kind, equals(EntryKind.asked));
      expect(decoded.text, equals('What is this on my screen?'));
      expect(decoded.itemID, equals('item_101'));
    });

    test('BlueySession summary and export text', () {
      final start = DateTime(2026, 3, 1, 10, 0, 0);
      final session = BlueySession(
        started: start,
        ended: start.add(const Duration(minutes: 15)),
        entries: [
          TranscriptEntry(
            kind: EntryKind.heard,
            text: 'Hello world',
            time: start.add(const Duration(seconds: 5)),
          ),
          TranscriptEntry(
            kind: EntryKind.asked,
            text: 'Point at the search bar',
            time: start.add(const Duration(seconds: 10)),
          ),
          TranscriptEntry(
            kind: EntryKind.reply,
            text: 'Pointing at search bar.',
            time: start.add(const Duration(seconds: 12)),
          ),
        ],
      );

      expect(session.questionCount, equals(1));
      expect(session.summary, equals('Point at the search bar'));
      expect(session.duration.inMinutes, equals(15));

      final exportText = session.exportText;
      expect(exportText, contains('Point at the search bar'));
      expect(exportText, contains('Bluey: Pointing at search bar.'));
    });

    test('SessionStore.generateMarkdownNotes produces correct markdown header and turns', () {
      final sessionJson = {
        'id': 'sess1234',
        'started': 1772359200.0,
        'ended': 1772360100.0,
        'transcribing': 0,
        'entries': [
          {
            'kind': 'asked',
            'text': 'What is this?',
            'time': 1772359210.0,
          },
          {
            'kind': 'reply',
            'text': 'It is a blueberry.',
            'time': 1772359215.0,
          },
          {
            'kind': 'transcript',
            'speaker': 'A',
            'text': 'Yes that looks like a blueberry.',
            'time': 1772359220.0,
          }
        ]
      };

      final md = SessionStore.generateMarkdownNotes(sessionJson);
      expect(md, contains('# Bluey session:'));
      expect(md, contains('User asked Bluey:** What is this?'));
      expect(md, contains('> **Bluey:** It is a blueberry.'));
      expect(md, contains('Speaker A:** Yes that looks like a blueberry.'));
    });
  });
}
