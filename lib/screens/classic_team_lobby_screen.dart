import 'dart:async';

import 'package:flutter/material.dart';
import '../screens/game_screen.dart';
import '../service/team_lobby_service.dart';

class ClassicTeamLobbyScreen extends StatefulWidget {
  final String teamId;
  final bool isHost;

  const ClassicTeamLobbyScreen({super.key, required this.teamId, required this.isHost});

  @override
  State<ClassicTeamLobbyScreen> createState() => _ClassicTeamLobbyScreenState();
}

class _ClassicTeamLobbyScreenState extends State<ClassicTeamLobbyScreen> {
  final TeamLobbyService _teamLobbyService = TeamLobbyService();
  bool _guestReady = false;
  Map<String, dynamic>? team;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadTeam();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) => _loadTeam());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTeam() async {
    final loadedTeam = await _teamLobbyService.getTeam(widget.teamId);
    if (!mounted) return;
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

  void _startMatchmaking() {
    if (team == null || team?['guest_id'] == null) return;
    if (!(team?['guest_ready'] == true)) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GameScreen()),
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

    return Column(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
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

    return Scaffold(
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
                Text('Rejoins l’équipe avec l’ID ci-dessus ou attends ton coéquipier.', style: const TextStyle(color: Colors.white)),
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
                const SizedBox(height: 24),
                if (isHost)
                  ElevatedButton(
                    onPressed: team != null && team?['guest_id'] != null && team?['guest_ready'] == true
                        ? _startMatchmaking
                        : null,
                    style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: const Text('Matchmaking'),
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
            ),
          ),
        ),
      ),
    );
  }
}
