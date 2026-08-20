import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:miloka/service/ludo_team_lobby_service.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../game/ludo/ludo_engine.dart';
import '../providers/auth_provider.dart';
import '../service/ludo_multiplayer_service.dart';
import '../service/stats_service.dart';
import '../utils/image_cache.dart';
import '../widgets/friends_dialog.dart';
import 'home_screen.dart';
import 'ludo_lobby_screen.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class LudoScreen extends StatefulWidget {
  final bool beginGame;
  final List<Map<String, dynamic>> playerSubscribe;
  final bool isHost;
  final String teamId;
  const LudoScreen({
    super.key,
    this.beginGame = false,
    this.playerSubscribe = const [],
    this.isHost = false,
    this.teamId = '',
  });

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with TickerProviderStateMixin {
  late LudoEngine _engine;
  Timer? _aiTimer;
  late AnimationController _diceController;
  late AnimationController _moveController;
  final ValueNotifier<int> _displayDice = ValueNotifier<int>(1);
  LudoPawn? _selectedPawn;
  bool _winnerDialogShown = false;
  bool _beginGame = false;
  bool _aiPlaying = false;
  bool _diceRolledThisTurn = false;
  final ValueNotifier<bool> _isDraggingDice = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isSlidingDice = ValueNotifier<bool>(false);
  late final Listenable _diceListenable;
  bool _isMultiplayer = false;
  List<LudoHuman> _playerSubscribe = [];
  String _roomCode = '';
  String _playerName = '';
  StreamSubscription<Map<String, dynamic>>? _multiplayerSubscription;
  final LudoMultiplayerService _multiplayerService = LudoMultiplayerService();
  final ValueNotifier<List<String>> _participantsNotifier = ValueNotifier([]);
  bool isHost = true;
  final Set<LudoColor> _disconnectedColors = {};
  final ValueNotifier<Set<String>> _readyPlayersNotifier = ValueNotifier({});

  Timer? _inactivityTimer;
  Timer? _inactivityWarningTimer;
  bool _isWarningShown = false;

  Offset _slideVelocity = Offset.zero;
  final ValueNotifier<Offset> _diceDragOffset = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<double> _diceSlideAngle = ValueNotifier<double>(0);
  Timer? _slideTimer;
  final GlobalKey _stackKey = GlobalKey();
  double _cellSize = 0;
  int? _movingPawnId;
  LudoColor? _movingPawnColor;
  List<Offset> _movePath = [];
  dynamic _userProfile;

  @override
  void initState() {
    super.initState();
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _moveController = AnimationController(vsync: this);
    _diceListenable = Listenable.merge([
      _diceDragOffset,
      _diceSlideAngle,
      _displayDice,
      _isDraggingDice,
      _isSlidingDice,
    ]);
    //_beginGame = widget.beginGame;
    if (widget.beginGame) {
      //_startGame(LudoColor.yellow);
      _playerSubscribe = widget.playerSubscribe
          .map(
            (player) => LudoHuman(
              name: player['name']?.toString() ?? 'Joueur inconnu',
              color: _parseColor(player['color']),
              id: player['id'],
              avatar: player['avatar'],
              bet: (player['bet'] as int?) ?? 0,
            ),
          )
          .toList();

      _startMultParticipantGame();
    }

    _userProfile = context.read<AuthProvider?>()?.userProfile;
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _slideTimer?.cancel();
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    _multiplayerSubscription?.cancel();
    if (_roomCode.isNotEmpty && _isMultiplayer && _beginGame) {
      if (isHost) {
        _multiplayerService.sendGameEnded(_roomCode);
      } else if (_engine.players.isNotEmpty) {
        final player = _engine.players.firstWhere(
          (p) => p.namePlayer == _playerName,
          orElse: () => _engine.players.first,
        );
        _multiplayerService.sendPlayerLeft(
          _roomCode,
          player.namePlayer ?? _playerName,
          player.color.name,
        );
      }
      _multiplayerService.disposeRoom(_roomCode);
    } else if (_roomCode.isNotEmpty) {
      _multiplayerService.disposeRoom(_roomCode);
    }
    _participantsNotifier.dispose();
    _readyPlayersNotifier.dispose();
    _diceController.dispose();
    _moveController.dispose();
    _displayDice.dispose();
    _diceDragOffset.dispose();
    _diceSlideAngle.dispose();
    _isDraggingDice.dispose();
    _isSlidingDice.dispose();
    super.dispose();
  }

  void _scheduleAiTurn() {
    if (_engine.winner != null) return;
    if (_disconnectedColors.contains(_engine.currentPlayer.color)) {
      _engine.advancePastDisconnected(_disconnectedColors);
      setState(() {});
      if (_isMultiplayer && isHost && _engine.onStateChange != null) {
        _engine.onStateChange!(_engine.snapshot());
      }
      _scheduleAiTurn();
      return;
    }
    if (_engine.currentPlayer.isHuman) return;
    if (_aiTimer != null && _aiTimer!.isActive) return;
    if (_aiPlaying) return;

    _aiTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      _aiPlaying = true;
      _aiTimer = null;
      final value = _engine.rollDice();
      setState(() {});
      _animateDiceRoll(value).then((_) {
        if (!mounted) return;
        _engine.aiPlay();
        final move = _engine.lastMove;

        if (move != null) {
          _startPawnMove(
            move.pawn.color,
            move.pawn.id,
            move.fromSteps,
            move.toSteps,
            () {
              if (!mounted) return;
              setState(() {
                if (_engine.winner == null) {
                  if (_engine.extraTurn) {
                    _engine.scheduleTurnEnd(extraTurn: true);
                  } else {
                    _engine.scheduleTurnEnd(extraTurn: false);
                  }
                }
                _aiPlaying = false;
                _scheduleAiTurn();
              });
            },
          );
        } else {
          setState(() {
            if (_engine.winner == null) {
              if (_engine.extraTurn) {
                _engine.scheduleTurnEnd(extraTurn: true);
              } else {
                _engine.scheduleTurnEnd(extraTurn: false);
              }
            }
            _aiPlaying = false;
            _scheduleAiTurn();
          });
        }
      });
    });
  }

  Future<void> _animateDiceRoll(int value) async {
    _diceController.forward(from: 0).then((_) {
      if (mounted) _displayDice.value = value;
    });
    for (var i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 70), () {
        if (mounted) _displayDice.value = math.Random().nextInt(6) + 1;
      });
    }
    await Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) _displayDice.value = value;
    });
  }

  bool get _isMyTurn =>
      _engine.currentPlayer.isHuman &&
      _engine.winner == null &&
      (!_engine.isMultiplayer ||
          _engine.currentPlayer.id == _userProfile?['id']);

  void _onRollDice() {
    if (!_isMyTurn || _diceRolledThisTurn) {
      return;
    }

    print('Host? => $isHost');
    _diceRolledThisTurn = true;
    _resetInactivityTimer();
    final value = _engine.rollDice();
    setState(() => _selectedPawn = null);
    // engine now broadcasts state via its `onStateChange` callback in multiplayer

    if (isHost) {
      _animateDiceRoll(value).then((_) {
        if (!mounted) return;
        setState(() {
          if (_engine.getValidMoves().isEmpty) {
            _diceRolledThisTurn = false;
            _engine.scheduleTurnEnd(extraTurn: false);
            _scheduleAiTurn();
          }
        });
      });
    } else {
      _animateDiceRoll(value).then((_) {
        if (!mounted) return;
        setState(() {
          if (_engine.getValidMoves().isEmpty) {
            _diceRolledThisTurn = false;
            _engine.scheduleTurnEnd(extraTurn: false);
            //_scheduleAiTurn();
          }
        });
      });
    }
  }

  void _onPawnTap(LudoPawn pawn) {
    if (!_isMyTurn) return;
    if (!_diceRolledThisTurn || !_engine.canMovePawn(pawn)) return;

    _resetInactivityTimer();
    final fromSteps = pawn.stepsFromStart;
    final move = _engine.getValidMoves().firstWhere(
      (m) => m.pawn.id == pawn.id,
    );
    final toSteps = move.toSteps;

    final moved = _engine.applyMove(pawn);
    if (!moved) return;

    _startPawnMove(pawn.color, pawn.id, fromSteps, toSteps, () {
      if (!mounted) return;
      setState(() {
        _selectedPawn = null;
        _diceRolledThisTurn = false;
      });
      if (_engine.winner != null) {
        return;
      }
      if (_engine.extraTurn) {
        _engine.scheduleTurnEnd(extraTurn: true);
      } else {
        _engine.scheduleTurnEnd(extraTurn: false);
        if (isHost || !_engine.isMultiplayer) _scheduleAiTurn();
      }
      // engine will broadcast new state when needed via its callback
    });
  }

  void _handleGameEnded() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text(
          'Partie terminée',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'La partie a été interrompue.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (widget.teamId.isNotEmpty) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LudoLobbyScreen(
                      teamId: widget.teamId,
                      isHost: widget.isHost,
                      fromGame: true,
                    ),
                  ),
                );
              } else {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => route.isFirst,
                );
              }
            },
            child: const Text('OK', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  void _handlePlayerLeft(Map<String, dynamic> payload) {
    final colorName = payload['color']?.toString();
    final playerName = payload['player']?.toString() ?? 'Un joueur';
    if (colorName == null) return;

    final color = LudoColor.values.firstWhere(
      (c) => c.name == colorName,
      orElse: () => LudoColor.red,
    );

    setState(() {
      _disconnectedColors.add(color);
    });

    _participantsNotifier.value = _participantsNotifier.value
        .where((name) => name != playerName)
        .toList();

    if (_disconnectedColors.contains(_engine.currentPlayer.color)) {
      _engine.advancePastDisconnected(_disconnectedColors);
      setState(() {});
      if (_isMultiplayer && isHost && _engine.onStateChange != null) {
        _engine.onStateChange!(_engine.snapshot());
      }
      _scheduleAiTurn();
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$playerName a quitté la partie.'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _quitGame() {
    if (_isMultiplayer && _roomCode.isNotEmpty) {
      final playerColor = _engine.players.any((p) => p.namePlayer == _playerName)
          ? _engine.players.firstWhere((p) => p.namePlayer == _playerName).color
          : LudoColor.yellow;
      _multiplayerService.sendPlayerLeft(_roomCode, _playerName, playerColor.name);
      _multiplayerService.disposeRoom(_roomCode);
      _multiplayerSubscription?.cancel();
      _roomCode = '';
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => route.isFirst,
    );
  }

  bool get _inactivityEnabled =>
      _isMultiplayer && _roomCode.isNotEmpty;

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityWarningTimer?.cancel();
    if (_isWarningShown) {
      _isWarningShown = false;
      Navigator.of(context).pop();
    }
    if (!_beginGame || _engine.winner != null) return;
    // Le forfait d'inactivité n'existe qu'en partie en ligne réelle
    // (2 joueurs ou plus), jamais en solo contre l'IA.
    if (!_inactivityEnabled) return;
    if (!_isMyTurn) return;
    final currentColor = _engine.currentPlayer.color;
    _inactivityTimer = Timer(const Duration(seconds: 60), () {
      if (!mounted || !_beginGame || _engine.winner != null) return;
      if (!_inactivityEnabled) return;
      if (_engine.currentPlayer.color != currentColor) return;
      if (!_isMyTurn) return;
      _forfeitLocalPlayer();
    });
    _inactivityWarningTimer = Timer(const Duration(seconds: 50), () {
      if (!mounted || !_beginGame || _engine.winner != null) return;
      if (_engine.currentPlayer.color != currentColor) return;
      if (!_isMyTurn) return;
      _showForfeitWarning();
    });
  }

  void _showForfeitWarning() {
    if (!mounted || !_beginGame || _engine.winner != null) return;
    if (!_inactivityEnabled || !_isMyTurn) return;
    _isWarningShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: false,
      builder: (_) => const _LudoForfeitWarningDialog(),
    ).whenComplete(() {
      _isWarningShown = false;
    });
  }

  LudoColor? _winningForfeitColor() {
    final mine = _engine.currentPlayer.color;
    for (final p in _engine.players) {
      if (p.isHuman &&
          p.color != mine &&
          !_disconnectedColors.contains(p.color)) {
        return p.color;
      }
    }
    return null;
  }

  void _forfeitLocalPlayer() {
    _inactivityTimer?.cancel();
    if (!mounted || !_beginGame || _engine.winner != null) return;
    if (!_inactivityEnabled || !_isMyTurn) return;
    final winnerColor = _winningForfeitColor();
    if (winnerColor == null) return;
    _engine
      ..winner = winnerColor
      ..message = '${winnerColor.label} gagne par forfait !';
    if (_engine.onStateChange != null) {
      _engine.onStateChange!(_engine.snapshot());
    }
    setState(() {});
  }

  void _startPawnMove(
    LudoColor color,
    int pawnId,
    int fromSteps,
    int toSteps,
    VoidCallback onComplete,
  ) {
    _movePath = LudoBoardLayout.movePath(
      color,
      fromSteps,
      toSteps,
      pawnId,
      _cellSize,
    );
    if (_movePath.isEmpty) {
      onComplete();
      return;
    }
    _movingPawnId = pawnId;
    _movingPawnColor = color;

    _moveController.duration = Duration(milliseconds: _movePath.length * 100);
    _moveController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      _movingPawnId = null;
      _movingPawnColor = null;
      _movePath = [];
      setState(() {});
      onComplete();
    });
  }

  void _startDiceSlide() {
    _slideTimer?.cancel();
    const friction = 0.96;
    const minVelocity = 20.0;

    final renderBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final stackSize = renderBox.size;
    final diceSize = 60.0;
    const bottomPadding = 24.0;
    final topBound = -stackSize.height + bottomPadding + diceSize;
    final leftBound = -stackSize.width / 2 + diceSize / 2;
    final rightBound = stackSize.width / 2 - diceSize / 2;

    _slideTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      _slideVelocity *= friction;

      if (_slideVelocity.distance < minVelocity) {
        timer.cancel();
        _animateDiceBack();
        return;
      }

      _diceDragOffset.value += _slideVelocity * 0.016;
      _diceSlideAngle.value += _slideVelocity.distance * 0.0003;

      if (_diceDragOffset.value.dx < leftBound) {
        _diceDragOffset.value =
            Offset(leftBound, _diceDragOffset.value.dy);
        _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
      } else if (_diceDragOffset.value.dx > rightBound) {
        _diceDragOffset.value =
            Offset(rightBound, _diceDragOffset.value.dy);
        _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
      }
      if (_diceDragOffset.value.dy < topBound) {
        _diceDragOffset.value =
            Offset(_diceDragOffset.value.dx, topBound);
        _slideVelocity = Offset(_slideVelocity.dx, -_slideVelocity.dy);
      }
    });
  }

  void _animateDiceBack() {
    const duration = Duration(milliseconds: 300);
    final startOffset = _diceDragOffset.value;
    final startAngle = _diceSlideAngle.value;
    final startTime = DateTime.now();

    _slideTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds /
          duration.inMilliseconds;
      final t = elapsed.clamp(0.0, 1.0);
      final easeOut = 1 - (1 - t) * (1 - t);

      _diceDragOffset.value = Offset.lerp(startOffset, Offset.zero, easeOut)!;
      _diceSlideAngle.value = startAngle * (1 - easeOut);

      if (t >= 1) {
        timer.cancel();
        _isSlidingDice.value = false;
        _diceDragOffset.value = Offset.zero;
        _diceSlideAngle.value = 0;
        _slideVelocity = Offset.zero;
        _onRollDice();
      }
    });
  }

  void _startGame(LudoColor color) {
    setState(() {
      _engine = LudoEngine(
        human: [LudoHuman(name: 'Joueur', color: color)],
      );
      _beginGame = true;
    });
    if (!_engine.currentPlayer.isHuman) {
      _scheduleAiTurn();
    }
  }

  void _startLocalGame(List<LudoColor> colors) {
    final names = <String>['Joueur 1', 'Joueur 2', 'Joueur 3', 'Joueur 4'];
    setState(() {
      _engine = LudoEngine(
        human: [
          for (var i = 0; i < colors.length; i++)
            LudoHuman(name: names[i], color: colors[i]),
        ],
      );
      _beginGame = true;
    });
    if (!_engine.currentPlayer.isHuman) {
      _scheduleAiTurn();
    }
  }

  LudoColor _parseColor(dynamic colorValue) {
    if (colorValue is LudoColor) return colorValue;
    if (colorValue is String) {
      return LudoColor.values.firstWhere(
        (c) => c.name == colorValue,
        orElse: () => LudoColor.yellow,
      );
    }
    return LudoColor.yellow;
  }

  void _startMultParticipantGame() async {
    if (_playerSubscribe.isEmpty) return;

    print('Participant => $_playerSubscribe');

    await _multiplayerService.joinRoom(
      playerName: _playerSubscribe.first.name,
      playerColor: _playerSubscribe.first.color.name,
    );

    setState(() {
      _roomCode = 'ludo_global';
      _playerName = _playerSubscribe.first.name;
      _engine = LudoEngine(
        human: _playerSubscribe,
        isMultiplayer: true,
        roomCode: 'ludo_global',
        onStateChange: (snapshot) => _multiplayerService.sendState(
          'ludo_global',
          snapshot.toJson(),
          true,
        ),
      );
      isHost = widget.isHost;
      _beginGame = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _resetInactivityTimer());

    if (!_engine.currentPlayer.isHuman && isHost) {
      _scheduleAiTurn();
    }

    _multiplayerSubscription = _multiplayerService
        .watchRoom('ludo_global')
        .listen((payload) {
          if (!mounted) return;
          final type = payload['type']?.toString();
          if (type == 'presence' || type == 'participants' || type == 'start') {
            return;
          }
          if (type == 'game_ended') {
            _handleGameEnded();
            return;
          }
          if (type == 'player_left') {
            _handlePlayerLeft(payload);
            return;
          }

          final snapshot = LudoGameSnapshot.fromJson(payload);
          if (snapshot.roomCode == 'ludo_global') {
            setState(() {
              _engine.applySnapshot(snapshot);
              _diceRolledThisTurn = snapshot.diceRolled && _isMyTurn;
              _displayDice.value = snapshot.lastDice == 0 ? 1 : snapshot.lastDice;
            });
            _resetInactivityTimer();
            if (isHost) {
              _scheduleAiTurn();
            }
          }
        });
  }

  Future<void> _showColorPicker() async {
    LudoColor? selectedColor;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Center(
            child: Text(
              'Choisis ta couleur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          content: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Quelle couleur pour tenter ta chance ?',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColor == color;
                    final baseColor = LudoBoardLayout.colorValues[color]!;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [baseColor, baseColor.withValues(alpha: 0.6)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white24,
                            width: isSelected ? 3 : 1.5,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: baseColor.withValues(alpha: 0.5),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            color.label,
                            style: TextStyle(
                              color: color == LudoColor.yellow
                                  ? Colors.black87
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SizedBox(
                  width: 180,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: selectedColor != null
                          ? const Color(0xFFD4A017)
                          : Colors.grey.shade700,
                      foregroundColor: selectedColor != null
                          ? const Color(0xFF1C1C2E)
                          : Colors.white38,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: selectedColor != null ? 4 : 0,
                    ),
                    onPressed: selectedColor != null
                        ? () {
                            Navigator.pop(ctx);
                            _startGame(selectedColor!);
                          }
                        : null,
                    child: Text(
                      'C\'est parti !',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLocalPicker() async {
    final selectedColors = <LudoColor>{};

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1C1C2E),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Center(
            child: Text(
              'Local multi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          content: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Choisis 2 à 4 joueurs',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColors.contains(color);
                    final baseColor = LudoBoardLayout.colorValues[color]!;
                    return GestureDetector(
                      onTap: () {
                        setDialogState(() {
                          if (isSelected) {
                            selectedColors.remove(color);
                          } else {
                            selectedColors.add(color);
                          }
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              baseColor,
                              baseColor.withValues(alpha: isSelected ? 1 : 0.4),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.white24,
                            width: isSelected ? 3 : 1.5,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: baseColor.withValues(alpha: 0.5),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                color.label,
                                style: TextStyle(
                                  color: color == LudoColor.yellow
                                      ? Colors.black87
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isSelected)
                                Text(
                                  '${selectedColors.toList().indexOf(color) + 1}',
                                  style: TextStyle(
                                    color: color == LudoColor.yellow
                                        ? Colors.black54
                                        : Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (selectedColors.length < 2)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Minimum 2 joueurs',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColors.length >= 2
                            ? const Color(0xFFD4A017)
                            : Colors.grey.shade700,
                        foregroundColor: selectedColors.length >= 2
                            ? const Color(0xFF1C1C2E)
                            : Colors.white38,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: selectedColors.length >= 2
                          ? () {
                              Navigator.pop(ctx);
                              _startLocalGame(selectedColors.toList());
                            }
                          : null,
                      child: const Text(
                        'Jouer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _finishGameWithStats() async {
    await StatsService().recordGameResult(
      gameName: 'ludo',
      won: _engine.winner == _engine.currentPlayer.color,
      context: context,
    );
  }

  Future<void> _processLudoBetTransfer() async {
    final anyBet = _playerSubscribe.any((p) => p.bet > 0);
    if (!anyBet || _engine.winner == null) return;

    final winnerColor = _engine.winner!;
    final winnerHuman = _playerSubscribe.where((p) => p.color == winnerColor).firstOrNull;
    if (winnerHuman == null) return;

    final winnerBet = winnerHuman.bet;
    final loserBets = _playerSubscribe
        .where((p) => p.color != winnerColor && p.bet > 0 && !(p.id?.startsWith('ai_') ?? false))
        .toList();

    if (loserBets.isEmpty) return;

    final totalPot = _playerSubscribe
        .where((p) => p.bet > 0 && !(p.id?.startsWith('ai_') ?? false))
        .fold(0, (sum, p) => sum + p.bet);
    final remaining = totalPot - winnerBet;
    final appShare = remaining ~/ 2;
    final winnerExtra = remaining - appShare;

    final supabase = Supabase.instance.client;

    if (winnerExtra > 0 && winnerHuman.id != null) {
      final winnerCoins = await supabase
          .from('users')
          .select('coins')
          .eq('id', winnerHuman.id!)
          .single();
      final currentWinnerCoins = (winnerCoins['coins'] as int?) ?? 0;
      await supabase
          .from('users')
          .update({'coins': currentWinnerCoins + winnerBet + winnerExtra})
          .eq('id', winnerHuman.id!);
    }

    for (final loser in loserBets) {
      if (loser.id == null) continue;
      final loserCoins = await supabase
          .from('users')
          .select('coins')
          .eq('id', loser.id!)
          .single();
      final currentLoserCoins = (loserCoins['coins'] as int?) ?? 0;
      await supabase
          .from('users')
          .update({'coins': currentLoserCoins - loser.bet})
          .eq('id', loser.id!);
    }

    if (appShare > 0) {
      await supabase.from('app_gains').insert({
        'match_code': widget.playerSubscribe.isNotEmpty
            ? _roomCode
            : 'ludo_${DateTime.now().millisecondsSinceEpoch}',
        'amount': appShare,
        'bet': winnerBet,
        'winner_team': winnerColor.name,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  void _showWinnerDialog() {
    if (_winnerDialogShown) return;
    _winnerDialogShown = true;
    final winner = _engine.winner;
    final bool iWon;
    if (winner == null) {
      iWon = false;
    } else if (_engine.isMultiplayer) {
      iWon = _engine.players.any(
        (p) => p.isHuman && p.color == winner && p.id == _userProfile?['id'],
      );
    } else {
      iWon = _engine.humanColor.contains(winner);
    }
    final winColor = winner != null
        ? LudoBoardLayout.colorValues[winner]!
        : Colors.amber;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        final dialog = Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF1C1C2E),
                    winColor.withValues(alpha: 0.15),
                    const Color(0xFF1C1C2E),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: iWon ? const Color(0xFFD4A017) : Colors.white24,
                  width: 2,
                ),
                boxShadow: [
                  if (iWon)
                    BoxShadow(
                      color: const Color(0xFFD4A017).withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                ],
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFFD4A017).withValues(alpha: 0.3),
                          const Color(0xFFD4A017).withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    child: Icon(
                      iWon ? Icons.emoji_events : Icons.sentiment_dissatisfied,
                      color: iWon
                          ? const Color(0xFFD4A017)
                          : Colors.white54,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    iWon ? '💰 Victoire !' : '😞 Perdu',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    iWon
                        ? '${winner!.label} empoche la cagnotte !'
                        : '${winner!.label} remporte la victoire !',
                    style: TextStyle(
                      color: winColor.withValues(alpha: 0.8),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD4A017),
                        foregroundColor: const Color(0xFF1C1C2E),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: 4,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        if (widget.teamId.isNotEmpty) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LudoLobbyScreen(
                                teamId: widget.teamId,
                                isHost: widget.isHost,
                                fromGame: true,
                              ),
                            ),
                          );
                        } else {
                          Navigator.pop(context);
                        }
                      },
                      child: const Text(
                        'Retour au lobby',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (iWon) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(child: const _ConfettiWidget()),
              dialog,
            ],
          );
        }
        return dialog;
      },
    );
  }

  Future<void> _confirmLeaveGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Quitter la partie ?', style: TextStyle(color: Colors.white)),
        content: const Text('Êtes-vous sûr de vouloir quitter la partie ?', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    if (_isMultiplayer && _roomCode.isNotEmpty) {
      _multiplayerService.sendGameEnded(_roomCode);
      _multiplayerService.disposeRoom(_roomCode);
      _roomCode = '';
    }

    if (widget.teamId.isNotEmpty) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LudoLobbyScreen(
            teamId: widget.teamId,
            isHost: widget.isHost,
            fromGame: true,
          ),
        ),
      );
    } else {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => route.isFirst,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_beginGame) {
      if (_engine.winner != null && !_winnerDialogShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _finishGameWithStats();
            _processLudoBetTransfer();
            context.read<AuthProvider?>()?.refreshProfile();
            _showWinnerDialog();
          }
        });
      }
    }

    //final profileName = context.read<AuthProvider?>()?.userProfile?['username']?.toString();

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: _beginGame
          ? FloatingActionButton(
              mini: true,
              backgroundColor: Colors.black.withValues(alpha: 0.6),
              shape: const CircleBorder(),
              onPressed: _confirmLeaveGame,
              child: const Icon(Icons.arrow_back, color: Colors.white70),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: _beginGame
              ? Stack(
                  key: _stackKey,
                  children: [
                    Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: Center(child: _buildBoard())),
                      ],
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: AnimatedBuilder(
                          animation: _diceListenable,
                          builder: (context, _) {
                            final canRoll =
                                !_isDraggingDice.value &&
                                    !_isSlidingDice.value &&
                                    _isMyTurn &&
                                    !_diceRolledThisTurn;
                            return GestureDetector(
                              onTap: canRoll ? _onRollDice : null,
                              onPanStart: (_) {
                                _slideTimer?.cancel();
                                _isDraggingDice.value = true;
                                _isSlidingDice.value = false;
                                _slideVelocity = Offset.zero;
                              },
                              onPanUpdate: (details) {
                                _diceDragOffset.value += details.delta;
                              },
                              onPanEnd: (details) {
                                final rollEnabled =
                                    _isDraggingDice.value &&
                                    _isMyTurn &&
                                    !_diceRolledThisTurn;

                                _slideVelocity = details.velocity.pixelsPerSecond;

                                if (_slideVelocity.distance > 50 && rollEnabled) {
                                  _isSlidingDice.value = true;
                                  _isDraggingDice.value = false;
                                  _startDiceSlide();
                                } else {
                                  _isDraggingDice.value = false;
                                  _diceDragOffset.value = Offset.zero;
                                  if (rollEnabled) {
                                    _onRollDice();
                                  }
                                }
                              },
                              child: Transform.translate(
                                offset: _diceDragOffset.value,
                                child: Transform.rotate(
                                  angle: _diceSlideAngle.value,
                                  child: _buildDice(_isMyTurn, _engine),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _buildTopBar(),
                    ),

                  ],
                )
              : _buildMain(),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final authProvider = context.read<AuthProvider?>();
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ??
        0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username =
        authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => showFriendsDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Icon(Icons.people_alt, color: Colors.white, size: 20),
            ),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: Colors.white24,
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? cachedNetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              color: Colors.white,
                              size: 16,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      username,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PurchaseScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on,
                      color: Colors.amber,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$coins',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMain() {
    if (_isMultiplayer && !_beginGame) {
      return _buildWaitingRoom();
    }

    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '🎲 Ludo',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(color: Colors.black87, blurRadius: 12),
                    Shadow(color: Color(0xFFD4A017), blurRadius: 20),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFD4A017).withValues(alpha: 0.3)),
                ),
                child: const Text(
                  '💰 Tente ta chance',
                  style: TextStyle(
                    color: Color(0xFFD4A017),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              _buildGameChip('Solo', LudoColor.red, Icons.person, () {
                _showColorPicker();
              }),
              const SizedBox(height: 16),
              _buildGameChip('Local', LudoColor.yellow, Icons.people, () {
                _showLocalPicker();
              }),
              const SizedBox(height: 16),
              _buildGameChip('En ligne', LudoColor.green, Icons.wifi, () async {
                final userProfile = context.read<AuthProvider?>()?.userProfile;
                if (userProfile == null) return;
                final userId = userProfile['id']?.toString();
                if (userId == null) return;
                final teamId = await LudoTeamLobbyService().createTeam(userId, userProfile);
                if (teamId == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erreur lors de la création du lobby')),
                    );
                  }
                  return;
                }
                if (!mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LudoLobbyScreen(teamId: teamId, isHost: true),
                  ),
                );
              }),
              /* const SizedBox(height: 16),
              _buildGameChip('Multi', LudoColor.blue, Icons.groups, () async {
                await _startMultiplayerGame(createRoom: false);
              }), */
            ],
          ),
        ),
        Positioned(top: 12, left: 12, right: 12, child: _buildTopBar()),
        Positioned(
          bottom: 20,
          left: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: Colors.black.withValues(alpha: 0.6),
            shape: const CircleBorder(),
            onPressed: _quitGame,
            child: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildGameChip(String label, LudoColor color, IconData icon, VoidCallback onTap) {
    final baseColor = LudoBoardLayout.colorValues[color]!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              baseColor.withValues(alpha: 0.8),
              baseColor.withValues(alpha: 0.4),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: baseColor.withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaitingRoom() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color(0xFFD4A017).withValues(alpha: 0.3),
                  width: 2,
                ),
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFD4A017)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'En attente du host...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _roomCode.isNotEmpty
                  ? 'Salle : $_roomCode'
                  : 'Connexion en cours...',
              style: const TextStyle(color: Colors.white54, fontSize: 15),
            ),
            const SizedBox(height: 28),
            ValueListenableBuilder<List<String>>(
              valueListenable: _participantsNotifier,
              builder: (context, list, _) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Participants (${list.length})',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Aucun participant détecté',
                          style: TextStyle(color: Colors.white38, fontSize: 14),
                        ),
                      )
                    else
                      ...list.map(
                        (name) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                foregroundColor: Colors.white54,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () {
                _multiplayerSubscription?.cancel();
                if (_roomCode.isNotEmpty) {
                  _multiplayerService.sendPlayerLeft(
                    _roomCode, _playerName, LudoColor.yellow.name,
                  );
                  _multiplayerService.disposeRoom(_roomCode);
                }
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                  (route) => route.isFirst,
                );
              },
              child: const Text('Quitter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 16, right: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _engine.currentPlayer.isHuman
                      ? Icons.person
                      : Icons.smart_toy,
                  size: 16,
                  color: LudoBoardLayout
                      .colorValues[_engine.currentPlayer.color]!
                      .withValues(alpha: 0.8),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _engine.message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight) - 24;
        _cellSize = size / LudoBoardLayout.gridSize;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              RepaintBoundary(
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _LudoBoardPainter(cellSize: _cellSize),
                ),
              ),
              ..._buildPlayerInfo(),
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _moveController,
                  builder: (context, child) {
                    return Stack(children: _buildPawns(_cellSize));
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPawns(double cellSize) {
    final Map<String, List<_PawnRenderInfo>> posGroups = {};
    for (final player in _engine.players) {
      for (final pawn in player.pawns) {
        final isAnimating =
            _movingPawnId == pawn.id && _movingPawnColor == pawn.color;
        Offset pos;
        if (isAnimating && _movePath.isNotEmpty) {
          final t = (_moveController.value * (_movePath.length - 1))
              .clamp(0.0, (_movePath.length - 1).toDouble());
          final idx = t.floor();
          final next = idx + 1 < _movePath.length ? idx + 1 : idx;
          pos = Offset.lerp(_movePath[idx], _movePath[next], t - idx)!;
        } else {
          pos = LudoBoardLayout.pawnPosition(pawn, cellSize);
        }

        final isSelectable =
            _isMyTurn &&
            _diceRolledThisTurn &&
            _engine.canMovePawn(pawn) &&
            !isAnimating;

        final isSelected =
            _selectedPawn?.id == pawn.id && _selectedPawn?.color == pawn.color;

        final key = '${pos.dx.toStringAsFixed(1)}_${pos.dy.toStringAsFixed(1)}';
        posGroups.putIfAbsent(key, () => []);
        posGroups[key]!.add(_PawnRenderInfo(
          pawn: pawn,
          pos: pos,
          isSelectable: isSelectable,
          isSelected: isSelected,
          isAnimating: isAnimating,
          playerColor: player.color,
        ));
      }
    }

    final widgets = <Widget>[];
    for (final group in posGroups.values) {
      final count = group.length;
      for (var i = 0; i < count; i++) {
        final info = group[i];
        Offset renderPos;
        if (count > 1 && !info.isAnimating) {
          final angle = (2 * math.pi * i / count) - math.pi / 2;
          final offset = cellSize * 0.18;
          renderPos = info.pos +
              Offset(math.cos(angle) * offset, math.sin(angle) * offset);
        } else {
          renderPos = info.pos;
        }

        final pawnColor = LudoBoardLayout.colorValues[info.playerColor]!;
        widgets.add(
          Positioned(
            left: renderPos.dx - cellSize * 0.32,
            top: renderPos.dy - cellSize * 0.32,
            child: GestureDetector(
              onTap: info.isSelectable ? () => _onPawnTap(info.pawn) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: cellSize * 0.64,
                height: cellSize * 0.64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [pawnColor, pawnColor.withValues(alpha: 0.7)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: info.isSelected
                        ? Colors.white
                        : info.isSelectable
                        ? const Color(0xFFD4A017)
                        : Colors.black87,
                    width: info.isSelected || info.isSelectable ? 3 : 1.5,
                  ),
                  boxShadow: [
                    if (info.isSelectable)
                      BoxShadow(
                        color: const Color(0xFFD4A017).withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(1, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: info.pawn.finished
                      ? const Icon(Icons.star, color: Colors.white, size: 12)
                      : Container(
                          width: cellSize * 0.2,
                          height: cellSize * 0.2,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                        ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _buildPlayerInfo() {
    return _engine.players.map((player) {
      final color = player.color;
      final isHuman = player.isHuman;

      final matchingPlayer = _playerSubscribe.firstWhere(
        (p) => p.color == color,
        orElse: () => LudoHuman(name: player.namePlayer ?? color.label, color: color),
      );

      final displayName = isHuman ? matchingPlayer.name : 'IA ${color.label}';

      Widget avatar;
      if (isHuman &&
          matchingPlayer.avatar != null &&
          matchingPlayer.avatar!.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 8,
          backgroundImage: cachedNetworkImage(matchingPlayer.avatar!),
        );
      } else if (isHuman) {
        avatar = const Icon(Icons.person, color: Colors.white, size: 14);
      } else {
        avatar = const Icon(Icons.smart_toy, color: Colors.white, size: 14);
      }

      return Positioned(
        left: color == LudoColor.green || color == LudoColor.red ? 4 : null,
        right: color == LudoColor.yellow || color == LudoColor.blue ? 4 : null,
        top: color == LudoColor.green || color == LudoColor.yellow ? 4 : null,
        bottom: color == LudoColor.red || color == LudoColor.blue ? 4 : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              avatar,
              if (displayName.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  displayName,
                  style: TextStyle(
                    color: color == LudoColor.yellow
                        ? Colors.black87
                        : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildDice(bool canRoll, LudoEngine engine) {
    return AnimatedBuilder(
      animation: _diceController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _diceController.value * math.pi * 2,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              color: canRoll ? Colors.white : Colors.grey.shade700,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: /* canRoll
                    ? */
                    LudoBoardLayout.colorValues[engine.currentPlayer.color]!,
                /* : Colors.grey, */
                width: 3,
              ),
              boxShadow: [
                  BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 6,
                  offset: const Offset(2, 3),
                ),
              ],
            ),
            child: Center(
              child: _displayDice.value > 0
                  ? _DiceFace(value: _displayDice.value, dark: !canRoll)
                  : const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}

class _ConfettiWidget extends StatefulWidget {
  const _ConfettiWidget();

  @override
  State<_ConfettiWidget> createState() => _ConfettiWidgetState();
}

class _ConfettiWidgetState extends State<_ConfettiWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _particles = List<_ConfettiParticle>.generate(
    24,
    (_) => _ConfettiParticle(),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_particles, _controller.value),
        );
      },
    );
  }
}

class _ConfettiParticle {
  final double startOffset = math.Random().nextDouble();
  final double x = math.Random().nextDouble();
  final double speed = 0.12 + math.Random().nextDouble() * 0.28;
  final double size = 3 + math.Random().nextDouble() * 5;
  final Color color =
      Colors.primaries[math.Random().nextInt(Colors.primaries.length)];
  final double rotation = math.Random().nextDouble() * 6.28;
  final double rotationSpeed = (math.Random().nextDouble() - 0.5) * 8;
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width.isInfinite || size.height.isInfinite) return;

    final paint = Paint();
    for (final p in particles) {
      final t = (progress + p.startOffset) % 1.0;
      final y = -0.15 + t * 1.3;
      if (y < -0.1 || y > 1.1) continue;
      final x = p.x + math.sin(t * 8 + p.x * 10) * 0.025;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.rotation + t * p.rotationSpeed);

      final alpha = (1 - y.clamp(0, 1)) * 0.85;
      paint.color = p.color.withValues(alpha: alpha);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.particles != particles;
}

class _PawnRenderInfo {
  final LudoPawn pawn;
  final Offset pos;
  final bool isSelectable;
  final bool isSelected;
  final bool isAnimating;
  final LudoColor playerColor;

  const _PawnRenderInfo({
    required this.pawn,
    required this.pos,
    required this.isSelectable,
    required this.isSelected,
    required this.isAnimating,
    required this.playerColor,
  });
}

class _DiceFace extends StatelessWidget {
  final int value;
  final bool dark;

  const _DiceFace({required this.value, this.dark = false});

  @override
  Widget build(BuildContext context) {
    const dotPositions = {
      1: [Offset(0.5, 0.5)],
      2: [Offset(0.25, 0.25), Offset(0.75, 0.75)],
      3: [Offset(0.25, 0.25), Offset(0.5, 0.5), Offset(0.75, 0.75)],
      4: [
        Offset(0.25, 0.25),
        Offset(0.75, 0.25),
        Offset(0.25, 0.75),
        Offset(0.75, 0.75),
      ],
      5: [
        Offset(0.25, 0.25),
        Offset(0.75, 0.25),
        Offset(0.5, 0.5),
        Offset(0.25, 0.75),
        Offset(0.75, 0.75),
      ],
      6: [
        Offset(0.25, 0.2),
        Offset(0.75, 0.2),
        Offset(0.25, 0.5),
        Offset(0.75, 0.5),
        Offset(0.25, 0.8),
        Offset(0.75, 0.8),
      ],
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: dotPositions[value]!.map((p) {
            return Positioned(
              left: p.dx * w - 5,
              top: p.dy * h - 5,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: dark ? Colors.white54 : Colors.black87,
                    shape: BoxShape.circle,
                  ),
                ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _FriendsInviteList extends StatefulWidget {
  final void Function(Map<String, dynamic> friend) onInvite;
  const _FriendsInviteList({required this.onInvite});

  @override
  State<_FriendsInviteList> createState() => _FriendsInviteListState();
}

class _FriendsInviteListState extends State<_FriendsInviteList> {
  List<dynamic>? _friends;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    try {
      _friends = await FriendsService().getFriendsList();
    } catch (_) {
      _friends = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_friends == null || _friends!.isEmpty) {
      return const Column(
        children: [
          Text(
            "Vous n'avez pas d'amis",
            style: TextStyle(color: Colors.white70),
          ),
          SizedBox(height: 8),
          Text(
            'Ajoute des amis pour jouer',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Invite des amis à rejoindre',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        ..._friends!.map((f) {
          final avatarUrl = f['avatar_url']?.toString();
          final isOnline = f['is_connected'] == true;
          return ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              backgroundImage:
                  avatarUrl != null && avatarUrl.isNotEmpty
                      ? cachedNetworkImage(avatarUrl)
                      : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
            title: Text(
              f['username'] ?? '',
              style: const TextStyle(color: Colors.white),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.person_add,
                color: isOnline ? Colors.amber : Colors.white24,
              ),
              onPressed: isOnline
                  ? () => widget.onInvite(f)
                  : null,
            ),
          );
        }),
      ],
    );
  }
}

class _LudoBoardPainter extends CustomPainter {
  final double cellSize;

  _LudoBoardPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Fond sombre du plateau pour vibe casino
    paint.color = const Color(0xFF1C1C2E);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Fond central plus clair
    paint.color = const Color(0xFF2A2A40);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize),
        Radius.circular(cellSize * 0.2),
      ),
      paint,
    );

    // Bases colorées avec dégradé
    _drawBase(canvas, LudoColor.red, 9, 0);
    _drawBase(canvas, LudoColor.green, 0, 0);
    _drawBase(canvas, LudoColor.yellow, 0, 9);
    _drawBase(canvas, LudoColor.blue, 9, 9);

    // Couloirs maison
    _drawHomeStretch(canvas, LudoColor.green);
    _drawHomeStretch(canvas, LudoColor.red);
    _drawHomeStretch(canvas, LudoColor.yellow);
    _drawHomeStretch(canvas, LudoColor.blue);

    // Chemin principal
    for (var i = 0; i < LudoBoardLayout.pathCoords.length; i++) {
      final c = LudoBoardLayout.pathCoords[i];
      final isSafe = LudoEngine.safeTrackIndices.contains(i);
      paint.color = isSafe
          ? const Color(0xFF3A3A55)
          : const Color(0xFF2A2A40);
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.color = const Color(0xFF4A4A65);
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 0.5;
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.style = PaintingStyle.fill;

      if (isSafe) {
        paint.color = const Color(0xFFD4A017).withValues(alpha: 0.6);
        canvas.drawCircle(
          Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize),
          cellSize * 0.14,
          paint,
        );
        paint.color = const Color(0xFFD4A017).withValues(alpha: 0.2);
        canvas.drawCircle(
          Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize),
          cellSize * 0.28,
          paint,
        );
      }
    }

    // Centre triangulaire
    _drawCenter(canvas);
  }

  void _drawBase(Canvas canvas, LudoColor color, int row, int col) {
    final baseColor = LudoBoardLayout.colorValues[color]!;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [baseColor.withValues(alpha: 0.7), baseColor.withValues(alpha: 0.35)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(
        col * cellSize,
        row * cellSize,
        6 * cellSize,
        6 * cellSize,
      ));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          col * cellSize, row * cellSize, 6 * cellSize, 6 * cellSize,
        ),
        Radius.circular(cellSize * 0.3),
      ),
      paint,
    );

    paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          col * cellSize, row * cellSize, 6 * cellSize, 6 * cellSize,
        ),
        Radius.circular(cellSize * 0.3),
      ),
      paint,
    );
    paint
      ..style = PaintingStyle.fill
      ..strokeWidth = 0;

    paint.color = Colors.white.withValues(alpha: 0.25);
    for (final coords in LudoBoardLayout.baseCoords[color]!) {
      canvas.drawCircle(
        Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize),
        cellSize * 0.32,
        paint,
      );
      paint.color = Colors.white.withValues(alpha: 0.1);
      canvas.drawCircle(
        Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize),
        cellSize * 0.38,
        paint,
      );
      paint.color = Colors.white.withValues(alpha: 0.25);
    }
  }

  void _drawHomeStretch(Canvas canvas, LudoColor color) {
    final baseColor = LudoBoardLayout.colorValues[color]!;
    final paint = Paint()
      ..color = baseColor.withValues(alpha: 0.3);
    for (final c in LudoBoardLayout.homeStretchCoords[color]!) {
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
    }
  }

  void _drawCenter(Canvas canvas) {
    final center = Offset(7.5 * cellSize, 7.5 * cellSize);
    final r = cellSize * 1.5;
    final colors = [
      LudoBoardLayout.colorValues[LudoColor.blue]!,
      LudoBoardLayout.colorValues[LudoColor.red]!,
      LudoBoardLayout.colorValues[LudoColor.green]!,
      LudoBoardLayout.colorValues[LudoColor.yellow]!,
    ];

    for (var i = 0; i < 4; i++) {
      final paint = Paint()..color = colors[i].withValues(alpha: 0.7);
      final path = Path();
      final angle = -math.pi / 4 + i * math.pi / 2;
      path.moveTo(center.dx, center.dy);
      path.arcTo(
        Rect.fromCircle(center: center, radius: r),
        angle,
        math.pi / 2,
        false,
      );
      path.close();
      canvas.drawPath(path, paint);
    }

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1);
    canvas.drawCircle(center, cellSize * 0.8, paint);
    paint.color = const Color(0xFFD4A017).withValues(alpha: 0.3);
    canvas.drawCircle(center, cellSize * 0.5, paint);
    paint.color = const Color(0xFFD4A017).withValues(alpha: 0.6);
    canvas.drawCircle(center, cellSize * 0.2, paint);
  }

  @override
  bool shouldRepaint(covariant _LudoBoardPainter oldDelegate) =>
      oldDelegate.cellSize != cellSize;
}

class _LudoForfeitWarningDialog extends StatefulWidget {
  const _LudoForfeitWarningDialog();

  @override
  State<_LudoForfeitWarningDialog> createState() =>
      _LudoForfeitWarningDialogState();
}

class _LudoForfeitWarningDialogState extends State<_LudoForfeitWarningDialog> {
  int _seconds = 10;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        _timer?.cancel();
        return;
      }
      setState(() {
        _seconds--;
      });
      if (_seconds <= 0) {
        _timer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.orange.shade900,
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
          SizedBox(width: 8),
          Text('Inactivité', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Vous n\'avez pas joué depuis 50s.\nJouez votre coup dans les',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          Text(
            '$_seconds',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'secondes',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          const Text(
            'sinon vous perdez la partie par forfait.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}
