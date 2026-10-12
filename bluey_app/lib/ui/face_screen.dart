import 'dart:async';
import 'package:flutter/material.dart';
import '../audio/chirp_synthesizer.dart';
import '../graphics/face_animator.dart';
import '../graphics/face_painter.dart';
import '../storage/session_store.dart';
import 'bluey_app_view.dart';
import 'mode_indicator.dart';
import 'pairing_view.dart';
import 'sound_button.dart';

class FaceScreen extends StatefulWidget {
  final SessionStore store;

  const FaceScreen({super.key, required this.store});

  @override
  State<FaceScreen> createState() => _FaceScreenState();
}

class _FaceScreenState extends State<FaceScreen>
    with SingleTickerProviderStateMixin {
  final FaceAnimator _animator = FaceAnimator();
  late AnimationController _animationController;

  bool _showPairing = true;
  bool _showApp = false;
  bool _isConnected = false;
  bool _holdingToAsk = false;
  Timer? _holdTimer;
  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 100),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onDoubleTap() {
    setState(() {
      _animator.awake = !_animator.awake;
    });
    ChirpSynthesizer.playChirp(syllables: 2, volume: _volume);
  }

  void _onTapDown(TapDownDetails details) {
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _holdingToAsk = true;
      });
    });
  }

  void _onTapUp(TapUpDetails details) {
    if (_holdTimer?.isActive ?? false) {
      _holdTimer?.cancel();
    } else if (_holdingToAsk) {
      setState(() {
        _holdingToAsk = false;
      });
      ChirpSynthesizer.playChirp(syllables: 3, volume: _volume);
    }
  }

  void _onTapCancel() {
    _holdTimer?.cancel();
    if (_holdingToAsk) {
      setState(() {
        _holdingToAsk = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final frame = _animator.step(now);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Face Canvas Layer
          GestureDetector(
            onDoubleTap: _onDoubleTap,
            onTapDown: _onTapDown,
            onTapUp: _onTapUp,
            onTapCancel: _onTapCancel,
            child: AnimatedBuilder(
              animation: _animationController,
              builder: (context, child) {
                final currentFrame = _animator.step(
                  DateTime.now().millisecondsSinceEpoch / 1000.0,
                );
                return CustomPaint(
                  size: Size.infinite,
                  painter: FacePainter(currentFrame),
                );
              },
            ),
          ),

          // Mode Indicator Border & Badge
          ModeIndicator(
            mood: frame.mood,
            awake: _animator.awake,
            asking: _holdingToAsk,
          ),

          // Top-Right Drawer Button
          Positioned(
            top: 10,
            right: 62,
            child: IconButton(
              onPressed: () => setState(() => _showApp = true),
              icon: const Icon(Icons.grid_view_rounded, color: Colors.white30, size: 20),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.06),
              ),
            ),
          ),

          // Sound Popover Button
          SoundButton(
            volume: _volume,
            onVolumeChanged: (val) => setState(() => _volume = val),
            onSayHi: () => ChirpSynthesizer.playChirp(syllables: 2, volume: _volume),
            isConnected: _isConnected,
            macs: const ["My Computer"],
            currentMac: "My Computer",
          ),

          // Pairing Overlay
          if (_showPairing && !_isConnected)
            PairingView(
              onPlay: () {
                setState(() => _showPairing = false);
              },
            ),

          // App Drawer Screen
          if (_showApp)
            Positioned.fill(
              child: BlueyAppView(
                store: widget.store,
                isConnected: _isConnected,
                macs: const ["My Computer"],
                currentMac: "My Computer",
                onClose: () => setState(() => _showApp = false),
                onToggleSession: () {
                  if (_animator.awake) {
                    widget.store.end();
                    _animator.awake = false;
                  } else {
                    widget.store.start();
                    _animator.awake = true;
                  }
                  setState(() {});
                },
                isSessionRunning: _animator.awake,
              ),
            ),
        ],
      ),
    );
  }
}
