import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/domino/domino_block_engine.dart';
import 'package:miloka/game/domino/domino_engine.dart';

void main() {
  DominoBlockEngine createBlockEngine({int players = 2, int seed = 42}) {
    final engine = DominoBlockEngine(
      human: [
        for (var i = 0; i < players; i++)
          DominoHuman(id: 'ai_$i', name: 'Robot ${i + 1}'),
      ],
      random: Random(seed),
    );
    engine.start();
    return engine;
  }

  group('DominoBlockEngine distribution', () {
    test('28 tuiles, 7 par joueur et double d\'ouverture', () {
      final engine = createBlockEngine(players: 4);

      expect(engine.variant, 'block');
      expect(engine.played.length, 1);
      expect(engine.played.first.isDouble, isTrue);
      final hands = engine.players.map((p) => p.hand.length).toList();
      // Le joueur qui ouvre a posé son double : 6 tuiles, les autres 7.
      expect(hands.where((c) => c == 7).length, 3);
      expect(hands.where((c) => c == 6).length, 1);
      expect(
        hands.fold<int>(0, (s, c) => s + c) +
            engine.boneyardCount +
            engine.played.length,
        28,
      );
    });
  });

  group('DominoBlockEngine : jamais de pioche', () {
    test('canDraw toujours faux et la pioche ne rend rien', () {
      final engine = createBlockEngine(players: 2);

      // Avec 2 joueurs, il reste des tuiles au bac, mais le Bloc n'utilise
      // jamais le bac : on passe obligatoirement.
      expect(engine.boneyardCount, greaterThan(0));
      expect(engine.canDraw, isFalse);
      expect(engine.drawFromBoneyard(), isNull);
    });

    test('canPass vrai quand aucune tuile jouable, faux sinon', () {
      final engine = createBlockEngine(players: 2);
      engine.openLeft = 6;
      engine.openRight = 6;
      engine.players[0].hand
        ..clear()
        ..add(DominoTile(5, 5));
      engine.players[1].hand
        ..clear()
        ..add(DominoTile(4, 4));
      engine.currentPlayerIndex = 0;
      engine.blocked = false;
      engine.winnerIndex = null;

      expect(engine.canPass, isTrue);
      expect(engine.passTurn(), isTrue);

      // Le joueur suivant a une tuile jouable : pas de blocage.
      engine.players[1].hand
        ..clear()
        ..add(DominoTile(6, 4));
      engine.currentPlayerIndex = 0;
      engine.blocked = false;
      engine.winnerIndex = null;
      expect(engine.canPass, isTrue);
      expect(engine.passTurn(), isTrue);
      expect(engine.blocked, isFalse);
    });
  });

  group('DominoBlockEngine : blocage', () {
    test('partie bloquée -> vainqueur avec le moins de points', () {
      final engine = createBlockEngine(players: 2);

      // Aucun joueur ne peut jouer : 6-6 bloqué des deux côtés.
      engine.openLeft = 6;
      engine.openRight = 6;
      engine.players[0].hand
        ..clear()
        ..add(DominoTile(5, 5)); // 10 points
      engine.players[1].hand
        ..clear()
        ..add(DominoTile(4, 4)); // 8 points
      engine.currentPlayerIndex = 0;
      engine.blocked = false;
      engine.winnerIndex = null;

      expect(engine.passTurn(), isTrue);
      expect(engine.blocked, isTrue);
      expect(engine.winnerIndex, 1);
      expect(engine.message.contains('gagne'), isTrue);
    });
  });

  group('DominoBlockEngine : fin de partie', () {
    test('les IA jouent jusqu\'à la fin (sortie ou blocage)', () {
      final engine = createBlockEngine(players: 4, seed: 7);
      var tours = 0;
      while (!engine.gameOver && tours < 200) {
        engine.aiTurn();
        tours++;
      }
      expect(engine.gameOver, isTrue);
      expect(engine.winnerIndex, isNotNull);
      expect(engine.message.contains('gagn'), isTrue);
    });
  });

  group('DominoSnapshot Bloc', () {
    test('aller-retour JSON conserve la variante block', () {
      final engine = createBlockEngine(players: 2, seed: 3);
      final snapshot = engine.snapshot();

      expect(snapshot.variant, 'block');

      final restored = DominoSnapshot.fromJson(snapshot.toJson());
      expect(restored.variant, 'block');
      expect(restored.played, snapshot.played);
      expect(restored.openLeft, snapshot.openLeft);
      expect(restored.openRight, snapshot.openRight);
    });

    test('applySnapshot restaure un moteur Bloc', () {
      final engine = createBlockEngine(players: 2, seed: 5);
      final snapshot = engine.snapshot();

      final other = createBlockEngine(players: 2, seed: 9);
      other.applySnapshot(snapshot);

      for (var i = 0; i < other.players.length; i++) {
        final expected = snapshot.hands[i];
        final actual =
            other.players[i].hand.expand((t) => [t.left, t.right]).toList();
        expect(actual.toString(), expected.toString());
      }
      expect(other.openLeft, snapshot.openLeft);
      expect(other.openRight, snapshot.openRight);
    });
  });
}
