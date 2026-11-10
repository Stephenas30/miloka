import 'dart:async';

import 'package:flutter/material.dart';
import '../screens/game_screen.dart';
import '../screens/private_game_lobby_screen.dart';
import '../service/friends_service.dart';
import '../service/game_channel_service.dart';
import '../service/private_match_service.dart';
import '../service/team_invitation_service.dart';
import '../service/team_lobby_service.dart';
import '../utils/image_cache.dart';

class ClassicTeamLobbyScreen extends StatefulWidget {
  final String teamId;
  final bool isHost;

  const ClassicTeamLobbyScreen({super.key, required this.teamId, required this.isHost});

  @override
  State<ClassicTeamLobbyScreen> createState() => _ClassicTeamLobbyScreenState();
}

class _ClassicTeamLobbyScreenState extends State<ClassicTeamLobbyScreen> {
  final TeamLobbyService _teamLobbyService = TeamLobbyService();
  final GameChannelService _gameChannel = GameChannelService();
  final PrivateMatchService _privateMatchService = PrivateMatchService();
  bool _guestReady = false;
  Map<String, dynamic>? team;
  Timer? _refreshTimer;
  bool _isNavigating = false;

  String? _privateMatchCode;
  String? _privateMatchStatus;
  Timer? _privateMatchTimer;

  bool _isSearching = false;
  Timer? _matchmakingTimer;

  @override
  void initState() {
    super.initState();
    _loadTeam();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadTeam());
    _privateMatchTimer = Timer.periodic(const Duration(seconds: 2), (_) => _checkPrivateMatchStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _privateMatchTimer?.cancel();
    _matchmakingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    if (_isNavigating) return;

    if (team != null) {
      final exists = await _teamLobbyService.teamExists(widget.teamId);
      if (!mounted) return;
      if (!exists) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }
    }

    final loadedTeam = await _teamLobbyService.getTeam(widget.teamId);
    if (!mounted) return;

    final hostProfile = loadedTeam?['host_profile'] as Map<String, dynamic>?;
    final matchCode = hostProfile?['private_match_code'] as String?;
    final matchStatus = hostProfile?['private_match_status'] as String?;

    if (loadedTeam?['status'] == 'playing') {
      if (matchCode != null) {
        _refreshTimer?.cancel();
        final match = await _privateMatchService.getMatch(matchCode, forceRefresh: true);
        if (match != null && match['status'] == 'ready') {
          _gameChannel.connect(matchCode);
          if (!mounted) return;
          final bool thisIsTeamA = widget.teamId == match['team_a_id'];
          final bool thisIsTeamB = widget.teamId == match['team_b_id'];
          if (!thisIsTeamA && !thisIsTeamB) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => PrivateGameLobbyScreen(
                matchCode: matchCode,
                isTeamA: thisIsTeamA,
                match: match,
                localPosition: thisIsTeamA ? (widget.isHost ? 'Sud' : 'Nord') : (widget.isHost ? 'Ouest' : 'Est'),
                isHost: widget.isHost,
              ),
            ),
          );
          return;
        }
        return;
      }

      // Fallback: find match in DB where this team is team B
      final fallbackMatch = await _privateMatchService.findMatchByTeamId(widget.teamId);
      if (fallbackMatch != null && fallbackMatch['status'] == 'ready') {
        _refreshTimer?.cancel();
        final fc = fallbackMatch['match_code'] as String;
        _gameChannel.connect(fc);
        if (!mounted) return;
        final bool thisIsTeamA = widget.teamId == fallbackMatch['team_a_id'];
        final bool thisIsTeamB = widget.teamId == fallbackMatch['team_b_id'];
        if (!thisIsTeamA && !thisIsTeamB) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PrivateGameLobbyScreen(
              matchCode: fc,
              isTeamA: thisIsTeamA,
              match: fallbackMatch,
              localPosition: thisIsTeamA ? (widget.isHost ? 'Sud' : 'Nord') : (widget.isHost ? 'Ouest' : 'Est'),
              isHost: widget.isHost,
            ),
          ),
        );
        return;
      }

      if (!widget.isHost) {
        if (!mounted) return;
        _refreshTimer?.cancel();
        _gameChannel.connect(widget.teamId);
        final guestProfile = loadedTeam?['guest_profile'] as Map<String, dynamic>?;
        final hostName = hostProfile?['username'] ?? hostProfile?['full_name'] ?? 'Sud';
        final guestName = guestProfile?['username'] ?? guestProfile?['full_name'] ?? 'Nord';
        final hostAvatar = hostProfile?['avatar_url']?.toString() ?? '';
        final guestAvatar = guestProfile?['avatar_url']?.toString() ?? '';
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GameScreen(
              teamId: widget.teamId,
              isHost: false,
              humanPlayers: const {'Sud', 'Nord'},
              playerNames: {'Sud': hostName, 'Nord': guestName},
              playerAvatars: {'Sud': hostAvatar, 'Nord': guestAvatar},
            ),
          ),
        );
        return;
      }
    }

    if (loadedTeam?['status'] == 'public_waiting') {
      if (widget.isHost && !_isSearching) {
        setState(() => _isSearching = true);
      }
    }

    if (matchCode != null && _privateMatchCode == null) {
      _privateMatchCode = matchCode;
    }

    if (matchCode != null) {
      if (matchStatus == 'cancelled') {
        _privateMatchCode = null;
        _privateMatchStatus = null;
      } else if (matchStatus == 'ready') {
        _privateMatchStatus = 'ready';
      } else {
        _privateMatchStatus = matchStatus ?? 'waiting';
      }
    }

    setState(() {
      team = loadedTeam;
      _guestReady = loadedTeam?['guest_ready'] ?? false;
    });
  }

  Future<void> _toggleReady() async {
    if (team == null) return;
    final ready = !_guestReady;
    if (await _teamLobbyService.updateGuestReady(widget.teamId, ready)) {
      setState(() {
        _guestReady = ready;
        team?['guest_ready'] = ready;
      });
    }
  }

  Future<void> _startGame(String gameType) async {
    if (team == null || team?['guest_id'] == null) return;
    if (!(team?['guest_ready'] == true)) return;

    await _teamLobbyService.startGame(widget.teamId);
    await _gameChannel.connect(widget.teamId);

    final hostProfile = team?['host_profile'] as Map<String, dynamic>?;
    final guestProfile = team?['guest_profile'] as Map<String, dynamic>?;
    final hostName = hostProfile?['username'] ?? hostProfile?['full_name'] ?? 'Sud';
    final guestName = guestProfile?['username'] ?? guestProfile?['full_name'] ?? 'Nord';
    final hostAvatar = hostProfile?['avatar_url']?.toString() ?? '';
    final guestAvatar = guestProfile?['avatar_url']?.toString() ?? '';

    final isHost = gameType != 'join_private';

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(
          teamId: widget.teamId,
          isHost: isHost,
          humanPlayers: const {'Sud', 'Nord'},
          playerNames: {'Sud': hostName, 'Nord': guestName},
          playerAvatars: {'Sud': hostAvatar, 'Nord': guestAvatar},
        ),
      ),
    );
  }

  Future<void> _startPublicMatchmaking() async {
    if (team == null || team?['guest_id'] == null) return;
    if (!(team?['guest_ready'] == true)) return;

    setState(() => _isSearching = true);
    await _teamLobbyService.setPublicWaiting(widget.teamId);

    _matchmakingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkForPublicMatch());
  }

  Future<void> _cancelPublicMatchmaking() async {
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;
    setState(() => _isSearching = false);
    await _teamLobbyService.cancelPublicWaiting(widget.teamId);
  }

  Future<void> _checkForPublicMatch() async {
    if (!widget.isHost) return;
    if (team == null) return;

    final freshTeam = await _teamLobbyService.getTeam(widget.teamId);
    if (freshTeam?['status'] != 'public_waiting') return;

    final opponent = await _teamLobbyService.findPublicMatch(widget.teamId);
    if (opponent == null) return;

    final opponentId = opponent['team_id'] as String;

    final claimed = await _teamLobbyService.claimForMatch(opponentId);
    if (!claimed) return;

    if (!mounted) return;
    await _onPublicMatchFound(opponent);
  }

  Future<void> _onPublicMatchFound(Map<String, dynamic> opponent) async {
    _isNavigating = true;
    _refreshTimer?.cancel();
    _privateMatchTimer?.cancel();
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;

    final opponentId = opponent['team_id'] as String;
    final myHostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
    final myGuestProfile = team?['guest_profile'] as Map<String, dynamic>? ?? {};
    final oppHostProfile = opponent['host_profile'] as Map<String, dynamic>? ?? {};
    final oppGuestProfile = opponent['guest_profile'] as Map<String, dynamic>? ?? {};

    final matchCode = await _privateMatchService.createPublicMatch(
      teamAId: widget.teamId,
      teamAHostId: team?['host_id'] as String,
      teamAHostProfile: myHostProfile,
      teamAGuestId: team?['guest_id'] as String,
      teamAGuestProfile: myGuestProfile,
      teamBId: opponentId,
      teamBHostId: opponent['host_id'] as String,
      teamBHostProfile: oppHostProfile,
      teamBGuestId: opponent['guest_id'] as String,
      teamBGuestProfile: oppGuestProfile,
    );

    if (matchCode == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur réseau lors de la création du match.')),
        );
      }
      return;
    }

    final updatedMyProfile = Map<String, dynamic>.from(myHostProfile);
    updatedMyProfile['private_match_code'] = matchCode;
    updatedMyProfile['private_match_status'] = 'ready';
    await _teamLobbyService.updateHostProfile(widget.teamId, updatedMyProfile);
    await _teamLobbyService.startGame(widget.teamId);

    final updatedOppProfile = Map<String, dynamic>.from(oppHostProfile);
    updatedOppProfile['private_match_code'] = matchCode;
    updatedOppProfile['private_match_status'] = 'ready';
    await _teamLobbyService.updateHostProfile(opponentId, updatedOppProfile);
    await _teamLobbyService.startGame(opponentId);

    await _gameChannel.connect(matchCode);

    final match = await _privateMatchService.getMatch(matchCode, forceRefresh: true);
    if (!mounted || match == null) return;

    final bool thisIsTeamA = widget.teamId == match['team_a_id'];
    final bool thisIsTeamB = widget.teamId == match['team_b_id'];
    if (!thisIsTeamA && !thisIsTeamB) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur: équipe non reconnue dans le match')),
        );
      }
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateGameLobbyScreen(
          matchCode: matchCode,
          isTeamA: thisIsTeamA,
          isHost: widget.isHost,
          match: match,
          localPosition: thisIsTeamA ? (widget.isHost ? 'Sud' : 'Nord') : (widget.isHost ? 'Ouest' : 'Est'),
        ),
      ),
    );
  }

  void _showPrivateGamePopup() {
    final roomController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 280,
          height: 260,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                "Partie privée",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: roomController,
                decoration: const InputDecoration(labelText: "Numéro de salle"),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        final code = roomController.text.trim();
                        if (code.isEmpty) return;
                        Navigator.pop(ctx);
                        _joinPrivateMatch(code);
                      },
                      child: const Text('Joindre'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _createPrivateMatch();
                      },
                      child: const Text('Créer'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _createPrivateMatch() async {
    if (team == null || team?['guest_id'] == null) return;

    final hostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
    final guestProfile = team?['guest_profile'] as Map<String, dynamic>? ?? {};

    try {
      final code = await _privateMatchService.createMatch(
        teamAId: widget.teamId,
        hostId: team?['host_id'] as String,
        hostProfile: hostProfile,
        guestId: team?['guest_id'] as String,
        guestProfile: guestProfile,
      );

      if (code == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Erreur réseau : impossible de créer le match.')),
          );
        }
        return;
      }

      final updatedProfile = Map<String, dynamic>.from(hostProfile);
      updatedProfile['private_match_code'] = code;
      updatedProfile['private_match_status'] = 'waiting';
      await _teamLobbyService.updateHostProfile(widget.teamId, updatedProfile);

      setState(() {
        _privateMatchCode = code;
        _privateMatchStatus = 'waiting';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e')),
        );
      }
    }
  }

  Future<void> _joinPrivateMatch(String code) async {
    if (team == null || team?['guest_id'] == null) return;

    final hostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
    final guestProfile = team?['guest_profile'] as Map<String, dynamic>? ?? {};

    final success = await _privateMatchService.joinMatch(
      matchCode: code,
      teamBId: widget.teamId,
      hostId: team?['host_id'] as String,
      hostProfile: hostProfile,
      guestId: team?['guest_id'] as String,
      guestProfile: guestProfile,
    );

    if (success) {
      final updatedProfile = Map<String, dynamic>.from(hostProfile);
      updatedProfile['private_match_code'] = code;
      updatedProfile['private_match_status'] = 'ready';
      await _teamLobbyService.updateHostProfile(widget.teamId, updatedProfile);

      final match = await _privateMatchService.getMatch(code, forceRefresh: true);
      if (match != null && mounted) {
        _startPrivateGame(match, isTeamA: false);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de rejoindre cette salle')),
        );
      }
    }
  }

  Future<void> _cancelPrivateMatch() async {
    if (_privateMatchCode == null) return;

    await _privateMatchService.cancelMatch(_privateMatchCode!);

    final hostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
    final updatedProfile = Map<String, dynamic>.from(hostProfile);
    updatedProfile.remove('private_match_code');
    updatedProfile.remove('private_match_status');
    await _teamLobbyService.updateHostProfile(widget.teamId, updatedProfile);

    setState(() {
      _privateMatchCode = null;
      _privateMatchStatus = null;
    });
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
                    onTap: () {
                      setDialogState(() {
                        selectedId = fid;
                        selectedName = fname;
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.amber : Colors.white12,
                          width: isSelected ? 1.5 : 1,
                        ),
                        color: isSelected ? Colors.amber.withAlpha(25) : Colors.white.withAlpha(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white24,
                            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                                ? cachedNetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(Icons.person, color: Colors.white38)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fname,
                              style: const TextStyle(color: Colors.white, fontSize: 15),
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: isSelected ? Colors.amber : Colors.white38,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: selectedId != null
                  ? () async {
                      Navigator.pop(ctx);
                      final hostProfile = team?['host_profile'] as Map<String, dynamic>?;
                      final hostName = hostProfile?['username']?.toString() ?? hostProfile?['full_name']?.toString() ?? 'Quelqu\'un';
                      try {
                        await TeamInvitationService().sendInvitation(
                          inviteeId: selectedId!,
                          teamId: widget.teamId,
                          inviterName: hostName,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Invitation envoyée à $selectedName')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erreur: $e')),
                          );
                        }
                      }
                    }
                  : null,
              child: const Text('Envoyer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _checkPrivateMatchStatus() async {
    if (_privateMatchCode == null) return;

    final match = await _privateMatchService.getMatch(_privateMatchCode!, forceRefresh: true);
    if (match == null || !mounted) return;

    if (match['status'] == 'cancelled') {
      final hostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
      final updatedProfile = Map<String, dynamic>.from(hostProfile);
      updatedProfile.remove('private_match_code');
      updatedProfile.remove('private_match_status');
      await _teamLobbyService.updateHostProfile(widget.teamId, updatedProfile);
      setState(() {
        _privateMatchCode = null;
        _privateMatchStatus = null;
      });
      return;
    }

    if (match['status'] == 'ready' && _privateMatchStatus != 'ready') {
      if (team == null) return;

      final hostProfile = team?['host_profile'] as Map<String, dynamic>? ?? {};
      final updatedProfile = Map<String, dynamic>.from(hostProfile);
      updatedProfile['private_match_status'] = 'ready';
      await _teamLobbyService.updateHostProfile(widget.teamId, updatedProfile);

      setState(() {
        _privateMatchStatus = 'ready';
      });

      await _startPrivateGame(match, isTeamA: true);
    }
  }

  Future<void> _startPrivateGame(Map<String, dynamic> match, {required bool isTeamA}) async {
    _isNavigating = true;
    _refreshTimer?.cancel();
    _privateMatchTimer?.cancel();
    final matchCode = match['match_code'] as String;

    await _teamLobbyService.startGame(widget.teamId);
    await _gameChannel.connect(matchCode);

    if (!mounted) return;
    final String localPos;
    if (isTeamA) {
      localPos = widget.isHost ? 'Sud' : 'Nord';
    } else {
      localPos = widget.isHost ? 'Ouest' : 'Est';
    }
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateGameLobbyScreen(
          matchCode: matchCode,
          isTeamA: isTeamA,
          isHost: widget.isHost,
          match: match,
          localPosition: localPos,
        ),
      ),
    );
  }

  Widget _playerCard(Map<String, dynamic>? profile, String position, {bool isReady = false}) {
    if (profile == null) {
      return Column(
        children: [
          CircleAvatar(radius: 32, child: Text(position.substring(0, 1))),
          const SizedBox(height: 8),
          Text(position),
          const SizedBox(height: 4),
          const Text('En attente', style: TextStyle(fontSize: 12)),
        ],
      );
    }

    final username = profile['username'] ?? profile['full_name'] ?? 'Joueur';
    final avatarUrl = profile['avatar_url']?.toString();
    const level = 1;

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? cachedNetworkImage(avatarUrl)
              : null,
          child: avatarUrl == null || avatarUrl.isEmpty ? Text(username.substring(0, 1).toUpperCase()) : null,
        ),
        const SizedBox(height: 8),
        Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Niveau $level', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (widget.isHost == false && position == 'Sud')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(isReady ? 'Prêt' : 'Pas prêt', style: TextStyle(color: isReady ? Colors.green : Colors.red)),
          ),
        if (widget.isHost == true && position == 'Nord')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(team?['guest_id'] != null ? 'Prêt: ${team?['guest_ready'] == true ? 'Oui' : 'Non'}' : 'En attente',
                style: TextStyle(color: team?['guest_ready'] == true ? Colors.green : Colors.red)),
          ),
      ],
      ),
    );
  }

  String _buildStatusText(bool isHost) {
    if (!isHost) {
      return 'Ton hôte est en face. Appuie sur Prêt pour démarrer.';
    }

    if (team == null || team!['guest_id'] == null) {
      return 'En attente d’un coéquipier';
    }

    return team!['guest_ready'] == true
        ? 'Ton coéquipier est prêt'
        : 'Ton coéquipier n’est pas prêt';
  }

  @override
  Widget build(BuildContext context) {
    final hostProfile = team?['host_profile'] as Map<String, dynamic>?;
    final guestProfile = team?['guest_profile'] as Map<String, dynamic>?;
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
        if (_isSearching) {
          await _cancelPublicMatchmaking();
        }
        if (isHost) {
          await _teamLobbyService.deleteTeam(widget.teamId);
        } else {
          await _teamLobbyService.removeGuest(widget.teamId);
        }
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text('Table Classique #${widget.teamId}'),
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
                Text('Rejoins l\'équipe avec l\'ID ci-dessus ou attends ton coéquipier.', style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                    color: const Color.fromARGB(46, 255, 255, 255),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Équipe: ${widget.teamId}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      if (!isHost)
                        ElevatedButton(
                          onPressed: _toggleReady,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _guestReady ? Colors.red : Colors.green,
                          ),
                          child: Text(_guestReady ? 'Annuler' : 'Prêt'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _playerCard(isHost ? guestProfile : hostProfile, 'Nord', isReady: team?['guest_ready'] == true),
                      Container(
                        width: 1,
                        height: 200,
                        color: Colors.white30,
                      ),
                      _playerCard(isHost ? hostProfile : guestProfile, 'Sud', isReady: _guestReady),
                    ],
                  ),
                ),
                if (_privateMatchCode != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(46, 255, 255, 255),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text('Table: ${_privateMatchCode!}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                        const SizedBox(height: 8),
                        const Text('En attente d\'équipe adverse', style: TextStyle(color: Colors.orange, fontSize: 14)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (isHost)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _cancelPrivateMatch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: const Text('Annuler'),
                      ),
                    ),
                ] else if (team?['status'] == 'public_waiting' || _isSearching) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      color: const Color.fromARGB(46, 255, 255, 255),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(color: Colors.orange),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Recherche d\'un adversaire...',
                          style: TextStyle(color: Colors.orange, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'En attente d\'une autre équipe',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        if (isHost) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () async {
                                await _cancelPublicMatchmaking();
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                minimumSize: const Size.fromHeight(48),
                              ),
                              child: const Text('Annuler'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 24),
                  if (isHost)
                    Column(
                      children: [
                        if (team?['guest_id'] == null) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _showInviteFriendDialog,
                              icon: const Icon(Icons.person_add),
                              label: const Text('Inviter un ami'),
                              style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: team != null && team?['guest_id'] != null && team?['guest_ready'] == true
                                    ? _showPrivateGamePopup
                                    : null,
                                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                                child: const Text('Partie privée'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: team != null && team?['guest_id'] != null && team?['guest_ready'] == true
                                    ? () => _startPublicMatchmaking()
                                    : null,
                                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                                child: const Text('Partie publique'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: team != null && team?['guest_id'] != null && team?['guest_ready'] == true
                                ? () => _startGame('coop_vs_ai')
                                : null,
                            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                            child: const Text('Partie contre IA'),
                          ),
                        ),
                      ],
                    ),
                  if (!isHost)
                    ElevatedButton(
                      onPressed: _toggleReady,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _guestReady ? Colors.red : Colors.green,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: Text(_guestReady ? 'Annuler' : 'Prêt'),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    _buildStatusText(isHost),
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}