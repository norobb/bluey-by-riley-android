import 'dart:math';
import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';
import 'blob_shape.dart';
import 'face_animator.dart';

class FacePainter extends CustomPainter {
  final FaceFrame frame;

  static const Size design = Size(844, 390);

  FacePainter(this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.black);

    final scale = max(size.width / design.width, size.height / design.height);
    canvas.save();
    canvas.translate((size.width - design.width * scale) / 2, size.height - design.height * scale);
    canvas.scale(scale, scale);

    final bounce = -frame.talk * 16 + frame.breathe * 3 - frame.hop;
    final body = Rect.fromLTWH(12, 44 + bounce, 820, 700);
    final pivot = Offset(body.center.dx, body.bottom);

    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(frame.lean);
    final stretch = 1.0 + min(0.03, max(-0.03, frame.hop / 900));
    canvas.scale(2.0 - stretch, stretch);
    canvas.translate(-pivot.dx, -pivot.dy);

    final blob = BlobShape.path(body);

    // Glow shadow
    final shadowPaint = Paint()
      ..color = const Color(Palette.berry2).withOpacity(0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 45);
    canvas.drawPath(blob, shadowPaint);

    // Body gradient fill
    final bodyPaint = Paint()..shader = BlobShape.shader(body);
    canvas.drawPath(blob, bodyPaint);

    // Body radial shine
    canvas.save();
    canvas.clipPath(blob);
    final shineCenter = Offset(body.left + 246, body.top + 126);
    final shineShader = RadialGradient(
      center: Alignment(
        (shineCenter.dx - body.center.dx) / (body.width / 2),
        (shineCenter.dy - body.center.dy) / (body.height / 2),
      ),
      radius: 0.6,
      colors: [
        Colors.white.withOpacity(0.5),
        Colors.white.withOpacity(0.0),
      ],
    ).createShader(body);
    canvas.drawPath(blob, Paint()..shader = shineShader);

    // Head glossy sparkle
    canvas.drawOval(
      Rect.fromLTWH(body.left + 190, body.top + 40, 46, 22),
      Paint()..color = Colors.white.withOpacity(0.35),
    );
    canvas.restore();

    final navy = const Color(Palette.nose);
    final ink = const Color(Palette.ink);

    // Crown
    final crownRect = Rect.fromLTWH(
      body.left + 368,
      body.top - 20 - frame.browLift * 0.3,
      84,
      56,
    );
    canvas.drawPath(Crown.path(crownRect), Paint()..color = navy);

    final eyeY = body.top + 157;
    final eyes = [
      Offset(body.left + 280, eyeY),
      Offset(body.left + 540, eyeY),
    ];
    final squash = 1 - frame.talk * 0.12;

    // Blush cheeks
    for (var i = 0; i < eyes.length; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final c = eyes[i];
      final cheek = Rect.fromLTWH(c.dx - 45 + side * 62, c.dy + 96, 90, 42);
      final cheekPaint = Paint()
        ..color = const Color(0xFFF3A6D8).withOpacity(0.25 + 0.45 * frame.blush)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawOval(cheek, cheekPaint);
    }

    for (var i = 0; i < eyes.length; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final c = eyes[i];

      // Eyebrows
      canvas.save();
      final browY = c.dy - 112 - min(18.0, max(-10.0, frame.browLift)) * 0.7;
      canvas.translate(c.dx + side * 6, browY);
      canvas.rotate(frame.browTilt * side * -1 + (frame.mood == Mood.thinking && i == 1 ? -0.25 : 0));

      final arch = Path();
      arch.moveTo(-38, 6);
      arch.quadraticBezierTo(0, -12, 38, 6);

      canvas.drawPath(
        arch,
        Paint()
          ..color = navy
          ..style = PaintingStyle.stroke
          ..strokeWidth = 14
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();

      switch (frame.mood) {
        case Mood.resting:
          final shut = Path();
          shut.moveTo(c.dx - 62, c.dy + 6);
          shut.quadraticBezierTo(c.dx, c.dy + 52, c.dx + 62, c.dy + 6);
          canvas.drawPath(
            shut,
            Paint()
              ..color = ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 18
              ..strokeCap = StrokeCap.round,
          );
          break;

        case Mood.happy:
          if (frame.squint > 0.6) {
            final arc = Path();
            arc.moveTo(c.dx - 60, c.dy + 34);
            arc.quadraticBezierTo(c.dx, c.dy - 54, c.dx + 60, c.dy + 34);
            canvas.drawPath(
              arc,
              Paint()
                ..color = ink
                ..style = PaintingStyle.stroke
                ..strokeWidth = 24
                ..strokeCap = StrokeCap.round,
            );
            break;
          }
          continue defaultEye;

        defaultEye:
        default:
          final open = max(0.06, 1.0 - frame.closed) * squash;
          final whiteRect = Rect.fromLTWH(c.dx - 95, c.dy - 95 * open, 190, 190 * open);
          final whitePath = Path()..addOval(whiteRect);

          canvas.drawPath(whitePath, Paint()..color = Colors.white);
          if (open <= 0.2) continue;

          var g = frame.gaze;
          final len = sqrt(g.dx * g.dx + g.dy * g.dy);
          if (len > 1.0) g = Offset(g.dx / len, g.dy / len);

          const reach = 50.0;
          final r = 46.0 * frame.pupil;
          var pupilCenter = Offset(c.dx + g.dx * reach - side * 3, c.dy + g.dy * reach * open);
          if (frame.mood == Mood.sleepy) {
            pupilCenter = Offset(pupilCenter.dx, max(pupilCenter.dy, c.dy) + 28);
          }

          canvas.save();
          canvas.clipPath(whitePath);

          // Pupil
          canvas.drawOval(
            Rect.fromCircle(center: pupilCenter, radius: r),
            Paint()..color = ink,
          );

          // Catchlights
          canvas.drawOval(
            Rect.fromCircle(center: Offset(pupilCenter.dx - r * 0.29, pupilCenter.dy - r * 0.36), radius: r * 0.28),
            Paint()..color = Colors.white,
          );
          canvas.drawOval(
            Rect.fromCircle(center: Offset(pupilCenter.dx + r * 0.14, pupilCenter.dy + r * 0.11), radius: r * 0.12),
            Paint()..color = Colors.white.withOpacity(0.85),
          );

          // Happy squint
          if (frame.squint > 0.02) {
            final lid = Rect.fromLTWH(c.dx - 110, c.dy + 95 * open - 70 * frame.squint, 220, 160);
            _fillSkin(canvas, Path()..addOval(lid), body);
          }

          // Sleepy droop
          if (frame.mood == Mood.sleepy) {
            final droop = 0.5 + 0.06 * sin(frame.time * 1.3);
            _fillSkin(
              canvas,
              Path()..addRect(Rect.fromLTWH(c.dx - 100, whiteRect.top - 10, 200, whiteRect.height * droop + 10)),
              body,
            );
            canvas.drawLine(
              Offset(c.dx - 92, whiteRect.top + whiteRect.height * droop),
              Offset(c.dx + 92, whiteRect.top + whiteRect.height * droop),
              Paint()
                ..color = navy.withOpacity(0.7)
                ..strokeWidth = 8
                ..strokeCap = StrokeCap.round,
            );
          }

          // Pointing lid
          if (frame.mood == Mood.pointing) {
            _fillSkin(canvas, Path()..addRect(Rect.fromLTWH(c.dx - 100, whiteRect.top - 20, 200, 40)), body);
          }

          canvas.restore();
          break;
      }
    }

    // Floating sleeping 'z's
    if (frame.mood == Mood.resting) {
      for (var i = 0; i < 3; i++) {
        final phase = ((frame.time * 0.35 + i / 3.0) % 1.0);
        final sizeVal = 26.0 + i * 8.0;
        final point = Offset(
          body.left + 660 + phase * 70 + sin(phase * 6) * 8,
          body.top + 90 - phase * 110,
        );

        final textPainter = TextPainter(
          text: TextSpan(
            text: 'z',
            style: TextStyle(
              fontFamily: 'Fredoka',
              fontSize: sizeVal,
              color: Colors.white.withOpacity(0.9 * sin(pi * phase)),
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        textPainter.paint(canvas, point);
      }
    }

    // Thinking dots
    if (frame.mood == Mood.thinking) {
      for (var i = 0; i < 3; i++) {
        final wobble = sin(frame.time * 3 + i) * 4;
        final dot = Rect.fromLTWH(body.left + 690 + i * 26, body.top + 40 - i * 12 + wobble, 16, 16);
        canvas.drawOval(
          dot,
          Paint()..color = Colors.white.withOpacity(1.0 - i * 0.3),
        );
      }
    }

    // Mouth / Nose
    final noseW = 60.0 - frame.talk * 8;
    final noseH = 38.0 + frame.talk * 34;
    final nose = Rect.fromLTWH(body.left + 410 - noseW / 2, body.top + 272 - frame.talk * 6, noseW, noseH);

    if (frame.mood == Mood.happy && frame.talk < 0.1) {
      final smile = Path();
      smile.moveTo(nose.left - 8, nose.top + 8);
      smile.quadraticBezierTo(nose.center.dx, nose.top + 58, nose.right + 8, nose.top + 8);
      smile.close();
      canvas.drawPath(smile, Paint()..color = navy);
    } else {
      canvas.drawOval(nose, Paint()..color = navy);
      if (frame.talk > 0.25) {
        final tongue = Rect.fromLTWH(
          nose.center.dx - noseW * 0.28,
          nose.bottom - noseH * 0.38,
          noseW * 0.56,
          noseH * 0.3,
        );
        canvas.drawOval(tongue, Paint()..color = const Color(0xFFE58BC4).withOpacity(0.9));
      }
    }

    canvas.restore();
  }

  void _fillSkin(Canvas canvas, Path path, Rect body) {
    canvas.drawPath(path, Paint()..shader = BlobShape.shader(body));
  }

  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) => true;
}
