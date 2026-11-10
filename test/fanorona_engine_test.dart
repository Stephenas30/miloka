import 'package:flutter_test/flutter_test.dart';
import 'package:miloka/game/fanorona/fanorona_engine.dart';

List<int> makeBoard({Map<int, int>? pieces}) {
  final b = List<int>.filled(FanoronaEngine.size, FanoronaEngine.empty);
  pieces?.forEach((pos, val) => b[pos] = val);
  return b;
}

void main() {
  group('Fanorona initial setup', () {
    test('starts with 22 pieces each and an empty center', () {
      final e = FanoronaEngine();
      expect(e.countPieces(FanoronaPlayer.human), 22);
      expect(e.countPieces(FanoronaPlayer.ai), 22);
      expect(e.board[22], FanoronaEngine.empty); // center (row2,col4)
      expect(e.turn, 0); // human plays first
      expect(e.winner, isNull);
    });

    test('matches the reference start state (white top / black bottom)', () {
      final e = FanoronaEngine();
      // rows 0 and 1 = ai (grey, top)
      expect(e.board.sublist(0, 9).toSet(), {FanoronaEngine.aiPiece});
      expect(e.board.sublist(9, 18).toSet(), {FanoronaEngine.aiPiece});
      // rows 3 and 4 = human (orange, bottom)
      expect(e.board.sublist(27, 36).toSet(), {FanoronaEngine.humanPiece});
      expect(e.board.sublist(36, 45).toSet(), {FanoronaEngine.humanPiece});
      // middle row: B W B W 1 W B W B
      expect(e.board[18], FanoronaEngine.humanPiece); // col0
      expect(e.board[19], FanoronaEngine.aiPiece); //    col1
      expect(e.board[20], FanoronaEngine.humanPiece); // col2
      expect(e.board[21], FanoronaEngine.aiPiece); //    col3
      expect(e.board[22], FanoronaEngine.empty); //      col4
      expect(e.board[23], FanoronaEngine.aiPiece); //    col5
      expect(e.board[24], FanoronaEngine.humanPiece); // col6
      expect(e.board[25], FanoronaEngine.aiPiece); //    col7
      expect(e.board[26], FanoronaEngine.humanPiece); // col8
    });
  });

  group('geometry helpers', () {
    test('directionBetween maps adjacent points', () {
      expect(FanoronaEngine.directionBetween(22, 13), 0); // north
      expect(FanoronaEngine.directionBetween(22, 23), 2); // east
      expect(FanoronaEngine.directionBetween(22, 31), 4); // south
      expect(FanoronaEngine.directionBetween(22, 21), 6); // west
      expect(FanoronaEngine.directionBetween(22, 14), 1); // NE (strong point)
    });

    test('strong points are (row+col) even', () {
      expect(FanoronaEngine.isStrongPoint(22), isTrue); // (2,4)
      expect(FanoronaEngine.isStrongPoint(23), isFalse); // (2,5)
      expect(FanoronaEngine.isStrongPoint(13), isFalse); // (1,4)
    });
  });

  group('captures', () {
    test('approach capture removes the line ahead', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          23: FanoronaEngine.humanPiece, // (2,5)
          5: FanoronaEngine.aiPiece, //     (0,5)
        }),
      );
      final moves = e.legalMoves();
      expect(moves.length, 1);
      expect(moves.first.type, FanoronaMoveType.approach);
      expect(moves.first.from, 23);
      expect(moves.first.dir, 0);

      final captured = e.applyMove(moves.first);
      expect(captured, [5]);
      expect(e.board[14], FanoronaEngine.humanPiece);
      expect(e.board[23], FanoronaEngine.empty);
      expect(e.board[5], FanoronaEngine.empty);
      expect(e.inCaptureSequence, isTrue);
    });

    test('withdrawal capture removes the line behind', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          23: FanoronaEngine.humanPiece, // (2,5)
          32: FanoronaEngine.aiPiece, //     (3,5)
        }),
      );
      final moves = e.legalMoves();
      expect(
        moves.any((m) =>
            m.type == FanoronaMoveType.withdrawal && m.from == 23 && m.dir == 0),
        isTrue,
      );

      final captured = e.applyMove(
        moves.firstWhere((m) => m.type == FanoronaMoveType.withdrawal),
      );
      expect(captured, [32]);
      expect(e.board[14], FanoronaEngine.humanPiece);
    });

    test('captures are forced (no paika when a capture exists)', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          41: FanoronaEngine.humanPiece, // (4,5)
          23: FanoronaEngine.aiPiece, //     (2,5)
          14: FanoronaEngine.aiPiece, //     (1,5)
        }),
      );
      final moves = e.legalMoves();
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.type != FanoronaMoveType.paika), isTrue);
    });

    test('paika is allowed only when no capture exists', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          4: FanoronaEngine.humanPiece, // (0,4)
          40: FanoronaEngine.aiPiece, //    (4,4)
        }),
      );
      final moves = e.legalMoves();
      expect(moves, isNotEmpty);
      expect(moves.every((m) => m.type == FanoronaMoveType.paika), isTrue);
    });

    test('capture sequence continues then ends on endTurn', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          22: FanoronaEngine.humanPiece, // (2,4)
          31: FanoronaEngine.aiPiece, //     (3,4) withdrawal target
          15: FanoronaEngine.aiPiece, //     (1,6) approach target
        }),
      );

      // move 1: withdrawal north (captures 31, lands on 13)
      final m1 = e.legalMoves().first;
      expect(m1.type, FanoronaMoveType.withdrawal);
      expect(e.applyMove(m1), [31]);

      // only one continuation: approach east (captures 15)
      final cont = e.legalMoves();
      expect(cont.length, 1);
      expect(cont.first.type, FanoronaMoveType.approach);
      expect(cont.first.dir, 2);
      expect(e.applyMove(cont.first), [15]);

      // no more captures -> no continuation
      expect(e.legalMoves(), isEmpty);
      e.endTurn();
      // ai has no pieces -> human wins
      expect(e.winner, 0);
    });

    test('no two captures in the same direction in a row', () {
      final e = FanoronaEngine(
        initialBoard: makeBoard(pieces: {
          13: FanoronaEngine.humanPiece, // (1,4)
          12: FanoronaEngine.aiPiece, //     (1,3) withdrawal-behind target
          16: FanoronaEngine.aiPiece, //     (1,7) same-direction approach target
        }),
      );
      // move 1: withdrawal east (captures 12, lands on 14)
      final m1 = e.legalMoves().first;
      expect(m1.type, FanoronaMoveType.withdrawal);
      expect(m1.dir, 2);
      expect(e.applyMove(m1), [12]);

      // the same-direction (east) capture of 16 is forbidden by the rule,
      // and west leads back to the visited square 13
      expect(e.legalMoves(), isEmpty);
    });
  });

  group('game end', () {
    test('player wins when opponent is eliminated', () {
      final board = makeBoard(pieces: {
        22: FanoronaEngine.humanPiece,
      });
      final e2 = FanoronaEngine(initialBoard: board);
      e2.endTurn(); // switch to ai turn -> ai has no pieces
      expect(e2.winner, 0);
    });
  });

  group('snapshot round-trip', () {
    test('applySnapshot restores identical state', () {
      final e = FanoronaEngine();
      // make a capture move so lastCapture is set
      final moves = e.legalMoves();
      e.applyMove(moves.first);

      final snap = e.snapshot();
      final e2 = FanoronaEngine();
      e2.applySnapshot(snap);

      expect(e2.board, e.board);
      expect(e2.turn, e.turn);
      expect(e2.inCaptureSequence, e.inCaptureSequence);
      expect(e2.movingPiecePos, e.movingPiecePos);
      expect(e2.consecutivePaika, e.consecutivePaika);
      expect(e2.winner, e.winner);
      expect(e2.drawReason, e.drawReason);
    });
  });

  group('smoke tests', () {
    test('random play terminates (win or draw)', () {
      final e = FanoronaEngine();
      var guard = 0;
      while (!e.isGameOver && guard < 3000) {
        final moves = e.legalMoves();
        if (moves.isEmpty) {
          e.endTurn();
          guard++;
          continue;
        }
        final move = moves[(guard + moves.length) % moves.length];
        e.applyMove(move);
        if (e.inCaptureSequence && e.legalMoves().isEmpty) {
          e.endTurn();
        }
        guard++;
      }
      expect(e.isGameOver, isTrue);
    });

    test('aiChooseNextMove completes a game', () {
      final e = FanoronaEngine();
      var guard = 0;
      while (!e.isGameOver && guard < 3000) {
        final move = e.aiChooseNextMove();
        if (move == null) {
          if (e.inCaptureSequence) e.endTurn();
          guard++;
          continue;
        }
        e.applyMove(move);
        if (e.inCaptureSequence && e.legalMoves().isEmpty) {
          e.endTurn();
        }
        guard++;
      }
      expect(e.isGameOver, isTrue);
    });
  });
}