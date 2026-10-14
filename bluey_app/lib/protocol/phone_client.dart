import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'googly_protocol.dart';
import 'line_connection.dart';

/// Manages client-side network pairing and discovery with Desktop PhoneServer over TCP.
class PhoneClient extends ChangeNotifier {
  static final PhoneClient _instance = PhoneClient._internal();
  factory PhoneClient() => _instance;
  PhoneClient._internal();

  LineConnection? _connection;
  bool _connected = false;
  String? _macName;
  final List<String> _macs = [];

  void Function(FaceState face)? onFace;
  void Function(String command)? onCommand;

  bool get connected => _connected;
  String? get macName => _macName;
  List<String> get macs => List.unmodifiable(_macs);

  Timer? _discoveryTimer;
  Timer? _reconnectTimer;
  bool _isSearching = false;

  void start() {
    if (_isSearching) return;
    _isSearching = true;
    _startDiscovery();
  }

  void stop() {
    _isSearching = false;
    _discoveryTimer?.cancel();
    _reconnectTimer?.cancel();
    _connection?.close();
    _connection = null;
    _connected = false;
    notifyListeners();
  }

  void _startDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_connected) {
        _scanLocalNetwork();
      }
    });
    _scanLocalNetwork();
  }

  Future<void> _scanLocalNetwork() async {
    final candidateHosts = <String>['127.0.0.1', 'localhost'];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          final parts = ip.split('.');
          if (parts.length == 4 && parts[0] != '127') {
            final subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            // Probe common local IPs in subnet
            candidateHosts.add('$subnet.1');
            candidateHosts.add('$subnet.100');
            for (var i = 2; i <= 254; i++) {
              if (i == int.tryParse(parts[3])) continue;
              if (i < 20 || (i >= 100 && i <= 120) || i > 250) {
                candidateHosts.add('$subnet.$i');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Network interface lookup error: $e");
    }

    for (final host in candidateHosts) {
      if (_connected) break;
      _tryConnect(host, 8080);
    }
  }

  Future<bool> _tryConnect(String host, int port) async {
    if (_connected) return true;

    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 600));
      _setupConnection(socket);
      return true;
    } catch (_) {
      return false;
    }
  }

  void connectDirect(String host, {int port = 8080}) {
    _tryConnect(host, port);
  }

  void _setupConnection(Socket socket) {
    _connection?.close();
    final conn = LineConnection(socket);
    _connection = conn;

    conn.onStateChange = (connected) {
      _connected = connected;
      if (!connected) {
        _connection = null;
        _macName = null;
        _scheduleReconnect();
      }
      notifyListeners();
    };

    conn.onPacket = (packet) {
      if (packet.hello != null) {
        _macName = packet.hello;
        if (!_macs.contains(_macName!)) {
          _macs.add(_macName!);
        }
        notifyListeners();
      }

      if (packet.face != null) {
        onFace?.call(packet.face!);
      }

      if (packet.command != null) {
        onCommand?.call(packet.command!);
      }
    };

    _connected = true;
    conn.send(Packet(hello: Platform.operatingSystem));
    notifyListeners();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (!_connected && _isSearching) {
        _scanLocalNetwork();
      }
    });
  }

  void send(Packet packet) {
    _connection?.send(packet);
  }
}
