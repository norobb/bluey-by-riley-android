import 'package:uuid/uuid.dart';

enum EntryKind {
  heard,
  asked,
  reply,
  report,
  transcript;

  static EntryKind fromString(String raw) {
    return EntryKind.values.firstWhere(
      (k) => k.name == raw,
      orElse: () => EntryKind.heard,
    );
  }
}

class TranscriptEntry {
  final String id;
  EntryKind kind;
  String text;
  DateTime time;
  String? itemID;
  String? speaker;

  TranscriptEntry({
    String? id,
    required this.kind,
    required this.text,
    required this.time,
    this.itemID,
    this.speaker,
  }) : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'text': text,
        'time': time.millisecondsSinceEpoch / 1000.0,
        if (itemID != null) 'itemID': itemID,
        if (speaker != null) 'speaker': speaker,
      };

  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    final rawTime = json['time'];
    DateTime timeVal;
    if (rawTime is num) {
      timeVal = DateTime.fromMillisecondsSinceEpoch((rawTime * 1000).toInt());
    } else if (rawTime is String) {
      timeVal = DateTime.tryParse(rawTime) ?? DateTime.now();
    } else {
      timeVal = DateTime.now();
    }

    return TranscriptEntry(
      id: json['id'] as String?,
      kind: json['kind'] != null
          ? EntryKind.fromString(json['kind'].toString())
          : EntryKind.heard,
      text: (json['text'] as String?) ?? '',
      time: timeVal,
      itemID: json['itemID'] as String?,
      speaker: json['speaker'] as String?,
    );
  }
}

class PendingChunk {
  final int index;
  final DateTime started;

  PendingChunk({required this.index, required this.started});

  Map<String, dynamic> toJson() => {
        'index': index,
        'started': started.millisecondsSinceEpoch / 1000.0,
      };

  factory PendingChunk.fromJson(Map<String, dynamic> json) {
    final rawStarted = json['started'];
    DateTime startVal;
    if (rawStarted is num) {
      startVal =
          DateTime.fromMillisecondsSinceEpoch((rawStarted * 1000).toInt());
    } else {
      startVal = DateTime.now();
    }
    return PendingChunk(
      index: (json['index'] as num?)?.toInt() ?? 0,
      started: startVal,
    );
  }
}

class BlueySession {
  final String id;
  final DateTime started;
  DateTime? ended;
  List<TranscriptEntry> entries;
  String? notesPath;
  List<PendingChunk>? pending;

  BlueySession({
    String? id,
    required this.started,
    this.ended,
    List<TranscriptEntry>? entries,
    this.notesPath,
    this.pending,
  })  : id = id ?? const Uuid().v4(),
        entries = entries ?? [];

  int get questionCount => entries.where((e) => e.kind == EntryKind.asked).length;

  String get summary {
    final asked = entries.firstWhere(
      (e) => e.kind == EntryKind.asked && e.text.isNotEmpty,
      orElse: () => TranscriptEntry(kind: EntryKind.asked, text: '', time: DateTime.now()),
    );
    if (asked.text.isNotEmpty) return asked.text;

    final display = displayEntries.firstWhere(
      (e) => (e.kind == EntryKind.transcript || e.kind == EntryKind.heard) && e.text.isNotEmpty,
      orElse: () => TranscriptEntry(kind: EntryKind.heard, text: '', time: DateTime.now()),
    );
    return display.text.isNotEmpty ? display.text : "Nothing said yet";
  }

  Duration get duration => (ended ?? DateTime.now()).difference(started);

  List<TranscriptEntry> get displayEntries {
    final transcriptEntries = entries.where((e) => e.kind == EntryKind.transcript);
    final properUntil = transcriptEntries.isEmpty
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : transcriptEntries.map((e) => e.time).reduce((a, b) => a.isAfter(b) ? a : b);

    final filtered = entries.where((e) {
      if (e.text.isEmpty) return false;
      if (e.kind == EntryKind.heard && !e.time.isAfter(properUntil)) {
        return false;
      }
      return true;
    }).toList();

    filtered.sort((a, b) => a.time.compareTo(b.time));
    return filtered;
  }

  int get transcribing => pending?.length ?? 0;

  String get exportText {
    final buffer = StringBuffer();
    buffer.writeln("Bluey session, ${started.toString()}");
    buffer.writeln();

    for (final entry in displayEntries) {
      String who;
      switch (entry.kind) {
        case EntryKind.transcript:
          who = "Speaker ${entry.speaker ?? '?'}";
          break;
        case EntryKind.heard:
          who = "You";
          break;
        case EntryKind.asked:
          who = "You asked";
          break;
        case EntryKind.reply:
          who = "Bluey";
          break;
        case EntryKind.report:
          who = "Research";
          break;
      }
      buffer.writeln("[${entry.time.hour}:${entry.time.minute.toString().padLeft(2, '0')}:${entry.time.second.toString().padLeft(2, '0')}] $who: ${entry.text}");
    }
    return buffer.toString();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'started': started.millisecondsSinceEpoch / 1000.0,
        if (ended != null) 'ended': ended!.millisecondsSinceEpoch / 1000.0,
        'entries': entries.map((e) => e.toJson()).toList(),
        if (notesPath != null) 'notesPath': notesPath,
        if (pending != null) 'pending': pending!.map((p) => p.toJson()).toList(),
      };

  factory BlueySession.fromJson(Map<String, dynamic> json) {
    final rawStarted = json['started'];
    final startVal = rawStarted is num
        ? DateTime.fromMillisecondsSinceEpoch((rawStarted * 1000).toInt())
        : DateTime.now();

    final rawEnded = json['ended'];
    final endVal = rawEnded is num
        ? DateTime.fromMillisecondsSinceEpoch((rawEnded * 1000).toInt())
        : null;

    final rawEntries = json['entries'] as List<dynamic>? ?? [];
    final entriesList = rawEntries
        .map((e) => TranscriptEntry.fromJson(e as Map<String, dynamic>))
        .toList();

    final rawPending = json['pending'] as List<dynamic>?;
    final pendingList = rawPending
        ?.map((p) => PendingChunk.fromJson(p as Map<String, dynamic>))
        .toList();

    return BlueySession(
      id: json['id'] as String?,
      started: startVal,
      ended: endVal,
      entries: entriesList,
      notesPath: json['notesPath'] as String?,
      pending: pendingList,
    );
  }
}
