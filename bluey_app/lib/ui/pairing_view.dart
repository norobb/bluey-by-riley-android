import 'dart:math';
import 'package:flutter/material.dart';
import '../graphics/blob_shape.dart';
import '../protocol/googly_protocol.dart';

class PairingView extends StatelessWidget {
  final VoidCallback onPlay;

  const PairingView({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 72),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 220,
              height: 190,
              child: SleepyBlob(),
            ),
            const SizedBox(width: 56),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Wake me up from your Mac",
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF4F1FA),
                  ),
                ),
                const SizedBox(height: 14),
                const SizedBox(
                  width: 380,
                  child: Text(
                    "Open Bluey in your computer's menu bar or system tray. Keep both on the same Wi-Fi and I'll find it.",
                    style: TextStyle(
                      fontFamily: 'IBMPlexSans',
                      fontSize: 16,
                      color: Color(Palette.inkSoft),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Color(Palette.berry1)),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Looking for your computer...",
                      style: TextStyle(
                        fontFamily: 'IBMPlexMono',
                        fontSize: 13,
                        color: Color(Palette.inkSoft),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextButton(
                  onPressed: onPlay,
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(Palette.panel),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    "Play without the Mac",
                    style: TextStyle(
                      fontFamily: 'IBMPlexSans',
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF4F1FA),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SleepyBlob extends StatefulWidget {
  const SleepyBlob({super.key});

  @override
  State<SleepyBlob> createState() => _SleepyBlobState();
}

class _SleepyBlobState extends State<SleepyBlob>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * pi;
        final scale = 1.0 + 0.02 * sin(t * 1.1);

        return Transform.scale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: const Size(220, 190),
                painter: _SleepyPainter(),
              ),
              Positioned(
                right: 20,
                top: 20 + 4 * sin(t * 1.5),
                child: const Text(
                  'z',
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 26,
                    color: Color(Palette.berry3),
                  ),
                ),
              ),
              Positioned(
                right: 5,
                top: 5 + 4 * sin(t * 1.5 + 1),
                child: const Text(
                  'z',
                  style: TextStyle(
                    fontFamily: 'Fredoka',
                    fontSize: 18,
                    color: Color(Palette.berry4),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SleepyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = BlobShape.path(rect);

    // Gradient fill
    final fillPaint = Paint()..shader = BlobShape.shader(rect);
    canvas.drawPath(path, fillPaint);

    // Closed eyes
    final eyePaint = Paint()
      ..color = const Color(Palette.ink)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;

    final leftEye = Path()
      ..moveTo(size.width * 0.3, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.38, size.height * 0.45, size.width * 0.46, size.height * 0.4);

    final rightEye = Path()
      ..moveTo(size.width * 0.54, size.height * 0.4)
      ..quadraticBezierTo(size.width * 0.62, size.height * 0.45, size.width * 0.7, size.height * 0.4);

    canvas.drawPath(leftEye, eyePaint);
    canvas.drawPath(rightEye, eyePaint);

    // Nose
    final noseRect = Rect.fromCenter(
      center: Offset(size.width * 0.5, size.height * 0.58),
      width: 18,
      height: 12,
    );
    canvas.drawOval(noseRect, Paint()..color = const Color(Palette.nose));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
