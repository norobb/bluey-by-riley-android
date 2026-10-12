import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../graphics/blob_shape.dart';
import '../models/session_models.dart';
import '../protocol/googly_protocol.dart';
import '../storage/session_store.dart';

class BlueyAppView extends StatefulWidget {
  final SessionStore store;
  final bool isConnected;
  final String? macName;
  final List<String> macs;
  final String? currentMac;
  final VoidCallback onClose;
  final VoidCallback onToggleSession;
  final bool isSessionRunning;

  const BlueyAppView({
    super.key,
    required this.store,
    required this.isConnected,
    this.macName,
    required this.macs,
    this.currentMac,
    required this.onClose,
    required this.onToggleSession,
    required this.isSessionRunning,
  });

  @override
  State<BlueyAppView> createState() => _BlueyAppViewState();
}

class _BlueyAppViewState extends State<BlueyAppView> {
  String? _selectedSessionID;

  @override
  Widget build(BuildContext context) {
    final selectedSession = widget.store.sessions.firstWhere(
      (s) => s.id == _selectedSessionID,
      orElse: () => widget.store.sessions.isNotEmpty
          ? widget.store.sessions.first
          : BlueySession(started: DateTime.now()),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 300,
            color: const Color(Palette.panel).withOpacity(0.6),
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const MiniBluey(size: Size(54, 48)),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Bluey",
                          style: TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: widget.isConnected
                                    ? const Color(0xFF5BE49B)
                                    : const Color(Palette.inkSoft).withOpacity(0.5),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              widget.isConnected
                                  ? (widget.macName ?? widget.currentMac ?? "Computer")
                                  : "Looking for computer",
                              style: const TextStyle(
                                fontFamily: 'IBMPlexSans',
                                fontSize: 12,
                                color: Color(Palette.inkSoft),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onToggleSession();
                      if (!widget.isSessionRunning) {
                        widget.onClose();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !widget.isSessionRunning
                          ? const Color(Palette.berry2)
                          : const Color(0xFFE5547A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(!widget.isSessionRunning ? Icons.play_arrow : Icons.stop, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          !widget.isSessionRunning ? "Start session" : "End session",
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  !widget.isSessionRunning
                      ? "He listens the whole session. Hold his face to ask something, let go and he answers."
                      : "Session running. Hold his face to ask; everything you say is saved here.",
                  style: const TextStyle(
                    fontFamily: 'IBMPlexSans',
                    fontSize: 12,
                    color: Color(Palette.inkSoft),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.face, color: Colors.white),
                    label: const Text(
                      "Back to his face",
                      style: TextStyle(
                        fontFamily: 'IBMPlexSans',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.08),
                      side: BorderSide.none,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Main content: sessions list + detail
          Expanded(
            child: widget.store.sessions.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Color(Palette.berry2)),
                        SizedBox(height: 12),
                        Text(
                          "No sessions yet",
                          style: TextStyle(fontFamily: 'Fredoka', fontSize: 20, color: Colors.white),
                        ),
                        SizedBox(height: 6),
                        Text(
                          "Start one and your transcript and his replies show up here.",
                          style: TextStyle(fontFamily: 'IBMPlexSans', fontSize: 13, color: Color(Palette.inkSoft)),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: [
                      // Sessions list
                      SizedBox(
                        width: 280,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Text(
                                "Sessions (${widget.store.sessions.length})",
                                style: const TextStyle(
                                  fontFamily: 'Fredoka',
                                  fontSize: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                itemCount: widget.store.sessions.length,
                                itemBuilder: (context, index) {
                                  final session = widget.store.sessions[index];
                                  final isSelected = session.id == selectedSession.id;
                                  return ListTile(
                                    selected: isSelected,
                                    selectedTileColor: const Color(Palette.panel),
                                    title: Text(
                                      session.started.toString().substring(0, 16),
                                      style: const TextStyle(
                                        fontFamily: 'IBMPlexSans',
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    subtitle: Text(
                                      session.summary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'IBMPlexSans',
                                        fontSize: 12,
                                        color: Color(Palette.inkSoft),
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() => _selectedSessionID = session.id);
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1, color: Colors.white10),
                      // Session detail view
                      Expanded(
                        child: SessionDetailWidget(session: selectedSession),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class SessionDetailWidget extends StatefulWidget {
  final BlueySession session;

  const SessionDetailWidget({super.key, required this.session});

  @override
  State<SessionDetailWidget> createState() => _SessionDetailWidgetState();
}

class _SessionDetailWidgetState extends State<SessionDetailWidget> {
  bool _copied = false;

  void _copyPrompt() {
    final prompt = """
I recorded a meeting with my Bluey app on ${widget.session.started.toString()}.
The notes are saved on my computer. Read the notes in notes.md, then help me summarize.
""";
    Clipboard.setData(ClipboardData(text: prompt));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Detail Header
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.session.started.toString().substring(0, 16),
                    style: const TextStyle(
                      fontFamily: 'Fredoka',
                      fontSize: 20,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    "${widget.session.duration.inMinutes}m · ${widget.session.questionCount} asked",
                    style: const TextStyle(
                      fontFamily: 'IBMPlexMono',
                      fontSize: 12,
                      color: Color(Palette.inkSoft),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _copyPrompt,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? "Copied" : "Copy prompt for agent"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(Palette.berry3),
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Colors.white10),
        // Transcript Timeline Entries
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: widget.session.displayEntries.length,
            itemBuilder: (context, index) {
              final entry = widget.session.displayEntries[index];
              return _buildEntryRow(entry);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEntryRow(TranscriptEntry entry) {
    switch (entry.kind) {
      case EntryKind.transcript:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                child: Text(
                  "Speaker ${entry.speaker ?? '?'}",
                  style: const TextStyle(
                    fontFamily: 'IBMPlexMono',
                    fontSize: 11,
                    color: Color(Palette.berry1),
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  entry.text,
                  style: const TextStyle(
                    fontFamily: 'IBMPlexSans',
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      case EntryKind.heard:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Text(
            entry.text,
            style: const TextStyle(
              fontFamily: 'IBMPlexSans',
              fontSize: 14,
              color: Color(Palette.inkSoft),
            ),
          ),
        );
      case EntryKind.asked:
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              gradient: BlobShape.linearGradient,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              entry.text,
              style: const TextStyle(
                fontFamily: 'IBMPlexSans',
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        );
      case EntryKind.reply:
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              entry.text,
              style: const TextStyle(
                fontFamily: 'Fredoka',
                fontSize: 16,
                color: Color(Palette.ink),
              ),
            ),
          ),
        );
      case EntryKind.report:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF0FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(Palette.berry2), width: 2),
          ),
          child: Text(
            entry.text,
            style: const TextStyle(
              fontFamily: 'IBMPlexSans',
              fontSize: 14,
              color: Color(Palette.ink),
            ),
          ),
        );
    }
  }
}

class MiniBluey extends StatelessWidget {
  final Size size;

  const MiniBluey({super.key, this.size = const Size(54, 48)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size.width,
      height: size.height,
      child: CustomPaint(
        painter: _MiniBlueyPainter(),
      ),
    );
  }
}

class _MiniBlueyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final blob = BlobShape.path(rect);

    canvas.drawPath(blob, Paint()..shader = BlobShape.shader(rect));

    final eyeRadius = size.width * 0.13;
    final pupilRadius = size.width * 0.06;

    final leftEye = Offset(size.width * 0.38, size.height * 0.45);
    final rightEye = Offset(size.width * 0.62, size.height * 0.45);

    canvas.drawCircle(leftEye, eyeRadius, Paint()..color = Colors.white);
    canvas.drawCircle(rightEye, eyeRadius, Paint()..color = Colors.white);

    canvas.drawCircle(
      leftEye + Offset(size.width * 0.02, size.width * 0.02),
      pupilRadius,
      Paint()..color = const Color(Palette.ink),
    );
    canvas.drawCircle(
      rightEye + Offset(size.width * 0.02, size.width * 0.02),
      pupilRadius,
      Paint()..color = const Color(Palette.ink),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
