import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../service/game_channel_service.dart';
import '../service/private_match_service.dart';
import '../service/team_lobby_service.dart';
import 'classic_team_lobby_screen.dart';
import 'private_belote_game_screen.dart';

class PrivateGameLobbyScreen extends StatefulWidget {
  final String matchCode;
  final bool isTeamA;
  final bool isHost;
  final Map<String, dynamic> match;
  final String localPosition;

  const PrivateGameLobbyScreen({
    super.key,
    required this.matchCode,
    required this.isTeamA,
    required this.isHost,
    required this.match,
    required this.localPosition,
  });

  @override
  State<PrivateGameLobbyScreen> createState() => _PrivateGameLobbyScreenState();
}

class _PrivateGameLobbyScreenState extends State<PrivateGameLobbyScreen> {
  final GameChannelService _gameChannel = GameChannelService();
  final TeamLobbyService _teamLobbyService = TeamLobbyService();
  final PrivateMatchService _privateMatchService = PrivateMatchService();
  final TextEditingController _betController = TextEditingController();

  static const List<String> positions = ['Sud', 'Nord', 'Est', 'Ouest'];
  final Map<String, int?> _bets = {};
  final Set<String> _acceptedPositions = {};
  bool _gameStarting = false;
  bool _negotiating = false;

  StreamSubscription<Map<String, dynamic>>? _subscription;
  StreamSubscription<Map<String, dynamic>>? _matchSubscription;

  @override
  void initState() {
    super.initState();
    for (final pos in positions) {
      _bets[pos] = null;
    }
    _subscription = _gameChannel.events.listen(_handleEvent);
    _initMatchSubscription();
  }

  Future<void> _initMatchSubscription() async {
    final match = await _privateMatchService.getMatch(widget.matchCode, forceRefresh: true);
    if (match != null && mounted) {
      if (match['status'] == 'cancelled') {
        _returnToTeamLobby();
        return;
      }
      _applyMatchState(match);
    }

    _matchSubscription = _privateMatchService.subscribeToMatch(widget.matchCode).listen((match) {
      if (match['status'] == 'cancelled') {
        if (mounted) _returnToTeamLobby();
        return;
      }
      if (mounted) {
        _applyMatchState(match);
      }
    });
  }

  void _returnToTeamLobby() {
    final teamId = widget.isTeamA ? widget.match['team_a_id'] : widget.match['team_b_id'];
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ClassicTeamLobbyScreen(
          teamId: teamId as String,
          isHost: widget.isHost,
        ),
      ),
    );
  }

  void _applyMatchState(Map<String, dynamic> match) {
    final betsRaw = match['bets'] as Map? ?? {};
    final acceptedRaw = match['accepted_by'] as List? ?? [];

    final newBets = <String, int?>{};
    for (final pos in positions) {
      newBets[pos] = betsRaw[pos] as int?;
    }

    final newAccepted = acceptedRaw.cast<String>().toSet();

    final betsChanged = !_mapsEqual(_bets, newBets);
    final acceptedChanged = !_setsEqual(_acceptedPositions, newAccepted);

    if (!betsChanged && !acceptedChanged) return;

    setState(() {
      _bets.clear();
      _bets.addAll(newBets);
      _acceptedPositions.clear();
      _acceptedPositions.addAll(newAccepted);
    });

    if (betsChanged) _checkAllBets();
  }

  bool _mapsEqual(Map<String, int?> a, Map<String, int?> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }

  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }

  @override
  void dispose() {
    _betController.dispose();
    _subscription?.cancel();
    _matchSubscription?.cancel();
    super.dispose();
  }

  void _handleEvent(Map<String, dynamic> event) {
    final action = event['action'] as String?;
    switch (action) {
      case 'cancel':
        _navigateToTeamLobby();
        break;
      case 'start_game':
        _startGame();
        break;
    }
  }

  void _placeBet() {
    final bet = int.tryParse(_betController.text.trim()) ?? 0;
    if (bet <= 0) return;

    final authProvider = context.read<AuthProvider?>();
    final coins = int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;
    if (bet > coins) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jeton insuffisant')),
      );
      return;
    }

    _betController.clear();
    _privateMatchService.placeBet(widget.matchCode, widget.localPosition, bet);
  }

  void _checkAllBets() {
    final allNonNull = _bets.values.every((v) => v != null);
    if (!allNonNull) return;

    final values = _bets.values.cast<int>().toSet();
    if (values.length == 1) {
      _startGame();
    } else {
      _showNegotiationPopup();
    }
  }

  Map<String, dynamic>? _profileForPosition(String pos) {
    switch (pos) {
      case 'Sud': return widget.match['team_a_host_profile'] as Map<String, dynamic>?;
      case 'Nord': return widget.match['team_a_guest_profile'] as Map<String, dynamic>?;
      case 'Est': return widget.match['team_b_guest_profile'] as Map<String, dynamic>?;
      case 'Ouest': return widget.match['team_b_host_profile'] as Map<String, dynamic>?;
      default: return null;
    }
  }

  void _showNegotiationPopup() {
    if (_negotiating || !mounted) return;
    _negotiating = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            final myPos = widget.localPosition;
            final iAccepted = _acceptedPositions.contains(myPos);

            return AlertDialog(
              title: const Text('Négociation'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final pos in positions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        () {
                          final profile = _profileForPosition(pos);
                          final name = profile?['username'] ?? profile?['full_name'] ?? pos;
                          return '$name: ${_bets[pos]}';
                        }(),
                        style: TextStyle(
                          fontWeight: _acceptedPositions.contains(pos) ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  if (iAccepted)
                    const Text('En attente des autres...')
                  else
                    Column(
                      children: [
                        Text('Acceptes-tu ta mise de ${_bets[myPos]} ?'),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                _privateMatchService.acceptBet(widget.matchCode, myPos);
                                setDlgState(() {});
                              },
                              child: const Text('Oui'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                _privateMatchService.rejectBets(widget.matchCode);
                                Navigator.pop(ctx);
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                              child: const Text('Non'),
                            ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      _negotiating = false;
    });
  }

  Future<void> _cancelPrivateMatch() async {
    final match = widget.match;
    final teamAId = match['team_a_id'] as String;
    final teamBId = match['team_b_id'] as String;

    await _teamLobbyService.resetGame(teamAId);
    await _teamLobbyService.resetGame(teamBId);

    for (final teamId in [teamAId, teamBId]) {
      final profile = match[teamId == teamAId ? 'team_a_host_profile' : 'team_b_host_profile'] as Map<String, dynamic>? ?? {};
      final clean = Map<String, dynamic>.from(profile)
        ..remove('private_match_code')
        ..remove('private_match_status');
      await _teamLobbyService.updateHostProfile(teamId, clean);
    }

    await _privateMatchService.cancelMatch(widget.matchCode);
    _gameChannel.send('cancel', {});
    _navigateToTeamLobby();
  }

  void _navigateToTeamLobby() {
    final teamId = widget.isTeamA
        ? widget.match['team_a_id'] as String
        : widget.match['team_b_id'] as String;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => ClassicTeamLobbyScreen(
          teamId: teamId,
          isHost: widget.isHost,
        ),
      ),
      (route) => route.isFirst,
    );
  }

  void _startGame() {
    if (_gameStarting) return;
    _gameStarting = true;

    final match = widget.match;

    String n(Object? v, String fallback) => v?.toString() ?? fallback;

    final sudId = n(match['team_a_host_profile']?['id'], '');
    final nordId = n(match['team_a_guest_profile']?['id'], '');
    final estId = n(match['team_b_guest_profile']?['id'], '');
    final ouestId = n(match['team_b_host_profile']?['id'], '');

    final sudName = n(match['team_a_host_profile']?['username'], n(match['team_a_host_profile']?['full_name'], 'Sud'));
    final nordName = n(match['team_a_guest_profile']?['username'], n(match['team_a_guest_profile']?['full_name'], 'Nord'));
    final estName = n(match['team_b_guest_profile']?['username'], n(match['team_b_guest_profile']?['full_name'], 'Est'));
    final ouestName = n(match['team_b_host_profile']?['username'], n(match['team_b_host_profile']?['full_name'], 'Ouest'));

    final sudAvatar = n(match['team_a_host_profile']?['avatar_url'], '');
    final nordAvatar = n(match['team_a_guest_profile']?['avatar_url'], '');
    final estAvatar = n(match['team_b_guest_profile']?['avatar_url'], '');
    final ouestAvatar = n(match['team_b_host_profile']?['avatar_url'], '');

    final Map<String, String> playerNames = {
      'Sud': sudName,
      'Nord': nordName,
      'Est': estName,
      'Ouest': ouestName,
    };
    final Map<String, String> playerAvatars = {
      'Sud': sudAvatar,
      'Nord': nordAvatar,
      'Est': estAvatar,
      'Ouest': ouestAvatar,
    };
    final Map<String, String> playerIds = {
      'Sud': sudId,
      'Nord': nordId,
      'Est': estId,
      'Ouest': ouestId,
    };

    final bet = _bets.values.where((v) => v != null).cast<int>().firstOrNull ?? 0;

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateBeloteGameScreen(
          matchCode: widget.matchCode,
          localPosition: widget.localPosition,
          playerNames: playerNames,
          playerAvatars: playerAvatars,
          playerIds: playerIds,
          bet: bet,
        ),
      ),
    );
  }

  Widget _playerCard(Map<String, dynamic>? profile, String position) {
    final username = profile?['username'] ?? profile?['full_name'] ?? position;
    final avatarUrl = profile?['avatar_url']?.toString();
    final bet = _bets[position];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 20,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty
              ? Text(username.substring(0, 1).toUpperCase(), style: const TextStyle(fontSize: 14))
              : null,
        ),
        const SizedBox(height: 2),
        Text(position, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
        Text(username, style: const TextStyle(fontSize: 9), overflow: TextOverflow.ellipsis, maxLines: 1),
        if (bet != null)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('$bet', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final match = widget.match;

    final sudProfile = match['team_a_host_profile'] as Map<String, dynamic>?;
    final nordProfile = match['team_a_guest_profile'] as Map<String, dynamic>?;
    final estProfile = match['team_b_guest_profile'] as Map<String, dynamic>?;
    final ouestProfile = match['team_b_host_profile'] as Map<String, dynamic>?;

    final authProvider = context.watch<AuthProvider?>();
    final coins = int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;
    final myPos = widget.localPosition;
    final hasBet = _bets[myPos] != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Dissoudre la table'),
            content: const Text('Veux-tu vraiment dissoudre la table privée ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
              ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Oui')),
            ],
          ),
        );
        if (confirm == true && mounted) _cancelPrivateMatch();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Table privée #${widget.matchCode}'),
        backgroundColor: const Color(0xFF006400),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Partie privée 2v2', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildTeamSection('Équipe A (Sud/Nord)', sudProfile, 'Sud', nordProfile, 'Nord'),
                        const Divider(color: Colors.white38, height: 16),
                        _buildTeamSection('Équipe B (Est/Ouest)', estProfile, 'Est', ouestProfile, 'Ouest'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(46, 255, 255, 255),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text('Jeton disponible: $coins', style: const TextStyle(color: Colors.white, fontSize: 16)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _betController,
                              decoration: InputDecoration(
                                labelText: 'Mise ($myPos)',
                                labelStyle: const TextStyle(color: Colors.white70),
                                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                              ),
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              enabled: !hasBet,
                            ),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton(
                            onPressed: hasBet ? null : _placeBet,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              minimumSize: const Size(100, 48),
                            ),
                            child: const Text('Miser', style: TextStyle(color: Colors.black)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildTeamSection(
    String title,
    Map<String, dynamic>? profile1,
    String pos1,
    Map<String, dynamic>? profile2,
    String pos2,
  ) {

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: const Color.fromARGB(46, 255, 255, 255),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _playerCard(profile1, pos1),
              _playerCard(profile2, pos2),
            ],
          ),
        ],
      ),
    );
  }
}
