import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'googly_protocol.dart';

/// Newline-delimited JSON over Socket.
class LineConnection {
  final Socket socket;
  Function(Packet packet)? onPacket;
  Function(bool connected)? onStateChange;

  final List<int> _buffer = [];
  late StreamSubscription<Uint8List> _subscription;

  LineConnection(this.socket) {
    _subscription = socket.listen(
      _onData,
      onError: (err) {
        close();
      },
      onDone: () {
        close();
      },
    );
    onStateChange?.call(true);
  }

  void send(Packet packet) {
    try {
      final jsonString = jsonEncode(packet.toJson());
      socket.add(utf8.encode('$jsonString\n'));
    } catch (e) {
      // Ignore or log encode errors
    }
  }

  void close() {
    _subscription.cancel();
    socket.destroy();
    onStateChange?.call(false);
  }

  void _onData(Uint8List data) {
    _buffer.addAll(data);
    while (true) {
      final index = _buffer.indexOf(0x0A); // newline '\n'
      if (index == -1) break;

      final lineBytes = _buffer.sublist(0, index);
      _buffer.removeRange(0, index + 1);

      if (lineBytes.isEmpty) continue;

      try {
        final lineStr = utf8.decode(lineBytes);
        final jsonMap = jsonDecode(lineStr) as Map<String, dynamic>;
        final packet = Packet.fromJson(jsonMap);
        onPacket?.call(packet);
      } catch (e) {
        // Ignore malformed JSON line
      }
    }
  }
}
