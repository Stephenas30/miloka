import 'dart:async';
import 'dart:convert';
import 'dart:io';

class PoolNetwork {
  PoolNetwork({
    required this.onLine,
    required this.onStatus,
  });

  static const bool supportsLan = true;
  static const int port = 5050;

  final void Function(String message) onLine;
  final void Function(String status) onStatus;
  ServerSocket? _server;
  Socket? _socket;
  StreamSubscription<String>? _subscription;
  bool _closed = false;

  Future<String> host() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_attach, onError: (Object error) {
      if (!_closed) onStatus('error');
    });
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback) return address.address;
      }
    }
    return '?';
  }

  Future<void> join(String address) async {
    final socket = await Socket.connect(
      address,
      port,
      timeout: const Duration(seconds: 8),
    );
    _attach(socket);
  }

  void _attach(Socket socket) {
    if (_closed) {
      socket.destroy();
      return;
    }
    _socket = socket;
    onStatus('connected');
    _subscription = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(onLine, onError: (Object error) {
      if (!_closed) onStatus('lost');
    }, onDone: () {
      if (!_closed) onStatus('lost');
    });
  }

  void send(String message) {
    _socket?.write('$message\n');
  }

  Future<void> close() async {
    _closed = true;
    await _subscription?.cancel();
    await _socket?.close();
    await _server?.close();
    _socket?.destroy();
  }
}
