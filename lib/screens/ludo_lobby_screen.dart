import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../game/ludo/ludo_engine.dart';
import '../game/ludo/ludo_board_layout.dart';
import '../service/friends_service.dart';
import '../service/ludo_multiplayer_service.dart';
import '../service/ludo_team_invitation_service.dart';
import '../service/ludo_team_lobby_service.dart';
import 'ludo_screen.dart';

class LudoLobbyScreen extends StatefulWidget {
  final String teamId;
  final bool isHost;
  final bool fromGame;

  const LudoLobbyScreen({
    super.key,
    required this.teamId,
    required this.isHost,
    this.fromGame = false,
  });

  @override
  State<LudoLobbyScreen> createState() => _LudoLobbyScreenState();
}

class _LudoLobbyScreenState extends State<LudoLobbyScreen> {
  final LudoTeamLobbyService _teamService = LudoTeamLobbyService();
  final LudoMultiplayerService _multiplayerService = LudoMultiplayerService();
  Map<String, dynamic>? _team;
  Timer? _refreshTimer;
  bool _isNavigating = false;

  bool _isSearching = false;
  Timer? _matchmakingTimer;
  int _matchmakingSeconds = 0;
  static const int _matchmakingTimeout = 60;

  bool _inColorSelection = false;
  RealtimeChannel? _colorChannel;
  StreamSubscription<Map<String, dynamic>>? _colorSubscription;
  final Map<String, ColorSelectionState> _colorStates = {};
  bool _hostAiEnabled = false;
  String? _myUserId;

  Timer? _colorTimer;
  int _colorSecondsLeft = 60;

  bool _bettingEnabled = false;
  final Map<String, int> _betAmounts = {};
  final TextEditingController _betController = TextEditingController();
  bool _awaitingAgreement = false;
  Set<String> _agreedUserIds = {};
  bool _showingBetPopup = false;
  bool _hasReceivedSyncState = false;

  @override
  void initState() {
    super.initState();
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadTeam();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadTeam());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _matchmakingTimer?.cancel();
    _colorSubscription?.cancel();
    _colorTimer?.cancel();
    _betController.dispose();
    if (_colorChannel != null) {
      _multiplayerService.disposeColorChannel(widget.teamId);
    }
    super.dispose();
  }

  Future<void> _loadTeam() async {
    if (_isNavigating) return;

    if (_team != null) {
      final exists = await _teamService.teamExists(widget.teamId);
      if (!mounted) return;
      if (!exists) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
    }

    final loadedTeam = await _teamService.getTeam(widget.teamId);
    if (!mounted || loadedTeam == null) return;

    if (loadedTeam['status'] == 'playing' && widget.fromGame) {
      if (widget.isHost) {
        await _teamService.updateStatus(widget.teamId, 'waiting');
        loadedTeam['status'] = 'waiting';
      } else {
        return;
      }
    }

    if (loadedTeam['status'] == 'playing') {
      _isNavigating = true;
      _refreshTimer?.cancel();
      _matchmakingTimer?.cancel();
      _colorTimer?.cancel();
      if (mounted) _startGameFromTeam(loadedTeam);
      return;
    }

    if (loadedTeam['status'] == 'color_selection' && !_inColorSelection) {
      _startColorSelection();
    }

    if (loadedTeam['status'] != 'color_selection' && _inColorSelection) {
      if (_colorChannel != null) {
        _multiplayerService.disposeColorChannel(widget.teamId);
        _colorChannel = null;
      }
      _colorTimer?.cancel();
      _colorTimer = null;
      _teamService.resetMemberBets(widget.teamId);
      _betAmounts.clear();
      setState(() {
        _team = loadedTeam;
        _inColorSelection = false;
        _hasReceivedSyncState = false;
        _bettingEnabled = false;
        _hostAiEnabled = false;
      });
      return;
    }

    if (_inColorSelection && !widget.isHost && !_hasReceivedSyncState && _myUserId != null) {
      _multiplayerService.sendColorSyncRequest(widget.teamId, _myUserId!);
    }

    if (_inColorSelection) {
      bool stateChanged = false;
      final freshMembers = _teamService.getMembersList(loadedTeam);
      for (final member in freshMembers) {
        final id = member['id']?.toString() ?? '';
        if (id.isEmpty || id == _myUserId) continue;
        final dbColor = member['color']?.toString() ?? '';
        final existing = _colorStates[id];
        if (existing == null) {
          _colorStates[id] = ColorSelectionState(
            userId: id,
            fixedColor: dbColor.isNotEmpty ? dbColor : null,
          );
          stateChanged = true;
        } else if (existing.pendingColor == null) {
          final targetColor = dbColor.isNotEmpty ? dbColor : null;
          if (existing.fixedColor != targetColor) {
            _colorStates[id] = ColorSelectionState(
              userId: id,
              fixedColor: targetColor,
            );
            stateChanged = true;
          }
        }
      }
      if (loadedTeam['host_profile'] is Map && !widget.isHost) {
        final hostProfile = loadedTeam['host_profile'] as Map;
        if (hostProfile.containsKey('betting_enabled')) {
          final dbBetting = hostProfile['betting_enabled'] == true;
          if (_bettingEnabled != dbBetting) {
            _bettingEnabled = dbBetting;
            stateChanged = true;
          }
        }
        if (hostProfile.containsKey('host_ai_enabled')) {
          final dbAi = hostProfile['host_ai_enabled'] == true;
          if (_hostAiEnabled != dbAi) {
            _hostAiEnabled = dbAi;
            stateChanged = true;
          }
        }
      }
      for (final member in freshMembers) {
        final id = member['id']?.toString() ?? '';
        if (id.isEmpty || id == _myUserId) continue;
        final memberBet = member['bet'] as int? ?? 0;
        if ((_betAmounts[id] ?? 0) != memberBet) {
          _betAmounts[id] = memberBet;
          stateChanged = true;
        }
      }
      if (stateChanged) setState(() {});
    }

    setState(() => _team = loadedTeam);
  }

  List<Map<String, dynamic>> get _members {
    if (_team == null) return [];
    return _teamService.getMembersList(_team!);
  }

  int get _memberCount => _members.length;

  ColorSelectionState? get _myColorState {
    if (_myUserId == null) return null;
    return _colorStates[_myUserId];
  }

  Future<void> _startGameFromTeam(Map<String, dynamic> team) async {
    final members = _teamService.getMembersList(team);
    if (!mounted) return;

    final playerData = members.map((m) {
      final profile = m['profile'] as Map<String, dynamic>? ?? {};
      final id = m['id']?.toString() ?? '';
      final bet = _betAmounts[id] ?? profile['bet'] as int? ?? 0;
      return {
        'name': profile['username']?.toString() ?? profile['full_name']?.toString() ?? 'Joueur',
        'color': m['color']?.toString() ?? 'yellow',
        'id': id,
        'avatar': profile['avatar_url']?.toString() ?? '',
        'bet': bet,
      };
    }).toList();

    // Apply bets to member profiles for the game screen
    if (_bettingEnabled) {
      for (final member in members) {
        final id = member['id']?.toString() ?? '';
        final bet = _betAmounts[id];
        if (bet != null && bet > 0) {
          final profile = member['profile'] as Map<String, dynamic>? ?? {};
          profile['bet'] = bet;
        }
      }
    }

    await _multiplayerService.createRoom(
      playerName: playerData.isNotEmpty ? playerData[0]['name']?.toString() ?? 'Player' : 'Player',
      playerColor: playerData.isNotEmpty ? playerData[0]['color']?.toString() ?? 'red' : 'red',
    );

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => LudoScreen(
          beginGame: true,
          playerSubscribe: playerData,
          isHost: widget.isHost,
          teamId: widget.teamId,
        ),
      ),
    );
  }

  Future<void> _startPrivateGame() async {
    if (_team == null) return;
    if (_isSearching) await _teamService.cancelPublicWaiting(widget.teamId);
    await _teamService.updateStatus(widget.teamId, 'color_selection');
  }

  Future<void> _startColorSelection() async {
    setState(() {
      _inColorSelection = true;
      _colorSecondsLeft = 60;
    });

    _colorChannel = await _multiplayerService.createColorChannel(widget.teamId);
    _colorSubscription = _multiplayerService
        .watchColorChannel(widget.teamId)
        .listen(_handleColorEvent);

    _colorTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _colorSecondsLeft--;
      });
      if (_colorSecondsLeft <= 0) {
        _colorTimer?.cancel();
        _colorTimer = null;
        _autoAssignColors();
      }
    });

    if (widget.isHost) {
      _multiplayerService.sendColorStart(widget.teamId, _myUserId ?? '');
      if (!_hostAiEnabled) {
        _bettingEnabled = true;
        _multiplayerService.sendBetEnable(widget.teamId, true);
        _teamService.updateBettingEnabled(widget.teamId, true, hostAiEnabled: false);
      } else {
        _teamService.updateBettingEnabled(widget.teamId, false, hostAiEnabled: true);
      }
    } else {
      _multiplayerService.sendColorSyncRequest(widget.teamId, _myUserId ?? '');
    }

    for (final member in _members) {
      final id = member['id']?.toString() ?? '';
      if (id.isNotEmpty && !_colorStates.containsKey(id)) {
        final dbColor = member['color']?.toString();
        _colorStates[id] = ColorSelectionState(
          userId: id,
          fixedColor: dbColor,
        );
      }
    }
    setState(() {});
  }

  void _autoAssignColors() {
    if (!mounted) return;
    final allColors = ['red', 'green', 'yellow', 'blue'];
    for (final member in _members) {
      final id = member['id']?.toString() ?? '';
      final state = _colorStates[id];
      if (state == null || state.fixedColor == null) {
        final free = allColors.where((c) => !_isColorTaken(c)).toList();
        if (free.isNotEmpty) {
          final assigned = free.first;
          _colorStates[id] = ColorSelectionState(userId: id, pendingColor: null, fixedColor: assigned);
          if (id == _myUserId) {
            _multiplayerService.sendColorFix(widget.teamId, id, assigned);
          }
        }
      }
    }
    setState(() {});
  }

  void _handleColorEvent(Map<String, dynamic> payload) {
    if (!mounted) return;
    final type = payload['type']?.toString();

    if (type == 'ludo_color_select') {
      final userId = payload['userId']?.toString() ?? '';
      final color = payload['color']?.toString();
      final existing = _colorStates[userId];
      if (existing != null && existing.fixedColor != null) return;
      _colorStates[userId] = ColorSelectionState(userId: userId, pendingColor: color, fixedColor: null);
      setState(() {});
    } else if (type == 'ludo_color_fix') {
      final userId = payload['userId']?.toString() ?? '';
      final color = payload['color']?.toString();
      final conflict = _colorStates.values.any((s) => s.userId != userId && s.fixedColor == color);
      if (conflict) return;
      _colorStates[userId] = ColorSelectionState(userId: userId, pendingColor: null, fixedColor: color);
      setState(() {});
    } else if (type == 'ludo_color_unfix') {
      final userId = payload['userId']?.toString() ?? '';
      _colorStates[userId] = ColorSelectionState(userId: userId);
      setState(() {});
    } else if (type == 'ludo_color_sync_request') {
      if (!widget.isHost) return;
      final states = _colorStates.values.map((s) => s.toJson()).toList();
      _multiplayerService.sendColorSyncState(widget.teamId, states, bettingEnabled: _bettingEnabled);
      if (_bettingEnabled) {
        _multiplayerService.sendBetEnable(widget.teamId, true);
      }
    } else if (type == 'ludo_color_sync_state') {
      if (_hasReceivedSyncState) return;
      _hasReceivedSyncState = true;
      final rawStates = payload['states'] as List<dynamic>? ?? [];
      for (final raw in rawStates) {
        if (raw is Map<String, dynamic>) {
          final state = ColorSelectionState.fromJson(raw);
          _colorStates.putIfAbsent(state.userId, () => state);
        }
      }
      if (payload['bettingEnabled'] == true) {
        _bettingEnabled = true;
      }
      setState(() {});
    } else if (type == 'ludo_bet_enable') {
      _bettingEnabled = payload['enabled'] == true;
      if (!_bettingEnabled) {
        _betAmounts.clear();
        _awaitingAgreement = false;
        _agreedUserIds.clear();
      }
      setState(() {});
    } else if (type == 'ludo_bet_amount') {
      final userId = payload['userId']?.toString() ?? '';
      final amount = payload['amount'] as int? ?? 0;
      _betAmounts[userId] = amount;
      setState(() {});
    } else if (type == 'ludo_bet_request_agreement') {
_awaitingAgreement = true;
  _agreedUserIds.clear();
      setState(() {});
      _showBetAgreementPopup();
    } else if (type == 'ludo_bet_agree') {
      final userId = payload['userId']?.toString() ?? '';
      _agreedUserIds.add(userId);
      setState(() {});
    } else if (type == 'ludo_bet_disagree') {
      setState(() {});
    } else if (type == 'ludo_bet_reset') {
      _awaitingAgreement = false;
      _agreedUserIds.clear();
      setState(() {});
    } else if (type == 'ludo_color_done') {
      _finalizeColorsAndStart();
    }
  }

  bool get _allPlayersFixed {
    for (final member in _members) {
      final id = member['id']?.toString() ?? '';
      final state = _colorStates[id];
      if (state == null || state.fixedColor == null) return false;
    }
    return true;
  }

  bool get _allBetsSet {
    if (!_bettingEnabled) return true;
    return _members.where((m) => !(m['id']?.toString().startsWith('ai_') ?? false)).every((m) {
      final id = m['id']?.toString() ?? '';
      return _betAmounts[id] != null && _betAmounts[id]! > 0;
    });
  }

  bool get _allAgreed {
    final humanMembers = _members.where((m) => !(m['id']?.toString().startsWith('ai_') ?? false)).length;
    return _agreedUserIds.length >= humanMembers;
  }

  bool _isColorTaken(String color) {
    return _colorStates.values.any((s) => s.fixedColor == color);
  }

  bool _isColorPending(String color) {
    return _colorStates.values.any((s) => s.pendingColor == color && s.fixedColor == null);
  }

  void _onColorTap(String color) {
    if (_myUserId == null) return;
    final myState = _colorStates[_myUserId];
    if (myState != null && myState.fixedColor != null) return;
    if (_isColorTaken(color)) return;
    _colorStates[_myUserId!] = ColorSelectionState(userId: _myUserId!, pendingColor: color, fixedColor: null);
    _multiplayerService.sendColorSelect(widget.teamId, _myUserId!, color);
    setState(() {});
  }

  Future<void> _onFixColor() async {
    if (_myUserId == null) return;
    final myState = _colorStates[_myUserId];
    if (myState == null || myState.pendingColor == null) return;
    final color = myState.pendingColor!;
    if (_isColorTaken(color)) return;
    await _teamService.updateMemberColor(widget.teamId, _myUserId!, color);
    _colorStates[_myUserId!] = ColorSelectionState(userId: _myUserId!, pendingColor: null, fixedColor: color);
    _multiplayerService.sendColorFix(widget.teamId, _myUserId!, color);
    if (mounted) setState(() {});
  }

  Future<void> _onUnfixColor() async {
    if (_myUserId == null) return;
    final myState = _colorStates[_myUserId];
    if (myState == null || myState.fixedColor == null) return;
    await _teamService.updateMemberColor(widget.teamId, _myUserId!, '');
    _colorStates[_myUserId!] = ColorSelectionState(userId: _myUserId!);
    _multiplayerService.sendColorUnfix(widget.teamId, _myUserId!);
    if (mounted) setState(() {});
  }

  Future<void> _onFixBet() async {
    if (_myUserId == null) return;
    final amount = int.tryParse(_betController.text) ?? 0;
    if (amount <= 0) return;
    await _teamService.updateMemberBet(widget.teamId, _myUserId!, amount);
    _betAmounts[_myUserId!] = amount;
    _multiplayerService.sendBetAmount(widget.teamId, _myUserId!, amount);
    if (mounted) setState(() {});
  }

  bool get _betsAreDifferent {
    final humanBets = _betAmounts.entries
        .where((e) => _members.any((m) => m['id']?.toString() == e.key && !e.key.startsWith('ai_')))
        .map((e) => e.value)
        .toList();
    if (humanBets.length < 2) return false;
    return humanBets.toSet().length > 1;
  }

  Future<void> _onHostRequestAgreement() async {
    _awaitingAgreement = true;
    _agreedUserIds = {_myUserId ?? ''};
    _multiplayerService.sendBetRequestAgreement(widget.teamId);
    _multiplayerService.sendBetAgree(widget.teamId, _myUserId ?? '');
    setState(() {});
    _showBetAgreementPopup();
  }

  void _onAgree() {
    if (_myUserId == null) return;
    _agreedUserIds.add(_myUserId!);
    _multiplayerService.sendBetAgree(widget.teamId, _myUserId!);
    setState(() {});
  }

  void _onDisagree() {
    _multiplayerService.sendBetDisagree(widget.teamId, _myUserId ?? '');
    if (widget.isHost) {
      _multiplayerService.sendBetReset(widget.teamId);
    }
    setState(() {
      _awaitingAgreement = false;
      _agreedUserIds.clear();
    });
  }

  Future<void> _showBetAgreementPopup() async {
    if (_showingBetPopup || !mounted || _myUserId == null) return;
    final alreadyAgreed = _agreedUserIds.contains(_myUserId);
    _showingBetPopup = true;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Mises différentes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Les mises ne sont pas identiques.', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 12),
              ...(_betAmounts.entries.toList()..sort((a, b) => a.key.compareTo(b.key))).map((e) {
                final member = _members.firstWhere(
                  (m) => m['id']?.toString() == e.key,
                  orElse: () => <String, dynamic>{},
                );
                final profile = member['profile'] as Map<String, dynamic>? ?? {};
                final name = profile['username']?.toString() ?? profile['full_name']?.toString() ?? 'Joueur';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                      Text('${e.value} pièces', style: const TextStyle(color: Colors.amber, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              if (alreadyAgreed)
                const Text('Tu as déjà accepté. Attends les autres...', style: TextStyle(color: Colors.greenAccent, fontSize: 13))
              else
                const Text('Es-tu d\'accord ?', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          actions: alreadyAgreed
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('OK', style: TextStyle(color: Colors.amber)),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _onDisagree();
                    },
                    child: const Text('Non', style: TextStyle(color: Colors.red)),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _onAgree();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    child: const Text('Oui', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ],
        );
      },
    );
    _showingBetPopup = false;
  }

  Future<void> _onHostStartGame() async {
    if (_team == null) return;
    if (_bettingEnabled && _betsAreDifferent && !_allAgreed) {
      await _onHostRequestAgreement();
      return;
    }
    _multiplayerService.sendColorDone(widget.teamId);
    await _finalizeColorsAndStart();
  }

  Future<void> _finalizeColorsAndStart() async {
    if (_isNavigating) return;
    _isNavigating = true;

    _refreshTimer?.cancel();
    _matchmakingTimer?.cancel();
    _colorSubscription?.cancel();
    _colorTimer?.cancel();

    final members = _members;

    for (final member in members) {
      final id = member['id']?.toString() ?? '';
      final state = _colorStates[id];
      if (state != null && state.fixedColor != null) {
        member['color'] = state.fixedColor;
      }
    }

    if (_hostAiEnabled && !_bettingEnabled && widget.isHost) {
      final aiColors = ['red', 'green', 'yellow', 'blue']
          .where((c) => !members.any((m) => m['color']?.toString() == c))
          .toList();
      for (final c in aiColors) {
        if (members.length >= 4) break;
        members.add({
          'id': 'ai_$c',
          'profile': {'username': 'Robot ${c[0].toUpperCase()}${c.substring(1)}'},
          'color': c,
        });
      }
    }

    await _teamService.updateMembers(widget.teamId, members);
    await _teamService.startGame(widget.teamId);

    if (_colorChannel != null) {
      _multiplayerService.disposeColorChannel(widget.teamId);
      _colorChannel = null;
    }

    final updatedTeam = await _teamService.getTeam(widget.teamId);
    if (updatedTeam != null && mounted) _startGameFromTeam(updatedTeam);
  }

  Future<void> _startPublicMatchmaking() async {
    if (_team == null) return;
    setState(() {
      _isSearching = true;
      _matchmakingSeconds = 0;
    });
    await _teamService.setPublicWaiting(widget.teamId);
    _matchmakingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _matchmakingSeconds++);
      if (_matchmakingSeconds >= _matchmakingTimeout) _onMatchmakingTimeout();
    });
    _checkForPublicMatch();
  }

  Future<void> _checkForPublicMatch() async {
    while (_isSearching && mounted) {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || !_isSearching) return;
      final opponent = await _teamService.findPublicMatch(widget.teamId, _memberCount);
      if (opponent == null) continue;
      final claimed = await _teamService.claimForMatch(opponent['team_id'] as String);
      if (!claimed) continue;
      if (!mounted) return;
      final merged = await _teamService.mergeTeams(widget.teamId, opponent['team_id'] as String);
      if (merged && mounted) {
        _isNavigating = true;
        _matchmakingTimer?.cancel();
        _matchmakingTimer = null;
        final updatedTeam = await _teamService.getTeam(widget.teamId);
        if (updatedTeam != null && mounted) _startGameFromTeam(updatedTeam);
      }
      return;
    }
  }

  void _onMatchmakingTimeout() {
    if (!mounted) return;
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;
    setState(() => _isSearching = false);
    _teamService.cancelPublicWaiting(widget.teamId);
    _proceedWithCurrentPlayers();
  }

  Future<void> _cancelPublicMatchmaking() async {
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;
    setState(() => _isSearching = false);
    await _teamService.cancelPublicWaiting(widget.teamId);
  }

  void _proceedWithCurrentPlayers() {
    if (_team == null || _members.isEmpty) return;
    _isNavigating = true;
    _refreshTimer?.cancel();
    _teamService.startGame(widget.teamId);
    _startGameFromTeam(_team!);
  }

  Future<void> _showInviteFriendDialog() async {
    final friendIds = <String>{};
    final friendData = <String, Map<String, dynamic>>{};
    try {
      final friendsList = await FriendsService().getFriendsList();
      for (final f in friendsList) {
        final id = f['id']?.toString();
        if (id != null) {
          friendIds.add(id);
          friendData[id] = Map<String, dynamic>.from(f);
        }
      }
    } catch (_) {}
    if (friendIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucun ami à inviter. Ajoute des amis d\'abord !')),
        );
      }
      return;
    }
    String? selectedId;
    String? selectedName;
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.person_add_alt_1, color: Colors.amber.shade400, size: 24),
              const SizedBox(width: 10),
              const Text('Inviter un ami', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18)),
            ],
          ),
          content: SizedBox(
            width: 300,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: friendIds.length,
              itemBuilder: (ctx2, i) {
                final fid = friendIds.elementAt(i);
                final data = friendData[fid] ?? {};
                final fname = data['username']?.toString() ?? 'Inconnu';
                final avatarUrl = data['avatar_url']?.toString();
                final isSelected = fid == selectedId;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setDialogState(() { selectedId = fid; selectedName = fname; }),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSelected ? Colors.amber : Colors.white12, width: isSelected ? 1.5 : 1),
                        color: isSelected ? Colors.amber.withAlpha(25) : Colors.white.withAlpha(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white24,
                            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl == null || avatarUrl.isEmpty ? const Icon(Icons.person, color: Colors.white38) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(fname, style: const TextStyle(color: Colors.white, fontSize: 15))),
                          Icon(isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                              color: isSelected ? Colors.amber : Colors.white38, size: 22),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler', style: TextStyle(color: Colors.white54))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: selectedId != null ? () async {
                Navigator.pop(ctx);
                final hostProfile = _team?['host_profile'] as Map<String, dynamic>?;
                final hostName = hostProfile?['username']?.toString() ?? hostProfile?['full_name']?.toString() ?? 'Quelqu\'un';
                try {
                  await LudoTeamInvitationService().sendInvitation(inviteeId: selectedId!, teamId: widget.teamId, inviterName: hostName);
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invitation envoyée à $selectedName')));
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
                }
              } : null,
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHost = widget.isHost;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isHost ? 'Dissoudre l\'équipe' : 'Quitter l\'équipe'),
            content: Text(isHost ? 'Veux-tu vraiment dissoudre l\'équipe ?' : 'Veux-tu vraiment quitter l\'équipe ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui')),
            ],
          ),
        );
        if (confirm != true) return;
        if (_inColorSelection && _colorChannel != null) {
          _multiplayerService.disposeColorChannel(widget.teamId);
          _colorChannel = null;
        }
        if (_isSearching) await _cancelPublicMatchmaking();
        if (isHost) await _teamService.deleteTeam(widget.teamId);
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: _inColorSelection
            ? null
            : AppBar(
                title: Text('Lobby Ludo #${widget.teamId}'),
                backgroundColor: const Color(0xFF006400),
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () async {
                    if (_isSearching) await _cancelPublicMatchmaking();
                    if (isHost) await _teamService.deleteTeam(widget.teamId);
                    if (mounted) Navigator.of(context).pop();
                  },
                ),
              ),
        backgroundColor: const Color(0xFF1C1C2E),
        body: Container(
          decoration: _inColorSelection
              ? const BoxDecoration(color: Color(0xFF1C1C2E))
              : const BoxDecoration(
                  image: DecorationImage(image: AssetImage('assets/images/background.png'), fit: BoxFit.cover),
                ),
          child: SafeArea(
            child: _inColorSelection ? _buildColorSelection() : _buildLobby(),
          ),
        ),
      ),
    );
  }

  Widget _buildLobby() {
    final isHost = widget.isHost;
    final members = _members;
    final emptySlots = 4 - members.length;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(color: const Color.fromARGB(46, 255, 255, 255), borderRadius: BorderRadius.circular(16)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Équipe: ${widget.teamId}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                Text('${members.length}/4', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2, mainAxisSpacing: 24, crossAxisSpacing: 16,
              childAspectRatio: 0.85, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < members.length; i++) _memberSlot(members[i]),
                for (var i = 0; i < emptySlots; i++) _memberSlot(null),
              ],
            ),
          ),
          if (_isSearching) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(color: const Color.fromARGB(46, 255, 255, 255), borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  const SizedBox(width: 40, height: 40, child: CircularProgressIndicator(color: Colors.orange)),
                  const SizedBox(height: 16),
                  const Text('Recherche d\'autres joueurs...', style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text('${_matchmakingTimeout - _matchmakingSeconds}s restantes', style: const TextStyle(color: Colors.white70, fontSize: 14)),
                  if (isHost) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _cancelPublicMatchmaking,
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(48)),
                        child: const Text('Annuler'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            if (isHost) Column(
              children: [
                if (_memberCount < 4)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showInviteFriendDialog, icon: const Icon(Icons.person_add),
                      label: const Text('Inviter un ami'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white),
                    ),
                  ),
                if (_memberCount < 4) const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: ElevatedButton(
                      onPressed: _memberCount >= 1 ? _startPrivateGame : null,
                      style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      child: const Text('Partie privée'),
                    )),
                    if (_memberCount < 4) ...[
                      const SizedBox(width: 16),
                      Expanded(child: ElevatedButton(
                        onPressed: _memberCount >= 1 ? _startPublicMatchmaking : null,
                        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: const Text('Partie publique'),
                      )),
                    ],
                  ],
                ),
              ],
            ),
            if (!isHost) Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text('En attente que l\'hôte démarre la partie...', style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorSelection() {
    final isHost = widget.isHost;
    final members = _members;
    final myState = _myColorState;
    final myFixedColor = myState?.fixedColor;
    final myPendingColor = myState?.pendingColor;
    final allColors = ['red', 'green', 'yellow', 'blue'];
    final aiSlots = 4 - members.length;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white54),
                      onPressed: () async {
                        if (isHost) await _teamService.updateStatus(widget.teamId, 'waiting');
                        if (_colorChannel != null) {
                          _multiplayerService.disposeColorChannel(widget.teamId);
                          _colorChannel = null;
                        }
                        _colorTimer?.cancel();
                        _colorTimer = null;
                        _teamService.resetMemberBets(widget.teamId);
                        _betAmounts.clear();
                        setState(() {
                          _inColorSelection = false;
                          _hasReceivedSyncState = false;
                          _bettingEnabled = false;
                          _hostAiEnabled = false;
                        });
                      },
                    ),
                  const Spacer(),
                  Text('${_colorSecondsLeft}s', style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('Choisis ta couleur', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Sélectionne et valide', style: TextStyle(color: Colors.white38, fontSize: 14)),
                const SizedBox(height: 20),
                ...members.map((member) {
                  final id = member['id']?.toString() ?? '';
                  final profile = member['profile'] as Map<String, dynamic>? ?? {};
                  final name = profile['username']?.toString() ?? profile['full_name']?.toString() ?? 'Joueur';
                  final avatarUrl = profile['avatar_url']?.toString();
                  final state = _colorStates[id];
                  final fixedColor = state?.fixedColor;
                  final pendingColor = state?.pendingColor;
                  final isMe = id == _myUserId;

                  Color? displayColor;
                  String statusText = 'En attente...';
                  if (fixedColor != null) {
                    final c = LudoColor.values.where((e) => e.name == fixedColor).firstOrNull;
                    displayColor = c != null ? LudoBoardLayout.colorValues[c] : null;
                    statusText = 'Validé';
                  } else if (pendingColor != null) {
                    final c = LudoColor.values.where((e) => e.name == pendingColor).firstOrNull;
                    displayColor = c != null ? LudoBoardLayout.colorValues[c]?.withAlpha(100) : null;
                    statusText = 'Sélectionné';
                  }

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: displayColor ?? Colors.white12, width: fixedColor != null ? 2 : 1),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: displayColor ?? Colors.white12,
                          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? Icon(Icons.person, color: fixedColor != null ? Colors.white : Colors.white38, size: 18)
                              : null,
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(name, style: TextStyle(color: Colors.white, fontWeight: isMe ? FontWeight.bold : FontWeight.normal, fontSize: 14))),
                        if (_bettingEnabled) ...[
                          if ((_betAmounts[id] ?? 0) > 0)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Text('${_betAmounts[id]} pièces', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ],
                        if (isMe && fixedColor == null && pendingColor != null)
                          ElevatedButton(
                            onPressed: _onFixColor,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), minimumSize: Size.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Valider', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (isMe && fixedColor != null)
                          ElevatedButton(
                            onPressed: _onUnfixColor,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), minimumSize: Size.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Annuler', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        if (fixedColor != null && !isMe)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.green.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                            child: Text(statusText, style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                          )
                        else if (!isMe)
                          Text(statusText, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                const Text('Couleurs', style: TextStyle(color: Colors.white38, fontSize: 12)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 14, runSpacing: 14, alignment: WrapAlignment.center,
                  children: allColors.map((colorName) {
                    final color = LudoColor.values.firstWhere((c) => c.name == colorName, orElse: () => LudoColor.red);
                    final baseColor = LudoBoardLayout.colorValues[color]!;
                    final taken = _isColorTaken(colorName);
                    final pending = _isColorPending(colorName);
                    final isMine = myPendingColor == colorName || myFixedColor == colorName;
                    final canSelect = !taken && myFixedColor == null && !isMine;

                    return GestureDetector(
                      onTap: canSelect ? () => _onColorTap(colorName) : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [baseColor, baseColor.withAlpha(taken ? 60 : 180)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(color: isMine ? Colors.white : (taken ? Colors.white12 : Colors.white24), width: isMine ? 3 : 1.5),
                          boxShadow: isMine ? [BoxShadow(color: baseColor.withAlpha(120), blurRadius: 12, spreadRadius: 2)] : [],
                        ),
                        child: Center(
                          child: taken
                              ? const Icon(Icons.lock, color: Colors.white24, size: 18)
                              : pending && !isMine
                                  ? const Icon(Icons.hourglass_empty, color: Colors.white38, size: 18)
                                  : isMine
                                      ? const Icon(Icons.check, color: Colors.white, size: 22)
                                      : Text(color.label, style: TextStyle(color: color == LudoColor.yellow ? Colors.black87 : Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                if (aiSlots > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withAlpha(8), borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          children: [
                            const Icon(Icons.smart_toy, color: Colors.white38, size: 22),
                            const SizedBox(width: 10),
                            Expanded(child: Text('$aiSlots slot(s) Robot (IA)', style: const TextStyle(color: Colors.white54, fontSize: 13))),
                            Switch(
                              value: _hostAiEnabled,
                              onChanged: isHost ? (v) {
                                setState(() {
                                  _hostAiEnabled = v;
                                  _bettingEnabled = !v;
                                  if (v) {
                                    _betAmounts.clear();
                                    _awaitingAgreement = false;
                                    _agreedUserIds.clear();
                                  }
                                });
                                _multiplayerService.sendBetEnable(widget.teamId, !v);
                                _teamService.updateBettingEnabled(widget.teamId, !v, hostAiEnabled: v);
                              } : null,
                              activeTrackColor: Colors.amber.shade700,
                              activeThumbColor: Colors.amber,
                            ),
                          ],
                        ),
                      ),
                if (_bettingEnabled) ...[
                  const SizedBox(height: 8),
                  if (_myUserId != null) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withAlpha(6), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        if ((_betAmounts[_myUserId] ?? 0) > 0)
                          Text('Mise fixée : ${_betAmounts[_myUserId]} pièces',
                            style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                          )
                        else ...[
                          Text('Ma mise', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                          const Spacer(),
                          SizedBox(
                            width: 80, height: 36,
                            child: TextField(
                              controller: _betController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                hintText: 'Montant',
                                hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                filled: true, fillColor: Colors.white.withAlpha(15),
                              ),
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _onFixBet,
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), minimumSize: Size.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                            child: const Text('Miser', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.transparent, const Color(0xFF1C1C2E).withAlpha(220)],
            ),
          ),
          child: isHost
                      ? SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: (_allPlayersFixed && (!_bettingEnabled || _allBetsSet))
                                ? _onHostStartGame
                                : null,
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: (_allPlayersFixed && (!_bettingEnabled || _allBetsSet))
                                  ? Colors.amber.shade700
                                  : null,
                              foregroundColor: (_allPlayersFixed && (!_bettingEnabled || _allBetsSet))
                                  ? Colors.white
                                  : null,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _awaitingAgreement
                                  ? (_allAgreed
                                      ? 'Tout le monde est d\'accord !'
                                      : 'En attente des accords...')
                                  : (_bettingEnabled && _betsAreDifferent)
                                      ? 'Proposer les mises aux joueurs'
                                      : (_bettingEnabled && !_allBetsSet)
                                          ? 'En attente des mises...'
                                          : (!_allPlayersFixed
                                              ? 'En attente des validations...'
                                              : 'Démarrer la partie'),
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        )
              : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (myFixedColor != null)
                              Text(
                                _awaitingAgreement
                                    ? (_agreedUserIds.contains(_myUserId)
                                        ? 'En attente des autres joueurs...'
                                        : 'En attente de ton accord...')
                                    : 'En attente que l\'hôte démarre...',
                                style: const TextStyle(color: Colors.white54, fontSize: 13),
                              )
                            else
                              Text('Choisis et valide ta couleur !',
                                  style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
        ),
      ],
    );
  }

  Widget _memberSlot(Map<String, dynamic>? member) {
    if (member == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(radius: 28, backgroundColor: Colors.white12, child: const Icon(Icons.person_add, color: Colors.white38, size: 28)),
          const SizedBox(height: 6),
          const Text('Slot libre', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ],
      );
    }

    final profile = member['profile'] as Map<String, dynamic>? ?? {};
    final username = profile['username']?.toString() ?? profile['full_name']?.toString() ?? 'Joueur';
    final avatarUrl = profile['avatar_url']?.toString();
    final colorName = member['color']?.toString() ?? 'yellow';
    final color = LudoColor.values.firstWhere((c) => c.name == colorName, orElse: () => LudoColor.yellow);
    final baseColor = LudoBoardLayout.colorValues[color] ?? Colors.amber;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: baseColor, width: 2.5),
            boxShadow: [BoxShadow(color: baseColor.withAlpha(80), blurRadius: 8, spreadRadius: 1)],
          ),
          child: CircleAvatar(
            radius: 26, backgroundColor: Colors.white12,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null || avatarUrl.isEmpty ? Icon(Icons.person, color: baseColor, size: 26) : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(username, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Icon(Icons.circle, color: baseColor, size: 10),
      ],
    );
  }
}