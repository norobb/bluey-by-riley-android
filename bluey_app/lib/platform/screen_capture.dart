import 'dart:ui';

class Target {
  final String id;
  final String text;
  final Rect rect;

  Target({
    required this.id,
    required this.text,
    required this.rect,
  });
}

class ScreenSnapshot {
  final List<int> jpegBytes;
  final List<Target> controls;
  final List<Target> lines;
  final List<Target> words;
  final Size size;
  final String? appName;

  ScreenSnapshot({
    required this.jpegBytes,
    required this.controls,
    required this.lines,
    required this.words,
    required this.size,
    this.appName,
  });

  Target? findTarget(String id) {
    final cleanId = id.trim().toUpperCase();
    for (final c in controls) {
      if (c.id == cleanId) return c;
    }
    for (final l in lines) {
      if (l.id == cleanId) return l;
    }
    for (final w in words) {
      if (w.id == cleanId) return w;
    }
    return null;
  }

  String get targetList {
    String grid(Rect r) {
      final x = (r.center.dx / size.width * 1000).round();
      final y = (r.center.dy / size.height * 1000).round();
      return "@$x,$y";
    }

    final out = <String>[];
    if (appName != null) {
      out.add("Frontmost app: $appName");
    }
    if (controls.isNotEmpty) {
      out.add("Controls (click these by id):");
      for (final c in controls) {
        out.add("${c.id} control ${grid(c.rect)} \"${c.text}\"");
      }
    }
    out.add("Text on screen (L = line, W = word, @x,y on a 0-1000 grid):");
    if (lines.isEmpty) {
      out.add("(no text found)");
    } else {
      for (final l in lines) {
        out.add("${l.id} ${grid(l.rect)} \"${l.text}\"");
      }
    }
    return out.join("\n");
  }
}

class ScreenCaptureEngine {
  static Future<ScreenSnapshot> capture({Size screenSize = const Size(1440, 900)}) async {
    // Simulated screen snapshot fallback structure with sample target elements
    final dummyLines = [
      Target(id: "L1", text: "Welcome to Bluey", rect: const Rect.fromLTWH(200, 100, 400, 40)),
      Target(id: "L2", text: "Click to start session", rect: const Rect.fromLTWH(200, 160, 300, 30)),
    ];
    final dummyWords = [
      Target(id: "W1", text: "Welcome", rect: const Rect.fromLTWH(200, 100, 100, 40)),
      Target(id: "W2", text: "Bluey", rect: const Rect.fromLTWH(350, 100, 80, 40)),
    ];
    final dummyControls = [
      Target(id: "C1", text: "Start", rect: const Rect.fromLTWH(200, 220, 100, 40)),
    ];

    return ScreenSnapshot(
      jpegBytes: [0xFF, 0xD8, 0xFF, 0xD9], // Valid minimal JPEG bytes
      controls: dummyControls,
      lines: dummyLines,
      words: dummyWords,
      size: screenSize,
      appName: "Desktop",
    );
  }
}
