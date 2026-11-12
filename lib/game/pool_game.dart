import 'dart:math' as math;

enum PoolMode { solo, local, online }

enum PoolGameState { aiming, moving, placingCue, gameOver, striking }

class PoolBall {
  PoolBall(this.id, this.x, this.y);

  final int id;
  double x;
  double y;
  double vx = 0;
  double vy = 0;
  final List<double> orientation = [1, 0, 0, 0, 1, 0, 0, 0, 1];
  bool pocketed = false;
}

class PoolGame {
  PoolGame({
    required this.mode,
    this.level = 1,
    this.myPlayerIndex = 0,
    this.onSend,
  }) {
    start();
  }

  static const double tableWidth = 960;
  static const double tableHeight = 480;
  static const double rail = 46;
  static const double ballRadius = 12;
  static const double pocketRadius = 25;

  static const double _friction = .9925;
  static const double _restitution = .96;
  static const double _cushionBounce = .78;
  static const double _maxPower = 24;
  static const double _rollDeceleration = .012;

  final PoolMode mode;
  final int level;
  final int myPlayerIndex;
  final void Function(String message)? onSend;

  final List<PoolBall> balls = [];
  final List<int> _groups = [0, 0];
  final List<int> _potted = [];
  PoolGameState state = PoolGameState.aiming;
  int currentPlayer = 0;
  int winner = -1;
  bool ready = true;
  double aim = 0;
  double power = 0;
  String message = '';

  double _pullBase = 20;
  bool _charging = false;
  bool _cueWasPocketed = false;
  int _firstHit = -1;
  int _leftBeforeShot = -1;
  int _shotPlayer = 0;
  int _strikeFrames = 0;
  int _strikeDuration = 6;
  double _strikePower = 0;
  double _strikeAngle = 0;
  int _aiWait = 0;
  bool _aiPlanned = false;
  double _aiAngle = 0;
  double _aiPower = .5;
  bool _lastCuePlacementValid = true;

  static const List<List<double>> _pockets = [
    [rail, rail],
    [tableWidth - rail, rail],
    [rail, tableHeight - rail],
    [tableWidth - rail, tableHeight - rail],
    [tableWidth / 2, rail - 6],
    [tableWidth / 2, tableHeight - rail + 6],
  ];
  static List<List<double>> get pocketsForDrawing => _pockets;

  PoolBall get cueBall => balls.first;
  int get currentGroup => _groups[currentPlayer];
  bool get isOnline => mode == PoolMode.online;
  bool get isGameOver => state == PoolGameState.gameOver;
  bool get canControl =>
      ready &&
      (mode == PoolMode.local ||
          (mode == PoolMode.solo && currentPlayer == 0) ||
          (isOnline && currentPlayer == myPlayerIndex));
  bool get cuePlacementValid => _lastCuePlacementValid;

  int groupOf(int id) => id >= 1 && id <= 7 ? 1 : (id >= 9 && id <= 15 ? 2 : 0);

  int remaining(int group) =>
      balls.where((ball) => !ball.pocketed && groupOf(ball.id) == group).length;

  String playerName(int player) {
    if (mode == PoolMode.solo) {
      return player == 0 ? 'Vous' : 'Ordinateur · ${_levelName()}';
    }
    if (isOnline) {
      return player == myPlayerIndex ? 'Vous' : 'Adversaire';
    }
    return 'Joueur ${player + 1}';
  }

  String groupName(int group) => group == 1 ? 'Rouges' : 'Jaunes';

  String groupLabel(int player) {
    final group = _groups[player];
    return group == 0
        ? 'Table ouverte'
        : '${groupName(group)} · ${remaining(group)} restantes';
  }

  String _levelName() => const ['Facile', 'Moyen', 'Difficile'][level.clamp(0, 2)];

  String _turnMessage() {
    if (mode == PoolMode.solo && currentPlayer == 1) {
      return 'L’ordinateur réfléchit…';
    }
    if (isOnline) {
      return currentPlayer == myPlayerIndex
          ? 'À vous de jouer'
          : 'C’est au tour de l’adversaire';
    }
    return 'Au tour de ${playerName(currentPlayer)}';
  }

  void start({int? seed}) {
    final random = math.Random(seed ?? DateTime.now().microsecondsSinceEpoch);
    balls
      ..clear()
      ..add(PoolBall(0, rail + .25 * (tableWidth - 2 * rail),
          tableHeight / 2));
    final ids = <int>[1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15]
      ..shuffle(random);
    final spacing = 2 * ballRadius + .6;
    final apexX = rail + .68 * (tableWidth - 2 * rail);
    var index = 0;
    var idIndex = 0;
    for (var row = 0; row <= 4; row++) {
      for (var column = 0; column <= row; column++) {
        final id = index == 4 ? 8 : ids[idIndex++];
        balls.add(
          PoolBall(
            id,
            apexX + row * spacing * .866,
            tableHeight / 2 + (column - row / 2) * spacing,
          ),
        );
        index++;
      }
    }
    _groups
      ..[0] = 0
      ..[1] = 0;
    currentPlayer = 0;
    winner = -1;
    state = PoolGameState.aiming;
    power = 0;
    _charging = false;
    _cueWasPocketed = false;
    _firstHit = -1;
    _leftBeforeShot = -1;
    _lastCuePlacementValid = true;
    _strikeFrames = 0;
    _potted.clear();
    _aiWait = 0;
    _aiPlanned = false;
    message = _turnMessage();
  }

  void pointerDown(double x, double y) {
    if (!canControl || isGameOver) return;
    if (state == PoolGameState.aiming) {
      _charging = true;
      power = 0;
      _pullBase = math.max(_distance(cueBall.x, cueBall.y, x, y), 20);
    } else if (state == PoolGameState.placingCue) {
      _moveCue(x, y);
    }
  }

  void pointerMove(double x, double y) {
    if (state == PoolGameState.placingCue && canControl) {
      _moveCue(x, y);
    } else if (state == PoolGameState.aiming && _charging && canControl) {
      final dx = cueBall.x - x;
      final dy = cueBall.y - y;
      final distance = math.sqrt(dx * dx + dy * dy);
      if (distance > 12) aim = math.atan2(dy, dx);
      _pullBase = math.min(_pullBase, math.max(distance, 20));
      power = ((distance - _pullBase) / 190).clamp(0, 1);
    }
  }

  void pointerUp() {
    if (!canControl) return;
    if (_charging) {
      _charging = false;
      if (power > .06) {
        if (isOnline) onSend?.call('SHOT $aim $power');
        takeShot(aim, power);
      }
      power = 0;
    } else if (state == PoolGameState.placingCue && _canPlaceCue()) {
      if (isOnline) onSend?.call('PLACE ${cueBall.x} ${cueBall.y}');
      state = PoolGameState.aiming;
      message = _turnMessage();
    }
  }

  void _moveCue(double x, double y) {
    cueBall
      ..x = x.clamp(rail + ballRadius, tableWidth - rail - ballRadius)
      ..y = y.clamp(rail + ballRadius, tableHeight - rail - ballRadius);
    _lastCuePlacementValid = _canPlaceCue();
  }

  void takeShot(double angle, double shotPower, {bool remote = false}) {
    final computerTurn = mode == PoolMode.solo && currentPlayer == 1;
    if (state != PoolGameState.aiming ||
        (!canControl && !computerTurn && !remote)) {
      return;
    }
    _shotPlayer = currentPlayer;
    _firstHit = -1;
    _potted.clear();
    _cueWasPocketed = false;
    _leftBeforeShot = _groups[currentPlayer] == 0
        ? -1
        : remaining(_groups[currentPlayer]);
    _strikePower = shotPower.clamp(0, 1);
    _strikeAngle = angle;
    _strikeFrames = 0;
    _strikeDuration = (8 - 4 * _strikePower).toInt().clamp(4, 8);
    aim = angle;
    power = _strikePower;
    state = PoolGameState.striking;
  }

  void tick() {
    if (state == PoolGameState.striking) {
      if (++_strikeFrames >= _strikeDuration) _launch();
      return;
    }
    if (state == PoolGameState.moving) {
      _physicsStep();
      if (balls.every((ball) =>
          ball.pocketed || (ball.vx == 0 && ball.vy == 0))) {
        _finishTurn();
        if (isOnline && _shotPlayer == myPlayerIndex) {
          onSend?.call(snapshot());
        }
      }
      return;
    }
    if (mode == PoolMode.solo &&
        currentPlayer == 1 &&
        (state == PoolGameState.aiming ||
            state == PoolGameState.placingCue)) {
      _tickComputer();
    }
  }

  void _launch() {
    final speed = _strikePower * _maxPower;
    cueBall
      ..vx = math.cos(_strikeAngle) * speed
      ..vy = math.sin(_strikeAngle) * speed;
    state = PoolGameState.moving;
  }

  void _physicsStep() {
    for (var substep = 0; substep < 8; substep++) {
      for (final ball in balls) {
        if (ball.pocketed) continue;
        ball
          ..x += ball.vx / 8
          ..y += ball.vy / 8;
        if (_pockets.any((pocket) =>
            _distance(ball.x, ball.y, pocket[0], pocket[1]) < pocketRadius)) {
          ball
            ..pocketed = true
            ..vx = 0
            ..vy = 0;
          if (ball.id == 0) {
            _cueWasPocketed = true;
          } else {
            _potted.add(ball.id);
          }
          continue;
        }
        if (ball.x < rail + ballRadius) {
          ball
            ..x = rail + ballRadius
            ..vx = ball.vx.abs() * _cushionBounce;
        }
        if (ball.x > tableWidth - rail - ballRadius) {
          ball
            ..x = tableWidth - rail - ballRadius
            ..vx = -ball.vx.abs() * _cushionBounce;
        }
        if (ball.y < rail + ballRadius) {
          ball
            ..y = rail + ballRadius
            ..vy = ball.vy.abs() * _cushionBounce;
        }
        if (ball.y > tableHeight - rail - ballRadius) {
          ball
            ..y = tableHeight - rail - ballRadius
            ..vy = -ball.vy.abs() * _cushionBounce;
        }
      }
      for (var i = 0; i < balls.length; i++) {
        for (var j = i + 1; j < balls.length; j++) {
          final first = balls[i];
          final second = balls[j];
          if (first.pocketed || second.pocketed) continue;
          final dx = second.x - first.x;
          final dy = second.y - first.y;
          final distance = math.sqrt(dx * dx + dy * dy);
          if (distance >= 2 * ballRadius || distance == 0) continue;
          final nx = dx / distance;
          final ny = dy / distance;
          final overlap = (2 * ballRadius - distance) / 2;
          first
            ..x -= nx * overlap
            ..y -= ny * overlap;
          second
            ..x += nx * overlap
            ..y += ny * overlap;
          final relativeVelocity =
              (first.vx - second.vx) * nx + (first.vy - second.vy) * ny;
          if (relativeVelocity > 0) {
            final impulse = relativeVelocity * (1 + _restitution) / 2;
            first
              ..vx -= impulse * nx
              ..vy -= impulse * ny;
            second
              ..vx += impulse * nx
              ..vy += impulse * ny;
            if (_firstHit == -1) {
              if (first.id == 0) _firstHit = second.id;
              if (second.id == 0) _firstHit = first.id;
            }
          }
        }
      }
    }
    for (final ball in balls) {
      if (ball.pocketed) continue;
      final speed = math.sqrt(ball.vx * ball.vx + ball.vy * ball.vy);
      if (speed == 0) continue;
      final nextSpeed = speed * _friction - _rollDeceleration;
      if (nextSpeed < .05) {
        ball
          ..vx = 0
          ..vy = 0;
      } else {
        ball
          ..vx *= nextSpeed / speed
          ..vy *= nextSpeed / speed;
        _roll(ball, ball.vx / nextSpeed, ball.vy / nextSpeed,
            nextSpeed / ballRadius);
      }
    }
  }

  void _roll(PoolBall ball, double dx, double dy, double angle) {
    final axisX = -dy;
    final axisY = dx;
    final cosine = math.cos(angle);
    final sine = math.sin(angle);
    final oneMinusCosine = 1 - cosine;
    final m00 = oneMinusCosine * axisX * axisX + cosine;
    final m01 = oneMinusCosine * axisX * axisY;
    final m02 = axisY * sine;
    final m10 = oneMinusCosine * axisX * axisY;
    final m11 = oneMinusCosine * axisY * axisY + cosine;
    final m12 = -axisX * sine;
    final m20 = -axisY * sine;
    final m21 = axisX * sine;
    final m22 = cosine;
    final rotation = ball.orientation;
    for (var column = 0; column < 3; column++) {
      final x = rotation[column];
      final y = rotation[3 + column];
      final z = rotation[6 + column];
      rotation[column] = m00 * x + m01 * y + m02 * z;
      rotation[3 + column] = m10 * x + m11 * y + m12 * z;
      rotation[6 + column] = m20 * x + m21 * y + m22 * z;
    }

    var length = math.sqrt(
      rotation[0] * rotation[0] +
          rotation[3] * rotation[3] +
          rotation[6] * rotation[6],
    );
    rotation[0] /= length;
    rotation[3] /= length;
    rotation[6] /= length;
    final projection =
        rotation[1] * rotation[0] +
        rotation[4] * rotation[3] +
        rotation[7] * rotation[6];
    rotation[1] -= projection * rotation[0];
    rotation[4] -= projection * rotation[3];
    rotation[7] -= projection * rotation[6];
    length = math.sqrt(
      rotation[1] * rotation[1] +
          rotation[4] * rotation[4] +
          rotation[7] * rotation[7],
    );
    rotation[1] /= length;
    rotation[4] /= length;
    rotation[7] /= length;
    rotation[2] = rotation[3] * rotation[7] - rotation[6] * rotation[4];
    rotation[5] = rotation[6] * rotation[1] - rotation[0] * rotation[7];
    rotation[8] = rotation[0] * rotation[4] - rotation[3] * rotation[1];
  }

  void _finishTurn() {
    final player = currentPlayer;
    final opponent = 1 - player;
    final group = _groups[player];
    final required = group == 0 ? -1 : (_leftBeforeShot == 0 ? 8 : group);
    final foul = _cueWasPocketed ||
        _firstHit == -1 ||
        (group != 0 &&
            (_firstHit == 8 ? 8 : groupOf(_firstHit)) != required);

    if (_potted.contains(8)) {
      final won = !foul && group != 0 && _leftBeforeShot == 0;
      winner = won ? player : opponent;
      state = PoolGameState.gameOver;
      message = '${playerName(winner)} ${won ? 'gagne' : 'perd'} la partie !';
      return;
    }
    if (group == 0 && !foul && _potted.isNotEmpty) {
      _groups[player] = groupOf(_potted.first);
      _groups[opponent] = 3 - _groups[player];
    }
    final keepsTurn =
        !foul && _potted.any((id) => groupOf(id) == _groups[player]);
    if (!keepsTurn) currentPlayer = opponent;
    if (foul) {
      cueBall
        ..pocketed = false
        ..vx = 0
        ..vy = 0
        ..x = rail + .25 * (tableWidth - 2 * rail)
        ..y = tableHeight / 2;
      state = PoolGameState.placingCue;
      _lastCuePlacementValid = _canPlaceCue();
      message = _cueWasPocketed
          ? 'Faute : la bille blanche est empochée. Replacez-la.'
          : (_firstHit == -1
              ? 'Faute : aucune bille touchée. Replacez la bille blanche.'
              : 'Faute : mauvaise bille touchée. Replacez-la.');
    } else {
      state = PoolGameState.aiming;
      message = keepsTurn ? 'Bien joué, rejouez !' : _turnMessage();
    }
  }

  bool _canPlaceCue() => balls.every((ball) =>
      ball.id == 0 ||
      ball.pocketed ||
      _distance(ball.x, ball.y, cueBall.x, cueBall.y) >= 2 * ballRadius);

  void _tickComputer() {
    if (state == PoolGameState.placingCue) {
      if (++_aiWait < 45) return;
      _aiWait = 0;
      final random = math.Random();
      for (var attempt = 0; attempt < 201; attempt++) {
        _moveCue(
          rail +
              ballRadius +
              random.nextDouble() *
                  (tableWidth - 2 * rail - 2 * ballRadius) *
                  .45,
          rail +
              ballRadius +
              random.nextDouble() *
                  (tableHeight - 2 * rail - 2 * ballRadius),
        );
        if (_canPlaceCue()) break;
      }
      state = PoolGameState.aiming;
      message = _turnMessage();
      return;
    }
    const waits = [70, 50, 30];
    if (!_aiPlanned) {
      if (++_aiWait < waits[level.clamp(0, 2)]) return;
      _aiWait = 0;
      _chooseComputerShot();
      _aiPlanned = true;
      power = 0;
    }
    aim = _aiAngle;
    power += .03;
    if (power >= _aiPower) {
      _aiPlanned = false;
      takeShot(_aiAngle, _aiPower);
      power = 0;
    }
  }

  void _chooseComputerShot() {
    final group = _groups[1];
    final targets = balls.where((ball) {
      if (ball.pocketed || ball.id == 0) return false;
      if (group == 0) return ball.id != 8;
      return remaining(group) > 0 ? groupOf(ball.id) == group : ball.id == 8;
    }).toList();
    final candidates = <({double score, double angle, double power})>[];
    for (final target in targets) {
      for (final pocket in _pockets) {
        final tx = pocket[0] - target.x;
        final ty = pocket[1] - target.y;
        final pocketDistance = math.sqrt(tx * tx + ty * ty).clamp(1, double.infinity);
        final ghostX = target.x - tx / pocketDistance * 2 * ballRadius;
        final ghostY = target.y - ty / pocketDistance * 2 * ballRadius;
        final cx = ghostX - cueBall.x;
        final cy = ghostY - cueBall.y;
        final cueDistance = math.sqrt(cx * cx + cy * cy).clamp(1, double.infinity);
        final cut = (cx * tx + cy * ty) / (cueDistance * pocketDistance);
        if (cut < .25 ||
            !_isPathClear(cueBall.x, cueBall.y, ghostX, ghostY, target) ||
            !_isPathClear(target.x, target.y, pocket[0], pocket[1], target)) {
          continue;
        }
        candidates.add((
          score: cut * 1000 / (cueDistance + pocketDistance),
          angle: math.atan2(cy, cx),
          power: ((cueDistance + pocketDistance) * .018 + 4) / _maxPower,
        ));
      }
    }
    _aiAngle = math.atan2(
      tableHeight / 2 - cueBall.y,
      tableWidth / 2 - cueBall.x,
    );
    _aiPower = .6;
    if (candidates.isNotEmpty) {
      final candidate = level == 0
          ? candidates[math.Random().nextInt(candidates.length)]
          : candidates.reduce((a, b) => a.score > b.score ? a : b);
      _aiAngle = candidate.angle;
      _aiPower = candidate.power;
    } else if (targets.isNotEmpty) {
      targets.sort((a, b) =>
          _distance(a.x, a.y, cueBall.x, cueBall.y)
              .compareTo(_distance(b.x, b.y, cueBall.x, cueBall.y)));
      final target = targets.first;
      _aiAngle =
          math.atan2(target.y - cueBall.y, target.x - cueBall.x);
      _aiPower = .5;
    }
    final random = math.Random();
    const errors = [.14, .05, .012];
    _aiAngle += (random.nextDouble() - .5) * 2 * errors[level.clamp(0, 2)];
    if (level == 0 && random.nextDouble() < .2) {
      _aiAngle += (random.nextDouble() - .5) * 1.2;
    }
    _aiPower = (_aiPower * (level == 0 ? .7 + random.nextDouble() * .6 : 1))
        .clamp(.25, 1);
  }

  bool _isPathClear(
    double x1,
    double y1,
    double x2,
    double y2,
    PoolBall ignored,
  ) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    final lengthSquared = dx * dx + dy * dy;
    if (lengthSquared < 1) return true;
    for (final ball in balls) {
      if (ball.pocketed || ball.id == 0 || ball.id == ignored.id) continue;
      final fraction =
          (((ball.x - x1) * dx + (ball.y - y1) * dy) / lengthSquared)
              .clamp(0, 1);
      if (_distance(
            ball.x,
            ball.y,
            x1 + fraction * dx,
            y1 + fraction * dy,
          ) <
          2 * ballRadius - 1) {
        return false;
      }
    }
    return true;
  }

  void remoteShot(double angle, double shotPower) {
    if (state != PoolGameState.aiming) return;
    takeShot(angle, shotPower, remote: true);
  }

  void remotePlace(double x, double y) {
    if (state != PoolGameState.placingCue) return;
    _moveCue(x, y);
    state = PoolGameState.aiming;
    message = _turnMessage();
  }

  String snapshot() {
    final stateCode = switch (state) {
      PoolGameState.aiming => 0,
      PoolGameState.moving => 1,
      PoolGameState.placingCue => 2,
      PoolGameState.gameOver => 3,
      PoolGameState.striking => 4,
    };
    final encodedBalls = balls
        .map((ball) =>
            '${ball.id}:${ball.x.toStringAsFixed(2)}:${ball.y.toStringAsFixed(2)}:${ball.pocketed ? 1 : 0}')
        .join(',');
    return 'STATE $currentPlayer ${_groups[0]} ${_groups[1]} '
        '$stateCode $winner $encodedBalls';
  }

  bool applySnapshot(String line) {
    final fields = line.split(' ');
    if (fields.length < 7 || fields.first != 'STATE') return false;
    final current = int.tryParse(fields[1]);
    final firstGroup = int.tryParse(fields[2]);
    final secondGroup = int.tryParse(fields[3]);
    final stateCode = int.tryParse(fields[4]);
    final gameWinner = int.tryParse(fields[5]);
    if (current == null ||
        current < 0 ||
        current > 1 ||
        firstGroup == null ||
        secondGroup == null ||
        stateCode == null ||
        stateCode < 0 ||
        stateCode > 3 ||
        gameWinner == null) {
      return false;
    }
    for (final encoded in fields[6].split(',')) {
      final values = encoded.split(':');
      if (values.length != 4) return false;
      final id = int.tryParse(values[0]);
      final x = double.tryParse(values[1]);
      final y = double.tryParse(values[2]);
      final pocketed = int.tryParse(values[3]);
      if (id == null || x == null || y == null || pocketed == null) {
        return false;
      }
      final ball = balls.where((item) => item.id == id).firstOrNull;
      if (ball == null) continue;
      ball
        ..x = x
        ..y = y
        ..pocketed = pocketed == 1
        ..vx = 0
        ..vy = 0;
    }
    currentPlayer = current;
    _groups
      ..[0] = firstGroup
      ..[1] = secondGroup;
    winner = gameWinner;
    state = PoolGameState.values[stateCode];
    _charging = false;
    power = 0;
    message = state == PoolGameState.gameOver
        ? '${playerName(winner)} ${winner == myPlayerIndex ? 'a gagné' : 'a perdu'} !'
        : (state == PoolGameState.placingCue
            ? 'Faute : replacez la bille blanche.'
            : _turnMessage());
    return true;
  }

  double _distance(double x1, double y1, double x2, double y2) {
    final dx = x2 - x1;
    final dy = y2 - y1;
    return math.sqrt(dx * dx + dy * dy);
  }
}
