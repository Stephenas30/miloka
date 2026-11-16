import 'package:wakelock_plus/wakelock_plus.dart';

class GameWakeLock {
  static int _holders = 0;

  static bool get isHeld => _holders > 0;

  static Future<void> acquire() async {
    _holders += 1;
    if (_holders == 1) {
      await WakelockPlus.enable();
    }
  }

  static Future<void> release() async {
    if (_holders == 0) return;
    _holders -= 1;
    if (_holders == 0) {
      await WakelockPlus.disable();
    }
  }

  static Future<void> onAppResumed() async {
    if (isHeld) {
      await WakelockPlus.enable();
    }
  }
}
