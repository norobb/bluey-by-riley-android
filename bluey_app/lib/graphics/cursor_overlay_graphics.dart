import 'dart:math';
import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';

class TimingCurve {
  final double x1, y1, x2, y2;

  const TimingCurve(this.x1, this.y1, this.x2, this.y2);

  static const launch = TimingCurve(0.42, 0, 0.22, 1);
  static const redirect = TimingCurve(0.25, 0.25, 0.22, 1);
  static const steady = TimingCurve(0.42, 0, 0.38, 1);

  double _coordinate(double t, double a, double b) {
    final u = 1 - t;
    return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t;
  }

  double _derivative(double t, double a, double b) {
    final u = 1 - t;
    return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b);
  }

  double _parameter(double x) {
    var t = x;
    for (var i = 0; i < 8; i++) {
      final error = _coordinate(t, x1, x2) - x;
      if (error.abs() < 1e-7) return t;
      final d = _derivative(t, x1, x2);
      if (d.abs() < 1e-7) break;
      t -= error / d;
    }
    var low = 0.0, high = 1.0;
    t = x;
    for (var i = 0; i < 40; i++) {
      final value = _coordinate(t, x1, x2);
      if ((value - x).abs() < 1e-7) break;
      if (value < x) {
        low = t;
      } else {
        high = t;
      }
      t = (low + high) / 2;
    }
    return t;
  }

  double value(double x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    return _coordinate(_parameter(x), y1, y2);
  }

  double rate(double x) {
    final t = _parameter(max(0.0, min(1.0, x)));
    final dx = _derivative(t, x1, x2);
    final dy = _derivative(t, y1, y2);
    return dx > 1e-7 ? dy / dx : 0.0;
  }
}

class TeardropPath {
  /// Teardrop shape path: square of side s with tip radius r at top-left.
  static Path path({required double size, double tipRadius = 6.0}) {
    final path = Path();
    final big = size / 2;

    path.moveTo(tipRadius, 0);
    path.arcToPoint(Offset(size, big), radius: Radius.circular(big));
    path.arcToPoint(Offset(big, size), radius: Radius.circular(big));
    path.arcToPoint(Offset(0, big), radius: Radius.circular(big));
    path.arcToPoint(Offset(0, tipRadius), radius: Radius.circular(tipRadius));
    path.close();
    return path;
  }

  static Path star({required double radius}) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final r = i % 2 == 0 ? radius : radius * 0.4;
      final a = i * pi / 4 - pi / 2;
      final p = Offset(cos(a) * r, sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    return path;
  }
}

enum PointerTrailMode { comet, string, none }

class TeardropCursorPainter extends CustomPainter {
  final Offset tip;
  final double angle;
  final double size;
  final double opacity;
  final bool glow;
  final double squish;
  final Offset look;

  TeardropCursorPainter({
    required this.tip,
    required this.angle,
    this.size = 72.0,
    this.opacity = 1.0,
    this.glow = true,
    this.squish = 1.0,
    this.look = const Offset(-0.7, -0.7),
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    if (opacity <= 0.01) return;

    canvas.save();
    canvas.translate(tip.dx, tip.dy);
    canvas.rotate(-angle);
    canvas.scale(squish, squish);

    final k = size / 96.0;
    final path = TeardropPath.path(size: size, tipRadius: 6.0 * k);

    // Glow shadow
    if (glow) {
      final glowPaint = Paint()
        ..color = const Color(Palette.berry2).withValues(alpha: 0.7 * opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30.0 * k);
      canvas.drawPath(path, glowPaint);
    }

    // Gradient fill
    final rect = Rect.fromLTWH(0, 0, size, size);
    final fillShader = const LinearGradient(
      begin: Alignment(-0.5, -0.866),
      end: Alignment(0.5, 0.866),
      colors: [
        Color(Palette.berry1),
        Color(Palette.berry2),
        Color(Palette.berry3),
        Color(Palette.berry4),
      ],
      stops: Palette.gradientStops,
    ).createShader(rect);

    canvas.drawPath(path, Paint()..shader = fillShader);

    // Rim stroke
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0 * k;
    canvas.drawPath(path, rimPaint);

    // Googly eyes
    final eyeRadius = 9.0 * k;
    final eyeCenters = [
      Offset((34 + 9) * k, (40 + 9) * k),
      Offset((34 + 24 + 9) * k, (40 + 9) * k),
    ];

    for (final c in eyeCenters) {
      canvas.drawCircle(c, eyeRadius, Paint()..color = Colors.white);
      final pupilRadius = 4.5 * k;
      final pupilOffset = Offset(c.dx + look.dx * 3.4 * k, c.dy + look.dy * 3.4 * k);
      canvas.drawCircle(pupilOffset, pupilRadius, Paint()..color = const Color(Palette.ink));
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TeardropCursorPainter oldDelegate) => true;
}
