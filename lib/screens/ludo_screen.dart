import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:provider/provider.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../game/ludo/ludo_engine.dart';
import '../providers/auth_provider.dart';
import '../service/ludo_multiplayer_service.dart';
import '../service/stats_service.dart';
import '../widgets/friends_dialog.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class LudoScreen extends StatefulWidget {
  final bool beginGame;
  final List<Map<String, dynamic>> playerSubscribe;
  const LudoScreen({
    super.key,
    this.beginGame = false,
    this.playerSubscribe = const [],
  });

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late LudoEngine _engine;
  Timer? _aiTimer;
  late AnimationController _diceController;
  int _displayDice = 1;
  LudoPawn? _selectedPawn;
  bool _winnerDialogShown = false;
  bool _beginGame = false;
  bool _aiPlaying = false;
  bool _diceRolledThisTurn = false;
  bool _isDraggingDice = false;
  bool _isSlidingDice = false;
  bool _isMultiplayer = false;
  List<LudoHuman> _playerSubscribe = [];
  String _roomCode = '';
  String _playerName = '';
  bool _isRoomReady = false;
  StreamSubscription<Map<String, dynamic>>? _multiplayerSubscription;
  final LudoMultiplayerService _multiplayerService = LudoMultiplayerService();
  final ValueNotifier<List<String>> _participantsNotifier = ValueNotifier([]);
  final List<LudoColor> _participantColorSelection = [];
  bool isHost = true;
  final Set<LudoColor> _disconnectedColors = {};

  Offset _diceDragOffset = Offset.zero;
  Offset _slideVelocity = Offset.zero;
  double _diceSlideAngle = 0;
  Timer? _slideTimer;
  final GlobalKey _stackKey = GlobalKey();
  double _cellSize = 0;
  Timer? _moveTimer;
  int? _movingPawnId;
  LudoColor? _movingPawnColor;
  List<Offset> _movePath = [];
  int _moveIndex = 0;
  dynamic _userProfile;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
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
            ),
          )
          .toList();

      _startMultParticipantGame();
    }

    _userProfile = context.read<AuthProvider?>()?.userProfile;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _aiTimer?.cancel();
    _moveTimer?.cancel();
    _slideTimer?.cancel();
    _multiplayerSubscription?.cancel();
    if (_roomCode.isNotEmpty && _isMultiplayer && _beginGame) {
      final code = _roomCode;
      final host = isHost;
      final name = _playerName;
      String? colorName;
      if (!host && _engine.players.isNotEmpty) {
        try {
          final player = _engine.players.firstWhere(
            (p) => p.namePlayer == name,
            orElse: () => _engine.players.first,
          );
          colorName = player.color.name;
        } catch (_) {}
      }
      Future.microtask(() {
        if (host) {
          _multiplayerService.sendGameEnded(code);
        } else if (colorName != null) {
          _multiplayerService.sendPlayerLeft(code, name, colorName);
        }
        _multiplayerService.disposeRoom(code);
      });
    } else if (_roomCode.isNotEmpty) {
      final code = _roomCode;
      Future.microtask(() => _multiplayerService.disposeRoom(code));
    }
    _participantsNotifier.dispose();
    _diceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      if (_roomCode.isNotEmpty && _isMultiplayer && _beginGame && mounted) {
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
      }
    }
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
      if (mounted) setState(() => _displayDice = value);
    });
    for (var i = 0; i < 6; i++) {
      Future.delayed(Duration(milliseconds: i * 70), () {
        if (mounted) {
          setState(() => _displayDice = math.Random().nextInt(6) + 1);
        }
      });
    }
    await Future.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _displayDice = value);
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
    setState(() => _isMultiplayer = false);
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
          "L'hôte a quitté la partie.",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                (route) => route.isFirst,
              );
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
    _moveIndex = 0;

    _moveTimer?.cancel();
    _moveTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _moveIndex++;
      });
      if (_moveIndex >= _movePath.length) {
        timer.cancel();
        _movingPawnId = null;
        _movingPawnColor = null;
        _movePath = [];
        onComplete();
      }
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

      setState(() {
        _diceDragOffset += _slideVelocity * 0.016;
        _diceSlideAngle += _slideVelocity.distance * 0.0003;

        if (_diceDragOffset.dx < leftBound) {
          _diceDragOffset = Offset(leftBound, _diceDragOffset.dy);
          _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
        } else if (_diceDragOffset.dx > rightBound) {
          _diceDragOffset = Offset(rightBound, _diceDragOffset.dy);
          _slideVelocity = Offset(-_slideVelocity.dx, _slideVelocity.dy);
        }
        if (_diceDragOffset.dy < topBound) {
          _diceDragOffset = Offset(_diceDragOffset.dx, topBound);
          _slideVelocity = Offset(_slideVelocity.dx, -_slideVelocity.dy);
        }
      });
    });
  }

  void _animateDiceBack() {
    const duration = Duration(milliseconds: 300);
    final startOffset = _diceDragOffset;
    final startAngle = _diceSlideAngle;
    final startTime = DateTime.now();

    _slideTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds /
          duration.inMilliseconds;
      final t = elapsed.clamp(0.0, 1.0);
      final easeOut = 1 - (1 - t) * (1 - t);

      setState(() {
        _diceDragOffset = Offset.lerp(startOffset, Offset.zero, easeOut)!;
        _diceSlideAngle = startAngle * (1 - easeOut);
      });

      if (t >= 1) {
        timer.cancel();
        setState(() {
          _isSlidingDice = false;
          _diceDragOffset = Offset.zero;
          _diceSlideAngle = 0;
          _slideVelocity = Offset.zero;
        });
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

  void _rebuildEngineFromSubscribers() {
    final humanPlayers = _playerSubscribe;

    _engine = LudoEngine(
      human: humanPlayers,
      isMultiplayer: true,
      roomCode: _roomCode,
      onStateChange: (snapshot) {
        if (_roomCode.isNotEmpty) {
          _multiplayerService.sendState(_roomCode, snapshot.toJson());
        }
      },
    );
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
      isHost = false;
      _isMultiplayer = true;
      _beginGame = true;
    });

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
              _displayDice = snapshot.lastDice == 0 ? 1 : snapshot.lastDice;
            });
          }
        });
  }

  Future<void> _startMultiplayerGame({required bool createRoom}) async {
    final playerHote = _userProfile;

    final playerFriends = await FriendsService().getFriendsSubscribeToGam();

    const friendColors = [LudoColor.blue, LudoColor.green, LudoColor.yellow];

    final List<LudoHuman> players = [
      LudoHuman(
        name: playerHote!['username'] ?? 'Player',
        color: LudoColor.red,
        id: playerHote['id'],
        avatar: playerHote['avatar_url'],
      ),
      ...playerFriends.take(3).toList().asMap().entries.map(
        (entry) {
          final i = entry.key;
          final e = entry.value;
          return LudoHuman(
            name: e['username'],
            color: friendColors[i],
            id: e['id'],
            avatar: e['avatar_url'],
          );
        },
      ),
    ];

    setState(() {
      _playerSubscribe = players;
    });

    setState(() {
      _playerName = playerHote['username'] ?? 'Player';
      _isMultiplayer = true;
    });

    if (createRoom) {
      final session = await _multiplayerService.createRoom(
        playerName: playerHote['username'] ?? 'Player',
        playerColor: LudoColor.red.name,
      );

      print('Session => ${session.roomCode}');

      setState(() {
        _roomCode = session.roomCode;
        _isRoomReady = true;
      });
      // host is already participant (store names for the notifier)
      _participantsNotifier.value = players
          .map((elt) => elt.name.toString())
          .toList();
      // listen for presence/state
      _multiplayerSubscription = _multiplayerService
          .watchRoom('ludo_global')
          .listen((payload) {
            if (!mounted) return;
            print('=>  response payload = $payload');
            final type = payload['type']?.toString();
            if (type == 'presence') {
              final action = payload['action']?.toString();
              final playerData = payload['player'] as Map<String, dynamic>?;
              if (action == 'join' && playerData != null) {
                final playerName = playerData['name']?.toString() ?? '';
                if (playerName.isNotEmpty) {
                  final list = List<String>.from(_participantsNotifier.value);
                  if (!list.contains(playerName)) list.add(playerName);
                  _participantsNotifier.value = list;
                }
              }
              return;
            }
            if (type == 'color_change') {
              final playerName = payload['player']?.toString() ?? '';
              final newColorStr = payload['color']?.toString() ?? '';
              if (playerName.isEmpty || newColorStr.isEmpty) return;
              final newColor = LudoColor.values.firstWhere(
                (c) => c.name == newColorStr,
                orElse: () => LudoColor.yellow,
              );
              final index = _playerSubscribe.indexWhere(
                (p) => p.name == playerName,
              );
              if (index == -1) return;
              final existingIndex = _playerSubscribe.indexWhere(
                (p) => p.color == newColor && p.name != playerName,
              );
              setState(() {
                if (existingIndex != -1) {
                  final oldColor = _playerSubscribe[index].color;
                  _playerSubscribe[existingIndex] = LudoHuman(
                    name: _playerSubscribe[existingIndex].name,
                    color: oldColor,
                    id: _playerSubscribe[existingIndex].id,
                    avatar: _playerSubscribe[existingIndex].avatar,
                  );
                }
                _playerSubscribe[index] = LudoHuman(
                  name: _playerSubscribe[index].name,
                  color: newColor,
                  id: _playerSubscribe[index].id,
                  avatar: _playerSubscribe[index].avatar,
                );
              });
              _multiplayerService.sendParticipants(
                _roomCode,
                _playerSubscribe
                    .map((p) => {
                          'name': p.name,
                          'color': p.color.name,
                          'id': p.id.toString(),
                          'avatar': p.avatar.toString(),
                        })
                    .toList(),
              );
              return;
            }
            if (type == 'participants') {
              final participantList = payload['participants'] as List<dynamic>?;
              if (participantList != null) {
                final parsed = participantList.map<LudoHuman>((item) {
                  final map = item as Map<String, dynamic>;
                  final colorString = map['color']?.toString() ?? '';
                  final color = LudoColor.values.firstWhere(
                    (c) => c.name == colorString,
                    orElse: () => LudoColor.yellow,
                  );
                  return LudoHuman(
                    name: map['name']?.toString() ?? 'Joueur inconnu',
                    color: color,
                  );
                }).toList();
                setState(() {
                  _playerSubscribe = parsed;
                  _participantsNotifier.value = parsed
                      .map((e) => e.name.toString())
                      .where((name) => name.isNotEmpty)
                      .toList();
                });
            }
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
            if (snapshot.roomCode == session.roomCode) {
              setState(() {
                _engine.applySnapshot(snapshot);
                _beginGame = true;
                _diceRolledThisTurn = snapshot.diceRolled;
                _displayDice = snapshot.lastDice == 0 ? 1 : snapshot.lastDice;
              });
              if (!_engine.currentPlayer.isHuman) {
                _scheduleAiTurn();
              }
            }
          });

      // show participants and ask host to start
      final start = await _showParticipantsConfirmDialog(players);

      _engine = LudoEngine(
        human: _playerSubscribe,
        isMultiplayer: true,
        roomCode: session.roomCode,
        onStateChange: (snapshot) =>
            _multiplayerService.sendState(session.roomCode, snapshot.toJson()),
      );

      if (start == true) {
        _multiplayerService.sendParticipants(
          session.roomCode,
          _playerSubscribe
              .map(
                (player) => {
                  'name': player.name.toString(),
                  'color': _parseColor(player.color).name,
                  'id': player.id.toString(),
                  'avatar': player.avatar.toString(),
                },
              )
              .toList(),
        );
        _multiplayerService.sendGameStart(session.roomCode);
        await _multiplayerService.sendState(
          session.roomCode,
          _engine.snapshot().toJson(),
        );
        for (final friend in playerFriends) {
          final fId = friend['id'];
          if (fId != null) {
            await FriendsService().playingGame(fId.toString());
          }
        }
        setState(() {
          _beginGame = true;
        });
        /* if (!widget.beginGame && isHost) {
          _listenChanelMultiplayerGame();
        } */
      } else {
        // host cancelled, cleanup
        _multiplayerService.disposeRoom(session.roomCode);
        setState(() {
          _isMultiplayer = false;
          _roomCode = '';
          _isRoomReady = false;
        });
      }
      setState(() {});
      return;
    }

    // Join the global platform without asking for a room code
    isHost = false;
    final session = await _multiplayerService.joinRoom(
      playerName: playerHote['username'] ?? 'Player',
      playerColor: LudoColor.yellow.name,
    );
    if (session == null) {
      setState(() {
        _isMultiplayer = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de rejoindre la plateforme.')),
      );
      return;
    }
    setState(() {
      _roomCode = session.roomCode;
      _isRoomReady = true;
      _playerName = playerHote['username'] ?? 'Player';
      _isMultiplayer = true;
      _playerSubscribe = [
        LudoHuman(
          name: playerHote['username'] ?? 'Player',
          color: LudoColor.yellow,
        ),
      ];
      _participantsNotifier.value = [playerHote['username'] ?? 'Player'];
    });

    _engine = LudoEngine(
      human: [
        LudoHuman(
          name: playerHote['username'] ?? 'Player',
          color: LudoColor.yellow,
        ),
      ],
      isMultiplayer: true,
      roomCode: session.roomCode,
      onStateChange: (snapshot) =>
          _multiplayerService.sendState(session.roomCode, snapshot.toJson()),
    );

    // notify host and others we joined
    _multiplayerService.sendJoin(
      session.roomCode,
      playerHote['username'] ?? 'Player',
      LudoColor.yellow.name,
    );

    // update local participants list from service
    _participantsNotifier.value = _multiplayerService
        .getParticipants(session.roomCode)
        .map((player) => player['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    // show waiting dialog for non-host participant
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showParticipantWaitingDialog();
    });

    // listen for presence, participants and state updates
    _multiplayerSubscription = _multiplayerService
        .watchRoom(session.roomCode)
        .listen((payload) {
          if (!mounted) return;
          final type = payload['type']?.toString();
          if (type == 'presence') {
            final action = payload['action']?.toString();
            final playerData = payload['player'] as Map<String, dynamic>?;
            if (action == 'join' && playerData != null) {
              final playerName = playerData['name']?.toString() ?? '';
              if (playerName.isNotEmpty) {
                final list = List<String>.from(_participantsNotifier.value);
                if (!list.contains(playerName)) list.add(playerName);
                _participantsNotifier.value = list;
              }
            }
            return;
          }
          if (type == 'participants') {
            final participantList = payload['participants'] as List<dynamic>?;
            if (participantList != null) {
              final parsed = participantList.map<LudoHuman>((item) {
                final map = item as Map<String, dynamic>;
                final colorString = map['color']?.toString() ?? '';
                final color = LudoColor.values.firstWhere(
                  (c) => c.name == colorString,
                  orElse: () => LudoColor.yellow,
                );
                return LudoHuman(
                  name: map['name']?.toString() ?? 'Joueur inconnu',
                  color: color,
                );
              }).toList();
              setState(() {
                _playerSubscribe = parsed;
                _participantsNotifier.value = parsed
                    .map((e) => e.name.toString())
                    .where((name) => name.isNotEmpty)
                    .toList();
              });
              _rebuildEngineFromSubscribers();
            }
            return;
          }

          if (type == 'start') {
            final participantsFromService = _multiplayerService
                .getParticipants(_roomCode);
            if (_playerSubscribe.length < participantsFromService.length) {
              final parsed = participantsFromService.map<LudoHuman>((item) {
                final colorString = item['color']?.toString() ?? '';
                final color = LudoColor.values.firstWhere(
                  (c) => c.name == colorString,
                  orElse: () => LudoColor.yellow,
                );
                return LudoHuman(
                  name: item['name']?.toString() ?? 'Joueur inconnu',
                  color: color,
                );
              }).toList();
              _playerSubscribe = parsed;
            }
            Navigator.of(context).pop();
            _rebuildEngineFromSubscribers();
            setState(() {
              _beginGame = true;
              _diceRolledThisTurn = false;
            });
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
          if (snapshot.roomCode == session.roomCode) {
            setState(() {
              _engine.applySnapshot(snapshot);
              _beginGame = true;
              _diceRolledThisTurn = snapshot.diceRolled;
              _displayDice = snapshot.lastDice == 0 ? 1 : snapshot.lastDice;
            });
          }
        });

    setState(() {});
  }

  // Room code dialog removed: joining now uses the global Supabase channel.

  Future<bool?> _showParticipantsConfirmDialog(
    List<LudoHuman> playerSubscribe,
  ) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final takenColors = _playerSubscribe
                .map((p) => p.color)
                .toSet();

            return AlertDialog(
              backgroundColor: const Color(0xFF1a1a2e),
              title: const Text(
                'Participants',
                style: TextStyle(color: Colors.white),
              ),
              content: SizedBox(
                width: 280,
                child: ValueListenableBuilder<List<String>>(
                  valueListenable: _participantsNotifier,
                  builder: (context, list, _) {
                    final bool showFriendsList = list.length <= 1;

                    // Sync new joiners into _playerSubscribe
                    while (_playerSubscribe.length < list.length) {
                      final usedColors = _playerSubscribe
                          .map((p) => p.color)
                          .toSet();
                      final freeColor = LudoColor.values.firstWhere(
                        (c) => !usedColors.contains(c),
                        orElse: () => LudoColor.yellow,
                      );
                      _playerSubscribe.add(
                        LudoHuman(
                          name: list[_playerSubscribe.length],
                          color: freeColor,
                        ),
                      );
                    }

                    if (showFriendsList) {
                      return _FriendsInviteList(
                        onInvite: (friend) async {
                          await FriendsService().sendGameRequest(
                            friend['id'],
                          );
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Invitation envoyée à ${friend['username']}',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...List.generate(
                          list.length,
                          (index) {
                            final participant = _playerSubscribe[index];
                            final availableColors = LudoColor.values.where(
                              (c) =>
                                  c == participant.color ||
                                  !takenColors.contains(c),
                            );

                            return ListTile(
                              leading: const Icon(
                                Icons.person,
                                color: Colors.white,
                              ),
                              title: Text(
                                list[index],
                                style: const TextStyle(color: Colors.white),
                              ),
                              trailing: DropdownButton<LudoColor>(
                                value: participant.color,
                                dropdownColor: const Color(0xFF2A2A40),
                                items: availableColors.map((color) {
                                  return DropdownMenuItem<LudoColor>(
                                    value: color,
                                    child: Icon(
                                      Icons.circle,
                                      color:
                                          LudoBoardLayout.colorValues[color],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  final newParticipant = LudoHuman(
                                    name: participant.name,
                                    color: value,
                                    id: participant.id,
                                    avatar: participant.avatar,
                                  );
                                  setDialogState(() {
                                    _playerSubscribe[index] = newParticipant;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Annuler'),
                ),
                if (_participantsNotifier.value.length > 1)
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Démarrer'),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showParticipantWaitingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return ValueListenableBuilder<List<String>>(
            valueListenable: _participantsNotifier,
            builder: (context, list, _) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1a1a2e),
                title: const Text('En attente du lancement...',
                  style: TextStyle(color: Colors.white)),
                content: SizedBox(
                  width: 280,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _playerSubscribe.map((participant) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (participant != _playerSubscribe.first)
                            const Divider(color: Colors.white24),
                          ListTile(
                            leading: Icon(Icons.circle,
                              color: LudoBoardLayout.colorValues[participant.color]),
                            title: Text(participant.name,
                              style: const TextStyle(color: Colors.white)),
                            trailing: participant.name == _playerName
                                ? TextButton(
                                    onPressed: () => _showColorSwapDialog(ctx),
                                    child: const Text('Changer',
                                      style: TextStyle(color: Colors.amber)),
                                  )
                                : null,
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      _multiplayerService.sendPlayerLeft(
                        _roomCode, _playerName, LudoColor.yellow.name,
                      );
                      _multiplayerService.disposeRoom(_roomCode);
                      Navigator.of(ctx).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const HomeScreen()),
                        (route) => route.isFirst,
                      );
                    },
                    child: const Text('Quitter',
                      style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  void _showColorSwapDialog(BuildContext dialogContext) {
    showDialog(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C2E),
        title: const Text('Choisis ta couleur'),
        content: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: LudoColor.values.map((color) {
            final takenBy = _playerSubscribe.cast<LudoHuman?>().firstWhere(
              (p) => p!.color == color,
              orElse: () => null,
            );
            final isMine = takenBy?.name == _playerName;
            final isFree = takenBy == null;
            final baseColor = LudoBoardLayout.colorValues[color]!;
            return GestureDetector(
              onTap: () {
                _multiplayerService.sendColorChange(
                  _roomCode,
                  _playerName,
                  color.name,
                );
                Navigator.pop(ctx);
              },
              child: Container(
                width: 60, height: 60,
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: isMine ? 1.0 : 0.6),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isMine ? Colors.white : Colors.white24,
                    width: isMine ? 3 : 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    isMine ? '✓' : (isFree ? '' : '⇄'),
                    style: TextStyle(
                      color: color == LudoColor.yellow
                          ? Colors.black87 : Colors.white,
                      fontSize: 20, fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
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

  void _restartGame() {
    _aiTimer?.cancel();
    _moveTimer?.cancel();
    _slideTimer?.cancel();
    setState(() {
      _winnerDialogShown = false;
      _engine.reset();
      _displayDice = 1;
      _selectedPawn = null;
      _movingPawnId = null;
      _movingPawnColor = null;
      _movePath = [];
      _aiPlaying = false;
      _diceRolledThisTurn = false;
      _isSlidingDice = false;
      _diceDragOffset = Offset.zero;
      _slideVelocity = Offset.zero;
      _diceSlideAngle = 0;
    });
  }

  Future<void> _finishGameWithStats() async {
    await StatsService().recordGameResult(
      gameName: 'ludo',
      won: _engine.winner == _engine.currentPlayer.color,
      context: context,
    );
  }

  void _showWinnerDialog() {
    if (_winnerDialogShown) return;
    _winnerDialogShown = true;
    final isHumanWin =
        _engine.winner != null && _engine.humanColor.contains(_engine.winner!);
    final winColor = _engine.winner != null
        ? LudoBoardLayout.colorValues[_engine.winner!]!
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
                  color: isHumanWin ? const Color(0xFFD4A017) : Colors.white24,
                  width: 2,
                ),
                boxShadow: [
                  if (isHumanWin)
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
                      isHumanWin ? Icons.emoji_events : Icons.smart_toy,
                      color: isHumanWin
                          ? const Color(0xFFD4A017)
                          : Colors.white54,
                      size: 44,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isHumanWin ? '💰 Victoire !' : 'Partie terminée',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isHumanWin
                        ? '${_engine.winner!.label} empoche la cagnotte !'
                        : '${_engine.winner!.label} remporte la victoire !',
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
                        _restartGame();
                      },
                      child: const Text(
                        'Rejouer',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const HomeScreen()),
                          (route) => route.isFirst,
                        );
                      },
                      child: const Text(
                        'Quitter',
                        style: TextStyle(color: Colors.white38, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        if (isHumanWin) {
          return Stack(children: [const _ConfettiWidget(), dialog]);
        }
        return dialog;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_beginGame) {
      if (_engine.winner != null && !_winnerDialogShown) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _finishGameWithStats();
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
              backgroundColor: const Color(0xFF006400),
              onPressed: () => Navigator.pop(context),
              child: const Icon(Icons.arrow_back, color: Colors.white),
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
                        child: GestureDetector(
                          onTap: /* () { */
                            /* print(
                              'verifier => ${_engine.currentPlayer.id == _userProfile['id']}\n ${_playerSubscribe.map((elt) => elt.id).toList()}\n ${_engine.currentPlayer.id}',
                            );
                            print([!_isDraggingDice, !_isSlidingDice, _engine.currentPlayer.isHuman, _engine.winner == null, !_diceRolledThisTurn, _engine.currentPlayer.id ==
                                        _userProfile['id']]); */
                            !_isDraggingDice &&
                                    !_isSlidingDice &&
                                    _isMyTurn &&
                                    !_diceRolledThisTurn
                                ? _onRollDice
                                : null,
                          /* }, */

                          onPanStart: (_) {
                            _slideTimer?.cancel();
                            setState(() {
                              _isDraggingDice = true;
                              _isSlidingDice = false;
                              _slideVelocity = Offset.zero;
                            });
                          },
                          onPanUpdate: (details) {
                            setState(() {
                              _diceDragOffset += details.delta;
                            });
                          },
                          onPanEnd: (details) {
                            final canRoll =
                                _isDraggingDice &&
                                _isMyTurn &&
                                !_diceRolledThisTurn;

                            _slideVelocity = details.velocity.pixelsPerSecond;

                            if (_slideVelocity.distance > 50 && canRoll) {
                              _isSlidingDice = true;
                              _isDraggingDice = false;
                              _startDiceSlide();
                            } else {
                              setState(() {
                                _isDraggingDice = false;
                                _diceDragOffset = Offset.zero;
                              });
                              if (canRoll) {
                                _onRollDice();
                              }
                            }
                          },
                          child: Transform.translate(
                            offset: _diceDragOffset,
                            child: Transform.rotate(
                              angle: _diceSlideAngle,
                              child: _buildDice(
                                _isMyTurn,
                                _engine,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: _buildTopBar(),
                    ),
                    Positioned(
                      top: 56,
                      right: 12,
                      child: GestureDetector(
                        onTap: _restartGame,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Icon(
                            Icons.refresh,
                            color: Color(0xFFD4A017),
                            size: 18,
                          ),
                        ),
                      ),
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
                          ? NetworkImage(avatarUrl)
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
                await _startMultiplayerGame(createRoom: true);
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
            onPressed: () => Navigator.pop(context),
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
              CustomPaint(
                size: Size(size, size),
                painter: _LudoBoardPainter(cellSize: _cellSize),
              ),
              ..._buildPlayerInfo(),
              ..._buildPawns(_cellSize),
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
        if (isAnimating && _moveIndex < _movePath.length) {
          pos = _movePath[_moveIndex];
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
    final authProvider = context.read<AuthProvider?>();

    return LudoColor.values.map((color) {
      final isHuman = _engine.humanColor.contains(color);

      final matchingPlayer = _playerSubscribe.firstWhere(
        (player) => player.color == color,
        orElse: () => LudoHuman(name: 'Joueur inconnu', color: color),
      );

      final displayName = isHuman ? matchingPlayer.name : 'IA ${color.label}';

      Widget avatar;
      if (isHuman &&
          matchingPlayer.avatar != null &&
          matchingPlayer.avatar!.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 8,
          backgroundImage: NetworkImage(matchingPlayer.avatar!),
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
              child: _displayDice > 0
                  ? _DiceFace(value: _displayDice, dark: !canRoll)
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
    60,
    (_) => _ConfettiParticle(),
  );

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
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
  final double x = math.Random().nextDouble();
  double y = math.Random().nextDouble() * -0.2 - 0.1;
  final double speed = 0.15 + math.Random().nextDouble() * 0.25;
  final double size = 4 + math.Random().nextDouble() * 6;
  final Color color =
      Colors.primaries[math.Random().nextInt(Colors.primaries.length)];
  final double rotation = math.Random().nextDouble() * 6.28;
  final double rotationSpeed = (math.Random().nextDouble() - 0.5) * 6;
}

class _ConfettiPainter extends CustomPainter {
  final List<_ConfettiParticle> particles;
  final double progress;

  _ConfettiPainter(this.particles, this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final y = (p.y + progress * p.speed) % 1.1 - 0.1;
      final x = p.x + math.sin(progress * 4 + p.x * 10) * 0.02;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.rotation + progress * p.rotationSpeed);

      final paint = Paint()
        ..color = p.color.withValues(alpha: (1 - (y.clamp(0, 1))) * 0.9);
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
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
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
                      ? NetworkImage(avatarUrl)
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
