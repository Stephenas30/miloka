import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/ludo/ludo_engine.dart';

void main() {
  group('Ludo multiplayer state', () {
    test('creates a multiplayer room snapshot with useful turn data', () {
      final engine = LudoEngine(humanColor: LudoColor.red, isMultiplayer: true);

      final snapshot = engine.snapshot();

      expect(engine.isMultiplayer, isTrue);
      expect(engine.roomCode.isNotEmpty, isTrue);
      expect(snapshot.currentPlayerColor, LudoColor.red);
      expect(snapshot.isMultiplayer, isTrue);
      expect(snapshot.currentPlayerIndex, 0);
    });
  });
}
