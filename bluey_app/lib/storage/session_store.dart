import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/session_models.dart';

class SessionStore {
  List<BlueySession> sessions = [];
  String? currentID;

  File? _file;
  Directory? _documentsDir;
  Timer? _saveTimer;
  Timer? _syncTimer;
  final Set<String> _dirty = {};

  Function(List<BlueySession> changed)? onSync;

  BlueySession? get current {
    if (currentID == null) return null;
    try {
      return sessions.firstWhere((s) => s.id == currentID);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    _documentsDir = await getApplicationDocumentsDirectory();
    _file = File(p.join(_documentsDir!.path, 'sessions.json'));

    if (await _file!.exists()) {
      try {
        final content = await _file!.readAsString();
        final List<dynamic> jsonList = jsonDecode(content);
        sessions = jsonList.map((j) {
          final s = BlueySession.fromJson(j as Map<String, dynamic>);
          s.ended ??= s.entries.isNotEmpty ? s.entries.last.time : s.started;
          return s;
        }).toList();
      } catch (e) {
        sessions = [];
      }
    }
  }

  void start() {
    end();
    final newSession = BlueySession(started: DateTime.now());
    sessions.insert(0, newSession);
    currentID = newSession.id;
    save();
  }

  void end() {
    if (currentID == null) return;
    final index = sessions.indexWhere((s) => s.id == currentID);
    if (index == -1) return;

    currentID = null;
    final session = sessions[index];

    final isEmpty = session.entries.every((e) => e.text.trim().isEmpty);
    final isShort = DateTime.now().difference(session.started).inSeconds < 20;

    if (isEmpty && session.transcribing == 0 && isShort) {
      sessions.removeAt(index);
    } else {
      session.ended = DateTime.now();
      session.entries.removeWhere((e) => e.text.trim().isEmpty);
      _dirty.add(session.id);
      _scheduleSync();
    }
    save();
  }

  void placeholder({required String itemID, required bool asked}) {
    _update((session) {
      if (!session.entries.any((e) => e.itemID == itemID)) {
        session.entries.add(
          TranscriptEntry(
            kind: asked ? EntryKind.asked : EntryKind.heard,
            text: '',
            time: DateTime.now(),
            itemID: itemID,
          ),
        );
      }
    });
  }

  void heard({required String itemID, required String text, required bool asked}) {
    final cleanText = text.trim();
    _update((session) {
      final index = session.entries.indexWhere((e) => e.itemID == itemID);
      if (index != -1) {
        session.entries[index].text = cleanText;
        if (asked) session.entries[index].kind = EntryKind.asked;
      } else if (cleanText.isNotEmpty) {
        session.entries.add(
          TranscriptEntry(
            kind: asked ? EntryKind.asked : EntryKind.heard,
            text: cleanText,
            time: DateTime.now(),
            itemID: itemID,
          ),
        );
      }
    });
  }

  void reply(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    _update((session) {
      session.entries.add(
        TranscriptEntry(
          kind: EntryKind.reply,
          text: cleanText,
          time: DateTime.now(),
        ),
      );
    });
  }

  void report(String text) {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;
    _update((session) {
      session.entries.add(
        TranscriptEntry(
          kind: EntryKind.report,
          text: cleanText,
          time: DateTime.now(),
        ),
      );
    });
  }

  void addPending(String sessionID, int index, DateTime started) {
    _updateSession(sessionID, (s) {
      final list = s.pending ?? [];
      if (!list.any((p) => p.index == index)) {
        list.add(PendingChunk(index: index, started: started));
      }
      s.pending = list;
    });
  }

  void transcribed(
    String sessionID,
    int index,
    DateTime started,
    List<Map<String, dynamic>> segments,
  ) {
    _updateSession(sessionID, (s) {
      s.pending?.removeWhere((p) => p.index == index);
      for (final seg in segments) {
        final text = (seg['text'] as String? ?? '').trim();
        if (text.isEmpty) continue;
        final startOffset = (seg['start'] as num? ?? 0.0).toDouble();
        final speaker = seg['speaker'] as String? ?? '?';
        s.entries.add(
          TranscriptEntry(
            kind: EntryKind.transcript,
            text: text,
            time: started.add(Duration(milliseconds: (startOffset * 1000).toInt())),
            speaker: speaker,
          ),
        );
      }
      s.entries.sort((a, b) => a.time.compareTo(b.time));
    });
  }

  void setNotesPath(String sessionID, String path) {
    final index = sessions.indexWhere((s) => s.id == sessionID);
    if (index != -1 && sessions[index].notesPath != path) {
      sessions[index].notesPath = path;
      save();
    }
  }

  String? recentText({int limit = 6000}) {
    final curr = current;
    if (curr == null) return null;
    final text = curr.displayEntries
        .where((e) => e.kind != EntryKind.report)
        .map((e) => (e.kind == EntryKind.reply ? "Bluey: " : "") + e.text)
        .join("\n");
    if (text.isEmpty) return null;
    return text.length > limit ? text.substring(text.length - limit) : text;
  }

  void delete(String id) {
    if (id == currentID) currentID = null;
    sessions.removeWhere((s) => s.id == id);
    save();
  }

  void _update(Function(BlueySession s) change) {
    if (currentID == null) return;
    _updateSession(currentID!, change);
  }

  void _updateSession(String id, Function(BlueySession s) change) {
    final index = sessions.indexWhere((s) => s.id == id);
    if (index == -1) return;
    change(sessions[index]);
    _dirty.add(id);
    _scheduleSync();
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), save);
  }

  void _scheduleSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 6), () {
      final changed = sessions.where((s) => _dirty.contains(s.id)).toList();
      _dirty.clear();
      if (changed.isNotEmpty) {
        onSync?.call(changed);
      }
    });
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    if (_file == null) return;
    try {
      final jsonList = sessions.map((s) => s.toJson()).toList();
      final content = jsonEncode(jsonList);
      await _file!.writeAsString(content);
    } catch (e) {
      // Ignore save errors
    }
  }

  /// Generates Markdown notes for a session (notes.md) matching MeetingNotes.swift format.
  static String generateMarkdownNotes(Map<String, dynamic> sessionJson) {
    final startedAt = (sessionJson['started'] as num? ?? 0).toDouble();
    final started = DateTime.fromMillisecondsSinceEpoch((startedAt * 1000).toInt());

    final endedAt = sessionJson['ended'] as num?;
    final ended = endedAt != null
        ? DateTime.fromMillisecondsSinceEpoch((endedAt * 1000).toInt())
        : null;

    final entries = sessionJson['entries'] as List<dynamic>? ?? [];
    final pending = (sessionJson['transcribing'] as num? ?? 0).toInt();

    final buffer = StringBuffer();
    buffer.writeln("# Bluey session: ${started.toIso8601String()}");
    buffer.writeln();

    if (ended != null) {
      final minutes = ended.difference(started).inMinutes;
      buffer.writeln("Ended ${ended.toString()} (${minutes ~/ 60}h ${minutes % 60}m).");
    } else {
      buffer.writeln("Still recording.");
    }

    if (pending > 0) {
      buffer.writeln("$pending recording chunk(s) still being transcribed; this file updates when they're done.");
    }

    final askedCount = entries.where((e) => (e as Map)['kind'] == 'asked').length;
    if (askedCount > 0) {
      buffer.writeln("Asked Bluey $askedCount question(s); they're marked inline below.");
    }

    buffer.writeln();
    buffer.writeln("## Transcript");
    buffer.writeln();

    for (final rawEntry in entries) {
      final entry = rawEntry as Map<String, dynamic>;
      final text = (entry['text'] as String? ?? '').trim();
      if (text.isEmpty) continue;

      final entryTimeNum = entry['time'] as num?;
      final entryTime = entryTimeNum != null
          ? DateTime.fromMillisecondsSinceEpoch((entryTimeNum * 1000).toInt())
          : DateTime.now();
      final timeStr = "${entryTime.hour}:${entryTime.minute.toString().padLeft(2, '0')}:${entryTime.second.toString().padLeft(2, '0')}";

      final kind = entry['kind'] as String? ?? 'heard';
      switch (kind) {
        case 'transcript':
          final speaker = entry['speaker'] as String? ?? '?';
          buffer.writeln("**[$timeStr] Speaker $speaker:** $text");
          break;
        case 'heard':
          buffer.writeln("[$timeStr] (live) $text");
          break;
        case 'asked':
          buffer.writeln("> **[$timeStr] User asked Bluey:** $text");
          break;
        case 'reply':
          buffer.writeln("> **Bluey:** $text");
          break;
        case 'report':
          final quoted = text.split('\n').map((l) => "> $l").join('\n');
          buffer.writeln("> **Research report:**\n$quoted");
          break;
        default:
          buffer.writeln("[$timeStr] $text");
      }
      buffer.writeln();
    }
    return buffer.toString();
  }
}
