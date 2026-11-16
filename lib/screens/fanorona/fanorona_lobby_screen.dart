import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../service/fanorona/lobby_service.dart';
import '../../service/fanorona/invitation_service.dart';
import '../../service/friends_service.dart';
import '../../utils/image_cache.dart';
import 'fanorona_screen.dart';

class FanoronaLobbyScreen extends StatefulWidget {
  final String teamId;
  final bool isHost;
  final bool autoPublic;

  const FanoronaLobbyScreen({
    super.key,
    required this.teamId,
    required this.isHost,
    this.autoPublic = false,
  });

  @override
  State<FanoronaLobbyScreen> createState() => _FanoronaLobbyScreenState();
}

class _FanoronaLobbyScreenState extends State<FanoronaLobbyScreen> {
  final FanoronaTeamLobbyService _teamService = FanoronaTeamLobbyService();
  Map<String, dynamic>? _team;
  Timer? _refreshTimer;
  bool _isNavigating = false;

  bool _isSearching = false;
  Timer? _matchmakingTimer;
  int _matchmakingSeconds = 0;
  static const int _matchmakingTimeout = 60;

  String? _myUserId;

  final TextEditingController _betController = TextEditingController();
  int _myCoins = 0;
  bool _savingBet = false;

  int _betOf(Map<String, dynamic>? member) =>
      ((member?['profile'] as Map?)?['bet'] as int?) ?? 0;

  bool _agreedOf(Map<String, dynamic>? member) =>
      ((member?['profile'] as Map?)?['bet_agreed'] as bool?) ?? false;

  Map<String, dynamic>? get _myMember {
    for (final m in _members) {
      if (m['id']?.toString() == _myUserId) return m;
    }
    return null;
  }

  Map<String, dynamic>? get _otherMember {
    for (final m in _members) {
      if (m['id']?.toString() != _myUserId) return m;
    }
    return null;
  }

  bool get _betsConflict {
    final mine = _betOf(_myMember);
    final other = _betOf(_otherMember);
    return (mine > 0 || other > 0) && mine != other;
  }

  /// Mise en jeu : au moins un joueur a posé une mise > 0.
  bool get _bettingActive {
    final mine = _betOf(_myMember);
    final other = _betOf(_otherMember);
    return mine > 0 || other > 0;
  }

  bool get _allBetsAgreed => _agreedOf(_myMember) && _agreedOf(_otherMember);

  bool get _canAcceptBet => _bettingActive && hasOpponent;

  bool get hasOpponent => _memberCount >= 2;

  Future<void> _loadMyCoins() async {
    if (_myUserId == null) return;
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('coins')
          .eq('id', _myUserId!)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(() => _myCoins = (row['coins'] as int?) ?? 0);
    } catch (_) {}
  }

  Future<void> _setBetAgreement(bool agreed) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _teamService.setMemberBetAgreement(
      widget.teamId,
      _myUserId!,
      agreed,
    );
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Erreur lors de la mise à jour de l\'accord.'),
        ),
      );
    }
  }

  Future<void> _saveBet() async {
    final bet = int.tryParse(_betController.text.trim()) ?? 0;
    if (bet < 0) return;
    if (bet > _myCoins) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mise supérieure à tes pièces ($_myCoins).')),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingBet = true);
    final ok = await _teamService.setMemberBet(widget.teamId, _myUserId!, bet);
    if (!mounted) return;
    setState(() => _savingBet = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? (bet > 0 ? 'Mise de $bet pièces enregistrée.' : 'Mise retirée.')
              : 'Erreur lors de l\'enregistrement de la mise.',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Le lobby reste impérativement en portrait.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _myUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadTeam();
    _loadMyCoins();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadTeam(),
    );
    if (widget.autoPublic && widget.isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startPublicMatchmaking();
      });
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _matchmakingTimer?.cancel();
    _betController.dispose();
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

    // Fusion matchmaking : cette équipe a été fusionnée dans une autre
    // (canal différent) → rouvrir le lobby sur l'équipe cible.
    final redirectedChannel = loadedTeam['channel_id']?.toString();
    if (redirectedChannel != null &&
        redirectedChannel.isNotEmpty &&
        redirectedChannel != widget.teamId) {
      _isNavigating = true;
      _refreshTimer?.cancel();
      _matchmakingTimer?.cancel();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FanoronaLobbyScreen(teamId: redirectedChannel, isHost: false),
          ),
        );
      }
      return;
    }

    if (loadedTeam['status'] == 'playing') {
      _isNavigating = true;
      _refreshTimer?.cancel();
      _matchmakingTimer?.cancel();
      if (mounted) _startGameFromTeam(loadedTeam);
      return;
    }

    setState(() => _team = loadedTeam);
  }

  List<Map<String, dynamic>> get _members {
    if (_team == null) return [];
    return _teamService.getMembersList(_team!);
  }

  int get _memberCount => _members.length;

  void _startGameFromTeam(Map<String, dynamic> team) {
    final channelId = team['channel_id']?.toString() ?? widget.teamId;
    final isHost =
        _myUserId != null && team['host_id']?.toString() == _myUserId;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FanoronaScreen(
          isOnline: true,
          isHost: isHost,
          teamId: widget.teamId,
          channelId: channelId,
        ),
      ),
    );
  }

  Future<void> _startPrivateGame() async {
    if (_team == null) return;
    if (_memberCount < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Partie privée requiert 2 joueurs. Invite un ami !'),
        ),
      );
      return;
    }
    if (_bettingActive && !_allBetsAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Acceptez tous les deux la mise pour lancer, ou modifiez-la.',
          ),
        ),
      );
      return;
    }
    if (_isSearching) await _teamService.cancelPublicWaiting(widget.teamId);
    await _teamService.startGame(widget.teamId);
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
      final opponent = await _teamService.findPublicMatch(widget.teamId);
      if (opponent == null) continue;
      final claimed = await _teamService.claimForMatch(
        opponent['team_id'] as String,
      );
      if (!claimed) continue;
      if (!mounted) return;
      final merged = await _teamService.mergeTeams(
        widget.teamId,
        opponent['team_id'] as String,
      );
      if (merged && mounted) {
        // Adversaire trouvé : on reste dans le lobby pour la mise.
        _matchmakingTimer?.cancel();
        _matchmakingTimer = null;
        await _teamService.cancelPublicWaiting(widget.teamId);
        if (!mounted) return;
        setState(() => _isSearching = false);
        await _loadTeam();
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
  }

  Future<void> _cancelPublicMatchmaking() async {
    _matchmakingTimer?.cancel();
    _matchmakingTimer = null;
    setState(() => _isSearching = false);
    await _teamService.cancelPublicWaiting(widget.teamId);
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
          const SnackBar(
            content: Text('Aucun ami à inviter. Ajoute des amis d\'abord !'),
          ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Icon(
                Icons.person_add_alt_1,
                color: Colors.amber.shade400,
                size: 24,
              ),
              const SizedBox(width: 10),
              const Text(
                'Inviter un ami',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
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
                    onTap: () => setDialogState(() {
                      selectedId = fid;
                      selectedName = fname;
                    }),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? Colors.amber : Colors.white12,
                          width: isSelected ? 1.5 : 1,
                        ),
                        color: isSelected
                            ? Colors.amber.withAlpha(25)
                            : Colors.white.withAlpha(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: Colors.white24,
                            backgroundImage:
                                avatarUrl != null && avatarUrl.isNotEmpty
                                ? cachedNetworkImage(avatarUrl)
                                : null,
                            child: avatarUrl == null || avatarUrl.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    color: Colors.white38,
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              fname,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
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
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
              ),
              onPressed: selectedId != null
                  ? () async {
                      Navigator.pop(ctx);
                      final hostProfile =
                          _team?['host_profile'] as Map<String, dynamic>?;
                      final hostName =
                          hostProfile?['username']?.toString() ??
                          hostProfile?['full_name']?.toString() ??
                          'Quelqu\'un';
                      try {
                        await FanoronaTeamInvitationService().sendInvitation(
                          inviteeId: selectedId!,
                          teamId: widget.teamId,
                          inviterName: hostName,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Invitation envoyée à $selectedName',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Erreur: $e')));
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

  Widget _buildBetSection() {
    final mine = _betOf(_myMember);
    final other = _betOf(_otherMember);
    final hasOpponent = _memberCount >= 2;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Mise (optionnelle)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '$_myCoins pièces',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Le gagnant remporte les 2/3 de la mise, l\'app conserve 1/3.',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _betController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: mine > 0 ? '$mine' : 'Ta mise',
                    hintStyle: TextStyle(
                      color: mine > 0 ? Colors.amber : Colors.white24,
                    ),
                    filled: true,
                    fillColor: Colors.black26,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _savingBet ? null : _saveBet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _savingBet
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Valider'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasOpponent
                ? 'Mises — Toi : $mine • Adversaire : $other'
                : 'En attente de l\'adversaire...',
            style: TextStyle(
              color: _betsConflict ? Colors.orangeAccent : Colors.white70,
              fontSize: 13,
              fontWeight: _betsConflict ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          if (_betsConflict)
            const Text(
              'Mises différentes — acceptez-les tous les deux pour lancer, ou modifiez.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          if (_canAcceptBet) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _agreedOf(_myMember)
                      ? OutlinedButton.icon(
                          onPressed: () => _setBetAgreement(false),
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.greenAccent,
                            size: 18,
                          ),
                          label: const Text(
                            'Mise acceptée (annuler)',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _setBetAgreement(true),
                          icon: const Icon(Icons.handshake, size: 18),
                          label: Text(
                            _betsConflict
                                ? 'Accepter ces mises'
                                : 'Accepter la mise de $mine',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade700,
                            foregroundColor: Colors.white,
                          ),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _agreedOf(_otherMember)
                  ? 'L\'adversaire a accepté la mise.'
                  : 'L\'adversaire n\'a pas encore accepté.',
              style: TextStyle(
                color: _agreedOf(_otherMember)
                    ? Colors.greenAccent
                    : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _memberSlot(Map<String, dynamic>? member) {
    if (member == null) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: const Center(
          child: Icon(Icons.person_add, color: Colors.white24, size: 40),
        ),
      );
    }
    final profile = member['profile'] as Map<String, dynamic>? ?? {};
    final name =
        profile['username']?.toString() ??
        profile['full_name']?.toString() ??
        'Joueur';
    final avatarUrl = profile['avatar_url']?.toString();
    final isMe = member['id']?.toString() == _myUserId;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isMe ? Colors.amber : Colors.white24,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: isMe ? const Color(0xFFFF8C00) : Colors.grey,
            backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                ? cachedNetworkImage(avatarUrl)
                : null,
            child: avatarUrl == null || avatarUrl.isEmpty
                ? const Icon(Icons.person, color: Colors.white, size: 32)
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            isMe
                ? 'Toi'
                : (member['id']?.toString() == _team?['host_id']?.toString()
                      ? 'Hôte'
                      : 'Invité'),
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isHost = widget.isHost;
    final members = _members;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(isHost ? 'Dissoudre l\'équipe' : 'Quitter l\'équipe'),
            content: Text(
              isHost
                  ? 'Veux-tu vraiment dissoudre l\'équipe ?'
                  : 'Veux-tu vraiment quitter l\'équipe ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Non'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Oui'),
              ),
            ],
          ),
        );
        if (confirm != true) return;
        if (_isSearching) await _cancelPublicMatchmaking();
        if (isHost) await _teamService.deleteTeam(widget.teamId);
        if (mounted) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('Lobby Fanorona #${widget.teamId}'),
          backgroundColor: const Color(0xFF8D4E00),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (_isSearching) await _cancelPublicMatchmaking();
              if (isHost) await _teamService.deleteTeam(widget.teamId);
              if (mounted) navigator.pop();
            },
          ),
        ),
        backgroundColor: const Color(0xFF1C1C2E),
        body: Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/background.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (context, viewport) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: IntrinsicHeight(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 12,
                              horizontal: 16,
                            ),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(46, 255, 255, 255),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Équipe: ${widget.teamId}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${members.length}/2',
                                  style: const TextStyle(
                                    color: Colors.amber,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 170,
                            child: Row(
                              children: [
                                Expanded(
                                  child: _memberSlot(
                                    members.isNotEmpty ? members[0] : null,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: _memberSlot(
                                    members.length > 1 ? members[1] : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (hasOpponent) ...[
                            _buildBetSection(),
                            const Spacer(),
                          ],
                          if (_isSearching) ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 20,
                                horizontal: 16,
                              ),
                              decoration: BoxDecoration(
                                color: const Color.fromARGB(46, 255, 255, 255),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                children: [
                                  const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: CircularProgressIndicator(
                                      color: Colors.orange,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Recherche d\'un adversaire...',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${_matchmakingTimeout - _matchmakingSeconds}s restantes',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton(
                                      onPressed: _cancelPublicMatchmaking,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        minimumSize: const Size.fromHeight(48),
                                      ),
                                      child: const Text('Annuler'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            const SizedBox(height: 24),
                            if (isHost)
                              Column(
                                children: [
                                  if (_memberCount < 2)
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: _showInviteFriendDialog,
                                        icon: const Icon(Icons.person_add),
                                        label: const Text('Inviter un ami'),
                                        style: ElevatedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                          backgroundColor:
                                              Colors.amber.shade700,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  if (_memberCount < 2)
                                    const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _startPrivateGame,
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              48,
                                            ),
                                          ),
                                          child: const Text('Lancer la partie'),
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: ElevatedButton(
                                          onPressed: _memberCount < 2
                                              ? _startPublicMatchmaking
                                              : null,
                                          style: ElevatedButton.styleFrom(
                                            minimumSize: const Size.fromHeight(
                                              48,
                                            ),
                                          ),
                                          child: const Text('Partie publique'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            if (!isHost)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Text(
                                  'En attente que l\'hôte démarre la partie...',
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
