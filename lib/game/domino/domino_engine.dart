import 'dart:math';

enum DominoSide { left, right }

class DominoHuman {
  final String? id;
  final String name;

  const DominoHuman({this.id, required this.name});
}

class DominoTile {
  final int left;
  final int right;

  const DominoTile(this.left, this.right);

  static const int minPip = 0;
  static const int maxPip = 6;

  bool get isDouble => left == right;
  int get total => left + right;

  DominoTile flip() => DominoTile(right, left);

  @override
  bool operator ==(Object other) {
    if (other is! DominoTile) return false;
    return (left == other.left && right == other.right) ||
        (left == other.right && right == other.left);
  }

  @override
  int get hashCode => left < right ? left * 10 + right : right * 10 + left;

  Map<String, int> toJson() => {'left': left, 'right': right};

  static DominoTile fromJson(Map<String, dynamic> json) =>
      DominoTile(json['left'] as int, json['right'] as int);
}

class DominoPlayer {
  final String id;
  final String name;
  final bool isHuman;
  final List<DominoTile> hand;

  DominoPlayer({
    required this.id,
    required this.name,
    required this.isHuman,
    List<DominoTile>? hand,
  }) : hand = hand ?? [];

  int get tileCount => hand.length;
  int get handValue => hand.fold(0, (sum, t) => sum + t.total);
  bool get isOut => hand.isEmpty;

  void takeTile(DominoTile tile) => hand.add(tile);
  void removeTile(DominoTile tile) => hand.remove(tile);
}

class DominoSnapshot {
  final bool isMultiplayer;
  final String roomCode;
  final String variant;
  final int currentPlayerIndex;
  final List<String> playerIds;
  final List<String> playerNames;
  final List<List<int>> hands;
  final List<List<int>> boneyard;
  final List<List<int>> played;
  final List<int>? lastPlayed;
  final int? openLeft;
  final int? openRight;
  final int? winnerIndex;
  final bool blocked;
  final String message;
  final bool waitingForRemote;

  const DominoSnapshot({
    required this.isMultiplayer,
    required this.roomCode,
    this.variant = 'draw',
    required this.currentPlayerIndex,
    required this.playerIds,
    required this.playerNames,
    required this.hands,
    required this.boneyard,
    required this.played,
    required this.lastPlayed,
    required this.openLeft,
    required this.openRight,
    required this.winnerIndex,
    required this.blocked,
    required this.message,
    required this.waitingForRemote,
  });

  factory DominoSnapshot.fromJson(Map<String, dynamic> json) {
    List<List<int>> parsePairs(dynamic raw) => (raw as List<dynamic>? ?? [])
        .map<List<int>>(
          (row) => (row as List<dynamic>).whereType<int>().toList(),
        )
        .toList();

    return DominoSnapshot(
      isMultiplayer: json['isMultiplayer'] as bool? ?? false,
      roomCode: json['roomCode']?.toString() ?? '',
      variant: json['variant']?.toString() ?? 'draw',
      currentPlayerIndex: json['currentPlayerIndex'] as int? ?? 0,
      playerIds: (json['playerIds'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      playerNames: (json['playerNames'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      hands: (json['hands'] as List<dynamic>? ?? const [])
          .map((e) => (e as List<dynamic>).whereType<int>().toList())
          .toList(),
      boneyard: parsePairs(json['boneyard']),
      played: parsePairs(json['played']),
      lastPlayed: (json['lastPlayed'] as List<dynamic>?)
          ?.whereType<int>()
          .toList(),
      openLeft: json['openLeft'] as int?,
      openRight: json['openRight'] as int?,
      winnerIndex: json['winnerIndex'] as int?,
      blocked: json['blocked'] as bool? ?? false,
      message: json['message']?.toString() ?? '',
      waitingForRemote: json['waitingForRemote'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'isMultiplayer': isMultiplayer,
        'roomCode': roomCode,
        'variant': variant,
        'currentPlayerIndex': currentPlayerIndex,
        'playerIds': playerIds,
        'playerNames': playerNames,
        'hands': hands,
        'boneyard': boneyard,
        'played': played,
        'lastPlayed': lastPlayed,
        'openLeft': openLeft,
        'openRight': openRight,
        'winnerIndex': winnerIndex,
        'blocked': blocked,
        'message': message,
        'waitingForRemote': waitingForRemote,
      };
}

class DominoEngine {
  static const int tilesPerPlayer = 7;
  static const int maxPip = 6;

  /// Variante de jeu : 'draw' par défaut, 'block' pour le Block Game.
  String get variant => 'draw';

  final List<DominoHuman> human;
  final List<DominoPlayer> players;
  final List<DominoTile> boneyard = <DominoTile>[];
  final List<DominoTile> played = <DominoTile>[];

  int currentPlayerIndex = 0;
  int? openLeft;
  int? openRight;
  DominoTile? lastPlayed;
  int? winnerIndex;
  bool blocked = false;
  String message = 'Lancement de la partie...';
  bool waitingForRemote = false;

  final bool isMultiplayer;
  final String roomCode;
  final void Function(DominoSnapshot snapshot)? onStateChange;
  final Random _random;
  bool _dealt = false;

  DominoEngine({
    required this.human,
    bool? isMultiplayer,
    String? roomCode,
    this.onStateChange,
    Random? random,
  })  : isMultiplayer = isMultiplayer ?? false,
        roomCode =
            roomCode ?? (isMultiplayer ?? false ? _generateRoomCode() : ''),
        players = [
          for (var i = 0; i < human.length; i++)
            DominoPlayer(
              id: human[i].id ?? human[i].name,
              name: human[i].name,
              isHuman: !(human[i].id?.startsWith('ai_') ?? false),
            ),
        ],
        _random = random ?? Random();

  static String randomRoomCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    return List.generate(5, (_) => chars[random.nextInt(chars.length)]).join();
  }

  static String _generateRoomCode() => randomRoomCode();

  static List<DominoTile> fullTileSet() {
    final tiles = <DominoTile>[];
    for (var left = 0; left <= maxPip; left++) {
      for (var right = left; right <= maxPip; right++) {
        tiles.add(DominoTile(left, right));
      }
    }
    return tiles;
  }

  DominoPlayer get currentPlayer => players[currentPlayerIndex];

  bool get boardEmpty => openLeft == null || openRight == null;
  bool get gameOver => winnerIndex != null || blocked;
  int get boneyardCount => boneyard.length;

  void start() {
    if (_dealt) return;
    _dealt = true;
    deal();
  }

  void deal() {
    for (final p in players) {
      p.hand.clear();
    }
    boneyard.clear();
    played.clear();
    openLeft = null;
    openRight = null;
    lastPlayed = null;
    winnerIndex = null;
    blocked = false;
    currentPlayerIndex = 0;

    final tiles = fullTileSet()..shuffle(_random);
    var position = 0;
    for (final p in players) {
      for (var i = 0; i < tilesPerPlayer; i++) {
        p.takeTile(tiles[position++]);
      }
    }
    boneyard.addAll(tiles.sublist(position));

    _openWithBestStarter();
  }

  void _openWithBestStarter() {
    if (players.isEmpty) return;

    // Le détenteur du plus gros double commence ; sinon la tuile la plus forte.
    var starterIndex = 0;
    DominoTile? best;
    var bestTotal = -1;

    for (var i = 0; i < players.length; i++) {
      final doubles = players[i].hand.where((t) => t.isDouble);
      if (doubles.isEmpty) continue;
      final candidate = _maxBy(doubles, (t) => t.total)!;
      if (best == null || candidate.total > bestTotal) {
        best = candidate;
        bestTotal = candidate.total;
        starterIndex = i;
      }
    }

    if (best == null) {
      for (var i = 0; i < players.length; i++) {
        if (players[i].hand.isEmpty) continue;
        final candidate = _maxBy(players[i].hand, (t) => t.total)!;
        if (best == null || candidate.total > bestTotal) {
          best = candidate;
          bestTotal = candidate.total;
          starterIndex = i;
        }
      }
    }

    if (best == null) {
      message = 'Aucune tuile pour démarrer';
      return;
    }

    final starter = players[starterIndex];
    starter.removeTile(best);
    played.add(best);
    openLeft = best.left;
    openRight = best.right;
    lastPlayed = best;
    currentPlayerIndex = (starterIndex + 1) % players.length;
    message = '${starter.name} ouvre la partie';
  }

  bool canPlayTile(DominoTile tile) {
    if (boardEmpty) return true;
    return tile.left == openLeft ||
        tile.right == openLeft ||
        tile.left == openRight ||
        tile.right == openRight;
  }

  List<DominoTile> playableTilesFor(DominoPlayer player) {
    if (boardEmpty) return List.of(player.hand);
    return player.hand.where(canPlayTile).toList(growable: false);
  }

  List<DominoTile> get currentPlayableTiles =>
      playableTilesFor(currentPlayer);

  bool get canDraw => boneyard.isNotEmpty;
  bool get canPass => currentPlayableTiles.isEmpty && !canDraw;

  List<DominoSide> validSidesFor(DominoTile tile) {
    if (boardEmpty) return const [DominoSide.left];
    final sides = <DominoSide>[];
    if (tile.left == openLeft || tile.right == openLeft) {
      sides.add(DominoSide.left);
    }
    if (tile.left == openRight || tile.right == openRight) {
      sides.add(DominoSide.right);
    }
    return sides;
  }

  bool playTile(DominoTile tile, DominoSide side) {
    if (gameOver) return false;
    if (!currentPlayer.hand.contains(tile)) return false;

    if (boardEmpty) {
      currentPlayer.removeTile(tile);
      played.add(tile);
      openLeft = tile.left;
      openRight = tile.right;
      lastPlayed = tile;
      _endTurn();
      return true;
    }

    if (!validSidesFor(tile).contains(side)) {
      return false;
    }

    DominoTile oriented;
    if (side == DominoSide.left) {
      oriented = tile.right == openLeft ? tile : tile.flip();
      openLeft = oriented.left;
    } else {
      oriented = tile.left == openRight ? tile : tile.flip();
      openRight = oriented.right;
    }

    currentPlayer.removeTile(tile);
    played.add(oriented);
    lastPlayed = oriented;
    _endTurn();
    return true;
  }

  DominoTile? drawFromBoneyard() {
    if (boneyard.isEmpty) return null;
    final tile = boneyard.removeLast();
    currentPlayer.takeTile(tile);
    message = '${currentPlayer.name} pioche';
    _broadcast();
    return tile;
  }

  bool passTurn() {
    if (!canPass || gameOver) return false;
    message = '${currentPlayer.name} passe';
    _endTurn();
    return true;
  }

  void _endTurn() {
    if (currentPlayer.isOut) {
      winnerIndex = currentPlayerIndex;
      message = '${currentPlayer.name} a gagné !';
      _broadcast();
      return;
    }

    currentPlayerIndex = (currentPlayerIndex + 1) % players.length;

    if (computeBlocked()) {
      _declareBlocked();
    } else {
      message = 'Tour de ${currentPlayer.name}';
    }

    _broadcast();
  }

  /// Détecte si la partie est bloquée.
  ///
  /// En mode Draw, on ne bloque que lorsque le bac est vide et que personne
  /// ne peut plus jouer. Les variantes (ex. Block Game) peuvent surcharger
  /// cette méthode pour changer la règle de blocage.
  bool computeBlocked() {
    if (boneyard.isNotEmpty) return false;
    for (final p in players) {
      if (playableTilesFor(p).isNotEmpty) return false;
    }
    return true;
  }

  void _declareBlocked() {
    blocked = true;
    var bestIndex = 0;
    var bestValue = players[0].handValue;
    for (var i = 1; i < players.length; i++) {
      final v = players[i].handValue;
      if (v < bestValue) {
        bestValue = v;
        bestIndex = i;
      }
    }
    winnerIndex = bestIndex;
    message =
        'Partie bloquée — ${players[bestIndex].name} gagne (moins de points)';
  }

  void _broadcast() {
    if (isMultiplayer) {
      waitingForRemote = true;
      onStateChange?.call(snapshot());
    }
  }

  void aiTurn() {
    if (gameOver || currentPlayer.isHuman) return;

    while (currentPlayableTiles.isEmpty && boneyard.isNotEmpty) {
      drawFromBoneyard();
    }

    final playable = currentPlayableTiles;
    if (playable.isEmpty) {
      if (canPass) passTurn();
      return;
    }

    final move = chooseAiMove(playable);
    playTile(move.$1, move.$2);
  }

  (DominoTile, DominoSide) chooseAiMove(List<DominoTile> playable) {
    if (boardEmpty) {
      return (_maxBy(playable, (t) => t.total)!, DominoSide.left);
    }

    (DominoTile, DominoSide)? best;
    var bestScore = 1 << 30;
    for (final tile in playable) {
      for (final side in validSidesFor(tile)) {
        final exposed = _exposedValue(tile, side);
        final score = exposed * 100 - tile.total;
        if (score < bestScore) {
          bestScore = score;
          best = (tile, side);
        }
      }
    }
    return best ?? (playable.first, DominoSide.left);
  }

  int _exposedValue(DominoTile tile, DominoSide side) {
    if (side == DominoSide.left) {
      // La face qui reste ouverte à gauche après la pose.
      return tile.right == openLeft ? tile.left : tile.right;
    } else {
      // La face qui reste ouverte à droite après la pose.
      return tile.left == openRight ? tile.right : tile.left;
    }
  }

  void applySnapshot(DominoSnapshot snapshot) {
    waitingForRemote = false;
    currentPlayerIndex = snapshot.currentPlayerIndex;
    openLeft = snapshot.openLeft;
    openRight = snapshot.openRight;
    winnerIndex = snapshot.winnerIndex;
    blocked = snapshot.blocked;
    message = snapshot.message;

    lastPlayed = snapshot.lastPlayed == null
        ? null
        : DominoTile(
            snapshot.lastPlayed![0],
            snapshot.lastPlayed!.length > 1 ? snapshot.lastPlayed![1] : 0,
          );

    played
      ..clear()
      ..addAll(_tilesFrom(snapshot.played));
    boneyard
      ..clear()
      ..addAll(_tilesFrom(snapshot.boneyard));

    for (var i = 0; i < players.length; i++) {
      final hand = players[i].hand;
      hand.clear();
      final raw = i < snapshot.hands.length ? snapshot.hands[i] : const [];
      for (var j = 0; j + 1 < raw.length; j += 2) {
        hand.add(DominoTile(raw[j], raw[j + 1]));
      }
    }
  }

  List<DominoTile> _tilesFrom(List<List<int>> pairs) {
    final result = <DominoTile>[];
    for (final pair in pairs) {
      if (pair.length >= 2) {
        result.add(DominoTile(pair[0], pair[1]));
      }
    }
    return result;
  }

  DominoSnapshot snapshot() {
    return DominoSnapshot(
      isMultiplayer: isMultiplayer,
      roomCode: roomCode,
      variant: variant,
      currentPlayerIndex: currentPlayerIndex,
      playerIds: players.map((p) => p.id).toList(growable: false),
      playerNames: players.map((p) => p.name).toList(growable: false),
      hands: players
          .map(
            (p) => p.hand.expand((t) => [t.left, t.right]).toList(
              growable: false,
            ),
          )
          .toList(growable: false),
      boneyard:
          boneyard.map((t) => [t.left, t.right]).toList(growable: false),
      played: played.map((t) => [t.left, t.right]).toList(growable: false),
      lastPlayed: lastPlayed == null
          ? null
          : [lastPlayed!.left, lastPlayed!.right],
      openLeft: openLeft,
      openRight: openRight,
      winnerIndex: winnerIndex,
      blocked: blocked,
      message: message,
      waitingForRemote: waitingForRemote,
    );
  }
}

T? _maxBy<T>(Iterable<T> items, int Function(T) score) {
  T? best;
  var bestScore = -1;
  for (final item in items) {
    final s = score(item);
    if (best == null || s > bestScore) {
      best = item;
      bestScore = s;
    }
  }
  return best;
}