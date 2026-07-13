import 'dart:math';


enum LudoColor { red, green, yellow, blue }

extension LudoColorExt on LudoColor {
  String get label => switch (this) {
        LudoColor.red => 'Rouge',
        LudoColor.green => 'Vert',
        LudoColor.yellow => 'Jaune',
        LudoColor.blue => 'Bleu',
      };

  int get startIndex => index * 13;

}

class LudoPawn {
  final int id;
  final LudoColor color;
  int stepsFromStart;

  LudoPawn({required this.id, required this.color}) : stepsFromStart = -1;

  bool get inBase => stepsFromStart < 0;
  bool get onTrack => stepsFromStart >= 0 && stepsFromStart <= 50;
  bool get inHome => stepsFromStart >= 51 && stepsFromStart <= 55;
  bool get finished => stepsFromStart >= 56;

  int? get trackIndex {
    if (!onTrack) return null;
    return (color.startIndex + stepsFromStart) % 52;
  }

  LudoPawn copy() => LudoPawn(id: id, color: color)
    ..stepsFromStart = stepsFromStart;
}

class LudoPlayer {
  final LudoColor color;
  final List<LudoPawn> pawns;
  final bool isHuman;

  LudoPlayer({required this.color, required this.isHuman})
      : pawns = List.generate(4, (i) => LudoPawn(id: i, color: color));

  bool get hasWon => pawns.every((p) => p.finished);
}

class LudoMove {
  final LudoPawn pawn;
  final int dice;
  final int fromSteps;
  final int toSteps;

  LudoMove({
    required this.pawn,
    required this.dice,
    required this.fromSteps,
    required this.toSteps,
  });
}

class LudoEngine {
  static const safeTrackIndices = {0, 8, 13, 21, 26, 34, 39, 47};

  final List<LudoPlayer> players;
  int currentPlayerIndex = 0;
  int lastDice = 0;
  bool diceRolled = false;
  bool extraTurn = false;
  LudoColor? winner;
  LudoMove? lastMove;
  String message = 'Lance le dé pour commencer';

  final LudoColor humanColor;
  final Random _random = Random();

  LudoEngine({required this.humanColor})
      : players = [
          LudoPlayer(color: LudoColor.red, isHuman: humanColor == LudoColor.red),
          LudoPlayer(color: LudoColor.green, isHuman: humanColor == LudoColor.green),
          LudoPlayer(color: LudoColor.yellow, isHuman: humanColor == LudoColor.yellow),
          LudoPlayer(color: LudoColor.blue, isHuman: humanColor == LudoColor.blue),
        ];

  LudoPlayer get currentPlayer => players[currentPlayerIndex];

  int rollDice() {
    if (/* diceRolled || */ winner != null) return lastDice;
    lastDice =  _random.nextInt(6) + 1;
    //diceRolled = true;
    final moves = getValidMoves();
    if (moves.isEmpty) {
      message =
          '${currentPlayer.color.label} : $lastDice — aucun coup possible';
      //_scheduleTurnEnd(extraTurn: lastDice == 6);
    } else {
      message = lastDice == 6
          ? '${currentPlayer.color.label} : 6 ! Choisis un pion'
          : '${currentPlayer.color.label} : $lastDice — choisis un pion';
    }

    print('View DiceRolled (${currentPlayer.color.label}) => $lastDice');
    return lastDice;
  }

  List<LudoMove> getValidMoves() {
    if (/* !diceRolled || */ winner != null) return [];
    final moves = <LudoMove>[];
    for (final pawn in currentPlayer.pawns) {
      final move = _evaluateMove(pawn, lastDice);
      if (move != null) moves.add(move);
    }
    return moves;
  }

  LudoMove? _evaluateMove(LudoPawn pawn, int dice) {
    if (pawn.finished) return null;

    if (pawn.inBase) {
      if (dice != 6) return null;
      return LudoMove(pawn: pawn, dice: dice, fromSteps: -1, toSteps: 0);
    }

    final target = pawn.stepsFromStart + dice;
    if (target > 56) return null;

    return LudoMove(
      pawn: pawn,
      dice: dice,
      fromSteps: pawn.stepsFromStart,
      toSteps: target,
    );
  }

  bool canMovePawn(LudoPawn pawn) {
    return getValidMoves().any((m) => m.pawn.id == pawn.id && m.pawn.color == pawn.color);
  }

  bool applyMove(LudoPawn pawn) {
    if (winner != null /* || !diceRolled */) return false;

    final move = getValidMoves().where((m) => m.pawn.id == pawn.id).firstOrNull;
    if (move == null) return false;

    lastMove = move;
    pawn.stepsFromStart = move.toSteps;

    if (pawn.onTrack) {
      _captureAt(pawn);
    }

    if (currentPlayer.hasWon) {
      winner = currentPlayer.color;
      message = '${winner!.label} a gagné !';
      //diceRolled = false;
      return true;
    }

    final rolledSix = lastDice == 6;
    final captured = _lastCapture;
    final finishedPawn = move.toSteps >= 56;
    _lastCapture = false;

    extraTurn = false;
    if (rolledSix || captured || finishedPawn) {
      extraTurn = true;
      message = finishedPawn
          ? 'Pion arrivé au centre ! ${currentPlayer.color.label} rejoue'
          : captured
              ? 'Capture ! ${currentPlayer.color.label} rejoue'
              : '6 obtenu ! ${currentPlayer.color.label} rejoue';
    }
    return true;
  }

  bool _lastCapture = false;

  void _captureAt(LudoPawn movingPawn) {
    final index = movingPawn.trackIndex!;
    if (safeTrackIndices.contains(index)) return;

    _lastCapture = false;
    for (final player in players) {
      if (player.color == movingPawn.color) continue;
      for (final pawn in player.pawns) {
        if (pawn.onTrack && pawn.trackIndex == index) {
          pawn.stepsFromStart = -1;
          _lastCapture = true;
        }
      }
    }
  }

  void scheduleTurnEnd({required bool extraTurn}) {
    this.extraTurn = extraTurn;
    if (!extraTurn) {
       _nextPlayer();
    } else {
      diceRolled = false;
      message = '${currentPlayer.color.label} rejoue (6)';
    }
  }

  void skipTurnIfNoMoves() {
    extraTurn = false;
  }

  void _nextPlayer() {
      print('Lancer');

    extraTurn = false;
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    print(currentPlayerIndex);
    message = 'Tour de ${currentPlayer.color.label}';
  }

  void reset() {
    currentPlayerIndex = 0;
    lastDice = 0;
    //diceRolled = false;
    extraTurn = false;
    winner = null;
    message = 'Lance le dé pour commencer';
    for (final player in players) {
      for (final pawn in player.pawns) {
        pawn.stepsFromStart = -1;
      }
    }
  }

  void aiPlay() {
    if (winner != null || currentPlayer.isHuman) return;

    final moves = getValidMoves();
    if (moves.isEmpty) {
      lastMove = null;
      skipTurnIfNoMoves();
      return;
    }

    moves.sort((a, b) {
      int score(LudoMove m) {
        var s = 0;
        if (m.toSteps >= 56) s += 100;
        if (m.toSteps >= 51) s += 50;
        if (m.fromSteps < 0) s += 10;
        s += m.toSteps;
        return s;
      }

      return score(b).compareTo(score(a));
    });

    lastMove = moves.first;
    applyMove(moves.first.pawn); 
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (it.moveNext()) return it.current;
    return null;
  }
}
