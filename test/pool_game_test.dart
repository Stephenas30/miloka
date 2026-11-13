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

    test('scratch passes the turn and enters placement mode', () {
      final game = PoolGame(mode: PoolMode.local);
      game.cueBall.x = PoolGame.rail;
      game.cueBall.y = PoolGame.rail;

      game.takeShot(0, 1);
      for (var frame = 0; frame < 30; frame++) {
        game.tick();
      }

      expect(game.state, PoolGameState.placingCue);
      expect(game.currentPlayer, 1);
      expect(game.message, contains('ligne de départ'));
    });

    test('cue ball cannot be placed beyond the head string', () {
      final game = _scratchGame();

      game.pointerMove(900, 240);
      expect(game.cueBall.x, PoolGame.headStringX);

      game.pointerMove(58, 240);
      expect(game.cueBall.x, 58);
    });

    test('cue ball placement overlapping a pocket is invalid', () {
      final game = _scratchGame();

      game.pointerMove(30, 30);
      expect(game.cuePlacementValid, isFalse);

      game.pointerUp();
      expect(game.state, PoolGameState.placingCue);

      game.pointerMove(120, 240);
      expect(game.cuePlacementValid, isTrue);
      game.pointerUp();
      expect(game.state, PoolGameState.aiming);
    });

    test('cue ball placement in collision with another ball is invalid', () {
      final game = _scratchGame();
      final objectBall =
          game.balls.firstWhere((ball) => ball.id == 9 && !ball.pocketed);
      objectBall.x = 150;
      objectBall.y = 240;

      game.pointerMove(150, 240);
      expect(game.cuePlacementValid, isFalse);

      game.pointerMove(180, 320);
      expect(game.cuePlacementValid, isTrue);
    });

    test('timer counts down and passes the turn automatically', () {
      var now = DateTime(2026, 11, 13, 12);
      final game = PoolGame(mode: PoolMode.local, now: () => now);

      expect(game.turnSecondsLeft, PoolGame.turnSeconds);
      expect(game.currentPlayer, 0);

      now = now.add(const Duration(seconds: 5));
      game.tick();
      expect(game.turnSecondsLeft, 55);

      now = now.add(const Duration(seconds: 56));
      game.tick();
      expect(game.currentPlayer, 1);
      expect(game.turnSecondsLeft, PoolGame.turnSeconds);
      expect(game.state, PoolGameState.aiming);

      now = now.add(const Duration(seconds: 60));
      game.tick();
      expect(game.currentPlayer, 0);
    });

    test('timer stops once the shot is launched', () {
      var now = DateTime(2026, 11, 13, 12);
      final game = PoolGame(mode: PoolMode.local, now: () => now);

      now = now.add(const Duration(seconds: 3));
      game.tick();
      expect(game.turnSecondsLeft, 57);

      game.takeShot(0, .2);
      for (var frame = 0; frame < 10; frame++) {
        now = now.add(const Duration(seconds: 100));
        game.tick();
      }

      expect(game.state, PoolGameState.moving);
      expect(game.turnSecondsLeft, 57);
    });

    test('timeout during cue placement resets the cue and passes the turn',
        () {
      var now = DateTime(2026, 11, 13, 12);
      final game = PoolGame(mode: PoolMode.local, now: () => now);
      game.cueBall.x = PoolGame.rail;
      game.cueBall.y = PoolGame.rail;
      game.takeShot(0, 1);
      for (var frame = 0; frame < 30; frame++) {
        game.tick();
      }
      expect(game.state, PoolGameState.placingCue);
      expect(game.currentPlayer, 1);

      game.pointerMove(80, 300);
      now = now.add(const Duration(seconds: 61));
      game.tick();

      expect(game.currentPlayer, 0);
      expect(game.state, PoolGameState.aiming);
      expect(game.turnSecondsLeft, PoolGame.turnSeconds);
      expect(game.cueBall.x, lessThanOrEqualTo(PoolGame.headStringX));
      expect(game.cueBall.y, PoolGame.tableHeight / 2);
    });
  });
}

PoolGame _scratchGame() {
  final game = PoolGame(mode: PoolMode.local);
  game
    ..cueBall.x = PoolGame.rail
    ..cueBall.y = PoolGame.rail;
  game.takeShot(0, 1);
  for (var frame = 0; frame < 30; frame++) {
    game.tick();
  }
  return game;
}
