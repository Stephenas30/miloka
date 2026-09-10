import 'dart:math';

enum FanoronaPlayer { human, ai }

enum FanoronaMoveType { paika, approach, withdrawal }

class FanoronaMove {
  final int from;
  final int dir;
  final FanoronaMoveType type;

  const FanoronaMove(this.from, this.dir, this.type);

  @override
  String toString() => 'FanoronaMove(from:$from dir:$dir type:$type)';
}

class FanoronaCaptureInfo {
  final int to;
  final int dir;
  final FanoronaMoveType type;
  final List<int> captured;

  const FanoronaCaptureInfo({
    required this.to,
    required this.dir,
    required this.type,
    required this.captured,
  });
}

/// Pure Fanorona game logic.
///
/// Board: 5 rows x 9 cols = 45 points. Row 0 = top, row 4 = bottom.
/// Cell values: 0 empty, 1 = human piece (orange, bottom, plays first),
/// 2 = ai piece (grey, top).
///
/// Direction indices:
/// 0=N, 1=NE, 2=E, 3=SE, 4=S, 5=SW, 6=W, 7=NW
class FanoronaEngine {
  static const int rows = 5;
  static const int cols = 9;
  static const int size = rows * cols;
  static const int empty = 0;
  static const int humanPiece = 1;
  static const int aiPiece = 2;
  static const int paikaDrawLimit = 50;

  static const List<List<int>> _dirs = [
    [0, -1], // 0 N
    [1, -1], // 1 NE
    [1, 0], //  2 E
    [1, 1], //  3 SE
    [0, 1], //  4 S
    [-1, 1], // 5 SW
    [-1, 0], // 6 W
    [-1, -1], //7 NW
  ];

  late List<int> board;
  int turn = 0; // 0 = human, 1 = ai
  FanoronaCaptureInfo? lastCapture;
  late List<bool> visited;
  int consecutivePaika = 0;
  int halfMoves = 0;
  int? winner; // 0 or 1, null if none
  String? drawReason; // 'paika' or 'repetition'
  List<int> lastCapturedIndices = [];
  final Map<String, int> _positionCounts = {};
  final Random _random = Random();

  FanoronaEngine({List<int>? initialBoard}) {
    if (initialBoard != null) {
      board = List.of(initialBoard);
      visited = List.filled(size, false);
    } else {
      reset();
    }
  }

  FanoronaEngine._internal()
    : board = List.filled(size, empty),
      visited = List.filled(size, false);

  static int rowOf(int pos) => pos ~/ cols;
  static int colOf(int pos) => pos % cols;
  static bool isStrongPoint(int pos) => ((rowOf(pos) + colOf(pos)) % 2) == 0;
  static int oppositeDir(int dir) => (dir + 4) % 8;

  /// Direction de `from` vers `to` (adjacents), ou -1.
  static int directionBetween(int from, int to) {
    final dc = colOf(to) - colOf(from);
    final dr = rowOf(to) - rowOf(from);
    for (var d = 0; d < 8; d++) {
      if (_dirs[d][0] == dc && _dirs[d][1] == dr) return d;
    }
    return -1;
  }

  bool get inCaptureSequence => lastCapture != null;
  bool get isGameOver => winner != null || drawReason != null;
  int get movingPiecePos => lastCapture?.to ?? -1;
  int get activePiece => turn == 0 ? humanPiece : aiPiece;
  int get opponentPiece => turn == 0 ? aiPiece : humanPiece;

  void reset() {
    board = List.generate(size, (pos) {
      final r = rowOf(pos);
      final c = colOf(pos);
      if (r <= 1) return aiPiece; // rows 0,1: ai (grey) top
      if (r >= 3) return humanPiece; // rows 3,4: human (orange) bottom
      if (c == 4) return empty; // center
      return c.isEven ? humanPiece : aiPiece;
    });
    turn = 0;
    lastCapture = null;
    visited = List.filled(size, false);
    consecutivePaika = 0;
    halfMoves = 0;
    winner = null;
    drawReason = null;
    lastCapturedIndices = [];
    _positionCounts.clear();
    _recordPosition();
  }

  int _neighbor(int pos, int dir) {
    if (pos < 0 || pos >= size) return -1;
    final r = rowOf(pos) + _dirs[dir][1];
    final c = colOf(pos) + _dirs[dir][0];
    if (r < 0 || r >= rows || c < 0 || c >= cols) return -1;
    return r * cols + c;
  }

  bool _dirValidFrom(int pos, int dir) {
    if (dir == 0 || dir == 2 || dir == 4 || dir == 6) return true;
    if (!isStrongPoint(pos)) return false;
    final n = _neighbor(pos, dir);
    return n != -1;
  }

  List<FanoronaMove> legalMoves() {
    if (isGameOver) return const [];
    if (inCaptureSequence) return _continuationCaptures();

    final captures = <FanoronaMove>[];
    for (var pos = 0; pos < size; pos++) {
      if (board[pos] != activePiece) continue;
      for (var d = 0; d < 8; d++) {
        for (final type in const [
          FanoronaMoveType.approach,
          FanoronaMoveType.withdrawal,
        ]) {
          if (_isCapture(pos, d, type)) {
            captures.add(FanoronaMove(pos, d, type));
          }
        }
      }
    }
    if (captures.isNotEmpty) return captures; // forced captures

    final paikas = <FanoronaMove>[];
    for (var pos = 0; pos < size; pos++) {
      if (board[pos] != activePiece) continue;
      for (var d = 0; d < 8; d++) {
        if (_isPaika(pos, d)) {
          paikas.add(FanoronaMove(pos, d, FanoronaMoveType.paika));
        }
      }
    }
    return paikas;
  }

  List<FanoronaMove> _continuationCaptures() {
    final lc = lastCapture!;
    final moves = <FanoronaMove>[];
    for (var d = 0; d < 8; d++) {
      if (d == lc.dir) continue; // no same direction twice in a row
      for (final type in const [
        FanoronaMoveType.approach,
        FanoronaMoveType.withdrawal,
      ]) {
        if (_isCapture(lc.to, d, type)) {
          moves.add(FanoronaMove(lc.to, d, type));
        }
      }
    }
    return moves;
  }

  bool _isCapture(int from, int dir, FanoronaMoveType type) {
    if (!_dirValidFrom(from, dir)) return false;
    final to = _neighbor(from, dir);
    if (to == -1 || board[to] != empty) return false;
    if (visited[to]) return false;
    final capStart = type == FanoronaMoveType.approach
        ? _neighbor(to, dir)
        : _neighbor(from, oppositeDir(dir));
    return capStart != -1 && board[capStart] == opponentPiece;
  }

  bool _isPaika(int from, int dir) {
    if (!_dirValidFrom(from, dir)) return false;
    final to = _neighbor(from, dir);
    return to != -1 && board[to] == empty && !visited[to];
  }

  bool canCaptureFrom(int pos) {
    for (var d = 0; d < 8; d++) {
      for (final type in const [
        FanoronaMoveType.approach,
        FanoronaMoveType.withdrawal,
      ]) {
        if (_isCapture(pos, d, type)) return true;
      }
    }
    return false;
  }

  /// Targets (destination index) and the capture types available for a piece.
  Map<int, Set<FanoronaMoveType>> targetsForPiece(int from) {
    final result = <int, Set<FanoronaMoveType>>{};
    for (final m in legalMoves()) {
      if (m.from != from) continue;
      final to = _neighbor(from, m.dir);
      result.putIfAbsent(to, () => {}).add(m.type);
    }
    return result;
  }

  /// Apply a move. Returns the captured indices (empty for paika).
  List<int> applyMove(FanoronaMove move) {
    lastCapturedIndices = [];
    final from = move.from;
    final dir = move.dir;
    final to = _neighbor(from, dir);

    if (move.type == FanoronaMoveType.paika) {
      _movePiece(from, to);
      consecutivePaika++;
      if (consecutivePaika >= paikaDrawLimit) {
        drawReason = 'paika';
        winner = null;
      }
      endTurn();
      return lastCapturedIndices;
    }

    // capture move
    final piece = board[from];
    board[from] = empty;
    board[to] = piece;

    final capDir = move.type == FanoronaMoveType.approach ? dir : oppositeDir(dir);
    var capPos = move.type == FanoronaMoveType.approach
        ? _neighbor(to, dir)
        : _neighbor(from, oppositeDir(dir));

    final captured = <int>[];
    while (capPos != -1 && board[capPos] == opponentPiece) {
      captured.add(capPos);
      board[capPos] = empty;
      capPos = _neighbor(capPos, capDir);
    }

    lastCapturedIndices = captured;
    consecutivePaika = 0;
    lastCapture = FanoronaCaptureInfo(
      to: to,
      dir: dir,
      type: move.type,
      captured: captured,
    );
    visited[from] = true;
    visited[to] = true;
    return captured;
  }

  void _movePiece(int from, int to) {
    board[to] = board[from];
    board[from] = empty;
  }

  /// End the current turn after a capture sequence (or paika).
  void endTurn() {
    turn = 1 - turn;
    lastCapture = null;
    visited = List.filled(size, false);
    halfMoves++;
    if (winner != null || drawReason != null) return;
    _recordPosition();
    _checkWinConditions();
  }

  void _recordPosition() {
    final key = '${board.join(',')}|$turn';
    _positionCounts[key] = (_positionCounts[key] ?? 0) + 1;
  }

  void _checkWinConditions() {
    if (drawReason != null || isGameOver) return;
    final legal = legalMoves();
    if (legal.isEmpty) {
      winner = 1 - turn; // current player cannot move -> other wins
      return;
    }
    if (_countPieces(activePiece) == 0) {
      winner = 1 - turn;
      return;
    }
    if (_countPieces(opponentPiece) == 0) {
      winner = turn;
      return;
    }
  }

  int _countPieces(int piece) => board.where((p) => p == piece).length;

  int countPieces(FanoronaPlayer p) =>
      _countPieces(p == FanoronaPlayer.human ? humanPiece : aiPiece);

  // ---------------- Snapshot (online sync) ----------------

  Map<String, dynamic> snapshot() => {
    'board': board,
    'turn': turn,
    'lastCapture': lastCapture == null
        ? null
        : {
            'to': lastCapture!.to,
            'dir': lastCapture!.dir,
            'type': lastCapture!.type.index,
            'captured': lastCapture!.captured,
          },
    'visited': visited.map((v) => v ? 1 : 0).toList(),
    'consecutivePaika': consecutivePaika,
    'halfMoves': halfMoves,
    'winner': winner,
    'drawReason': drawReason,
    'posCounts': _positionCounts,
  };

  /// Les nombres peuvent arriver en String ("1", "1.0") après le passage
  /// par Supabase Realtime ; on parse de façon tolérante.
  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
      return double.tryParse(trimmed)?.toInt();
    }
    return null;
  }

  void applySnapshot(Map<String, dynamic> json) {
    board = (json['board'] as List<dynamic>? ?? [])
        .map((e) => _asInt(e) ?? empty)
        .toList();
    while (board.length < size) {
      board.add(empty);
    }
    turn = _asInt(json['turn']) ?? 0;
    final lc = json['lastCapture'];
    lastCapture = lc is Map
        ? FanoronaCaptureInfo(
            to: _asInt(lc['to']) ?? 0,
            dir: _asInt(lc['dir']) ?? 0,
            type: FanoronaMoveType.values[(_asInt(lc['type']) ?? 0).clamp(
              0,
              FanoronaMoveType.values.length - 1,
            )],
            captured: (lc['captured'] as List<dynamic>? ?? [])
                .map((e) => _asInt(e) ?? empty)
                .toList(),
          )
        : null;
    visited = (json['visited'] as List<dynamic>? ?? [])
        .map((e) => (_asInt(e) ?? 0) == 1)
        .toList();
    while (visited.length < size) {
      visited.add(false);
    }
    consecutivePaika = _asInt(json['consecutivePaika']) ?? 0;
    halfMoves = _asInt(json['halfMoves']) ?? 0;
    winner = _asInt(json['winner']);
    drawReason = json['drawReason']?.toString();
    _positionCounts.clear();
    final counts = json['posCounts'];
    if (counts is Map) {
      counts.forEach((k, v) {
        _positionCounts[k.toString()] = _asInt(v) ?? 0;
      });
    }
  }

  // ---------------- AI ----------------

  FanoronaEngine cloneForSearch() {
    final e = FanoronaEngine._internal();
    e.board = List.of(board);
    e.turn = turn;
    e.lastCapture = lastCapture == null
        ? null
        : FanoronaCaptureInfo(
            to: lastCapture!.to,
            dir: lastCapture!.dir,
            type: lastCapture!.type,
            captured: List.of(lastCapture!.captured),
          );
    e.visited = List.of(visited);
    e.consecutivePaika = consecutivePaika;
    e.halfMoves = halfMoves;
    e.winner = winner;
    e.drawReason = drawReason;
    e.lastCapturedIndices = List.of(lastCapturedIndices);
    return e;
  }

  static const int _aiMaxSearchDepth = 14;

  int _maxCapturesFrom(FanoronaEngine e, int depth, Map<String, int> memo) {
    if (depth <= 0) return 0;
    final moves = e.legalMoves();
    if (moves.isEmpty) return 0;
    final key =
        '${e.board}|${e.movingPiecePos},${e.lastCapture?.dir ?? -1}|${e.visited}';
    final cached = memo[key];
    if (cached != null) return cached;
    int best = 0;
    for (final m in moves) {
      final copy = e.cloneForSearch();
      final captured = copy.applyMove(m);
      final total = captured.length + _maxCapturesFrom(copy, depth - 1, memo);
      if (total > best) best = total;
    }
    memo[key] = best;
    return best;
  }

  /// Pick the AI's next move (fresh turn or continuation). Null if none.
  FanoronaMove? aiChooseNextMove() {
    if (isGameOver) return null;
    final moves = legalMoves();
    if (moves.isEmpty) return null;

    if (inCaptureSequence || moves.first.type != FanoronaMoveType.paika) {
      var best = -1;
      final candidates = <FanoronaMove>[];
      final memo = <String, int>{};
      for (final m in moves) {
        final copy = cloneForSearch();
        final captured = copy.applyMove(m);
        final total = captured.length + _maxCapturesFrom(copy, _aiMaxSearchDepth, memo);
        if (total > best) {
          best = total;
          candidates
            ..clear()
            ..add(m);
        } else if (total == best) {
          candidates.add(m);
        }
      }
      if (candidates.isEmpty) return null;
      return candidates[_random.nextInt(candidates.length)];
    }

    // Paika phase: heuristic evaluation
    FanoronaMove? bestMove;
    var bestScore = double.negativeInfinity;
    for (final m in moves) {
      final score = _evaluatePaika(m);
      if (score > bestScore) {
        bestScore = score;
        bestMove = m;
      }
    }
    return bestMove;
  }

  double _evaluatePaika(FanoronaMove m) {
    final to = _neighbor(m.from, m.dir);
    var score = 0.0;
    if (isStrongPoint(to)) score += 3;
    final centerDist = (colOf(to) - 4).abs() + (rowOf(to) - 2).abs();
    score += (4 - centerDist) * 0.5;
    score += _enemyAdjacencyCount(to) * 2.0;
    if (_isVulnerable(board, to, opponentPiece)) score -= 8;
    if (_isVulnerable(board, m.from, opponentPiece)) score += 4;
    return score;
  }

  int _enemyAdjacencyCount(int pos) {
    var count = 0;
    for (var d = 0; d < 8; d++) {
      final n = _neighbor(pos, d);
      if (n != -1 && board[n] == opponentPiece) count++;
    }
    return count;
  }

  bool _isVulnerable(List<int> b, int pos, int opp) {
    for (var d = 0; d < 8; d++) {
      // withdrawal: opponent at pos+d moves away to pos+2d (empty)
      final p1 = _neighbor(pos, d);
      var p2 = -1;
      if (p1 != -1) p2 = _neighbor(p1, d);
      if (p1 != -1 && b[p1] == opp && p2 != -1 && b[p2] == empty) return true;
      // approach: opponent at pos-2d, pos-d empty, moves toward pos
      final a1 = _neighbor(pos, oppositeDir(d));
      var a2 = -1;
      if (a1 != -1) a2 = _neighbor(a1, oppositeDir(d));
      if (a2 != -1 && b[a2] == opp && a1 != -1 && b[a1] == empty) return true;
    }
    return false;
  }
}