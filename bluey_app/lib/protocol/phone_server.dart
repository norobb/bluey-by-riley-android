import 'dart:async';
import 'dart:io';

import 'googly_protocol.dart';
import 'line_connection.dart';

/// Hosts a TCP socket server for network pairing with phone clients over _googly._tcp.
class PhoneServer {
  ServerSocket? _serverSocket;
  final Map<LineConnection, String?> _clients = {};
  FaceState? _lastSentFace;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  void Function(List<String> names)? onPhonesChanged;
  void Function(Packet packet, void Function(Packet response) reply)? onRequest;

  List<String> get phoneNames =>
      _clients.values.map((name) => name ?? 'iPhone').toList();

  bool get isRunning => _serverSocket != null;

  Future<void> start({int port = 8080}) async {
    if (_serverSocket != null) return;

    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket?.listen(
        _acceptConnection,
        onError: (err) {
          stop();
        },
      );
    } catch (e) {
      // Failed to bind port
    }
  }

  void stop() {
    for (final conn in _clients.keys.toList()) {
      conn.close();
    }
    _clients.clear();
    _serverSocket?.close();
    _serverSocket = null;
    onPhonesChanged?.call(phoneNames);
  }

  void _acceptConnection(Socket socket) {
    late LineConnection connection;
    connection = LineConnection(socket);
    _clients[connection] = null;

    connection.onStateChange = (connected) {
      if (!connected) {
        _clients.remove(connection);
        onPhonesChanged?.call(phoneNames);
      }
    };

    connection.onPacket = (packet) {
      if (packet.hello != null) {
        _clients[connection] = packet.hello;
        onPhonesChanged?.call(phoneNames);
      }

      if (packet.command != null || packet.tool != null) {
        onRequest?.call(packet, (response) {
          connection.send(response);
        });
      }
    };

    connection.send(Packet(hello: Platform.localHostname));
    if (_lastSentFace != null) {
      connection.send(Packet(face: _lastSentFace));
    }
    onPhonesChanged?.call(phoneNames);
  }

  void broadcast(Packet packet) {
    for (final connection in _clients.keys) {
      connection.send(packet);
    }
  }

  void send(FaceState face) {
    final now = DateTime.now();
    if (_lastSentFace != null &&
        now.difference(_lastSentAt).inMilliseconds < 1000 &&
        _lastSentFace!.mood == face.mood &&
        (_lastSentFace!.gazeX - face.gazeX).abs() < 0.004 &&
        (_lastSentFace!.gazeY - face.gazeY).abs() < 0.004 &&
        (_lastSentFace!.talk - face.talk).abs() < 0.02) {
      return;
    }

    _lastSentFace = face;
    _lastSentAt = now;
    broadcast(Packet(face: face));
  }
}
