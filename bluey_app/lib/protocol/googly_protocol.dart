import 'dart:ui';

/// Everything the Mac, phone, and target platforms agree on:
/// the service name, face update payload, palette, and packet protocol.
class GooglyService {
  static const String type = '_googly._tcp';
}

enum Mood {
  listening,
  resting,
  thinking,
  talking,
  pointing,
  happy,
  sleepy;

  String get title => name[0].toUpperCase() + name.substring(1);

  static Mood fromString(String raw) {
    return Mood.values.firstWhere(
      (m) => m.name.toLowerCase() == raw.toLowerCase(),
      orElse: () => Mood.listening,
    );
  }
}

/// What the phone should show right now.
class FaceState {
  double gazeX;
  double gazeY;
  Mood mood;
  double talk;

  FaceState({
    this.gazeX = 0.0,
    this.gazeY = 0.0,
    this.mood = Mood.listening,
    this.talk = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'gazeX': gazeX,
        'gazeY': gazeY,
        'mood': mood.name,
        'talk': talk,
      };

  factory FaceState.fromJson(Map<String, dynamic> json) {
    return FaceState(
      gazeX: (json['gazeX'] as num?)?.toDouble() ?? 0.0,
      gazeY: (json['gazeY'] as num?)?.toDouble() ?? 0.0,
      mood: json['mood'] != null
          ? Mood.fromString(json['mood'].toString())
          : Mood.listening,
      talk: (json['talk'] as num?)?.toDouble() ?? 0.0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaceState &&
          runtimeType == other.runtimeType &&
          gazeX == other.gazeX &&
          gazeY == other.gazeY &&
          mood == other.mood &&
          talk == other.talk;

  @override
  int get hashCode =>
      gazeX.hashCode ^ gazeY.hashCode ^ mood.hashCode ^ talk.hashCode;
}

class Packet {
  FaceState? face;
  String? hello;
  double? volume;
  String? command;
  String? audio;
  int? speech;
  String? callID;
  String? tool;
  String? text;
  String? image;

  Packet({
    this.face,
    this.hello,
    this.volume,
    this.command,
    this.audio,
    this.speech,
    this.callID,
    this.tool,
    this.text,
    this.image,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (face != null) map['face'] = face!.toJson();
    if (hello != null) map['hello'] = hello;
    if (volume != null) map['volume'] = volume;
    if (command != null) map['command'] = command;
    if (audio != null) map['audio'] = audio;
    if (speech != null) map['speech'] = speech;
    if (callID != null) map['callID'] = callID;
    if (tool != null) map['tool'] = tool;
    if (text != null) map['text'] = text;
    if (image != null) map['image'] = image;
    return map;
  }

  factory Packet.fromJson(Map<String, dynamic> json) {
    return Packet(
      face: json['face'] != null
          ? FaceState.fromJson(json['face'] as Map<String, dynamic>)
          : null,
      hello: json['hello'] as String?,
      volume: (json['volume'] as num?)?.toDouble(),
      command: json['command'] as String?,
      audio: json['audio'] as String?,
      speech: json['speech'] as int?,
      callID: json['callID'] as String?,
      tool: json['tool'] as String?,
      text: json['text'] as String?,
      image: json['image'] as String?,
    );
  }
}

/// Blueberry colors from the design canvas (0xRRGGBB).
class Palette {
  static const int berry1 = 0xA9BCFF; // light periwinkle
  static const int berry2 = 0x6C86F5;
  static const int berry3 = 0x4254D6;
  static const int berry4 = 0x2B2F8F; // deep indigo
  static const int nose = 0x1C1F66;
  static const int ink = 0x17151F;
  static const int inkSoft = 0xB9B2CC;
  static const int panel = 0x1E1B29;

  static const List<int> gradient = [berry1, berry2, berry3, berry4];
  static const List<double> gradientStops = [0.0, 0.34, 0.68, 1.0];

  static Color color(int hex, [double opacity = 1.0]) {
    final r = (hex >> 16) & 0xFF;
    final g = (hex >> 8) & 0xFF;
    final b = hex & 0xFF;
    return Color.fromRGBO(r, g, b, opacity);
  }
}
