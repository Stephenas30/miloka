import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart';
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
import '../utils/game_wake_lock.dart';
import '../widgets/friends_dialog.dart';
import '../widgets/game_result_animation.dart';
import 'home_screen.dart';
import 'ludo_lobby_screen.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class _LudoTokens {
  static const card = Color(0xFFFFFDF7);
  static const cardBorder = Color(0xFFE7DAC0);
  static const ink = Color(0xFF2B2320);
  static const inkSoft = Color(0xFF6B5D4F);
  static const inkFaint = Color(0xFF9A8C7C);
  static const sand = Color(0xFFE4D7BE);
  static const sandDeep = Color(0xFFCBBB9C);
  static const cell = Color(0xFFFAF3E4);
  static const gold = Color(0xFFE3A008);
  static const goldDeep = Color(0xFFB87A05);
  static const goldSoft = Color(0xFFF6C453);
  static const red = Color(0xFFFF5A5F);
  static const redDeep = Color(0xFFD9484F);
  static const redLight = Color(0xFFFF8A87);
  static const green = Color(0xFF2FBF71);
  static const greenDeep = Color(0xFF1F9A55);
  static const greenLight = Color(0xFF6FE3A2);
  static const yellow = Color(0xFFFFC93C);
  static const yellowDeep = Color(0xFFCF8F0A);
  static const yellowLight = Color(0xFFFFE28A);
  static const blue = Color(0xFF3DA5F4);
  static const blueDeep = Color(0xFF1F7FCC);
  static const blueLight = Color(0xFF7ECBF9);
}

class _Candy {
  final Color light;
  final Color base;
  final Color deep;
  const _Candy(this.light, this.base, this.deep);
}

const _candyPieces = {
  LudoColor.red: _Candy(_LudoTokens.redLight, _LudoTokens.red, _LudoTokens.redDeep),
  LudoColor.green: _Candy(_LudoTokens.greenLight, _LudoTokens.green, _LudoTokens.greenDeep),
  LudoColor.yellow: _Candy(_LudoTokens.yellowLight, _LudoTokens.yellow, _LudoTokens.yellowDeep),
  LudoColor.blue: _Candy(_LudoTokens.blueLight, _LudoTokens.blue, _LudoTokens.blueDeep),
};

const _billardTitre = 'BillardTitre';
const _billardLora = 'BillardLora';

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
  Ticker? _slideTicker;
  AnimationController? _diceBackController;
  Duration _lastPhysicsTick = Duration.zero;
  double? _slideTopBound;
  double? _slideLeftBound;
  double? _slideRightBound;
  final GlobalKey _stackKey = GlobalKey();
  double _cellSize = 0;
  int? _movingPawnId;
  LudoColor? _movingPawnColor;
  List<Offset> _movePath = [];
  dynamic _userProfile;

  @override
  void initState() {
    super.initState();
    GameWakeLock.acquire();
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
    GameWakeLock.release();
    _slideTicker?.stop();
    _slideTicker?.dispose();
    _diceBackController?.dispose();
    _aiTimer?.cancel();
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
        backgroundColor: _LudoTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Partie terminée',
          style: TextStyle(
            color: _LudoTokens.ink,
            fontFamily: _billardTitre,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'La partie a été interrompue.',
          style: TextStyle(
            color: _LudoTokens.inkSoft,
            fontFamily: _billardLora,
          ),
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
            child: const Text(
              'OK',
              style: TextStyle(
                color: _LudoTokens.goldDeep,
                fontFamily: _billardLora,
                fontWeight: FontWeight.w800,
              ),
            ),
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
    _slideTicker?.stop();
    _slideTicker?.dispose();
    _slideTicker = null;
    _lastPhysicsTick = Duration.zero;

    final renderBox =
        _stackKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final stackSize = renderBox.size;
    final diceSize = 60.0;
    const bottomPadding = 24.0;
    _slideTopBound = -stackSize.height + bottomPadding + diceSize;
    _slideLeftBound = -stackSize.width / 2 + diceSize / 2;
    _slideRightBound = stackSize.width / 2 - diceSize / 2;

    _slideTicker = Ticker(_diceSlideTick)..start();
  }

  void _diceSlideTick(Duration elapsed) {
    final dt = _lastPhysicsTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastPhysicsTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastPhysicsTick = elapsed;
    final frictionStep = math.pow(0.96, dt / 0.016).toDouble();
    _slideVelocity = Offset(_slideVelocity.dx * frictionStep, _slideVelocity.dy * frictionStep);

    if (_slideVelocity.distance < 20.0) {
      _slideTicker?.stop();
      _slideTicker?.dispose();
      _slideTicker = null;
      _animateDiceBack();
      return;
    }

    _diceDragOffset.value += _slideVelocity * dt;
    _diceSlideAngle.value += _slideVelocity.distance * dt * 0.01875;

    if (_diceDragOffset.value.dx < _slideLeftBound!) {
      _diceDragOffset.value = Offset(_slideLeftBound!, _diceDragOffset.value.dy);
      _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
    } else if (_diceDragOffset.value.dx > _slideRightBound!) {
      _diceDragOffset.value = Offset(_slideRightBound!, _diceDragOffset.value.dy);
      _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
    }
    if (_diceDragOffset.value.dy < _slideTopBound!) {
      _diceDragOffset.value = Offset(_diceDragOffset.value.dx, _slideTopBound!);
      _slideVelocity = Offset(_slideVelocity.dx, -_slideVelocity.dy);
    }
  }

  void _animateDiceBack() {
    const duration = Duration(milliseconds: 300);
    final startOffset = _diceDragOffset.value;
    final startAngle = _diceSlideAngle.value;

    _diceBackController?.dispose();
    final controller = AnimationController(vsync: this, duration: duration);
    _diceBackController = controller;
    controller
      ..addListener(() {
        final easeOut = Curves.easeOutQuad.transform(controller.value);
        _diceDragOffset.value =
            Offset.lerp(startOffset, Offset.zero, easeOut)!;
        _diceSlideAngle.value = startAngle * (1 - easeOut);
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        _isSlidingDice.value = false;
        _diceDragOffset.value = Offset.zero;
        _diceSlideAngle.value = 0;
        _slideVelocity = Offset.zero;
        controller.dispose();
        if (identical(_diceBackController, controller)) {
          _diceBackController = null;
        }
        _onRollDice();
      })
      ..forward();
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
          backgroundColor: _LudoTokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Center(
            child: Text(
              'Choisis ta couleur',
              style: TextStyle(
                color: _LudoTokens.ink,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                fontFamily: _billardTitre,
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
                  style: TextStyle(
                    color: _LudoTokens.inkSoft,
                    fontSize: 13,
                    fontFamily: _billardLora,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColor == color;
                    final candy = _candyPieces[color]!;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [candy.light, candy.base, candy.deep],
                            stops: const [0, 0.45, 1],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? _LudoTokens.goldDeep
                                : Colors.white.withValues(alpha: 0.8),
                            width: isSelected ? 4 : 2,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: _LudoTokens.gold.withValues(alpha: 0.6),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            BoxShadow(
                              color: candy.deep.withValues(alpha: 0.45),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            color.label,
                            style: TextStyle(
                              color: color == LudoColor.yellow
                                  ? _LudoTokens.ink
                                  : Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              fontFamily: _billardLora,
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
                          ? _LudoTokens.gold
                          : _LudoTokens.sand,
                      foregroundColor: selectedColor != null
                          ? _LudoTokens.ink
                          : _LudoTokens.inkFaint,
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
                    child: const Text(
                      'C\'est parti !',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFamily: _billardLora,
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
          backgroundColor: _LudoTokens.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: const Center(
            child: Text(
              'Local multi',
              style: TextStyle(
                color: _LudoTokens.ink,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                fontFamily: _billardTitre,
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
                  style: TextStyle(
                    color: _LudoTokens.inkSoft,
                    fontSize: 13,
                    fontFamily: _billardLora,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColors.contains(color);
                    final candy = _candyPieces[color]!;
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
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: isSelected
                                ? [candy.light, candy.base, candy.deep]
                                : [candy.base, candy.deep],
                            stops: isSelected
                                ? const [0, 0.45, 1]
                                : const [0, 1],
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? _LudoTokens.goldDeep
                                : Colors.white.withValues(alpha: 0.8),
                            width: isSelected ? 3.5 : 2,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: _LudoTokens.gold.withValues(alpha: 0.6),
                                blurRadius: 14,
                                spreadRadius: 2,
                              ),
                            BoxShadow(
                              color: candy.deep.withValues(alpha: 0.35),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
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
                                      ? _LudoTokens.ink
                                      : Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: _billardLora,
                                ),
                              ),
                              if (isSelected)
                                Text(
                                  '${selectedColors.toList().indexOf(color) + 1}',
                                  style: TextStyle(
                                    color: color == LudoColor.yellow
                                        ? _LudoTokens.inkSoft
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
                            color: _LudoTokens.inkFaint,
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
                        style: TextStyle(
                          color: _LudoTokens.inkSoft,
                          fontFamily: _billardLora,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: selectedColors.length >= 2
                            ? _LudoTokens.gold
                            : _LudoTokens.sand,
                        foregroundColor: selectedColors.length >= 2
                            ? _LudoTokens.ink
                            : _LudoTokens.inkFaint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                        elevation: selectedColors.length >= 2 ? 4 : 0,
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
                          fontWeight: FontWeight.w800,
                          fontFamily: _billardLora,
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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => GameResultAnimation(
        won: iWon,
        title: iWon ? 'VICTOIRE !' : 'DÉFAITE',
        subtitle: iWon
            ? '${winner!.label} remporte la victoire !'
            : '${winner?.label ?? 'L’adversaire'} a gagné. Retente ta chance !',
        actions: [
          GameResultAction(
            label: 'Retour au lobby',
            color: const Color(0xFF9A5424),
            onPressed: () {
              Navigator.pop(dialogContext);
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
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLeaveGame() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _LudoTokens.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Quitter la partie ?',
          style: TextStyle(
            color: _LudoTokens.ink,
            fontFamily: _billardTitre,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: const Text(
          'Êtes-vous sûr de vouloir quitter la partie ?',
          style: TextStyle(
            color: _LudoTokens.inkSoft,
            fontFamily: _billardLora,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Annuler',
              style: TextStyle(
                color: _LudoTokens.inkSoft,
                fontFamily: _billardLora,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Quitter',
              style: TextStyle(
                color: _LudoTokens.redDeep,
                fontFamily: _billardLora,
                fontWeight: FontWeight.w800,
              ),
            ),
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
              backgroundColor: _LudoTokens.card,
              shape: const CircleBorder(
                side: BorderSide(color: _LudoTokens.cardBorder, width: 1.5),
              ),
              elevation: 6,
              onPressed: _confirmLeaveGame,
              child: const Icon(Icons.arrow_back, color: _LudoTokens.ink),
            )
          : null,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.jpg'),
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
                                _slideTicker?.stop();
                                _slideTicker?.dispose();
                                _slideTicker = null;
                                _diceBackController?.dispose();
                                _diceBackController = null;
                                _lastPhysicsTick = Duration.zero;
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
            decoration: const BoxDecoration(
              color: Colors.black54,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_alt, color: Colors.white, size: 20),
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
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
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
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.all(Radius.circular(20)),
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
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
        Positioned(
          top: 130,
          left: 26,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -0.18,
              child: _PawnToken(
                size: 54,
                candy: _candyPieces[LudoColor.red]!,
              ),
            ),
          ),
        ),
        Positioned(
          top: 180,
          right: 30,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: 0.22,
              child: _PawnToken(
                size: 46,
                candy: _candyPieces[LudoColor.blue]!,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 105,
          left: 36,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: 0.15,
              child: _PawnToken(
                size: 48,
                candy: _candyPieces[LudoColor.green]!,
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 150,
          right: 34,
          child: IgnorePointer(
            child: Transform.rotate(
              angle: -0.2,
              child: _PawnToken(
                size: 56,
                candy: _candyPieces[LudoColor.yellow]!,
              ),
            ),
          ),
        ),
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'LUDO',
                style: TextStyle(
                  fontFamily: _billardTitre,
                  fontSize: 74,
                  fontWeight: FontWeight.w900,
                  color: _LudoTokens.card,
                  letterSpacing: 8,
                  height: 0.95,
                  shadows: [
                    Shadow(
                      color: _LudoTokens.goldSoft,
                      offset: Offset(0, 4),
                      blurRadius: 0,
                    ),
                    Shadow(
                      color: Colors.black54,
                      offset: Offset(0, 10),
                      blurRadius: 16,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_LudoTokens.goldSoft, _LudoTokens.gold],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _LudoTokens.goldDeep, width: 2),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x59B87A05),
                      blurRadius: 0,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.monetization_on, color: _LudoTokens.ink, size: 17),
                    SizedBox(width: 8),
                    Text(
                      'TENTE TA CHANCE',
                      style: TextStyle(
                        color: _LudoTokens.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        fontFamily: _billardLora,
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 38),
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
            backgroundColor: _LudoTokens.card,
            shape: const CircleBorder(
              side: BorderSide(color: _LudoTokens.cardBorder, width: 1.5),
            ),
            elevation: 6,
            onPressed: _quitGame,
            child: const Icon(Icons.arrow_back, color: _LudoTokens.ink),
          ),
        ),
      ],
    );
  }

  Widget _buildGameChip(String label, LudoColor color, IconData icon, VoidCallback onTap) {
    final candy = _candyPieces[color]!;
    final darkText = color == LudoColor.yellow;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 222,
        height: 66,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [candy.light, candy.base, candy.deep],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.45, 1],
          ),
          borderRadius: BorderRadius.circular(33),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.75),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: candy.deep,
              blurRadius: 0,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: candy.deep.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              left: 6,
              right: 6,
              top: 3,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.45),
                      Colors.white.withValues(alpha: 0),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: darkText ? _LudoTokens.ink : Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: darkText ? _LudoTokens.ink : Colors.white,
                    fontFamily: _billardLora,
                    letterSpacing: 1.2,
                    shadows: darkText
                        ? null
                        : const [
                            Shadow(
                              color: Color(0x55000000),
                              offset: Offset(0, 2),
                              blurRadius: 2,
                            ),
                          ],
                  ),
                ),
              ],
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
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.fromLTRB(28, 26, 28, 26),
          decoration: BoxDecoration(
            color: _LudoTokens.card,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: _LudoTokens.cardBorder, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x2E2B2320),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: _LudoTokens.goldSoft,
                border: Border.fromBorderSide(
                  BorderSide(color: _LudoTokens.gold, width: 3),
                ),
              ),
              child: const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(_LudoTokens.goldDeep),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'En attente du host...',
              style: TextStyle(
                color: _LudoTokens.ink,
                fontSize: 24,
                fontWeight: FontWeight.w900,
                fontFamily: _billardTitre,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              _roomCode.isNotEmpty
                  ? 'Salle : $_roomCode'
                  : 'Connexion en cours...',
              style: const TextStyle(
                color: _LudoTokens.inkSoft,
                fontSize: 15,
                fontFamily: _billardLora,
              ),
            ),
            const SizedBox(height: 22),
            ValueListenableBuilder<List<String>>(
              valueListenable: _participantsNotifier,
              builder: (context, list, _) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 6,
                      ),
                      decoration: const BoxDecoration(
                        color: _LudoTokens.cell,
                        borderRadius: BorderRadius.all(Radius.circular(20)),
                        border: Border.fromBorderSide(
                          BorderSide(color: _LudoTokens.sand, width: 1.5),
                        ),
                      ),
                      child: Text(
                        'Participants (${list.length})',
                        style: const TextStyle(
                          color: _LudoTokens.inkSoft,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          fontFamily: _billardLora,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'Aucun participant détecté',
                          style: TextStyle(color: _LudoTokens.inkFaint, fontSize: 14),
                        ),
                      )
                    else
                      ...list.map(
                        (name) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: _LudoTokens.inkFaint,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: const TextStyle(
                                  color: _LudoTokens.ink,
                                  fontSize: 15,
                                  fontFamily: _billardLora,
                                  fontWeight: FontWeight.w600,
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
                backgroundColor: _LudoTokens.sand,
                foregroundColor: _LudoTokens.ink,
                side: const BorderSide(color: _LudoTokens.sandDeep),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                elevation: 0,
                textStyle: const TextStyle(
                  fontFamily: _billardLora,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1,
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
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(top: 56, left: 16, right: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              color: _LudoTokens.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _candyPieces[_engine.currentPlayer.color]!.base,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x2B2B2320),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _candyPieces[_engine.currentPlayer.color]!.light,
                        _candyPieces[_engine.currentPlayer.color]!.deep,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _engine.currentPlayer.isHuman
                        ? Icons.person
                        : Icons.smart_toy,
                    size: 17,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    _engine.message,
                    style: const TextStyle(
                      color: _LudoTokens.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      fontFamily: _billardLora,
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
        var pos = LudoBoardLayout.pawnPosition(pawn, cellSize);
        var hop = 0.0;
        var squash = 1.0;
        if (isAnimating && _movePath.isNotEmpty) {
          final t = (_moveController.value * (_movePath.length - 1))
              .clamp(0.0, (_movePath.length - 1).toDouble());
          final idx = t.floor();
          final next = idx + 1 < _movePath.length ? idx + 1 : idx;
          final segment = t - idx;
          pos = Offset.lerp(_movePath[idx], _movePath[next], segment)!;
          hop = math.sin(segment * math.pi) * cellSize * 0.22;
          squash = 1 - 0.16 * math.sin(segment * math.pi);
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
          hop: hop,
          squash: squash,
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

        final pawnSize = cellSize * 0.64;
        widgets.add(
          Positioned(
            left: renderPos.dx - pawnSize / 2,
            top: renderPos.dy - pawnSize / 2,
            child: GestureDetector(
              onTap: info.isSelectable ? () => _onPawnTap(info.pawn) : null,
              child: _PawnToken(
                size: pawnSize,
                candy: _candyPieces[info.playerColor]!,
                isSelected: info.isSelected,
                isSelectable: info.isSelectable,
                finished: info.pawn.finished,
                lift: info.hop,
                squash: info.squash,
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

      final candy = _candyPieces[color]!;
      final isActive =
          _engine.players.isNotEmpty &&
          _engine.currentPlayer.color == color &&
          _engine.winner == null;
      final finishedCount = player.pawns.where((p) => p.finished).length;
      final darkChip = color == LudoColor.yellow;
      final chipTextColor = darkChip ? _LudoTokens.ink : Colors.white;

      return Positioned(
        left: color == LudoColor.green || color == LudoColor.red ? 6 : null,
        right: color == LudoColor.yellow || color == LudoColor.blue ? 6 : null,
        top: color == LudoColor.green || color == LudoColor.yellow ? 6 : null,
        bottom: color == LudoColor.red || color == LudoColor.blue ? 6 : null,
        child: Transform.scale(
          scale: isActive ? 1.08 : 1,
          alignment: color == LudoColor.green || color == LudoColor.yellow
              ? Alignment.topLeft
              : Alignment.bottomLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [candy.light, candy.base, candy.deep],
                stops: const [0, 0.5, 1],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isActive ? _LudoTokens.gold : Colors.white.withValues(alpha: 0.7),
                width: isActive ? 2.5 : 1.5,
              ),
              boxShadow: [
                if (isActive)
                  BoxShadow(
                    color: _LudoTokens.gold.withValues(alpha: 0.65),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                const BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    avatar,
                    if (displayName.isNotEmpty) ...[
                      const SizedBox(width: 5),
                      Text(
                        displayName,
                        style: TextStyle(
                          color: chipTextColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          fontFamily: _billardLora,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    4,
                    (i) => Container(
                      margin: const EdgeInsets.only(right: 3),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < finishedCount
                            ? _LudoTokens.goldSoft
                            : Colors.white.withValues(alpha: 0.35),
                        border: i < finishedCount
                            ? Border.all(color: _LudoTokens.goldDeep, width: 1)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  Widget _buildDice(bool canRoll, LudoEngine engine) {
    final candy = _candyPieces[engine.currentPlayer.color]!;
    return AnimatedBuilder(
      animation: _diceController,
      builder: (context, child) {
        final bump = 1 + 0.22 * math.sin(_diceController.value * math.pi);
        return Transform.rotate(
          angle: _diceController.value * math.pi * 2,
          child: Transform.scale(
            scale: bump,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: canRoll
                      ? const [_LudoTokens.card, Color(0xFFEDE6D6)]
                      : const [Color(0xFF8A8175), Color(0xFF5F584E)],
                ),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: canRoll ? candy.base : _LudoTokens.sandDeep,
                  width: 3,
                ),
                boxShadow: [
                  BoxShadow(
                    color: candy.deep.withValues(alpha: canRoll ? 0.55 : 0.2),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 6,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 8,
                    right: 8,
                    top: 4,
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: canRoll ? 0.9 : 0.25),
                            Colors.white.withValues(alpha: 0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  Center(
                    child: _displayDice.value > 0
                        ? _DiceFace(value: _displayDice.value, dark: !canRoll)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PawnToken extends StatelessWidget {
  const _PawnToken({
    required this.size,
    required this.candy,
    this.isSelected = false,
    this.isSelectable = false,
    this.finished = false,
    this.lift = 0,
    this.squash = 1,
  });

  final double size;
  final _Candy candy;
  final bool isSelected;
  final bool isSelectable;
  final bool finished;
  final double lift;
  final double squash;

  @override
  Widget build(BuildContext context) {
    final body = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (isSelectable)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _LudoTokens.gold,
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _LudoTokens.gold.withValues(alpha: 0.55),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: size * 0.14,
            right: size * 0.14,
            child: Container(
              height: size * 0.17,
              decoration: const BoxDecoration(
                color: Color(0x332B2320),
                borderRadius: BorderRadius.all(Radius.circular(8)),
              ),
            ),
          ),
          Positioned(
            left: size * 0.15,
            bottom: size * 0.09,
            child: Container(
              width: size * 0.70,
              height: size * 0.56,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [candy.light, candy.base, candy.deep],
                  stops: const [0, 0.35, 1],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(size * 0.32),
                  topRight: Radius.circular(size * 0.32),
                  bottomLeft: Radius.circular(size * 0.17),
                  bottomRight: Radius.circular(size * 0.17),
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.65),
                  width: 1.3,
                ),
              ),
            ),
          ),
          Positioned(
            left: size * 0.26,
            bottom: size * 0.50,
            child: Container(
              width: size * 0.48,
              height: size * 0.12,
              decoration: BoxDecoration(
                color: candy.deep,
                borderRadius: BorderRadius.circular(size * 0.06),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 1.5,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: size * 0.03,
            left: size * 0.27,
            child: Container(
              width: size * 0.46,
              height: size * 0.46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.38, -0.42),
                  radius: 1.0,
                  colors: [
                    Colors.white,
                    candy.light,
                    candy.base,
                    candy.deep,
                  ],
                  stops: const [0, 0.22, 0.68, 1],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
            ),
          ),
          if (finished)
            Positioned(
              top: size * 0.13,
              left: size * 0.375,
              child: Icon(
                Icons.star_rounded,
                color: Colors.white,
                size: size * 0.25,
                shadows: const [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 1.5,
                    offset: Offset(0, 0.5),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Transform.translate(
      offset: Offset(0, -lift),
      child: Transform.scale(
        scaleX: 1 + (1 - squash) * 0.85,
        scaleY: squash,
        alignment: Alignment.bottomCenter,
        child: AnimatedScale(
          scale: isSelected ? 1.16 : 1,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: body,
        ),
      ),
    );
  }
}

class _PawnRenderInfo {
  final LudoPawn pawn;
  final Offset pos;
  final bool isSelectable;
  final bool isSelected;
  final bool isAnimating;
  final LudoColor playerColor;
  final double hop;
  final double squash;

  const _PawnRenderInfo({
    required this.pawn,
    required this.pos,
    required this.isSelectable,
    required this.isSelected,
    required this.isAnimating,
    required this.playerColor,
    this.hop = 0,
    this.squash = 1,
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
              left: p.dx * w - 6,
              top: p.dy * h - 6,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    radius: 0.95,
                    colors: dark
                        ? const [Colors.white70, Colors.white38, Color(0x55FFFFFF)]
                        : const [Color(0xFF5A4F42), _LudoTokens.ink, Color(0xFF171009)],
                  ),
                  boxShadow: dark
                      ? null
                      : const [
                          BoxShadow(
                            color: Color(0x40000000),
                            blurRadius: 1.5,
                            offset: Offset(0.5, 1),
                          ),
                        ],
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
            style: TextStyle(color: _LudoTokens.inkSoft),
          ),
          SizedBox(height: 8),
          Text(
            'Ajoute des amis pour jouer',
            style: TextStyle(color: _LudoTokens.inkFaint, fontSize: 12),
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
            style: TextStyle(color: _LudoTokens.inkSoft, fontSize: 13),
          ),
        ),
        ..._friends!.map((f) {
          final avatarUrl = f['avatar_url']?.toString();
          final isOnline = f['is_connected'] == true;
          return ListTile(
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: _LudoTokens.sand,
              backgroundImage:
                  avatarUrl != null && avatarUrl.isNotEmpty
                      ? cachedNetworkImage(avatarUrl)
                      : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? const Icon(Icons.person, color: _LudoTokens.ink)
                  : null,
            ),
            title: Text(
              f['username'] ?? '',
              style: const TextStyle(color: _LudoTokens.ink),
            ),
            trailing: IconButton(
              icon: Icon(
                Icons.person_add,
                color: isOnline ? _LudoTokens.goldDeep : _LudoTokens.sandDeep,
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
    final frame = cellSize * 0.32;

    final frameRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(cellSize * 0.55),
    );
    canvas.drawRRect(
      frameRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEDE1C8), Color(0xFFCDBFA0)],
        ).createShader(frameRect.outerRect),
    );
    canvas.drawRRect(
      frameRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.05
        ..color = _LudoTokens.sandDeep,
    );

    final playRect = Rect.fromLTWH(
      frame,
      frame,
      size.width - 2 * frame,
      size.height - 2 * frame,
    );
    final playRRect = RRect.fromRectAndRadius(
      playRect,
      Radius.circular(cellSize * 0.34),
    );
    canvas.drawRRect(
      playRRect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0, -0.18),
          radius: 1.15,
          colors: const [Color(0xFFFFFDF6), Color(0xFFF3EADA)],
        ).createShader(playRect),
    );

    canvas.save();
    canvas.clipRRect(playRRect);
    final dotPaint = Paint()..color = const Color(0x141F1810);
    for (var row = 0; row < LudoBoardLayout.gridSize; row++) {
      for (var col = 0; col < LudoBoardLayout.gridSize; col++) {
        canvas.drawCircle(
          Offset((col + 0.5) * cellSize, (row + 0.5) * cellSize),
          cellSize * 0.05,
          dotPaint,
        );
      }
    }
    canvas.restore();

    _drawBase(canvas, LudoColor.red, 9, 0);
    _drawBase(canvas, LudoColor.green, 0, 0);
    _drawBase(canvas, LudoColor.yellow, 0, 9);
    _drawBase(canvas, LudoColor.blue, 9, 9);

    _drawHomeStretch(canvas, LudoColor.green);
    _drawHomeStretch(canvas, LudoColor.red);
    _drawHomeStretch(canvas, LudoColor.yellow);
    _drawHomeStretch(canvas, LudoColor.blue);

    final cellRadius = Radius.circular(cellSize * 0.18);
    for (var i = 0; i < LudoBoardLayout.pathCoords.length; i++) {
      final c = LudoBoardLayout.pathCoords[i];
      final isSafe = LudoEngine.safeTrackIndices.contains(i);
      final cellRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          c[0] * cellSize + cellSize * 0.04,
          c[1] * cellSize + cellSize * 0.04,
          cellSize * 0.92,
          cellSize * 0.92,
        ),
        cellRadius,
      );
      canvas.drawRRect(
        cellRect,
        Paint()..color = isSafe ? const Color(0xFFFFE9AC) : _LudoTokens.cell,
      );
      canvas.drawRRect(
        cellRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = isSafe ? _LudoTokens.gold : _LudoTokens.sandDeep,
      );

      if (isSafe) {
        final center =
            Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize);
        canvas.drawCircle(
          center,
          cellSize * 0.34,
          Paint()..color = _LudoTokens.gold.withValues(alpha: 0.22),
        );
        _drawStar(
          canvas,
          center,
          cellSize * 0.17,
          Paint()..color = _LudoTokens.goldDeep,
        );
      }
    }

    _drawCenter(canvas);

    canvas.drawRRect(
      playRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.035
        ..color = _LudoTokens.gold.withValues(alpha: 0.85),
    );
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? radius : radius * 0.45;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawBase(Canvas canvas, LudoColor color, int row, int col) {
    final candy = _candyPieces[color]!;
    final baseRect = Rect.fromLTWH(
      col * cellSize,
      row * cellSize,
      6 * cellSize,
      6 * cellSize,
    );
    final baseRRect = RRect.fromRectAndRadius(
      baseRect,
      Radius.circular(cellSize * 0.42),
    );
    canvas.drawRRect(
      baseRRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [candy.light, candy.base, candy.deep],
          stops: const [0, 0.52, 1],
        ).createShader(baseRect),
    );
    canvas.drawRRect(
      baseRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.07
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      baseRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = candy.deep.withValues(alpha: 0.55),
    );

    for (final coords in LudoBoardLayout.baseCoords[color]!) {
      final center =
          Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize);
      canvas.drawCircle(
        center + Offset(0, cellSize * 0.05),
        cellSize * 0.36,
        Paint()..color = candy.deep.withValues(alpha: 0.5),
      );
      canvas.drawCircle(
        center,
        cellSize * 0.36,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
      canvas.drawCircle(
        center,
        cellSize * 0.23,
        Paint()..color = candy.base.withValues(alpha: 0.4),
      );
    }
  }

  void _drawHomeStretch(Canvas canvas, LudoColor color) {
    final candy = _candyPieces[color]!;
    final coords = LudoBoardLayout.homeStretchCoords[color]!;
    final horizontal = coords.first[0] != coords.last[0];
    for (final c in coords) {
      final rect = Rect.fromLTWH(
        c[0] * cellSize + cellSize * 0.04,
        c[1] * cellSize + cellSize * 0.04,
        cellSize * 0.92,
        cellSize * 0.92,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.18)),
        Paint()
          ..shader = LinearGradient(
            begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
            end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
            colors: [
              candy.base.withValues(alpha: 0.75),
              candy.light.withValues(alpha: 0.35),
            ],
          ).createShader(rect),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cellSize * 0.18)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = candy.deep.withValues(alpha: 0.5),
      );
    }
  }

  void _drawCenter(Canvas canvas) {
    final center = Offset(7.5 * cellSize, 7.5 * cellSize);
    final r = cellSize * 1.5;
    final colors = [
      _candyPieces[LudoColor.blue]!.base,
      _candyPieces[LudoColor.red]!.base,
      _candyPieces[LudoColor.green]!.base,
      _candyPieces[LudoColor.yellow]!.base,
    ];

    for (var i = 0; i < 4; i++) {
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
      canvas.drawPath(path, Paint()..color = colors[i]);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    canvas.drawCircle(
      center,
      cellSize * 0.78,
      Paint()..color = _LudoTokens.card,
    );
    canvas.drawCircle(
      center,
      cellSize * 0.78,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.07
        ..color = _LudoTokens.gold,
    );
    _drawStar(
      canvas,
      center,
      cellSize * 0.42,
      Paint()..color = _LudoTokens.goldDeep,
    );
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
      backgroundColor: _LudoTokens.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _LudoTokens.redDeep, size: 28),
          SizedBox(width: 8),
          Text(
            'Inactivité',
            style: TextStyle(
              color: _LudoTokens.ink,
              fontWeight: FontWeight.w900,
              fontFamily: _billardTitre,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Vous n\'avez pas joué depuis 50s.\nJouez votre coup dans les',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _LudoTokens.inkSoft,
              fontSize: 15,
              fontFamily: _billardLora,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _LudoTokens.redDeep.withValues(alpha: 0.12),
              border: Border.all(color: _LudoTokens.redDeep, width: 2.5),
            ),
            child: Center(
              child: Text(
                '$_seconds',
                style: const TextStyle(
                  color: _LudoTokens.redDeep,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  fontFamily: _billardTitre,
                ),
              ),
            ),
          ),
          const Text(
            'secondes',
            style: TextStyle(
              color: _LudoTokens.inkSoft,
              fontSize: 14,
              fontFamily: _billardLora,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'sinon vous perdez la partie par forfait.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _LudoTokens.inkFaint,
              fontSize: 13,
              fontFamily: _billardLora,
            ),
          ),
        ],
      ),
    );
  }
}
