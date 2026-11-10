class PoolNetwork {
  PoolNetwork({
    required this.onLine,
    required this.onStatus,
  });

  final void Function(String message) onLine;
  final void Function(String status) onStatus;

  static const bool supportsLan = false;

  Future<String> host() async =>
      throw UnsupportedError('Le jeu en réseau local n’est pas disponible ici.');

  Future<void> join(String address) async =>
      throw UnsupportedError('Le jeu en réseau local n’est pas disponible ici.');

  void send(String message) {}

  Future<void> close() async {}
}
