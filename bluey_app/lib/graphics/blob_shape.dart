import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';

class BlobShape {
  /// The blob outline path matching CSS `border-radius: 52% 48% 46% 54% / 58% 56% 44% 42%`.
  static Path path(Rect r) {
    final w = r.width;
    final h = r.height;
    final tl = Size(0.52 * w, 0.58 * h);
    final tr = Size(0.48 * w, 0.56 * h);
    final br = Size(0.46 * w, 0.44 * h);
    final bl = Size(0.54 * w, 0.42 * h);
    const k = 0.5523;

    final p = Path();
    p.moveTo(r.left + tl.width, r.top);
    p.lineTo(r.right - tr.width, r.top);
    p.cubicTo(
      r.right - tr.width * (1 - k), r.top,
      r.right, r.top + tr.height * (1 - k),
      r.right, r.top + tr.height,
    );
    p.lineTo(r.right, r.bottom - br.height);
    p.cubicTo(
      r.right, r.bottom - br.height * (1 - k),
      r.right - br.width * (1 - k), r.bottom,
      r.right - br.width, r.bottom,
    );
    p.lineTo(r.left + bl.width, r.bottom);
    p.cubicTo(
      r.left + bl.width * (1 - k), r.bottom,
      r.left, r.bottom - bl.height * (1 - k),
      r.left, r.bottom - bl.height,
    );
    p.lineTo(r.left, r.top + tl.height);
    p.cubicTo(
      r.left, r.top + tl.height * (1 - k),
      r.left + tl.width * (1 - k), r.top,
      r.left + tl.width, r.top,
    );
    p.close();
    return p;
  }

  /// 150° linear gradient matching original design.
  static LinearGradient get linearGradient => const LinearGradient(
        begin: Alignment(-0.5, -0.866), // 150 deg angle start
        end: Alignment(0.5, 0.866),    // 150 deg angle end
        colors: [
          Color(Palette.berry1),
          Color(Palette.berry2),
          Color(Palette.berry3),
          Color(Palette.berry4),
        ],
        stops: Palette.gradientStops,
      );

  static Shader shader(Rect r) {
    return linearGradient.createShader(r);
  }
}

class Crown {
  /// The blueberry crown on top of his head (SVG path from design, 60x40 box).
  static Path path(Rect r) {
    const pts = [
      Offset(30, 4),
      Offset(36, 16),
      Offset(52, 12),
      Offset(40, 24),
      Offset(46, 36),
      Offset(30, 28),
      Offset(14, 36),
      Offset(20, 24),
      Offset(8, 12),
      Offset(24, 16),
    ];

    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final pt = Offset(
        r.left + (pts[i].dx / 60) * r.width,
        r.top + (pts[i].dy / 40) * r.height,
      );
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }
}
