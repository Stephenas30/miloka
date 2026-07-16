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
    with SingleTickerProviderStateMixin {
  late final LudoEngine _engine;
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
    _aiTimer?.cancel();
    _moveTimer?.cancel();
    _slideTimer?.cancel();
    _multiplayerSubscription?.cancel();
    if (_roomCode.isNotEmpty) {
      _multiplayerService.disposeRoom(_roomCode);
    }
    _participantsNotifier.dispose();
    _diceController.dispose();
    super.dispose();
  }

  void _scheduleAiTurn() {
    if (_engine.winner != null || _engine.currentPlayer.isHuman) return;
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

  void _onRollDice() {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman ||
        _diceRolledThisTurn) {
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
    if (_engine.winner != null || !_engine.currentPlayer.isHuman) {
      return;
    }
    if (!_engine.canMovePawn(pawn)) return;

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

          final snapshot = LudoGameSnapshot.fromJson(payload);
          if (snapshot.roomCode == 'ludo_global') {
            setState(() {
              _engine.applySnapshot(snapshot);
              _diceRolledThisTurn = snapshot.diceRolled;
              _displayDice = snapshot.lastDice == 0 ? 1 : snapshot.lastDice;
            });
          }
        });
  }

  Future<void> _startMultiplayerGame({required bool createRoom}) async {
    final playerHote = _userProfile;

    final playerFriends = await FriendsService().getFriendsSubscribeToGam();

    final List<LudoHuman> players = [
      LudoHuman(
        name: playerHote!['username'] ?? 'Player',
        color: LudoColor.red,
        id: playerHote['id'],
        avatar: playerHote['avatar_url'],
      ),
      ...playerFriends.map(
        (e) => LudoHuman(
          name: e['username'],
          color: LudoColor.yellow,
          id: e['id'],
          avatar: e['avatar_url'],
        ),
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

      final friendId = playerFriends[0]['id'];
      if (start == true) {
        await _multiplayerService.sendParticipants(
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
        await _multiplayerService.sendGameStart(session.roomCode);
        await _multiplayerService.sendState(
          session.roomCode,
          _engine.snapshot().toJson(),
        );
        await FriendsService().playingGame(friendId);
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
    await _multiplayerService.sendJoin(
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
            _rebuildEngineFromSubscribers();
            setState(() {
              _beginGame = true;
              _diceRolledThisTurn = false;
            });
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
    setState(() {});
  }

  // Room code dialog removed: joining now uses the global Supabase channel.

  Future<bool?> _showParticipantsConfirmDialog(
    List<LudoHuman> playerSubscribe,
  ) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
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
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...List.generate(
                      list.length,
                      (index) => ListTile(
                        leading: const Icon(Icons.person, color: Colors.white),
                        title: Text(
                          list[index],
                          style: const TextStyle(color: Colors.white),
                        ),
                        trailing: DropdownButton<LudoColor>(
                          value: _parseColor(playerSubscribe[index].color),
                          items: LudoColor.values.map((color) {
                            return DropdownMenuItem<LudoColor>(
                              value: color,
                              child: Icon(
                                Icons.circle,
                                color: LudoBoardLayout.colorValues[color],
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            /* setState(() {
                                _playerSubscribe[index].color = value;
                              }); */
                          },
                        ),
                      ),
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
            ElevatedButton(
              onPressed: () async => {Navigator.pop(context, true)},

              child: const Text('Démarrer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showColorPicker() async {
    LudoColor? selectedColor;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1a1a2e),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Center(
            child: Text(
              'Choisis ta couleur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          content: SizedBox(
            width: 220,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Quelle couleur veux-tu jouer ?',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: LudoColor.values.map((color) {
                    final isSelected = selectedColor == color;
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: LudoBoardLayout.colorValues[color],
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.black26,
                            width: isSelected ? 4 : 2,
                          ),
                          boxShadow: [
                            if (isSelected)
                              BoxShadow(
                                color: LudoBoardLayout.colorValues[color]!
                                    .withValues(alpha: 0.6),
                                blurRadius: 12,
                                spreadRadius: 2,
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
                              fontSize: 16,
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
              child: SizedBox(
                width: 180,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: selectedColor != null
                        ? LudoBoardLayout.colorValues[selectedColor]
                        : Colors.grey.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: selectedColor != null
                      ? () {
                          Navigator.pop(ctx);
                          _startGame(selectedColor!);
                        }
                      : null,
                  child: const Text(
                    'Valider',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
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
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isHumanWin ? Icons.emoji_events : Icons.smart_toy,
                    color: isHumanWin ? Colors.amber : Colors.white54,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isHumanWin ? 'Victoire !' : 'Partie terminée',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_engine.winner!.label} remporte la victoire !',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        _restartGame();
                      },
                      child: const Text(
                        'Rejouer',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.pop(context);
                      },
                      child: const Text(
                        'Quitter',
                        style: TextStyle(color: Colors.white54, fontSize: 14),
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
                                    _engine.currentPlayer.isHuman &&
                                    _engine.winner == null &&
                                    //!_diceRolledThisTurn &&
                                    _engine.currentPlayer.id ==
                                        _userProfile['id']
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
                                _engine.currentPlayer.isHuman &&
                                _engine.winner == null &&
                                //!_diceRolledThisTurn &&
                                _engine.currentPlayer.id == _userProfile['id'];

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
                                _engine.currentPlayer.isHuman &&
                                    _engine.winner == null &&
                                   // !_diceRolledThisTurn &&
                                    _engine.currentPlayer.id ==
                                        _userProfile['id'],
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
                'Ludo',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                ),
              ),
              const SizedBox(height: 40),
              _buildPawnChoice('Solo', LudoColor.red, () {
                _showColorPicker();
              }),
              const SizedBox(height: 20),
              _buildPawnChoice('En ligne', LudoColor.green, () async {
                await _startMultiplayerGame(createRoom: true);
              }),
              const SizedBox(height: 20),
              _buildPawnChoice('Multi', LudoColor.blue, () async {
                await _startMultiplayerGame(createRoom: false);
              }),
            ],
          ),
        ),
        Positioned(top: 12, left: 12, right: 12, child: _buildTopBar()),
        Positioned(
          bottom: 20,
          left: 16,
          child: FloatingActionButton(
            mini: true,
            backgroundColor: const Color(0xFF006400),
            onPressed: () => Navigator.pop(context),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildPawnChoice(String label, LudoColor color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 180,
        height: 68,
        decoration: BoxDecoration(
          color: LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(2, 4),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 140,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: LudoBoardLayout.colorValues[color],
                ),
              ),
            ),
          ),
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
            const Text(
              'En attente du host...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              _roomCode.isNotEmpty
                  ? 'Salle : $_roomCode'
                  : 'Connexion en cours...',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<List<String>>(
              valueListenable: _participantsNotifier,
              builder: (context, list, _) {
                return Column(
                  children: [
                    const Text(
                      'Participants',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (list.isEmpty)
                      const Text(
                        'Aucun participant détecté',
                        style: TextStyle(color: Colors.white54),
                      )
                    else
                      ...list.map(
                        (name) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
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
                backgroundColor: const Color(0xFFcc0000),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                _multiplayerSubscription?.cancel();
                if (_roomCode.isNotEmpty) {
                  _multiplayerService.disposeRoom(_roomCode);
                }
                setState(() {
                  _isMultiplayer = false;
                  _beginGame = false;
                  _roomCode = '';
                  _playerSubscribe = [];
                  _participantsNotifier.value = [];
                });
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              onPressed: () => _restartGame(),
              icon: const Icon(Icons.refresh, color: Colors.amber),
            ),
          ),

          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _engine.message,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
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
    final widgets = <Widget>[];
    //print('Les playeurs sont:');
    for (final player in _engine.players) {
      // print('${player.color} => ${player.isHuman}');
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
            _engine.currentPlayer.isHuman &&
            _engine.canMovePawn(pawn) &&
            !isAnimating;

        final isSelected =
            _selectedPawn?.id == pawn.id && _selectedPawn?.color == pawn.color;

        widgets.add(
          Positioned(
            left: pos.dx - cellSize * 0.32,
            top: pos.dy - cellSize * 0.32,
            child: GestureDetector(
              onTap: isSelectable ? () => _onPawnTap(pawn) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: cellSize * 0.64,
                height: cellSize * 0.64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LudoBoardLayout.colorValues[pawn.color],
                  border: Border.all(
                    color: isSelected
                        ? Colors.white
                        : isSelectable
                        ? Colors.amber
                        : Colors.black87,
                    width: isSelected || isSelectable ? 3 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 4,
                      offset: const Offset(1, 2),
                    ),
                  ],
                ),
                child: pawn.finished
                    ? const Icon(Icons.star, color: Colors.white, size: 14)
                    : null,
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

      final icon = isHuman
          ? (matchingPlayer.avatar != null && matchingPlayer.avatar!.isNotEmpty
                ? null as Widget?
                : const Icon(Icons.person, color: Colors.white, size: 14))
          : const Icon(Icons.smart_toy, color: Colors.white, size: 14);

      Widget avatar;
      if (isHuman &&
          matchingPlayer.avatar != null &&
          matchingPlayer.avatar!.isNotEmpty) {
        avatar = CircleAvatar(
          radius: 8,
          backgroundImage: NetworkImage(matchingPlayer.avatar ?? ''),
        );
      } else {
        avatar = icon!;
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: canRoll ? Colors.white : Colors.grey.shade600,
              borderRadius: BorderRadius.circular(12),
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
                  ? _DiceFace(value: _displayDice)
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

class _DiceFace extends StatelessWidget {
  final int value;

  const _DiceFace({required this.value});

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
                decoration: const BoxDecoration(
                  color: Colors.black87,
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

class _LudoBoardPainter extends CustomPainter {
  final double cellSize;

  _LudoBoardPainter({required this.cellSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    // Fond blanc central
    paint.color = Colors.white;
    canvas.drawRect(
      Rect.fromLTWH(6 * cellSize, 6 * cellSize, 3 * cellSize, 3 * cellSize),
      paint,
    );

    // Bases colorées
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
      paint.color = isSafe ? Colors.grey.shade300 : Colors.white;
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.color = Colors.black26;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 0.5;
      canvas.drawRect(
        Rect.fromLTWH(c[0] * cellSize, c[1] * cellSize, cellSize, cellSize),
        paint,
      );
      paint.style = PaintingStyle.fill;

      if (isSafe) {
        paint.color = Colors.black38;
        canvas.drawCircle(
          Offset((c[0] + 0.5) * cellSize, (c[1] + 0.5) * cellSize),
          cellSize * 0.12,
          paint,
        );
      }
    }

    // Centre triangulaire
    _drawCenter(canvas);
  }

  void _drawBase(Canvas canvas, LudoColor color, int row, int col) {
    final paint = Paint()
      ..color = LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          col * cellSize,
          row * cellSize,
          6 * cellSize,
          6 * cellSize,
        ),
        Radius.circular(cellSize * 0.3),
      ),
      paint,
    );

    paint.color = Colors.white.withValues(alpha: 0.9);
    for (final coords in LudoBoardLayout.baseCoords[color]!) {
      canvas.drawCircle(
        Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize),
        cellSize * 0.35,
        paint,
      );
    }
  }

  void _drawHomeStretch(Canvas canvas, LudoColor color) {
    final paint = Paint()
      ..color = LudoBoardLayout.colorValues[color]!.withValues(alpha: 0.75);
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
      final paint = Paint()..color = colors[i];
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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
