class NetworkRetry {
  static const int maxRetries = 3;
  static const Duration delay = Duration(seconds: 2);

  static Future<T> retry<T>(Future<T> Function() fn) async {
    for (int i = 0; i < maxRetries; i++) {
      try {
        return await fn();
      } catch (e) {
        if (i == maxRetries - 1) rethrow;
        await Future.delayed(delay);
      }
    }
    throw Exception('Network retry failed after $maxRetries attempts');
  }

  static bool isConnectionError(dynamic error) {
    final s = error.toString().toLowerCase();
    return s.contains('connection') ||
        s.contains('handshake') ||
        s.contains('timeout') ||
        s.contains('reset') ||
        s.contains('refused') ||
        s.contains('socket') ||
        s.contains('network') ||
        s.contains('host unreachable');
  }
}
