import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

class ChirpSynthesizer {
  static final AudioPlayer _player = AudioPlayer();

  static const double sampleRate = 24000.0;
  static const List<double> scale = [
    1046.5,
    1174.7,
    1318.5,
    1568.0,
    1760.0,
    2093.0,
    2349.3,
    2637.0
  ];

  static Future<void> playChirp({int syllables = 3, double volume = 1.0}) async {
    if (volume <= 0.01) return;

    final random = Random();
    var index = random.nextInt(3) + 1;
    final samples = <double>[];

    for (var i = 0; i < syllables; i++) {
      if (i > 0) {
        final step = [-1, 1, 1, 2][random.nextInt(4)];
        index = max(0, min(scale.length - 1, index + step));
      }
      final note = scale[index] * 0.5; // octave lower for warm round tone
      final duration = i == syllables - 1 ? 0.13 : (0.07 + random.nextDouble() * 0.02);
      final count = (duration * sampleRate).toInt();
      var phase = 0.0;

      for (var n = 0; n < count; n++) {
        final time = n / sampleRate;
        final t = n / count;
        final scoop = 1.0 - 0.18 * exp(-time / 0.012);
        final wobble = i == syllables - 1 ? 1.0 + 0.012 * sin(time * 2 * pi * 18) : 1.0;
        phase += 2 * pi * note * scoop * wobble / sampleRate;

        final attack = min(1.0, time / 0.006);
        final envelope = attack * exp(-t * 3.2) * (1.0 - pow(t, 6));
        final wave = sin(phase) + 0.12 * sin(2 * phase);

        samples.add(wave * envelope * 0.26 * volume);
      }

      final silenceCount = (sampleRate * 0.028).toInt();
      samples.addAll(List.filled(silenceCount, 0.0));
    }

    final pcmBytes = _encodeWav(samples, sampleRate.toInt());
    await _player.setVolume(volume);
    await _player.play(BytesSource(pcmBytes));
  }

  static Uint8List _encodeWav(List<double> samples, int sampleRate) {
    final byteCount = samples.length * 2;
    final totalSize = 36 + byteCount;
    final buffer = ByteData(44 + byteCount);

    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, totalSize, Endian.little);
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20);
    buffer.setUint32(16, 16, Endian.little); // Chunk size
    buffer.setUint16(20, 1, Endian.little); // PCM
    buffer.setUint16(22, 1, Endian.little); // Mono
    buffer.setUint32(24, sampleRate, Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    buffer.setUint16(32, 2, Endian.little); // Block align
    buffer.setUint16(34, 16, Endian.little); // Bits per sample

    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, byteCount, Endian.little);

    var offset = 44;
    for (final sample in samples) {
      final clamped = max(-1.0, min(1.0, sample));
      final int16Val = (clamped * 32767).toInt();
      buffer.setInt16(offset, int16Val, Endian.little);
      offset += 2;
    }

    return buffer.buffer.asUint8List();
  }
}
