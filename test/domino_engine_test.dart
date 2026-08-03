import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/domino/domino_engine.dart';

void main() {
  DominoEngine createEngine({int aiPlayers = 3, Random? random}) {
    final engine = DominoEngine(
      human: [
        DominoHuman(id: null, name: 'Joueur'),
        for (var i = 0; i < aiPlayers; i++)
          DominoHuman(id: 'ai_$i', name: 'Robot ${i + 1}'),
      ],
      random: random ?? Random(42),
    );
    engine.start();
    return engine;
  }

  group('DominoEngine distribution', () {
    test('mélange complet : 28 tuiles réparties et bac restant', () {
      final engine = createEngine();

      expect(DominoEngine.fullTileSet().length, 28);
      final totalInHands = engine.players.fold<int>(
        0,
        (sum, p) => sum + p.hand.length,
      );
      expect(engine.players.length, 4);
      expect(totalInHands + engine.boneyardCount + engine.played.length, 28);
      expect(engine.boneyardCount, 28 - 7 * 4);
    });

    test('le premier joueur joue le plus gros double, puis tour suivant', () {
      final engine = createEngine();

      final opener = engine.played.first;
      expect(opener.isDouble, isTrue);
      expect(engine.openLeft, opener.left);
      expect(engine.openRight, opener.right);

      // Aucun autre double plus gros ne doit rester en main.
      for (final p in engine.players) {
        for (final t in p.hand) {
          if (t.isDouble) {
            expect(t.total <= opener.total, isTrue, reason: '${t.left}|${t.right}');
          }
        }
      }

      expect(engine.currentPlayerIndex, inInclusiveRange(0, engine.players.length - 1));
      expect(engine.players[engine.currentPlayerIndex].hand.length, 7);
    });
  });

  group('DominoEngine gameplay', () {
    test('jouer une tuile valide met à jour les extrémités', () {
      final engine = createEngine();
      final player = engine.currentPlayer;
      final playable = engine.playableTilesFor(player);
      final tile = playable.first;
      final sides = engine.validSidesFor(tile);
      final before = player.hand.length;

      final ok = engine.playTile(tile, sides.first);

      expect(ok, isTrue);
      expect(player.hand.length, before - 1);
      expect(engine.played.contains(tile), isTrue);
      expect(engine.openLeft != null && engine.openRight != null, isTrue);
    });

    test('pioche quand aucune tuile jouable', () {
      final engine = createEngine();
      final player = engine.currentPlayer;
      final playable = engine.playableTilesFor(player);

      if (playable.isNotEmpty) {
        engine.playTile(playable.first, engine.validSidesFor(playable.first).first);
        final player2 = engine.currentPlayer;
        if (engine.playableTilesFor(player2).isEmpty && engine.canDraw) {
          final before = player2.hand.length;
          engine.drawFromBoneyard();
          expect(player2.hand.length, before + 1);
        }
      } else if (engine.canDraw) {
        final before = player.hand.length;
        engine.drawFromBoneyard();
        expect(player.hand.length, before + 1);
      }
    });

    test('passe uniquement si aucune tuile et bac vide', () {
      final engine = createEngine();
      expect(engine.canPass, isFalse);
      expect(engine.passTurn(), isFalse);
    });

    test("l'IA joue ou pioche, et la partie reste cohérente", () {
      final engine = DominoEngine(
        human: [
          for (var i = 0; i < 4; i++)
            DominoHuman(id: 'ai_$i', name: 'Robot ${i + 1}'),
        ],
        random: Random(42),
      );
      engine.start();
      var tours = 0;
      while (!engine.gameOver && tours < 200) {
        engine.aiTurn();
        tours++;
      }
      expect(engine.gameOver, isTrue);
      expect(engine.winnerIndex, isNotNull);
      expect(engine.message.contains('gagne'), isTrue);
    });
  });

  group('DominoSnapshot', () {
    test('aller-retour JSON identique', () {
      final engine = createEngine();
      final snapshot = engine.snapshot();

      final restored = DominoSnapshot.fromJson(snapshot.toJson());

      expect(restored.currentPlayerIndex, snapshot.currentPlayerIndex);
      expect(restored.playerNames, snapshot.playerNames);
      expect(restored.hands, snapshot.hands);
      expect(restored.boneyard, snapshot.boneyard);
      expect(restored.played, snapshot.played);
      expect(restored.openLeft, snapshot.openLeft);
      expect(restored.openRight, snapshot.openRight);
    });

    test("applySnapshot restaure l'état du moteur", () {
      final engine = createEngine();
      final snapshot = engine.snapshot();

      final other = DominoEngine(
        human: [
          DominoHuman(id: null, name: 'Joueur'),
          for (var i = 0; i < 3; i++) DominoHuman(id: 'ai_$i', name: 'Robot $i'),
        ],
        random: Random(1),
      );
      other.start();
      other.applySnapshot(snapshot);

      expect(other.handsEqual(snapshot), isTrue);
    });
  });
}

extension on DominoEngine {
  bool handsEqual(DominoSnapshot snapshot) {
    for (var i = 0; i < players.length; i++) {
      final expected = snapshot.hands[i];
      final actual = players[i].hand.expand((t) => [t.left, t.right]).toList();
      if (expected.toString() != actual.toString()) return false;
    }
    return true;
  }
}
