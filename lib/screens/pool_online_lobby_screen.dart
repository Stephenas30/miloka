import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../game/pool_game.dart';
import '../service/friends_service.dart';
import '../service/game_channel_service.dart';
import '../service/pool_team_invitation_service.dart';
import '../service/pool_team_lobby_service.dart';
import '../utils/image_cache.dart';
import 'pool_screen.dart';

class PoolOnlineLobbyScreen extends StatefulWidget {
  const PoolOnlineLobbyScreen({
    super.key,
    this.teamId,
    this.isHost = true,
    this.showEntryDialog = false,
  });

  final String? teamId;
  final bool isHost;
  final bool showEntryDialog;

  @override
  State<PoolOnlineLobbyScreen> createState() => _PoolOnlineLobbyScreenState();
}

class _PoolOnlineLobbyScreenState extends State<PoolOnlineLobbyScreen> {
  static const _matchmakingLimit = 60;

  /// Identifiant unique par appareil/session pour ignorer ses propres
  /// messages de broadcast (le filtre ne peut pas se baser sur _userId :
  /// les deux joueurs peuvent utiliser le même compte).
  final _sessionId =
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}'
      '${Random().nextInt(1 << 20).toRadixString(16)}';

  final _lobbies = PoolTeamLobbyService.instance;
  final _gameChannel = GameChannelService();
  final _betController = TextEditingController();
  Timer? _pollTimer;
  Timer? _searchTimer;
  StreamSubscription<Map<String, dynamic>>? _gameSubscription;
  StreamController<String>? _remoteMoves;
  String? _roomId;
  String? _userId;
  String? _error;
  bool _isHost = true;
  bool _isPublicSearch = false;
  bool _isCreatingRoom = false;
  bool _isSavingBet = false;
  bool _isSettlingResult = false;
  bool _didSettleResult = false;
  bool _isPolling = false;
  bool _isStarting = false;
  int _searchSeconds = 0;
  Map<String, dynamic>? _room;
  int _myCoins = 0;

  @override
  void initState() {
    super.initState();
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _isHost = widget.isHost;
    _roomId = widget.teamId;
    unawaited(_loadMyCoins());
    if (_roomId != null) _startPolling();
    if (widget.showEntryDialog && _roomId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_showOnlineEntryDialog());
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    _gameSubscription?.cancel();
    _remoteMoves?.close();
    _betController.dispose();
    unawaited(_gameChannel.disconnect());
    super.dispose();
  }

  Future<void> _loadMyCoins() async {
    try {
      final coins = await _lobbies.getCurrentUserCoins();
      if (mounted) setState(() => _myCoins = coins);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Impossible de charger votre solde : $error');
      }
    }
  }

  Future<void> _createRoom({required bool publicMatch}) async {
    if (_isCreatingRoom) return;
    if (_userId == null) {
      setState(() => _error = 'Connectez-vous à Kadri pour jouer en ligne.');
      return;
    }
    setState(() {
      _error = null;
      _isCreatingRoom = true;
      _isHost = true;
      _isPublicSearch = publicMatch;
    });
    try {
      _roomId = await _lobbies.createRoom(publicMatch: publicMatch);
      if (!mounted) return;
      _searchSeconds = 0;
      _startPolling();
      if (publicMatch) {
        _searchTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _searchSeconds++);
          if (_searchSeconds >= _matchmakingLimit) {
            unawaited(_cancelPublicSearch());
          }
        });
      } else {
        await _showFriends();
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Impossible de créer le salon : $error');
    } finally {
      if (mounted) setState(() => _isCreatingRoom = false);
    }
  }

  Future<void> _showOnlineEntryDialog() async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Partie en ligne',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Crée un salon pour inviter un ami ou chercher un adversaire, ou rejoins une partie avec son code.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'create'),
            child: const Text('Créer', style: TextStyle(color: Colors.amber)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'join'),
            child: const Text(
              'Rejoindre',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'join') {
      await _showJoinDialog();
    }
  }

  Future<void> _showJoinDialog() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E2C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Rejoindre une partie',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setDialogState(() {}),
            decoration: const InputDecoration(
              labelText: 'Code du salon',
              labelStyle: TextStyle(color: Colors.white54),
              hintText: 'ex. 123456',
              hintStyle: TextStyle(color: Colors.white24),
              counterText: '',
            ),
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.white54),
              ),
            ),
            ElevatedButton(
              onPressed: controller.text.length == 6
                  ? () => Navigator.pop(dialogContext, controller.text)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Rejoindre'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (code == null || !mounted) return;

    setState(() {
      _isCreatingRoom = true;
      _error = null;
    });
    try {
      final roomId = await _lobbies.joinRoomByCode(code);
      if (roomId == null) {
        throw StateError('Code invalide, salon fermé ou déjà complet.');
      }
      if (!mounted) return;
      setState(() {
        _roomId = roomId;
        _isHost = false;
        _isPublicSearch = false;
      });
      _startPolling();
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Impossible de rejoindre le salon : $error');
      }
    } finally {
      if (mounted) setState(() => _isCreatingRoom = false);
    }
  }

  Future<void> _copyJoinCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Code du salon copié.')));
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => unawaited(_pollRoom()),
    );
    unawaited(_pollRoom());
  }

  Future<void> _pollRoom() async {
    if (!mounted || _roomId == null || _isPolling || _isStarting) return;
    _isPolling = true;
    try {
      final room = await _lobbies.getRoom(_roomId!);
      if (!mounted) return;
      if (room == null ||
          (room['status'] == 'cancelled' && room['matched_team_id'] == null)) {
        setState(() {
          _room = room;
          _error = 'Ce salon n’est plus disponible.';
        });
        return;
      }
      setState(() {
        _room = room;
        _error = null;
      });

      if (_isPublicSearch && room['status'] == 'cancelled') {
        final matchedRoomId = room['matched_team_id']?.toString();
        if (matchedRoomId != null) {
          _roomId = matchedRoomId;
          _isHost = false;
          _isPublicSearch = false;
          _searchTimer?.cancel();
          _searchTimer = null;
        }
      } else if (_isPublicSearch && room['status'] == 'public_waiting') {
        await _lobbies.tryMatchPublicRoom(_roomId!);
      } else if (room['status'] == 'matched') {
        _isPublicSearch = false;
        _searchTimer?.cancel();
        _searchTimer = null;
      } else if (room['status'] == 'playing') {
        await _launchFlutterGame(room);
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Erreur de connexion au salon : $error');
    } finally {
      _isPolling = false;
    }
  }

  int _profileBet(Map<String, dynamic>? profile) =>
      (profile?['bet'] as num?)?.toInt() ?? 0;

  bool _profileAgreed(Map<String, dynamic>? profile) =>
      profile?['bet_agreed'] == true;

  Future<void> _saveBet() async {
    final roomId = _roomId;
    final bet = int.tryParse(_betController.text.trim());
    if (roomId == null || bet == null || bet < 0) {
      setState(() => _error = 'Entrez une mise valide (0 ou plus).');
      return;
    }
    setState(() {
      _isSavingBet = true;
      _error = null;
    });
    try {
      final updated = await _lobbies.setRoomBet(roomId, bet);
      if (!updated) throw StateError('La mise n’a pas pu être enregistrée.');
      await _loadMyCoins();
      await _pollRoom();
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Impossible d’enregistrer la mise : $error');
    } finally {
      if (mounted) setState(() => _isSavingBet = false);
    }
  }

  Future<void> _setBetAgreement(bool agreed) async {
    final roomId = _roomId;
    if (roomId == null) return;
    try {
      final updated = await _lobbies.setBetAgreement(roomId, agreed);
      if (!updated) throw StateError('L’accord n’a pas pu être modifié.');
      await _pollRoom();
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Impossible de confirmer la mise : $error');
    }
  }

  Future<void> _startMatchedGame() async {
    final roomId = _roomId;
    if (roomId == null || !_isHost || _isStarting) return;
    setState(() {
      _isStarting = true;
      _error = null;
    });
    try {
      final started = await _lobbies.startRoom(
        roomId,
        DateTime.now().microsecondsSinceEpoch,
      );
      if (!started) {
        throw StateError(
          'Les deux joueurs doivent accepter la mise avant le lancement.',
        );
      }
      await _pollRoom();
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Impossible de lancer la partie : $error');
    } finally {
      if (mounted) setState(() => _isStarting = false);
    }
  }

  Future<void> _showFriends() async {
    try {
      final friends = await FriendsService().getFriendsList();
      if (!mounted) return;
      if (friends.isEmpty) {
        setState(
          () => _error = 'Ajoutez un ami dans Kadri avant de l’inviter.',
        );
        return;
      }
      final friend = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) {
          String? selectedId;
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) => AlertDialog(
              backgroundColor: const Color(0xFF1E1E2C),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.person_add_alt_1, color: Colors.amber, size: 24),
                  SizedBox(width: 10),
                  Text(
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
                width: 320,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final item = Map<String, dynamic>.from(friends[index]);
                    final id = item['id']?.toString();
                    final name = item['username']?.toString() ?? 'Joueur';
                    final avatarUrl = item['avatar_url']?.toString();
                    final selected = id != null && id == selectedId;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: id == null
                            ? null
                            : () => setDialogState(() => selectedId = id),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? Colors.amber : Colors.white12,
                              width: selected ? 1.5 : 1,
                            ),
                            color: selected
                                ? Colors.amber.withAlpha(25)
                                : Colors.white.withAlpha(10),
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
                                  name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Icon(
                                selected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                color: selected ? Colors.amber : Colors.white38,
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
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedId == null
                      ? null
                      : () {
                          final selectedFriend = friends.firstWhere(
                            (item) => item['id']?.toString() == selectedId,
                          );
                          Navigator.pop(
                            dialogContext,
                            Map<String, dynamic>.from(selectedFriend),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Envoyer'),
                ),
              ],
            ),
          );
        },
      );
      if (friend == null || _roomId == null || !mounted) return;
      final username =
          Supabase.instance.client.auth.currentUser?.userMetadata?['username']
              ?.toString() ??
          Supabase.instance.client.auth.currentUser?.userMetadata?['name']
              ?.toString() ??
          'Un ami';
      await PoolTeamInvitationService().sendInvitation(
        inviteeId: friend['id'].toString(),
        teamId: _roomId!,
        inviterName: username,
      );
      if (mounted) {
        setState(
          () => _error =
              'Invitation envoyée à ${friend['username'] ?? 'votre ami'}.',
        );
      }
    } catch (error) {
      if (mounted)
        setState(() => _error = 'Impossible d’envoyer l’invitation : $error');
    }
  }

  Future<void> _launchFlutterGame(Map<String, dynamic> room) async {
    if (_isStarting || _roomId == null) return;
    _isStarting = true;
    _searchTimer?.cancel();
    _searchTimer = null;
    try {
      await _gameChannel.connect(_roomId!);
      await _gameSubscription?.cancel();
      await _remoteMoves?.close();
      final remoteMoves = StreamController<String>.broadcast();
      _remoteMoves = remoteMoves;
      _gameSubscription = _gameChannel.events.listen((event) {
        if (event['action'] == 'pool_result') {
          if (event['_sid'] != _sessionId) _refreshUserProfile();
          return;
        }
        if (event['action'] != 'pool_move' ||
            event['_sid'] == _sessionId ||
            event['line'] is! String) {
          return;
        }
        remoteMoves.add(event['line'] as String);
      });
      final seed =
          (room['game_seed'] as num?)?.toInt() ??
          int.tryParse('${room['game_seed'] ?? ''}') ??
          DateTime.now().microsecondsSinceEpoch;
      final hostBet = _profileBet(
        room['host_profile'] is Map
            ? Map<String, dynamic>.from(room['host_profile'] as Map)
            : null,
      );
      final guestBet = _profileBet(
        room['guest_profile'] is Map
            ? Map<String, dynamic>.from(room['guest_profile'] as Map)
            : null,
      );
      _pollTimer?.cancel();
      _pollTimer = null;
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PoolGameScreen(
            mode: PoolMode.online,
            kadri: KadriPoolSession(
              seed: seed,
              playerIndex: _isHost ? 0 : 1,
              hostBet: hostBet,
              guestBet: guestBet,
              onSendLine: (line) {
                final userId = _userId;
                if (userId != null) {
                  unawaited(
                    _gameChannel.send('pool_move', {
                      'line': line,
                      '_sid': _sessionId,
                    }, from: userId),
                  );
                }
              },
              remoteLines: remoteMoves.stream,
              onGameFinished: (winnerIndex) =>
                  unawaited(_onPoolGameFinished(winnerIndex)),
              onClosed: _closeOnlineGame,
            ),
          ),
        ),
      );
    } catch (error) {
      await _gameSubscription?.cancel();
      _gameSubscription = null;
      await _remoteMoves?.close();
      _remoteMoves = null;
      await _gameChannel.disconnect();
      if (mounted) {
        setState(() => _error = 'Impossible de lancer la partie : $error');
      }
    } finally {
      _isStarting = false;
    }
  }

  Future<void> _onPoolGameFinished(int winnerIndex) async {
    if (!_isHost || _roomId == null || _didSettleResult || _isSettlingResult) {
      return;
    }
    _isSettlingResult = true;
    try {
      Object? lastError;
      for (var attempt = 0; attempt < 3 && !_didSettleResult; attempt++) {
        try {
          final settled = await _lobbies.settleRoom(_roomId!, winnerIndex);
          if (!settled) {
            final room = await _lobbies.getRoom(_roomId!);
            if (room?['settled_at'] == null) {
              throw StateError('Le règlement de la mise a échoué.');
            }
          }
          _didSettleResult = true;
        } catch (error) {
          lastError = error;
          if (attempt < 2) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      }
      if (!_didSettleResult) {
        throw StateError('Échec après trois tentatives : $lastError');
      }
      _refreshUserProfile();
      final userId = _userId;
      if (userId != null) {
        await _gameChannel.send('pool_result', {
          'winnerIndex': winnerIndex,
          '_sid': _sessionId,
        }, from: userId);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Impossible de régler la mise : $error');
      }
    } finally {
      _isSettlingResult = false;
    }
  }

  void _refreshUserProfile() {
    unawaited(
      context.read<AuthProvider?>()?.refreshProfile() ?? Future<void>.value(),
    );
    unawaited(_loadMyCoins());
  }

  void _closeOnlineGame() {
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _cancelPublicSearch() async {
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    _pollTimer = null;
    _searchTimer = null;
    final roomId = _roomId;
    if (roomId != null && _isHost) await _lobbies.cancelRoom(roomId);
    if (!mounted) return;
    setState(() {
      _roomId = null;
      _room = null;
      _isPublicSearch = false;
      _searchSeconds = 0;
      _error = 'Aucun adversaire trouvé. Réessayez plus tard.';
    });
  }

  Future<void> _cancelAndLeave() async {
    _pollTimer?.cancel();
    _searchTimer?.cancel();
    final roomId = _roomId;
    if (roomId != null && _isHost) {
      try {
        await _lobbies.cancelRoom(roomId);
      } catch (error) {
        if (mounted) {
          setState(() => _error = 'Impossible de fermer le salon : $error');
          return;
        }
      }
    }
    if (mounted) Navigator.of(context).pop();
  }

  Widget _playerSlot(Map<String, dynamic>? profile, {required bool isMe}) {
    final name =
        profile?['username']?.toString() ??
        profile?['full_name']?.toString() ??
        (isMe ? 'Vous' : null);
    final avatarUrl = profile?['avatar_url']?.toString();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(profile == null ? 10 : 12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: profile == null
              ? Colors.white12
              : isMe
              ? Colors.amber
              : Colors.white24,
          width: isMe ? 2 : 1,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 31,
              backgroundColor: Colors.white24,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? cachedNetworkImage(avatarUrl)
                  : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Icon(
                      profile == null ? Icons.person_add : Icons.person,
                      color: profile == null ? Colors.white24 : Colors.white70,
                      size: 32,
                    )
                  : null,
            ),
            const SizedBox(height: 10),
            Text(
              name ?? 'En attente…',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              profile == null
                  ? 'Place libre'
                  : isMe
                  ? 'Toi'
                  : _isHost
                  ? 'Invité'
                  : 'Hôte',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchStatus() {
    final remaining = (_matchmakingLimit - _searchSeconds).clamp(
      0,
      _matchmakingLimit,
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(46),
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
            'Recherche d’un adversaire…',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$remaining s restantes',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _cancelPublicSearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Annuler'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetSection(
    Map<String, dynamic>? hostProfile,
    Map<String, dynamic>? guestProfile,
  ) {
    final myProfile = _isHost ? hostProfile : guestProfile;
    final opponentProfile = _isHost ? guestProfile : hostProfile;
    final myBet = _profileBet(myProfile);
    final opponentBet = _profileBet(opponentProfile);
    final bettingActive = myBet > 0 || opponentBet > 0;
    final myAgreed = _profileAgreed(myProfile);
    final opponentAgreed = _profileAgreed(opponentProfile);
    final canStart = !bettingActive || (myAgreed && opponentAgreed);

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
          const Text(
            'Le gagnant reçoit les 2/3 de la mise du perdant. 1/3 revient à Kadri.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
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
                    hintText: myBet > 0 ? '$myBet' : 'Votre mise',
                    hintStyle: TextStyle(
                      color: myBet > 0 ? Colors.amber : Colors.white24,
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
                onPressed: _isSavingBet ? null : _saveBet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                ),
                child: _isSavingBet
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
            'Mises — Vous : $myBet • Adversaire : $opponentBet',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (bettingActive) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: myAgreed
                  ? OutlinedButton.icon(
                      onPressed: () => _setBetAgreement(false),
                      icon: const Icon(
                        Icons.check_circle,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                      label: const Text(
                        'Mise acceptée (annuler)',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => _setBetAgreement(true),
                      icon: const Icon(Icons.handshake, size: 18),
                      label: Text(
                        'Accepter les mises (${_isHost ? _profileBet(hostProfile) : _profileBet(guestProfile)} / ${_isHost ? _profileBet(guestProfile) : _profileBet(hostProfile)})',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        foregroundColor: Colors.white,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              opponentAgreed
                  ? 'Votre adversaire a accepté la mise.'
                  : 'Votre adversaire n’a pas encore accepté.',
              style: TextStyle(
                color: opponentAgreed ? Colors.greenAccent : Colors.white54,
                fontSize: 12,
              ),
            ),
          ],
          if (_isHost) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canStart && !_isStarting ? _startMatchedGame : null,
                icon: _isStarting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: const Text('Lancer la partie'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
            const Center(
              child: Text(
                'En attente du lancement par l’hôte…',
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWaiting = _roomId != null;
    final roomStatus = _room?['status']?.toString();
    final hostProfile = _room?['host_profile'] is Map
        ? Map<String, dynamic>.from(_room!['host_profile'] as Map)
        : null;
    final guestProfile =
        _room?['guest_id'] != null && _room?['guest_profile'] is Map
        ? Map<String, dynamic>.from(_room!['guest_profile'] as Map)
        : null;
    final joinCode = _room?['join_code']?.toString();
    final hasPrivateJoinCode =
        _room?['access_type'] == 'friend' &&
        joinCode != null &&
        RegExp(r'^\d{6}$').hasMatch(joinCode);
    final myProfile = _isHost ? hostProfile : guestProfile;
    final opponentProfile = _isHost ? guestProfile : hostProfile;
    final authProfile = context.read<AuthProvider?>()?.userProfile;
    final userName =
        authProfile?['username']?.toString() ??
        authProfile?['full_name']?.toString() ??
        'Profil';
    final avatarUrl = authProfile?['avatar_url']?.toString();
    final statusMessage = !isWaiting
        ? 'Jouez avec un ami ou trouvez un adversaire.'
        : roomStatus == 'playing'
        ? 'La partie commence…'
        : roomStatus == 'matched'
        ? 'Adversaire trouvé. Choisissez vos mises avant de jouer.'
        : _isPublicSearch
        ? 'Recherche d’un adversaire…'
        : 'En attente de la réponse de votre ami…';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lobby Billard'),
        backgroundColor: const Color(0xFF8D4E00),
        foregroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
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
                          backgroundImage:
                              avatarUrl != null && avatarUrl.isNotEmpty
                              ? cachedNetworkImage(avatarUrl)
                              : null,
                          child: avatarUrl == null || avatarUrl.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  color: Colors.white,
                                  size: 15,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 100),
                          child: Text(
                            userName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
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
                          '$_myCoins',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Retour à Kadri',
          onPressed: _cancelAndLeave,
        ),
      ),
      backgroundColor: const Color(0xFF1C1C2E),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset('assets/images/background.jpg', fit: BoxFit.cover),
          ColoredBox(color: Colors.black.withValues(alpha: .22)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (isWaiting) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 16,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlpha(46),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (hasPrivateJoinCode)
                                TextButton.icon(
                                  onPressed: () => _copyJoinCode(joinCode),
                                  icon: const Icon(
                                    Icons.copy,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: Text(
                                    'Code : $joinCode',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                )
                              else
                                const Text(
                                  'Partie publique',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Text(
                                '${guestProfile == null ? 1 : 2}/2',
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
                                child: _playerSlot(myProfile, isMe: true),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: _playerSlot(
                                  opponentProfile,
                                  isMe: false,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (!isWaiting) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCreatingRoom
                                ? null
                                : () => _createRoom(publicMatch: false),
                            icon: const Icon(Icons.person_add),
                            label: const Text('Inviter un ami'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCreatingRoom
                                ? null
                                : () => _createRoom(publicMatch: true),
                            icon: const Icon(Icons.wifi),
                            label: const Text('Partie publique'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: const Color(0xFF8D4E00),
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        if (_isCreatingRoom) ...[
                          const SizedBox(height: 20),
                          const Center(
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ] else if (_isPublicSearch &&
                          roomStatus == 'public_waiting') ...[
                        _buildSearchStatus(),
                      ] else if (_isHost && roomStatus == 'waiting') ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showFriends,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Inviter un ami'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _cancelAndLeave,
                          icon: const Icon(Icons.close),
                          label: const Text('Fermer le salon'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                        ),
                      ] else if (roomStatus == 'matched') ...[
                        _buildBetSection(hostProfile, guestProfile),
                      ] else if (roomStatus == 'playing') ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ] else if (isWaiting && _room == null) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFFD180)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
