import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'googly_protocol.dart';
import 'line_connection.dart';

/// Manages client-side network pairing and discovery with Desktop PhoneServer over TCP.
class PhoneClient extends ChangeNotifier {
  static final PhoneClient _instance = PhoneClient._internal();
  factory PhoneClient() => _instance;
  PhoneClient._internal() {
    _loadLastIp();
  }

  static const String _prefLastIpKey = 'last_connected_ip';

  LineConnection? _connection;
  bool _connected = false;
  String? _macName;
  String? _lastManualIp;
  String? _connectedIp;
  final List<String> _macs = [];

  void Function(FaceState face)? onFace;
  void Function(String command)? onCommand;

  bool get connected => _connected;
  String? get macName => _macName;
  String? get lastManualIp => _lastManualIp;
  String? get connectedIp => _connectedIp;
  List<String> get macs => List.unmodifiable(_macs);

  Timer? _discoveryTimer;
  Timer? _reconnectTimer;
  bool _isSearching = false;

  Future<void> _loadLastIp() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _lastManualIp = prefs.getString(_prefLastIpKey);
    } catch (_) {}
  }

  Future<void> _saveLastIp(String ip) async {
    _lastManualIp = ip;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefLastIpKey, ip);
    } catch (_) {}
  }

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
    _connectedIp = null;
    notifyListeners();
  }

  void _startDiscovery() {
    _discoveryTimer?.cancel();
    _discoveryTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_connected && _isSearching) {
        _scanLocalNetwork();
      }
    });
    _scanLocalNetwork();
  }

  Future<void> _scanLocalNetwork() async {
    if (_connected) return;

    if (_lastManualIp == null) {
      await _loadLastIp();
    }

    // Try last remembered IP first
    if (_lastManualIp != null && _lastManualIp!.isNotEmpty) {
      if (await _tryConnect(_lastManualIp!, 8080)) {
        return;
      }
    }

    final candidateHosts = <String>{'127.0.0.1', 'localhost'};

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
            for (var i = 1; i <= 254; i++) {
              candidateHosts.add('$subnet.$i');
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Network interface lookup error: $e");
    }

    final hostList = candidateHosts.toList();
    const batchSize = 25;
    for (var i = 0; i < hostList.length; i += batchSize) {
      if (_connected) break;
      final batch = hostList.sublist(i, (i + batchSize < hostList.length) ? i + batchSize : hostList.length);
      final results = await Future.wait(
        batch.map((host) => _tryConnect(host, 8080)),
      );
      if (results.contains(true)) {
        break;
      }
    }
  }

  Future<bool> _tryConnect(String host, int port) async {
    if (_connected) return true;

    try {
      final socket = await Socket.connect(host, port, timeout: const Duration(milliseconds: 450));
      _setupConnection(socket, host);
      await _saveLastIp(host);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectDirect(String host, {int port = 8080}) async {
    final cleanHost = host.trim();
    if (cleanHost.isEmpty) return false;
    final success = await _tryConnect(cleanHost, port);
    if (success) {
      await _saveLastIp(cleanHost);
    }
    return success;
  }

  void _setupConnection(Socket socket, String host) {
    _connection?.close();
    final conn = LineConnection(socket);
    _connection = conn;

    conn.onStateChange = (connected) {
      _connected = connected;
      if (!connected) {
        _connection = null;
        _macName = null;
        _connectedIp = null;
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
    _connectedIp = host;
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
