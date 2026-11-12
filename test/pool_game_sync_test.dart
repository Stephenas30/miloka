import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/pool_game.dart';

void main() {
  test('two instances of the same game stay in sync through the wire protocol',
      () {
    const seed = 42;
    final host = PoolGame(mode: PoolMode.online, myPlayerIndex: 0);
    final guest = PoolGame(mode: PoolMode.online, myPlayerIndex: 1);
    host.start(seed: seed);
    guest.start(seed: seed);

    expect(host.balls.length, guest.balls.length);
    for (var i = 0; i < host.balls.length; i++) {
      expect(host.balls[i].id, guest.balls[i].id);
      expect(host.balls[i].x, guest.balls[i].x);
      expect(host.balls[i].y, guest.balls[i].y);
    }

    // Simulate the host breaking (straight at the apex) and the guest applying
    // the mirrored SHOT.
    host.takeShot(0, 0.9);
    guest.remoteShot(0, 0.9);

    for (var frame = 0; frame < 2000; frame++) {
      host.tick();
      guest.tick();
      if (host.state == PoolGameState.aiming &&
          guest.state == PoolGameState.aiming) {
        break;
      }
    }

    expect(host.state, PoolGameState.aiming);
    expect(guest.state, PoolGameState.aiming);
    expect(host.currentPlayer, guest.currentPlayer);
    for (var i = 0; i < host.balls.length; i++) {
      expect(host.balls[i].pocketed, guest.balls[i].pocketed,
          reason: 'ball $i pocketed mismatch');
      if (!host.balls[i].pocketed) {
        expect(host.balls[i].x, closeTo(guest.balls[i].x, 0.5),
            reason: 'ball $i x mismatch');
        expect(host.balls[i].y, closeTo(guest.balls[i].y, 0.5),
            reason: 'ball $i y mismatch');
      }
    }
    expect(host.currentPlayer, 1);
    expect(guest.canControl, isTrue);

    // Host sends STATE snapshot; guest applies it and they converge.
    final snapshot = host.snapshot();
    expect(guest.applySnapshot(snapshot), isTrue);
    expect(guest.currentPlayer, host.currentPlayer);
  });
}
