import 'dart:math';

class LudoGameSnapshot {
  final bool isMultiplayer;
  final String roomCode;
  final int currentPlayerIndex;
  final LudoColor currentPlayerColor;
  final int lastDice;
  final bool diceRolled;
  final bool extraTurn;
  final LudoColor? winner;
  final String message;
  final List<List<int>> pawnSteps;
  final bool waitingForRemote;

  const LudoGameSnapshot({
    required this.isMultiplayer,
    required this.roomCode,
    required this.currentPlayerIndex,
    required this.currentPlayerColor,
    required this.lastDice,
    required this.diceRolled,
    required this.extraTurn,
    required this.winner,
    required this.message,
    required this.pawnSteps,
    required this.waitingForRemote,
  });

  factory LudoGameSnapshot.fromJson(Map<String, dynamic> json) {
    return LudoGameSnapshot(
      isMultiplayer: json['isMultiplayer'] as bool? ?? false,
      roomCode: json['roomCode']?.toString() ?? '',
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      currentPlayerColor:
          LudoColor.values[json['currentPlayerColorIndex'] as int? ?? 0],
      lastDice: json['lastDice'] as int? ?? 0,
      diceRolled: json['diceRolled'] as bool? ?? false,
      extraTurn: json['extraTurn'] as bool? ?? false,
      winner: json['winnerIndex'] == null
          ? null
          : LudoColor.values[json['winnerIndex'] as int],
      message: json['message']?.toString() ?? '',
      pawnSteps: (json['pawnSteps'] as List<dynamic>? ?? [])
          .map<List<int>>(
            (row) => (row as List<dynamic>)
                .map<int>((value) => value as int)
                .toList(),
          )
          .toList(),
      waitingForRemote: json['waitingForRemote'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'isMultiplayer': isMultiplayer,
      'roomCode': roomCode,
      'currentPlayerIndex': currentPlayerIndex,
      'currentPlayerColorIndex': currentPlayerColor.index,
      'lastDice': lastDice,
      'diceRolled': diceRolled,
      'extraTurn': extraTurn,
      'winnerIndex': winner?.index,
      'message': message,
      'pawnSteps': pawnSteps,
      'waitingForRemote': waitingForRemote,
    };
  }
}

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

  LudoPawn copy() =>
      LudoPawn(id: id, color: color)..stepsFromStart = stepsFromStart;
}

class LudoPlayer {
  final LudoColor color;
  final List<LudoPawn> pawns;
  final bool isHuman;
  final String? namePlayer;
  final String? id;

  LudoPlayer({required this.color, required this.isHuman, this.namePlayer, this.id})
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

class LudoHuman {
  final String? id;
  final String name;
  final LudoColor color;
  final String? avatar;

  const LudoHuman({
    required this.name,
    required this.color,
    this.id,
    this.avatar
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

  final List<LudoHuman> human;
  final Random _random = Random();
  final bool isMultiplayer;
  final void Function(LudoGameSnapshot snapshot)? onStateChange;
  bool waitingForRemote = false;
  final String roomCode;

  List<LudoColor> get humanColor => human.map((player) => player.color).toList();

  String? playerNameForColor(LudoColor color) =>
      human.firstWhereOrNull((player) => player.color == color)?.name;

  LudoEngine({
    required this.human,
    bool? isMultiplayer,
    String? roomCode,
    this.onStateChange,
  }) : isMultiplayer = isMultiplayer ?? false,
       roomCode =
           roomCode ?? (isMultiplayer ?? false ? _generateRoomCode() : ''),
       players = [
         LudoPlayer(
           color: LudoColor.red,
           isHuman: human.any((elt) => elt.color == LudoColor.red),
           namePlayer: human.firstWhereOrNull((elt) => elt.color == LudoColor.red)?.name,
           id: human.firstWhereOrNull((elt) => elt.color == LudoColor.red)?.id
         ),
         LudoPlayer(
           color: LudoColor.green,
           isHuman: human.any((elt) => elt.color == LudoColor.green),
           namePlayer: human.firstWhereOrNull((elt) => elt.color == LudoColor.green)?.name,
           id: human.firstWhereOrNull((elt) => elt.color == LudoColor.green)?.id
         ),
         LudoPlayer(
           color: LudoColor.yellow,
           isHuman: human.any((elt) => elt.color == LudoColor.yellow),
           namePlayer: human.firstWhereOrNull((elt) => elt.color == LudoColor.yellow)?.name,
           id: human.firstWhereOrNull((elt) => elt.color == LudoColor.yellow)?.id
         ),
         LudoPlayer(
           color: LudoColor.blue,
           isHuman: human.any((elt) => elt.color == LudoColor.blue),
           namePlayer: human.firstWhereOrNull((elt) => elt.color == LudoColor.blue)?.name,
           id: human.firstWhereOrNull((elt) => elt.color == LudoColor.blue)?.id
         ),
       ];

  static String _generateRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(5, (_) => chars[random.nextInt(chars.length)]).join();
  }

  LudoPlayer get currentPlayer => players[currentPlayerIndex];

  int rollDice() {
    if (diceRolled || winner != null) return lastDice;
    //if (isMultiplayer && waitingForRemote) return lastDice;
    //if (isMultiplayer && !humanColor.contains(currentPlayer.color)) return lastDice;
    lastDice = _random.nextInt(6) + 1;
    diceRolled = true;
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
    if (isMultiplayer) {
      onStateChange?.call(snapshot());
      waitingForRemote = true;
    }
    return lastDice;
  }

  List<LudoMove> getValidMoves() {
    if (!diceRolled || winner != null) return [];
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
    return getValidMoves().any(
      (m) => m.pawn.id == pawn.id && m.pawn.color == pawn.color,
    );
  }

  bool applyMove(LudoPawn pawn) {
    if (winner != null /* || !diceRolled */ ) return false;

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
    diceRolled = false;

    extraTurn = false;
    if (rolledSix || captured || finishedPawn) {
      extraTurn = true;
      message = finishedPawn
          ? 'Pion arrivé au centre ! ${currentPlayer.color.label} rejoue'
          : captured
          ? 'Capture ! ${currentPlayer.color.label} rejoue'
          : '6 obtenu ! ${currentPlayer.color.label} rejoue';
    }
    if (isMultiplayer) {
      onStateChange?.call(snapshot());
      waitingForRemote = true;
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
    if (isMultiplayer) {
      onStateChange?.call(snapshot());
      waitingForRemote = true;
    }
  }

  void skipTurnIfNoMoves() {
    extraTurn = false;
    diceRolled = false;
  }

  void _nextPlayer() {
    diceRolled = false;
    extraTurn = false;
    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;
    message = 'Tour de ${currentPlayer.color.label}';
  }

  void advancePastDisconnected(Set<LudoColor> disconnected) {
    while (disconnected.contains(currentPlayer.color)) {
      _nextPlayer();
    }
  }

  void reset() {
    currentPlayerIndex = 0;
    lastDice = 0;
    diceRolled = false;
    extraTurn = false;
    winner = null;
    message = 'Lance le dé pour commencer';
    for (final player in players) {
      for (final pawn in player.pawns) {
        pawn.stepsFromStart = -1;
      }
    }
  }

  LudoGameSnapshot snapshot() {
    return LudoGameSnapshot(
      isMultiplayer: isMultiplayer,
      roomCode: roomCode,
      currentPlayerIndex: currentPlayerIndex,
      currentPlayerColor: currentPlayer.color,
      lastDice: lastDice,
      diceRolled: diceRolled,
      extraTurn: extraTurn,
      waitingForRemote: waitingForRemote,
      winner: winner,
      message: message,
      pawnSteps: players
          .map(
            (player) =>
                player.pawns.map((pawn) => pawn.stepsFromStart).toList(),
          )
          .toList(),
    );
  }

  void applySnapshot(LudoGameSnapshot snapshot) {
    // applying remote snapshot — stop waiting for remote
    waitingForRemote = false;
    currentPlayerIndex = snapshot.currentPlayerIndex;
    lastDice = snapshot.lastDice;
    diceRolled = snapshot.diceRolled;
    extraTurn = snapshot.extraTurn;
    winner = snapshot.winner;
    message = snapshot.message;

    for (var playerIndex = 0; playerIndex < players.length; playerIndex++) {
      final player = players[playerIndex];
      final steps = snapshot.pawnSteps[playerIndex];
      for (var pawnIndex = 0; pawnIndex < player.pawns.length; pawnIndex++) {
        player.pawns[pawnIndex].stepsFromStart = steps[pawnIndex];
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

extension _FirstWhereOrNull<E> on Iterable<E> {
  E? firstWhereOrNull(bool Function(E element) test) {
    for (final element in this) {
      if (test(element)) return element;
    }
    return null;
  }
}
