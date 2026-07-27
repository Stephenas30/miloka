import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../game/ludo/ludo_engine.dart';
import '../service/stats_service.dart';

class LudoScreen extends StatefulWidget {
  const LudoScreen({super.key});

  @override
  State<LudoScreen> createState() => _LudoScreenState();
}

class _LudoScreenState extends State<LudoScreen>
    with SingleTickerProviderStateMixin {

  final LudoEngine _engine = LudoEngine();
  Timer? _aiTimer;
  late AnimationController _diceController;
  int _displayDice = 1;
  LudoPawn? _selectedPawn;
  bool _winnerDialogShown = false;
  bool _beginGame = false;

  @override
  void initState() {
    super.initState();
    _diceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _userProfile = context.read<AuthProvider?>()?.userProfile;

    if (widget.beginGame) {
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
  }

  @override
  void dispose() {
    _aiTimer?.cancel();
    _diceController.dispose();
    super.dispose();
  }

  void _scheduleAiTurn() {
    final isHumanTurn = _engine.currentPlayer.isHuman && _engine.winner == null;
    if (isHumanTurn) return;
    _aiTimer?.cancel();
    if (_engine.winner != null || _engine.currentPlayer.isHuman) return;

    _aiTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      setState(() {
        _animateDiceRoll(_engine.rollDice());
        _engine.aiPlay();
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

    _engine.scheduleTurnEnd(extraTurn: value == 6); 

    return Future.value();
  }

  void _onRollDice() {
    if (_engine.winner != null ||
        !_engine.currentPlayer.isHuman) {
      return;
    }
    setState(() {
      _selectedPawn = null;
      _animateDiceRoll(_engine.rollDice());
    });
    if (_engine.getValidMoves().isEmpty /* && _engine.diceRolled == false */) {
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
      final playerColor =
          _engine.players.any((p) => p.namePlayer == _playerName)
          ? _engine.players.firstWhere((p) => p.namePlayer == _playerName).color
          : LudoColor.yellow;
      _multiplayerService.sendPlayerLeft(
        _roomCode,
        _playerName,
        playerColor.name,
      );
      _multiplayerService.disposeRoom(_roomCode);
      _multiplayerSubscription?.cancel();
      _roomCode = '';
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => route.isFirst,
    );
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
    if (!_engine.canMovePawn(pawn)) return;

    setState(() {
      _selectedPawn = pawn;
      _engine.applyMove(pawn);
      _selectedPawn = null;
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

    _participantsNotifier.value = _playerSubscribe
        .map((p) => p.name.toString())
        .where((name) => name.isNotEmpty)
        .toList();

    await _multiplayerService.joinRoom(
      playerName: _playerSubscribe.first.name,
      playerColor: _playerSubscribe.first.color.name,
    );

    setState(() {
      _roomCode = 'ludo_global';
      _playerName = _userProfile?['username']?.toString() ?? _playerSubscribe.first.name;
      isHost = false;
    });

    _multiplayerSubscription = _multiplayerService
        .watchRoom('ludo_global')
        .listen((payload) {
          if (!mounted) return;
          final type = payload['event']?.toString();

          if (type == 'ludo_presence') {
            final action = payload['action']?.toString();
            final playerData = payload['player'] as Map<String, dynamic>?;
            if (action == 'join' && playerData != null) {
              final playerName = playerData['name']?.toString() ?? '';
              final playerColorStr =
                  playerData['color']?.toString() ?? '';
              if (playerName.isNotEmpty) {
                final list = List<String>.from(_participantsNotifier.value);
                if (!list.contains(playerName)) {
                  final color = LudoColor.values.firstWhere(
                    (c) => c.name == playerColorStr,
                    orElse: () => LudoColor.yellow,
                  );
                  setState(() {
                    _playerSubscribe.add(
                      LudoHuman(name: playerName, color: color),
                    );
                  });
                  list.add(playerName);
                }
                _participantsNotifier.value = list;
              }
            }
            return;
          }
          if (type == 'ludo_player_ready') {
            final playerName = payload['player']?.toString() ?? '';
            final isReady = payload['ready'] == true;
            print(payload);
            if (playerName.isEmpty) return;
            final updated = Set<String>.from(_readyPlayersNotifier.value);
            if (isReady) {
              updated.add(playerName);
            } else {
              updated.remove(playerName);
            }
            _readyPlayersNotifier.value = updated;
            return;
          }
          if (type == 'ludo_participants') {
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
              if (!_beginGame) _rebuildEngineFromSubscribers();
            }
            return;
          }

          if (type == 'ludo_start') {
            final participantsFromService =
                _multiplayerService.getParticipants(_roomCode);
            if (participantsFromService.isNotEmpty) {
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
            if (!_engine.currentPlayer.isHuman) _scheduleAiTurn();
            return;
          }

          if (type == 'ludo_game_ended') {
            _handleGameEnded();
            return;
          }
          if (type == 'ludo_player_left') {
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showParticipantsListDialog(isHost: false);
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
      ...playerFriends.take(3).toList().asMap().entries.map((entry) {
        final i = entry.key;
        final e = entry.value;
        return LudoHuman(
          name: e['username'],
          color: friendColors[i],
          id: e['id'],
          avatar: e['avatar_url'],
        );
      }),
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
            final type = payload['event']?.toString();
            if (type == 'ludo_presence') {
              final action = payload['action']?.toString();
              final playerData = payload['player'] as Map<String, dynamic>?;
              if (action == 'join' && playerData != null) {
                final playerName = playerData['name']?.toString() ?? '';
                if (playerName.isNotEmpty) {
                  final list = List<String>.from(_participantsNotifier.value);
                  if (!list.contains(playerName)) list.add(playerName);
                  _participantsNotifier.value = list;

                  final playerColor =
                      playerData['color']?.toString() ?? 'yellow';
                  final color = LudoColor.values.firstWhere(
                    (c) => c.name == playerColor,
                    orElse: () => LudoColor.yellow,
                  );
                  if (!_playerSubscribe.any((p) => p.name == playerName)) {
                    setState(() {
                      _playerSubscribe.add(
                        LudoHuman(name: playerName, color: color),
                      );
                    });
                  }
                  _multiplayerService.sendParticipants(
                    _roomCode,
                    _playerSubscribe
                        .map(
                          (p) => {
                            'name': p.name,
                            'color': p.color.name,
                            'id': p.id.toString(),
                            'avatar': p.avatar.toString(),
                          },
                        )
                        .toList(),
                  );
                }
              }
              return;
            }
            if (type == 'ludo_color_change') {
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
                    .map(
                      (p) => {
                        'name': p.name,
                        'color': p.color.name,
                        'id': p.id.toString(),
                        'avatar': p.avatar.toString(),
                      },
                    )
                    .toList(),
              );
              return;
            }
            if (type == 'ludo_player_ready') {
              final playerName = payload['player']?.toString() ?? '';
              final isReady = payload['ready'] == true;
              if (playerName.isEmpty) return;
              final updated = Set<String>.from(_readyPlayersNotifier.value);
              if (isReady) {
                updated.add(playerName);
              } else {
                updated.remove(playerName);
              }
              _readyPlayersNotifier.value = updated;
              return;
            }
            if (type == 'ludo_participants') {
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

            if (type == 'ludo_game_ended') {
              _handleGameEnded();
              return;
            }
            if (type == 'ludo_player_left') {
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

      // Broadcast participants FIRST so friend's _dataOnChannel is populated
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

      // Then update DB send_partie = 'playing' in parallel
      await Future.wait(playerFriends.map((subscrib) {
        return Supabase.instance.client
            .from('amis')
            .update({'send_partie': 'playing'})
            .eq('id_ami', subscrib['id'])
            .eq('id_user', playerHote['id']);
      }));

      // show participants and ask host to start
      final start = await _showParticipantsListDialog(isHost: true);

      _engine = LudoEngine(
        human: _playerSubscribe,
        isMultiplayer: true,
        roomCode: session.roomCode,
        onStateChange: (snapshot) =>
            _multiplayerService.sendState(session.roomCode, snapshot.toJson()),
      );

      if (start == true) {
        _multiplayerService.sendGameStart(session.roomCode);
        await _multiplayerService.sendState(
          session.roomCode,
          _engine.snapshot().toJson(),
        );
        setState(() {
          _beginGame = true;
        });
        if (!_engine.currentPlayer.isHuman) _scheduleAiTurn();
      } else {
        // host cancelled, reset send_partie = 'none'
        await Future.wait(playerFriends.map((subscrib) {
          return Supabase.instance.client
              .from('amis')
              .update({'send_partie': 'none'})
              .eq('id_ami', subscrib['id'])
              .eq('id_user', playerHote['id']);
        }));
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

    // listen for presence, participants and state updates BEFORE sending join
    _multiplayerSubscription = _multiplayerService
        .watchRoom(session.roomCode)
        .listen((payload) {
          if (!mounted) return;
          final type = payload['event']?.toString();
          if (type == 'ludo_presence') {
            final action = payload['action']?.toString();
            final playerData = payload['player'] as Map<String, dynamic>?;
            if (action == 'join' && playerData != null) {
              final playerName = playerData['name']?.toString() ?? '';
              final playerColorStr =
                  playerData['color']?.toString() ?? '';
              if (playerName.isNotEmpty) {
                final list = List<String>.from(_participantsNotifier.value);
                if (!list.contains(playerName)) {
                  final color = LudoColor.values.firstWhere(
                    (c) => c.name == playerColorStr,
                    orElse: () => LudoColor.yellow,
                  );
                  setState(() {
                    _playerSubscribe.add(
                      LudoHuman(name: playerName, color: color),
                    );
                  });
                  list.add(playerName);
                }
                _participantsNotifier.value = list;
              }
            }
            return;
          }
          if (type == 'ludo_player_ready') {
            final playerName = payload['player']?.toString() ?? '';
            final isReady = payload['ready'] == true;
            if (playerName.isEmpty) return;
            final updated = Set<String>.from(_readyPlayersNotifier.value);
            if (isReady) {
              updated.add(playerName);
            } else {
              updated.remove(playerName);
            }
            _readyPlayersNotifier.value = updated;
            return;
          }
          if (type == 'ludo_participants') {
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
              if (!_beginGame) _rebuildEngineFromSubscribers();
            }
            return;
          }

          if (type == 'ludo_start') {
            final participantsFromService = _multiplayerService.getParticipants(
              _roomCode,
            );
            if (participantsFromService.isNotEmpty) {
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
            if (!_engine.currentPlayer.isHuman) _scheduleAiTurn();
            return;
          }

          if (type == 'ludo_game_ended') {
            _handleGameEnded();
            return;
          }
          if (type == 'ludo_player_left') {
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

    // show waiting dialog for non-host participant
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showParticipantsListDialog(isHost: false);
    });

    setState(() {});
  }

  // Room code dialog removed: joining now uses the global Supabase channel.

  Future<bool?> _showParticipantsListDialog({required bool isHost}) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ValueListenableBuilder<List<String>>(
          valueListenable: _participantsNotifier,
          builder: (context, list, _) {
            while (_playerSubscribe.length < list.length) {
              final usedColors = _playerSubscribe.map((p) => p.color).toSet();
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

            return ValueListenableBuilder<Set<String>>(
              valueListenable: _readyPlayersNotifier,
              builder: (context, readySet, _) {
                final nonHostCount = list.length - 1;
                final readyCount = readySet.length;
                final allReady =
                    nonHostCount <= 0 || readyCount >= nonHostCount;

                return AlertDialog(
                  backgroundColor: const Color(0xFF1a1a2e),
                  title: const Text(
                    'Participants',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: SizedBox(
                    width: 280,
                    child: list.length <= 1
                        ? _FriendsInviteList(
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
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ...List.generate(list.length, (index) {
                                final participant = _playerSubscribe[index];
                                final isMe = participant.name == _playerName;
                                final isPlayerReady = readySet.contains(
                                  participant.name,
                                );
                                final usedColors = _playerSubscribe
                                    .map((p) => p.color)
                                    .toSet();
                                final availableColors = LudoColor.values.where(
                                  (c) =>
                                      c == participant.color ||
                                      !usedColors.contains(c),
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isMe)
                                        DropdownButton<LudoColor>(
                                          value: participant.color,
                                          dropdownColor: const Color(
                                            0xFF2A2A40,
                                          ),
                                          items: availableColors.map((c) {
                                            return DropdownMenuItem<LudoColor>(
                                              value: c,
                                              child: Icon(
                                                Icons.circle,
                                                color: LudoBoardLayout
                                                    .colorValues[c],
                                              ),
                                            );
                                          }).toList(),
                                          onChanged: (value) {
                                            if (value == null) return;
                                            _multiplayerService.sendColorChange(
                                              _roomCode,
                                              _playerName,
                                              value.name,
                                            );
                                            final newColor = value;
                                            final idx = _playerSubscribe
                                                .indexWhere(
                                              (p) =>
                                                  p.name == _playerName,
                                            );
                                            if (idx == -1) return;
                                            final existingIdx =
                                                _playerSubscribe.indexWhere(
                                              (p) =>
                                                  p.color == newColor &&
                                                  p.name != _playerName,
                                            );
                                            if (existingIdx != -1) {
                                              final oldColor =
                                                  _playerSubscribe[idx].color;
                                              _playerSubscribe[existingIdx] =
                                                  LudoHuman(
                                                name: _playerSubscribe[
                                                        existingIdx]
                                                    .name,
                                                color: oldColor,
                                                id: _playerSubscribe[
                                                        existingIdx]
                                                    .id,
                                                avatar: _playerSubscribe[
                                                        existingIdx]
                                                    .avatar,
                                              );
                                            }
                                            _playerSubscribe[idx] = LudoHuman(
                                              name: _playerSubscribe[idx].name,
                                              color: newColor,
                                              id: _playerSubscribe[idx].id,
                                              avatar:
                                                  _playerSubscribe[idx].avatar,
                                            );
                                            _participantsNotifier.value =
                                                List<String>.from(
                                              _participantsNotifier.value,
                                            );
                                            if (isHost) {
                                              _multiplayerService
                                                  .sendParticipants(
                                                _roomCode,
                                                _playerSubscribe.map((p) {
                                                  return {
                                                    'name': p.name,
                                                    'color': p.color.name,
                                                    'id': p.id.toString(),
                                                    'avatar':
                                                        p.avatar.toString(),
                                                  };
                                                }).toList(),
                                              );
                                            }
                                          },
                                        )
                                      else
                                        Icon(
                                          Icons.circle,
                                          color: LudoBoardLayout
                                              .colorValues[participant.color],
                                        ),
                                      if (!isHost && !isMe)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            left: 8,
                                          ),
                                          child: Icon(
                                            isPlayerReady
                                                ? Icons.check_circle
                                                : Icons.radio_button_unchecked,
                                            color: isPlayerReady
                                                ? Colors.greenAccent
                                                : Colors.white38,
                                            size: 20,
                                          ),
                                        ),
                                    ],
                                  ),
                                  onTap: null,
                                );
                              }),
                              if (isHost)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    '$readyCount / $nonHostCount prêts',
                                    style: TextStyle(
                                      color: allReady
                                          ? Colors.greenAccent
                                          : Colors.white54,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  actions: [
                    if (isHost) ...[
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Annuler'),
                      ),
                      ElevatedButton(
                        onPressed: allReady
                            ? () => Navigator.pop(ctx, true)
                            : null,
                        child: const Text('Démarrer'),
                      ),
                    ] else ...[
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: readySet.contains(_playerName)
                              ? Colors.green
                              : Colors.grey.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () {
                          final newReady = !readySet.contains(_playerName);
                          _multiplayerService.sendPlayerReady(
                            _roomCode,
                            _playerName,
                            newReady,
                          );
                          final updated =
                              Set<String>.from(_readyPlayersNotifier.value);
                          if (newReady) {
                            updated.add(_playerName);
                          } else {
                            updated.remove(_playerName);
                          }
                          _readyPlayersNotifier.value = updated;
                        },
                        child: Text(
                          !readySet.contains(_playerName) ? '✓ Prêt' : 'Pas prêt',
                        ),
                      ),
                    ],
                  ],
                );
              },
            );
          },
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
                            colors: [
                              baseColor,
                              baseColor.withValues(alpha: 0.6),
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
                      style: TextStyle(color: Colors.white38, fontSize: 12),
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
    setState(() {
      _winnerDialogShown = false;
      _engine.reset();
      _displayDice = 1;
      _selectedPawn = null;
    });
  }

  Future<void> _finishGameWithStats() async {
    await StatsService().recordGameResult(
      gameName: 'ludo',
      won: _engine.winner?.isHuman ?? false,
      context: context,
    );
  }

  void _showWinnerDialog() {
    if (_winnerDialogShown) return;
    _winnerDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Partie terminée'),
        content: Text('${_engine.winner!.label} remporte la victoire !'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _restartGame();
            },
            child: const Text('Rejouer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('Humain => ${_engine.currentPlayer.isHuman}');


    if (_engine.winner != null && !_winnerDialogShown) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _finishGameWithStats();
          _showWinnerDialog();
        }
      });
    } else if (_engine.winner == null && !_engine.currentPlayer.isHuman) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAiTurn());
       print('àààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààààà');
    }

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF006400),
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
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
                              child: _buildDice(_isMyTurn, _engine),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFD4A017).withValues(alpha: 0.3),
                  ),
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
            onPressed: _quitGame,
            child: const Icon(Icons.arrow_back, color: Colors.white70),
          ),
        ),
      ],
    );
  }

  Widget _buildGameChip(
    String label,
    LudoColor color,
    IconData icon,
    VoidCallback onTap,
  ) {
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
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Color(0xFFD4A017),
                    ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () {
                _multiplayerSubscription?.cancel();
                if (_roomCode.isNotEmpty) {
                  _multiplayerService.sendPlayerLeft(
                    _roomCode,
                    _playerName,
                    LudoColor.yellow.name,
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
        final cellSize = size / LudoBoardLayout.gridSize;

        return SizedBox(
          width: size,
          height: size,
          child: Stack(
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _LudoBoardPainter(cellSize: cellSize),
              ),
              ..._buildPawns(cellSize),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildPawns(double cellSize) {
    final widgets = <Widget>[];
    for (final player in _engine.players) {
      for (final pawn in player.pawns) {
        final pos = LudoBoardLayout.pawnPosition(pawn, cellSize);

        final isSelectable =
            _engine.currentPlayer.isHuman &&
            /* _engine.diceRolled && */
            _engine.canMovePawn(pawn);

        final isSelected =
            _selectedPawn?.id == pawn.id && _selectedPawn?.color == pawn.color;

        final key = '${pos.dx.toStringAsFixed(1)}_${pos.dy.toStringAsFixed(1)}';
        posGroups.putIfAbsent(key, () => []);
        posGroups[key]!.add(
          _PawnRenderInfo(
            pawn: pawn,
            pos: pos,
            isSelectable: isSelectable,
            isSelected: isSelected,
            isAnimating: isAnimating,
            playerColor: player.color,
          ),
        );
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
          renderPos =
              info.pos +
              Offset(math.cos(angle) * offset, math.sin(angle) * offset);
        } else {
          renderPos = info.pos;
        }

        final pawnColor = LudoBoardLayout.colorValues[info.playerColor]!;
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

  Widget _buildControls() {
    final isHumanTurn = _engine.currentPlayer.isHuman && _engine.winner == null;

    //t('==> ${_engine.currentPlayerIndex}');
    //print(isHumanTurn);
    //print(!_engine.diceRolled);
    //print('/n/n');

    final canRoll = isHumanTurn /* && !_engine.diceRolled */;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _playerIndicator(LudoColor.red, true),
          _playerIndicator(LudoColor.green, false),
          _buildDice(canRoll),
          _playerIndicator(LudoColor.yellow, false),
          _playerIndicator(LudoColor.blue, false),
        ],
      ),
    );
  }

  Widget _playerIndicator(LudoColor color, bool isHuman) {
    final active = _engine.currentPlayer.color == color;
    return Column(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: LudoBoardLayout.colorValues[color],
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? Colors.white : Colors.transparent,
              width: 3,
            ),
          ),
          child: isHuman
              ? const Icon(Icons.person, size: 16, color: Colors.white)
              : null,
        ),
        if (active)
          const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
      ],
    );
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
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
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
              onPressed: isOnline ? () => widget.onInvite(f) : null,
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
      paint.color = isSafe ? const Color(0xFF3A3A55) : const Color(0xFF2A2A40);
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
      ..shader =
          LinearGradient(
            colors: [
              baseColor.withValues(alpha: 0.7),
              baseColor.withValues(alpha: 0.35),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(
            Rect.fromLTWH(
              col * cellSize,
              row * cellSize,
              6 * cellSize,
              6 * cellSize,
            ),
          );
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

    paint
      ..shader = null
      ..color = Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
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
    paint
      ..style = PaintingStyle.fill
      ..strokeWidth = 0;

    paint.color = Colors.white.withValues(alpha: 0.25);
    for (final coords in LudoBoardLayout.baseCoords[color]!) {
      canvas.drawCircle(
        Offset((coords[0] + 0.5) * cellSize, (coords[1] + 0.5) * cellSize),
        cellSize * 0.35,
        paint,
      );
    }
  }

  void _drawHomeStretch(Canvas canvas, LudoColor color) {
    final baseColor = LudoBoardLayout.colorValues[color]!;
    final paint = Paint()..color = baseColor.withValues(alpha: 0.3);
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

    final paint = Paint()..color = Colors.white.withValues(alpha: 0.1);
    canvas.drawCircle(center, cellSize * 0.8, paint);
    paint.color = const Color(0xFFD4A017).withValues(alpha: 0.3);
    canvas.drawCircle(center, cellSize * 0.5, paint);
    paint.color = const Color(0xFFD4A017).withValues(alpha: 0.6);
    canvas.drawCircle(center, cellSize * 0.2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
