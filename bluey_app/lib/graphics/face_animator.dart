import 'dart:math';
import 'package:flutter/material.dart';
import '../protocol/googly_protocol.dart';

class Spring {
  double value;
  double velocity = 0.0;
  final double stiffness;
  final double damping;

  Spring(this.value, {this.stiffness = 200.0, this.damping = 0.7});

  void step(double target, double dt) {
    final c = 2 * sqrt(stiffness) * damping;
    velocity += (stiffness * (target - value) - c * velocity) * dt;
    value += velocity * dt;
  }
}

class FaceFrame {
  final Offset gaze;
  final Mood mood;
  final double talk;
  final double closed;
  final double breathe;
  final double time;
  final double pupil;
  final double browLift;
  final double browTilt;
  final double lean;
  final double hop;
  final double blush;
  final double squint;

  FaceFrame({
    required this.gaze,
    required this.mood,
    required this.talk,
    required this.closed,
    required this.breathe,
    required this.time,
    required this.pupil,
    required this.browLift,
    required this.browTilt,
    required this.lean,
    required this.hop,
    required this.blush,
    required this.squint,
  });
}

class FaceAnimator {
  FaceState _target = FaceState();
  double _lastPacket = -100.0;

  final Spring gazeX = Spring(0, stiffness: 260, damping: 0.82);
  final Spring gazeY = Spring(0, stiffness: 260, damping: 0.82);
  final Spring pupil = Spring(1, stiffness: 160, damping: 0.5);
  final Spring browLift = Spring(0, stiffness: 180, damping: 0.55);
  final Spring browTilt = Spring(0, stiffness: 150, damping: 0.6);
  final Spring lean = Spring(0, stiffness: 60, damping: 0.8);
  final Spring hop = Spring(0, stiffness: 260, damping: 0.35);
  final Spring blush = Spring(0.25, stiffness: 40, damping: 1.0);
  final Spring squint = Spring(0, stiffness: 150, damping: 0.7);

  double talk = 0.0;
  Mood mood = Mood.listening;
  double moodChanged = 0.0;
  double blinkStart = -1.0;
  bool doubleBlink = false;
  double nextBlink = 2.0;
  double? lastTime;
  double nextSaccade = 0.0;
  Offset wanderTarget = const Offset(0, -0.3);
  Offset jitter = Offset.zero;
  double nextJitter = 0.0;
  double nextHop = 6.0;

  Offset? touchGaze;
  Mood? localMood;
  double Function() localTalk = () => 0.0;
  bool awake = false;

  final _random = Random();

  void receive(FaceState face, double time) {
    _target = face;
    _lastPacket = time;
  }

  FaceFrame step(double now) {
    final dt = min(now - (lastTime ?? now), 1.0 / 20.0);
    lastTime = now;

    final live = now - _lastPacket < 2.5;
    final wantedMood = localMood ?? (live ? _target.mood : Mood.listening);

    if (wantedMood != mood) {
      mood = wantedMood;
      moodChanged = now;
      blinkStart = now;
      if (mood != Mood.sleepy && mood != Mood.resting) {
        hop.velocity += 260;
        pupil.velocity += 3;
      }
    }

    Offset want;
    if (touchGaze != null) {
      want = touchGaze!;
    } else if (live) {
      want = Offset(_target.gazeX, _target.gazeY);
    } else {
      if (now > nextSaccade) {
        wanderTarget = Offset(
          _randomRange(-0.9, 0.9),
          _randomRange(-0.9, 0.4),
        );
        nextSaccade = now + _randomRange(0.6, 2.2);
      }
      want = wanderTarget;
    }

    if (mood == Mood.thinking) {
      want = Offset(0.6 + 0.08 * sin(now * 1.3), -0.85);
    }

    if (now > nextJitter) {
      final amount = !awake
          ? 0.015
          : (mood == Mood.talking
              ? 0.07
              : (mood == Mood.thinking ? 0.05 : 0.02));
      jitter = Offset(
        _randomRange(-amount, amount),
        _randomRange(-amount, amount),
      );
      nextJitter = now + _randomRange(0.5, 1.4);
    }

    gazeX.step(want.dx + jitter.dx, dt);
    gazeY.step(want.dy + jitter.dy, dt);

    double wantTalk = live
        ? _target.talk
        : (localMood == Mood.talking
            ? 0.5 + 0.5 * sin(now * 19) * sin(now * 7.3)
            : 0.0);
    wantTalk = max(wantTalk, localTalk());
    talk += (wantTalk - talk) * min(1.0, dt * 25);

    double wantPupil = 1.0,
        wantLift = 0.0,
        wantTilt = 0.0,
        wantBlush = 0.25,
        wantSquint = 0.0;

    switch (mood) {
      case Mood.listening:
        wantPupil = 1.12;
        wantLift = 10;
        break;
      case Mood.talking:
        wantPupil = 1.05;
        wantLift = 6 + talk * 18;
        wantTilt = 0.05 * sin(now * 2.3);
        break;
      case Mood.pointing:
        wantPupil = 0.95;
        wantLift = -4;
        wantTilt = -0.14;
        break;
      case Mood.thinking:
        wantPupil = 0.9;
        wantLift = 4;
        wantTilt = 0.22;
        break;
      case Mood.happy:
        wantPupil = 1.2;
        wantLift = 16;
        wantBlush = 0.85;
        wantSquint = 1.0;
        break;
      case Mood.resting:
        wantPupil = 0.9;
        wantLift = -8;
        wantBlush = 0.15;
        break;
      case Mood.sleepy:
        wantPupil = 0.88;
        wantLift = -10;
        wantTilt = 0.12;
        wantBlush = 0.15;
        break;
    }

    pupil.step(wantPupil, dt);
    browLift.step(wantLift, dt);
    browTilt.step(wantTilt, dt);
    blush.step(wantBlush, dt);
    squint.step(wantSquint, dt);
    lean.step(-gazeX.value * 0.045, dt);

    if (now > nextHop) {
      if (talk < 0.05 && mood != Mood.sleepy && mood != Mood.resting) {
        hop.velocity += _randomRange(180, 320);
      }
      nextHop = now + _randomRange(7, 14);
    }
    hop.step(0, dt);

    final drowsy = mood == Mood.sleepy;
    if (now > nextBlink) {
      blinkStart = now;
      doubleBlink = !drowsy && _random.nextDouble() < 0.25;
      nextBlink = now + (drowsy ? _randomRange(1.6, 3.0) : _randomRange(2.0, 5.0));
    }

    final p = (now - blinkStart) / (drowsy ? 0.7 : 0.15);
    double closed = (p >= 0 && p <= 1) ? sin(pi * p) : 0.0;
    if (doubleBlink && p >= 1.3 && p <= 2.3) {
      closed = sin(pi * (p - 1.3));
    }

    final breathe = sin(now * (mood == Mood.resting ? 1.1 : 1.8));

    return FaceFrame(
      gaze: Offset(gazeX.value, gazeY.value),
      mood: mood,
      talk: talk,
      closed: closed,
      breathe: breathe,
      time: now,
      pupil: pupil.value,
      browLift: browLift.value,
      browTilt: browTilt.value,
      lean: lean.value,
      hop: hop.value,
      blush: blush.value,
      squint: max(0.0, min(1.0, squint.value)),
    );
  }

  double _randomRange(double min, double max) {
    return min + _random.nextDouble() * (max - min);
  }
}
