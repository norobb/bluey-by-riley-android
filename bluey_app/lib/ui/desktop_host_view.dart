import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../audio/chirp_synthesizer.dart';
import '../graphics/cursor_overlay_graphics.dart';
import '../platform/computer_control.dart';
import '../platform/hotkeys.dart';
import '../protocol/googly_protocol.dart';
import '../protocol/phone_server.dart';
import '../storage/session_store.dart';

class DesktopHostView extends StatefulWidget {
  final SessionStore store;
  final bool enableAnimation;
  final bool enableServer;

  const DesktopHostView({
    super.key,
    required this.store,
    this.enableAnimation = true,
    this.enableServer = true,
  });

  @override
  State<DesktopHostView> createState() => _DesktopHostViewState();
}

class _DesktopHostViewState extends State<DesktopHostView>
    with SingleTickerProviderStateMixin {
  AnimationController? _ticker;
  final PhoneServer _phoneServer = PhoneServer();

  // Settings Parity with Settings.swift
  bool _awake = true;
  bool _followMouse = true;
  double _cursorSize = 72.0;
  double _phonePosition = 0.5;
  Mood _mood = Mood.listening;
  PointerTrailMode _trailMode = PointerTrailMode.comet;
  bool _glow = true;
  bool _showCursor = true;
  String _personality = "";
  String _apiKey = "";

  // Dynamic Overlay State
  CursorMode _mode = CursorMode.following;
  Offset _cursorTip = const Offset(400, 300);
  Offset _targetPoint = const Offset(400, 300);
  Offset _mousePos = const Offset(400, 300);
  String _caption = "";
  double _speechBorn = 0.0;
  final List<TrailPoint> _trailPoints = [];
  List<String> _connectedPhones = [];

  @override
  void initState() {
    super.initState();
    if (widget.enableAnimation) {
      _ticker = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1000),
      )..repeat();
    }

    if (widget.enableServer) {
      _setupServer();
    }
    _setupHotKeys();
  }

  void _setupServer() {
    _phoneServer.onPhonesChanged = (names) {
      if (mounted) {
        setState(() {
          _connectedPhones = names;
        });
      }
    };
    _phoneServer.onRequest = (packet, reply) {
      if (packet.command == "wake") {
        setState(() => _awake = true);
        reply(Packet(command: "ack_wake"));
      } else if (packet.command == "sleep") {
        setState(() => _awake = false);
        reply(Packet(command: "ack_sleep"));
      }
    };
    _phoneServer.start();
  }

  void _setupHotKeys() {
    final hk = GlobalHotKeyManager();
    hk.register(HotKeyAction.toggleAwake, _toggleAwake);
    hk.register(HotKeyAction.pointHere, _pointHere);
    hk.register(HotKeyAction.toggleFollow, _toggleFollow);
    hk.register(HotKeyAction.goHome, _dock);
    hk.register(HotKeyAction.talkTest, _talkTest);
    hk.register(HotKeyAction.toggleShow, () => setState(() => _showCursor = !_showCursor));
    hk.register(HotKeyAction.stopActions, _stopActions);
    HardwareKeyboard.instance.addHandler(hk.handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(GlobalHotKeyManager().handleKeyEvent);
    if (_ticker != null) {
      _ticker!.stop();
      _ticker!.dispose();
    }
    if (widget.enableServer) {
      _phoneServer.stop();
    }
    super.dispose();
  }

  void _toggleAwake() {
    setState(() {
      _awake = !_awake;
    });
    ChirpSynthesizer.playChirp(syllables: 2);
    if (widget.enableServer) {
      _phoneServer.broadcast(Packet(command: _awake ? "wake" : "sleep"));
    }
  }

  void _stopActions() {
    ComputerControl.stopActions();
    setState(() {
      _caption = "Stopped! Waiting for permission.";
      _speechBorn = DateTime.now().millisecondsSinceEpoch / 1000.0;
    });
  }

  void _pointHere() {
    setState(() {
      _mode = CursorMode.pointing;
      _targetPoint = _mousePos;
      _caption = "Pointing right here!";
      _speechBorn = DateTime.now().millisecondsSinceEpoch / 1000.0;
    });
    ChirpSynthesizer.playChirp(syllables: 1);
  }

  void _toggleFollow() {
    setState(() {
      _followMouse = !_followMouse;
      if (_followMouse) {
        _mode = CursorMode.following;
      } else {
        _mode = CursorMode.docked;
      }
    });
  }

  void _dock() {
    setState(() {
      _mode = _followMouse ? CursorMode.following : CursorMode.docked;
      _caption = "";
    });
  }

  void _talkTest() {
    setState(() {
      _caption = "Hello! I am Bluey on your desktop screen.";
      _speechBorn = DateTime.now().millisecondsSinceEpoch / 1000.0;
    });
    ChirpSynthesizer.playChirp(syllables: 3);
  }

  void _onHover(PointerEvent event) {
    _mousePos = event.position;
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    if (_mode == CursorMode.following) {
      _cursorTip = Offset(
        _cursorTip.dx + (_mousePos.dx - _cursorTip.dx) * 0.25,
        _cursorTip.dy + (_mousePos.dy - _cursorTip.dy) * 0.25,
      );
    } else if (_mode == CursorMode.pointing) {
      _cursorTip = Offset(
        _cursorTip.dx + (_targetPoint.dx - _cursorTip.dx) * 0.2,
        _cursorTip.dy + (_targetPoint.dy - _cursorTip.dy) * 0.2,
      );
    } else if (_mode == CursorMode.docked) {
      final dockX = context.size != null ? context.size!.width * _phonePosition : 400.0;
      final dockY = context.size != null ? context.size!.height - 120.0 : 500.0;
      _cursorTip = Offset(
        _cursorTip.dx + (dockX - _cursorTip.dx) * 0.15,
        _cursorTip.dy + (dockY - _cursorTip.dy) * 0.15,
      );
    }

    if (_trailMode == PointerTrailMode.comet) {
      _trailPoints.add(TrailPoint(position: _cursorTip, timestamp: now));
      _trailPoints.removeWhere((p) => now - p.timestamp > 0.6);
    }

    if (widget.enableServer) {
      _phoneServer.send(FaceState(
        gazeX: (_cursorTip.dx / (context.size?.width ?? 1000.0) - 0.5) * 2.0,
        gazeY: (_cursorTip.dy / (context.size?.height ?? 1000.0) - 0.5) * 2.0,
        mood: _mood,
        talk: _caption.isNotEmpty ? 1.0 : 0.0,
      ));
    }
  }

  void _showPersonalityDialog() {
    final controller = TextEditingController(text: _personality);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(Palette.panel),
        title: const Text("His Personality", style: TextStyle(color: Colors.white, fontFamily: 'Fredoka')),
        content: SizedBox(
          width: 480,
          height: 220,
          child: TextField(
            controller: controller,
            maxLines: 8,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Describe who he is and how he talks...",
              hintStyle: TextStyle(color: Colors.white38),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _personality = "");
              Navigator.pop(ctx);
            },
            child: const Text("Reset Default", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _personality = controller.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: _apiKey);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(Palette.panel),
        title: const Text("API Key", style: TextStyle(color: Colors.white, fontFamily: 'Fredoka')),
        content: SizedBox(
          width: 380,
          child: TextField(
            controller: controller,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: "Paste your API key here (e.g. sk-...)",
              hintStyle: TextStyle(color: Colors.white38),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel", style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _apiKey = controller.text);
              Navigator.pop(ctx);
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showNotesDialog() {
    final sessionMap = widget.store.sessions.isNotEmpty
        ? widget.store.sessions.first.toJson()
        : <String, dynamic>{'started': DateTime.now().millisecondsSinceEpoch / 1000.0, 'entries': []};
    final notes = SessionStore.generateMarkdownNotes(sessionMap);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(Palette.panel),
        title: const Text("Meeting Notes", style: TextStyle(color: Colors.white, fontFamily: 'Fredoka')),
        content: SizedBox(
          width: 500,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              notes.isEmpty ? "No active meeting notes yet." : notes,
              style: const TextStyle(color: Colors.white70, fontFamily: 'IBMPlexMono'),
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Close"),
          ),
        ],
      ),
    );
  }

  void _showPermissionsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(Palette.panel),
        title: const Text("Allow Clicking and Typing", style: TextStyle(color: Colors.white, fontFamily: 'Fredoka')),
        content: const Text(
          "To let Bluey control your computer cursor and typing, ensure desktop accessibility and input automation permissions are granted in your system settings.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Got It"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;

    return Scaffold(
      backgroundColor: const Color(Palette.ink),
      body: MouseRegion(
        onHover: _onHover,
        child: Stack(
          children: [
            // Live Interactive Desktop Overlay Canvas
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _ticker ?? const AlwaysStoppedAnimation(0.0),
                builder: (context, child) {
                  final size = MediaQuery.of(context).size;
                  final phoneStart = Offset(size.width * _phonePosition, size.height - 40);

                  return CustomPaint(
                    painter: _DesktopOverlayPainter(
                      tip: _cursorTip,
                      cursorSize: _cursorSize,
                      showCursor: _showCursor,
                      glow: _glow,
                      trailMode: _trailMode,
                      trailPoints: _trailPoints,
                      phoneStart: phoneStart,
                      caption: _caption,
                      speechBorn: _speechBorn,
                      now: now,
                      mousePos: _mousePos,
                    ),
                  );
                },
              ),
            ),

            // macOS Control Bar / System Menu Panel
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(Palette.panel).withOpacity(0.92),
                  border: const Border(bottom: BorderSide(color: Colors.white10)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Phone Connection Status Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _connectedPhones.isEmpty ? Icons.phone_android_outlined : Icons.phone_android,
                              size: 16,
                              color: _connectedPhones.isEmpty ? Colors.white38 : Colors.greenAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _connectedPhones.isEmpty
                                  ? "Waiting for phone app..."
                                  : "Phone connected: ${_connectedPhones.join(', ')}",
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Wake / Sleep Toggle
                      ElevatedButton.icon(
                        onPressed: _toggleAwake,
                        icon: Icon(_awake ? Icons.nightlight_round : Icons.wb_sunny_rounded, size: 16),
                        label: Text(_awake ? "Go to Sleep (⌥Space)" : "Wake Up and Talk"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _awake ? const Color(Palette.berry3) : Colors.green.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Computer Control Toggle
                      FilterChip(
                        selected: ComputerControl.computerControlEnabled,
                        label: const Text("Let Him Use Computer"),
                        onSelected: (val) {
                          setState(() {
                            ComputerControl.computerControlEnabled = val;
                          });
                          if (val) _showPermissionsDialog();
                        },
                        selectedColor: const Color(Palette.berry2),
                        checkmarkColor: Colors.white,
                        labelStyle: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(width: 8),

                      // Stop Him Emergency Stop
                      OutlinedButton.icon(
                        onPressed: _stopActions,
                        icon: const Icon(Icons.stop_circle_outlined, size: 16, color: Colors.redAccent),
                        label: const Text("Stop Him (⌃⌥S)", style: TextStyle(color: Colors.redAccent)),
                      ),
                      const SizedBox(width: 12),

                      // Action Buttons: Point Here, Follow, Dock, Talk
                      IconButton(
                        tooltip: "Point Here (⌃⌥P)",
                        icon: const Icon(Icons.touch_app, color: Colors.white70),
                        onPressed: _pointHere,
                      ),
                      IconButton(
                        tooltip: "Eyes Follow My Mouse (⌃⌥F)",
                        icon: Icon(_followMouse ? Icons.visibility : Icons.visibility_off,
                            color: _followMouse ? const Color(Palette.berry1) : Colors.white38),
                        onPressed: _toggleFollow,
                      ),
                      IconButton(
                        tooltip: "Stop Pointing (⌃⌥D)",
                        icon: const Icon(Icons.anchor, color: Colors.white70),
                        onPressed: _dock,
                      ),
                      IconButton(
                        tooltip: "Talk Test (⌃⌥T)",
                        icon: const Icon(Icons.record_voice_over, color: Colors.white70),
                        onPressed: _talkTest,
                      ),
                      const SizedBox(width: 8),

                      // Mood Popup
                      PopupMenuButton<Mood>(
                        tooltip: "Mood",
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text("Mood: ${_mood.title}", style: const TextStyle(color: Colors.white)),
                              const Icon(Icons.arrow_drop_down, color: Colors.white70),
                            ],
                          ),
                        ),
                        onSelected: (m) => setState(() => _mood = m),
                        itemBuilder: (ctx) => Mood.values
                            .where((m) => m != Mood.talking && m != Mood.pointing && m != Mood.sleepy)
                            .map((m) => PopupMenuItem(value: m, child: Text(m.title)))
                            .toList(),
                      ),
                      const SizedBox(width: 8),

                      // Size Popup
                      PopupMenuButton<double>(
                        tooltip: "Cursor Size",
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text("Size: ${_cursorSize.round()}pt", style: const TextStyle(color: Colors.white)),
                              const Icon(Icons.arrow_drop_down, color: Colors.white70),
                            ],
                          ),
                        ),
                        onSelected: (s) => setState(() => _cursorSize = s),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: 48.0, child: Text("Small (48 pt)")),
                          PopupMenuItem(value: 72.0, child: Text("Medium (72 pt)")),
                          PopupMenuItem(value: 96.0, child: Text("Large (96 pt)")),
                          PopupMenuItem(value: 120.0, child: Text("Huge (120 pt)")),
                        ],
                      ),
                      const SizedBox(width: 8),

                      // Trail Popup
                      PopupMenuButton<PointerTrailMode>(
                        tooltip: "Pointer Trail",
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text("Trail: ${_trailMode.name.toUpperCase()}",
                                  style: const TextStyle(color: Colors.white)),
                              const Icon(Icons.arrow_drop_down, color: Colors.white70),
                            ],
                          ),
                        ),
                        onSelected: (t) => setState(() => _trailMode = t),
                        itemBuilder: (ctx) => const [
                          PopupMenuItem(value: PointerTrailMode.none, child: Text("None")),
                          PopupMenuItem(value: PointerTrailMode.comet, child: Text("Comet")),
                          PopupMenuItem(value: PointerTrailMode.string, child: Text("String")),
                        ],
                      ),
                      const SizedBox(width: 8),

                      // Dialog Triggers: Notes, Personality, API Key
                      IconButton(
                        tooltip: "Open Meeting Notes",
                        icon: const Icon(Icons.note_alt_outlined, color: Colors.white70),
                        onPressed: _showNotesDialog,
                      ),
                      IconButton(
                        tooltip: "Personality...",
                        icon: const Icon(Icons.psychology, color: Colors.white70),
                        onPressed: _showPersonalityDialog,
                      ),
                      IconButton(
                        tooltip: "API Key...",
                        icon: const Icon(Icons.key, color: Colors.white70),
                        onPressed: _showApiKeyDialog,
                      ),
                      const SizedBox(width: 8),

                      // Glow & Show Cursor Toggles
                      FilterChip(
                        selected: _glow,
                        label: const Text("Glow"),
                        onSelected: (v) => setState(() => _glow = v),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        selected: _showCursor,
                        label: const Text("Show Cursor (⌃⌥H)"),
                        onSelected: (v) => setState(() => _showCursor = v),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopOverlayPainter extends CustomPainter {
  final Offset tip;
  final double cursorSize;
  final bool showCursor;
  final bool glow;
  final PointerTrailMode trailMode;
  final List<TrailPoint> trailPoints;
  final Offset phoneStart;
  final String caption;
  final double speechBorn;
  final double now;
  final Offset mousePos;

  _DesktopOverlayPainter({
    required this.tip,
    required this.cursorSize,
    required this.showCursor,
    required this.glow,
    required this.trailMode,
    required this.trailPoints,
    required this.phoneStart,
    required this.caption,
    required this.speechBorn,
    required this.now,
    required this.mousePos,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trailMode == PointerTrailMode.comet) {
      CometTrailPainter(points: trailPoints, currentTime: now).paint(canvas, size);
    } else if (trailMode == PointerTrailMode.string) {
      StringTrailPainter(start: phoneStart, end: tip).paint(canvas, size);
    }

    if (showCursor) {
      final dx = mousePos.dx - tip.dx;
      final dy = mousePos.dy - tip.dy;
      final dist = max(1.0, sqrt(dx * dx + dy * dy));
      final look = Offset((dx / dist).clamp(-1.0, 1.0), (dy / dist).clamp(-1.0, 1.0));

      TeardropCursorPainter(
        tip: tip,
        angle: 0.0,
        size: cursorSize,
        glow: glow,
        look: look,
      ).paint(canvas, size);
    }

    if (caption.isNotEmpty) {
      SpeechBubblePainter(
        text: caption,
        target: tip,
        bornTime: speechBorn,
        currentTime: now,
      ).paint(canvas, size);
    }
  }

  @override
  bool shouldRepaint(covariant _DesktopOverlayPainter oldDelegate) => true;
}
