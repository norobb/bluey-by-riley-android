import 'dart:math';
import 'package:flutter/material.dart';
import '../graphics/blob_shape.dart';
import '../protocol/googly_protocol.dart';
import '../protocol/phone_client.dart';

class PairingView extends StatelessWidget {
  final VoidCallback onPlay;

  const PairingView({super.key, required this.onPlay});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: SingleChildScrollView(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 32,
            runSpacing: 24,
            children: [
              const SizedBox(
                width: 220,
                height: 190,
                child: SleepyBlob(),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Wake me up from your Computer",
                      style: TextStyle(
                        fontFamily: 'Fredoka',
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF4F1FA),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      "Open Bluey on your PC or Mac. Keep both on the same Wi-Fi or connect manually by IP.",
                      style: TextStyle(
                        fontFamily: 'IBMPlexSans',
                        fontSize: 15,
                        color: Color(Palette.inkSoft),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      mainAxisSize: MainAxisSize.min,
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
                        Flexible(
                          child: Text(
                            "Looking for your computer...",
                            style: TextStyle(
                              fontFamily: 'IBMPlexMono',
                              fontSize: 13,
                              color: Color(Palette.inkSoft),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => showManualPairingDialog(context),
                          icon: const Icon(Icons.wifi_find, size: 18),
                          label: const Text(
                            "Manuell koppeln",
                            style: TextStyle(
                              fontFamily: 'IBMPlexSans',
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(Palette.berry2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onPlay,
                          style: TextButton.styleFrom(
                            backgroundColor: const Color(Palette.panel),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            "Play without Computer",
                            style: TextStyle(
                              fontFamily: 'IBMPlexSans',
                              fontSize: 14,
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
            ],
          ),
        ),
      ),
    );
  }
}

class ManualPairingDialog extends StatefulWidget {
  const ManualPairingDialog({super.key});

  @override
  State<ManualPairingDialog> createState() => _ManualPairingDialogState();
}

class _ManualPairingDialogState extends State<ManualPairingDialog> {
  late TextEditingController _ipController;
  late TextEditingController _portController;
  bool _isConnecting = false;
  String? _statusMessage;
  bool _isError = false;

  @override
  void initState() {
    super.initState();
    final client = PhoneClient();
    _ipController = TextEditingController(text: client.lastManualIp ?? '');
    _portController = TextEditingController(text: '8080');
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final ip = _ipController.text.trim();
    final portText = _portController.text.trim();
    final port = int.tryParse(portText) ?? 8080;

    if (ip.isEmpty) {
      setState(() {
        _statusMessage = "Bitte eine gültige IP-Adresse eingeben.";
        _isError = true;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _statusMessage = "Verbinde mit $ip:$port...";
      _isError = false;
    });

    final success = await PhoneClient().connectDirect(ip, port: port);

    if (mounted) {
      if (success) {
        setState(() {
          _isConnecting = false;
          _statusMessage = "Erfolgreich verbunden!";
          _isError = false;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _isConnecting = false;
          _statusMessage = "Verbindung fehlgeschlagen. Bitte IP & WLAN prüfen.";
          _isError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(Palette.panel),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.wifi_find_rounded, color: Color(Palette.berry1)),
          SizedBox(width: 10),
          Text(
            "Manuell koppeln",
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontSize: 22,
              color: Colors.white,
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Gib die IP-Adresse deiner Windows- oder Mac-App ein (steht oben in der Desktop-App):",
              style: TextStyle(
                fontFamily: 'IBMPlexSans',
                fontSize: 14,
                color: Color(Palette.inkSoft),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _ipController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontFamily: 'IBMPlexMono'),
                    decoration: InputDecoration(
                      labelText: "IP-Adresse",
                      hintText: "192.168.1.45",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _portController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white, fontFamily: 'IBMPlexMono'),
                    decoration: InputDecoration(
                      labelText: "Port",
                      hintText: "8080",
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_isConnecting)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                    )
                  else
                    Icon(
                      _isError ? Icons.error_outline : Icons.check_circle_outline,
                      size: 16,
                      color: _isError ? Colors.redAccent : Colors.greenAccent,
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        fontFamily: 'IBMPlexSans',
                        fontSize: 13,
                        color: _isError ? Colors.redAccent : Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            "Abbrechen",
            style: TextStyle(color: Colors.white60, fontFamily: 'IBMPlexSans'),
          ),
        ),
        ElevatedButton(
          onPressed: _isConnecting ? null : _handleConnect,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(Palette.berry2),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            "Verbinden",
            style: TextStyle(fontFamily: 'IBMPlexSans', fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

Future<bool?> showManualPairingDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => const ManualPairingDialog(),
  );
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
