import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/pool_game.dart';

void main() {
  group('PoolGame', () {
    test('uses the Fanorona board aspect ratio', () {
      expect(PoolGame.tableWidth / PoolGame.tableHeight, 2);
    });

    test('starts an eight-ball rack with a cue ball and the 8-ball', () {
      final game = PoolGame(mode: PoolMode.local);

      expect(game.balls, hasLength(16));
      expect(game.balls.first.id, 0);
      expect(game.balls.where((ball) => ball.id == 8), hasLength(1));
      expect(game.remaining(1), 7);
      expect(game.remaining(2), 7);
    });

    test('animates a shot and moves the cue ball', () {
      final game = PoolGame(mode: PoolMode.local);
      final startingX = game.cueBall.x;

      game.takeShot(0, 1);
      expect(game.state, PoolGameState.striking);
      for (var frame = 0; frame < 6; frame++) {
        game.tick();
      }

      expect(game.state, PoolGameState.moving);
      game.tick();
      expect(game.cueBall.x, greaterThan(startingX));
    });

    test('rolls the ball orientation as it travels', () {
      final game = PoolGame(mode: PoolMode.local);

      game.takeShot(0, 1);
      for (var frame = 0; frame < 7; frame++) {
        game.tick();
      }

      expect(game.cueBall.orientation[0], lessThan(1));
    });

    test('applies a matching online state snapshot', () {
      final host = PoolGame(mode: PoolMode.online, myPlayerIndex: 0)
        ..start(seed: 42);
      final guest = PoolGame(mode: PoolMode.online, myPlayerIndex: 1)
        ..start(seed: 42);

      expect(guest.applySnapshot(host.snapshot()), isTrue);
      expect(guest.cueBall.x, host.cueBall.x);
      expect(guest.balls.map((ball) => ball.id), host.balls.map((ball) => ball.id));
      expect(guest.state, host.state);
    });

    test('accepts a shot from the remote player', () {
      final guest = PoolGame(mode: PoolMode.online, myPlayerIndex: 1)
        ..start(seed: 42);

      guest.remoteShot(0, .5);

      expect(guest.state, PoolGameState.striking);
    });

    test('rejects malformed state snapshots', () {
      final game = PoolGame(mode: PoolMode.online);

      expect(game.applySnapshot('STATE invalid'), isFalse);
    });
  });
}
