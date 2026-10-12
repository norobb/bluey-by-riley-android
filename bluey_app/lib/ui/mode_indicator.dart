import 'dart:math';
import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';

class ModeLook {
  final Color color;
  final String? label;
  final IconData icon;
  final double border;
  final double pulse;

  const ModeLook({
    required this.color,
    this.label,
    required this.icon,
    required this.border,
    required this.pulse,
  });
}

class ModeIndicator extends StatefulWidget {
  final Mood mood;
  final bool awake;
  final bool asking;

  const ModeIndicator({
    super.key,
    required this.mood,
    this.awake = false,
    this.asking = false,
  });

  @override
  State<ModeIndicator> createState() => _ModeIndicatorState();
}

class _ModeIndicatorState extends State<ModeIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  static const blue = Color(0xFF4F8BFF);

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  ModeLook get _look {
    if (!widget.awake) {
      return const ModeLook(
        color: Color(Palette.inkSoft),
        label: null,
        icon: Icons.remove_red_eye,
        border: 0,
        pulse: 0,
      );
    }

    if (widget.asking) {
      return const ModeLook(
        color: blue,
        label: "I'm all ears",
        icon: Icons.mic,
        border: 16,
        pulse: 1.2,
      );
    }

    switch (widget.mood) {
      case Mood.happy:
      case Mood.listening:
        return const ModeLook(
          color: blue,
          label: 'Listening · hold to ask',
          icon: Icons.hearing,
          border: 10,
          pulse: 0,
        );
      case Mood.thinking:
        return const ModeLook(
          color: Color(0xFFC79BFF),
          label: 'Thinking',
          icon: Icons.auto_awesome,
          border: 8,
          pulse: 1.1,
        );
      case Mood.talking:
      case Mood.pointing:
        return const ModeLook(
          color: Color(0xFFFF9AD0),
          label: 'Replying',
          icon: Icons.chat_bubble,
          border: 8,
          pulse: 0,
        );
      case Mood.resting:
      case Mood.sleepy:
        return const ModeLook(
          color: Color(0xFFFFD66B),
          label: 'Waking up',
          icon: Icons.wb_sunny,
          border: 6,
          pulse: 1.6,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final look = _look;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _pulseController,
        builder: (context, child) {
          final wave = look.pulse > 0
              ? 0.5 + 0.5 * sin(_pulseController.value * 2 * pi * look.pulse)
              : 1.0;
          final opacity = look.pulse > 0 ? 0.65 + 0.35 * wave : 1.0;

          return Stack(
            children: [
              if (look.border > 0)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(45),
                      border: Border.all(
                        color: look.color.withValues(alpha: opacity),
                        width: look.border,
                      ),
                    ),
                  ),
                ),
              Positioned(
                top: 14 + look.border,
                left: 24 + look.border,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: look.label == null ? 8 : 14,
                    vertical: 6,
                  ),
                  decoration: ShapeDecoration(
                    color: look.label == null
                        ? Colors.white.withValues(alpha: 0.06)
                        : look.color,
                    shape: const StadiumBorder(),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        look.icon,
                        size: 16,
                        color: look.label == null
                            ? look.color.withValues(alpha: 0.7)
                            : Colors.white,
                      ),
                      if (look.label != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          look.label!,
                          style: const TextStyle(
                            fontFamily: 'Fredoka',
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
