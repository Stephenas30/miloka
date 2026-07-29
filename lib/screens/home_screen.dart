import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miloka/service/ludo_team_invitation_service.dart';
import 'package:miloka/screens/ludo_lobby_screen.dart';
import 'package:miloka/screens/ludo_screen.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:miloka/service/supabase_service.dart';
import 'package:miloka/service/team_invitation_service.dart';
import 'package:miloka/utils/retry_util.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/friends_dialog.dart';
import '../widgets/game_choice.dart';
import 'classic_team_lobby_screen.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _heartbeatTimer;
  bool _connectionLostDialogShown = false;
  bool _isConnectionHealthy = true;

  List<dynamic> fSubscribeToGame = [];
  dynamic _dataOnChannel;
  final List<RealtimeChannel> _homeChannels = [];
  List<Map<String, dynamic>> _pendingTeamInvitations = [];
  bool _isListeningLudoGlobal = false;
  BuildContext? _waitingDialogContext;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
    _subscribeToGameRequests();
    _responseToGameRequests();
    _subscribeToFriendNotifications();
    _subscribeToTeamInvitations();
  }

  void _listenChanelMultiplayerGame() {
    if (_isListeningLudoGlobal) return;
    _isListeningLudoGlobal = true;
    final channel = SupabaseService().client.channel('ludo_global');
    _homeChannels.add(channel);

    channel.onBroadcast(
      event: 'ludo_participants',
      callback: (payload, [ref]) {
        setState(() {
          _dataOnChannel = payload;
        });
      },
    );

    channel.subscribe();

    // Broadcast presence join so the host's ludo dialog picks up this player
    _broadcastPresenceJoin(channel);
  }

  Future<void> _broadcastPresenceJoin(RealtimeChannel channel) async {
    final currentUser = SupabaseService().getCurrentUser();
    if (currentUser == null) return;
    try {
      final userResp = await SupabaseService().client
          .from('users')
          .select('username')
          .eq('id', currentUser.id)
          .single();
      await channel.sendBroadcastMessage(
        event: 'ludo_presence',
        payload: {
          'type': 'presence',
          'action': 'join',
          'player': {
            'name': userResp['username']?.toString() ?? 'Joueur',
            'color': 'yellow',
          },
        },
      );
    } catch (_) {}
  }

  void _subscribeToGameRequests() {
    final channel = SupabaseService().client.channel('game_pending_channel');
    _homeChannels.add(channel);
    final currentUser = SupabaseService().getCurrentUser();
    print(currentUser?.id);

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_ami',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final data = payload.newRecord;
        if (data['send_partie'] == 'pending') showGameRequestPopup(data);
        if (data['send_partie'] == 'none') {
          if (mounted) {
            if (_waitingDialogContext != null) {
              Navigator.of(_waitingDialogContext!).pop();
              _waitingDialogContext = null;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('La partie a été annulée.')),
            );
          }
        }
        if (data['send_partie'] == 'accepted') {
          showWaitingGame();
          _listenChanelMultiplayerGame();

          final fsg = await FriendsService().getHoteSubscribeToGam();
          setState(() {
            fSubscribeToGame = fsg;
          });
        }
        if (data['send_partie'] == 'playing') {
          if (_waitingDialogContext != null) {
            Navigator.of(_waitingDialogContext!).pop();
            _waitingDialogContext = null;
          }
          print('data => ${_dataOnChannel['participants']}');
          final participantList =
              _dataOnChannel['participants'] as List<dynamic>?;
          if (participantList != null &&
              _dataOnChannel['event'] == 'ludo_participants') {
            final parsedParticipants = participantList
                .map<Map<String, dynamic>>((item) {
                  return Map<String, dynamic>.from(
                    item as Map<dynamic, dynamic>,
                  );
                })
                .toList();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => LudoScreen(
                  beginGame: true,
                  playerSubscribe: parsedParticipants,
                ),
              ),
            );
          }
        }
        //print(data);
      },
    );
    channel.subscribe();
  }

  void _responseToGameRequests() {
    final channel = SupabaseService().client.channel('game_response_channel');
    _homeChannels.add(channel);
    final currentUser = SupabaseService().getCurrentUser();
    print(currentUser?.id);

    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_user',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final data = payload.newRecord;
        if (data['send_partie'] == 'declined') showGameDeclinedPopup(data);
        if (data['send_partie'] == 'accepted' ||
            data['send_partie'] == 'none') {
          final fsg = await FriendsService().getFriendsSubscribeToGam();
          print(fsg);
          setState(() {
            fSubscribeToGame = fsg;
          });
        }
        //print(data);
      },
    );
    channel.subscribe();
  }

  void _subscribeToFriendNotifications() {
    final channel = SupabaseService().client.channel('friend_notif_channel');
    _homeChannels.add(channel);
    final currentUser = SupabaseService().getCurrentUser();

    // Nouvelle demande d'ami reçue
    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_ami',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final data = payload.newRecord;
        if (data['status'] == 'pending') {
          final requesterId = data['id_user'];
          final userResp = await SupabaseService().client
              .from('users')
              .select('username')
              .eq('id', requesterId)
              .single();
          if (mounted) {
            showFriendRequestPopup(
              requesterId.toString(),
              (userResp['username'] ?? 'Quelqu\'un').toString(),
            );
          }
        }
      },
    );

    // Demande d'ami acceptée
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_user',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final data = payload.newRecord;
        if (data['status'] == 'accepted') {
          final friendId = data['id_ami'];
          final userResp = await SupabaseService().client
              .from('users')
              .select('username')
              .eq('id', friendId)
              .single();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "${userResp['username']} a accepté votre demande d'ami !",
                ),
              ),
            );
          }
        }
      },
    );

    // Demande d'ami refusée
    channel.onPostgresChanges(
      event: PostgresChangeEvent.delete,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_user',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final oldData = payload.oldRecord;
        if (oldData['status'] == 'pending') {
          final friendId = oldData['id_ami'];
          final userResp = await SupabaseService().client
              .from('users')
              .select('username')
              .eq('id', friendId)
              .single();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  "${userResp['username']} a refusé votre demande d'ami.",
                ),
              ),
            );
          }
        }
      },
    );

    channel.subscribe();
  }

  Future<List<Map<String, dynamic>>> _loadPendingInvitations() async {
    final belote = await TeamInvitationService().getPendingInvitations();
    final ludo = await LudoTeamInvitationService().getPendingInvitations();
    return [...belote, ...ludo];
  }

  void _subscribeToTeamInvitations() {
    final channel = SupabaseService().client.channel('team_invitation_channel');
    _homeChannels.add(channel);
    final currentUser = SupabaseService().getCurrentUser();

    channel.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'team_invitations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'invitee_id',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final data = payload.newRecord;
        if (data['status'] == 'pending' && mounted) {
          final invitations = await _loadPendingInvitations();
          setState(() => _pendingTeamInvitations = invitations);
          _showTeamInvitationPopup();
        }
      },
    );

    // Also listen for status updates (when invitation is accepted/declined elsewhere)
    channel.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'team_invitations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'invitee_id',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        final invitations = await _loadPendingInvitations();
        if (mounted) setState(() => _pendingTeamInvitations = invitations);
      },
    );

    channel.subscribe();

    // Load existing pending invitations on init
    _loadPendingInvitations().then((invitations) {
      if (mounted) setState(() => _pendingTeamInvitations = invitations);
    });
  }

  void showFriendRequestPopup(String requesterId, String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Demande d'ami",
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          "$username vous a envoyé une demande d'ami !",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text(
              "Voir plus tard",
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FriendsService().acceptFriendRequest(requesterId);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        "Vous êtes maintenant ami avec $username !",
                      ),
                    ),
                  );
                }
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text("Erreur: $e")));
              }
            },
            child: const Text(
              "Accepter",
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }

  void showWaitingGame() {
    if (_waitingDialogContext != null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _waitingDialogContext = ctx;
        return const AlertDialog(
          content: Text('En attente du lancement de jeu ...'),
        );
      },
    ).then((_) => _waitingDialogContext = null);
  }

  void showGameDeclinedPopup(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Invitation de jeu"),
          content: Text(
            request['send_partie'] == "declined"
                ? "Ton ami a réfusé votre demande !"
                : "Votre ami vous avait fait sorti",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
              },
              child: Text("Fermer"),
            ),
          ],
        );
      },
    );
  }

  void _showTeamInvitationPopup() {
    if (_pendingTeamInvitations.isEmpty) return;
    final inv = _pendingTeamInvitations.first;
    final inviterName = inv['inviter_name']?.toString() ?? 'Quelqu\'un';
    final gameType = inv['game_type']?.toString() ?? 'belote';
    final gameName = gameType == 'ludo' ? 'Ludo' : 'belote';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Invitation équipe', style: TextStyle(color: Colors.white)),
        content: Text(
          '$inviterName vous a invité dans son équipe de $gameName',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (gameType == 'ludo') {
                await LudoTeamInvitationService().declineInvitation(inv['id']);
              } else {
                await TeamInvitationService().declineInvitation(inv['id']);
              }
              Navigator.pop(ctx);
              if (mounted) {
                final invitations = await _loadPendingInvitations();
                setState(() => _pendingTeamInvitations = invitations);
              }
            },
            child: const Text('Refuser', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (gameType == 'ludo') {
                final invResult = await LudoTeamInvitationService().acceptInvitation(inv['id']);
                if (invResult != null && mounted) {
                  final invitations = await _loadPendingInvitations();
                  setState(() => _pendingTeamInvitations = invitations);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LudoLobbyScreen(
                        teamId: invResult['team_id'],
                        isHost: false,
                      ),
                    ),
                  );
                }
              } else {
                final invResult = await TeamInvitationService().acceptInvitation(inv['id']);
                if (invResult != null && mounted) {
                  final invitations = await _loadPendingInvitations();
                  setState(() => _pendingTeamInvitations = invitations);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClassicTeamLobbyScreen(
                        teamId: invResult['team_id'],
                        isHost: false,
                      ),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Accepter', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void showGameRequestPopup(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Invitation de jeu"),
          content: Text(
            request['send_partie'] == "pending"
                ? "Ton ami veut jouer avec toi !"
                : "Veux-tu faire sortie ton ami?",
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Supabase.instance.client
                    .from('amis')
                    .update({
                      'send_partie': request['send_partie'] == "pending"
                          ? 'accepted'
                          : 'none',
                    })
                    .eq('id_ami', request['id_ami'])
                    .eq('id_user', request['id_user']);
                Navigator.pop(context);
              },
              child: Text("Accepter"),
            ),
            TextButton(
              onPressed: () async {
                if (request['send_partie'] == "pending") {
                  await Supabase.instance.client
                      .from('amis')
                      .update({'send_partie': 'declined'})
                      .eq('id_ami', request['id_ami'])
                      .eq('id_user', request['id_user']);
                }

                Navigator.pop(context);
              },
              child: Text("Refuser"),
            ),
          ],
        );
      },
    );
  }

  void _startHeartbeat() {
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      try {
        final ok = await SupabaseService().updateIsOnline();
        if (ok) {
          _isConnectionHealthy = true;
          return;
        }
      } catch (_) {}
      if (!_isConnectionHealthy) return;
      _isConnectionHealthy = false;
      _showConnectionLostDialog();
    });
  }

  void _showConnectionLostDialog() {
    if (!mounted || _connectionLostDialogShown) return;
    _connectionLostDialogShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Connexion perdue'),
          content: const Text('Problème de connexion réseau.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _tryReconnect();
              },
              child: const Text('Reconnecter'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _tryReconnect() async {
    try {
      await NetworkRetry.retry(() => SupabaseService().updateIsOnline());
      _isConnectionHealthy = true;
      _connectionLostDialogShown = false;
    } catch (_) {
      if (!mounted) return;
      _connectionLostDialogShown = false;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Connexion impossible'),
          content: const Text(
            'Vous avez perdu la connexion à cause de votre connexion ou le jeu est en maintenance. Réessayez plus tard.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _connectionLostDialogShown = false;
              },
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await SupabaseService().updateIsOffline();
    }
  }

  @override
  void dispose() {
    for (final channel in _homeChannels) {
      try {
        channel.unsubscribe();
      } catch (_) {}
    }
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _showFriendsDialog(BuildContext context) => showFriendsDialog(context);

  void _showSubscribedFriendsList() {
    if (fSubscribeToGame.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Amis invités",
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: fSubscribeToGame.length,
            itemBuilder: (ctx, index) {
              final friend = fSubscribeToGame[index];
              final avatarUrl = friend['avatar_url'];
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
                  friend['username'] ?? '',
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showRemoveFriendDialog(friend);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await FriendsService().removeAllFriendSubscribeToGame();
              final fsg = await FriendsService().getHoteSubscribeToGam();
              if (mounted) {
                setState(() => fSubscribeToGame = fsg);
                Navigator.pop(ctx);
              }
            },
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            label: const Text(
              "Tout supprimer",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveFriendDialog(dynamic friend) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Invitation de jeu"),
        content: Text("Tu veux vraiment faire sortir ${friend['username']} !"),
        actions: [
          TextButton(
            onPressed: () async {
              await FriendsService().removeFriendSubscribeToGam(friend['id']);
              final fsg = await FriendsService().getHoteSubscribeToGam();
              if (mounted) {
                setState(() => fSubscribeToGame = fsg);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text("Accepter"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Refuser"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ??
        0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username =
        authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Top controls: profil à gauche, boutique à droite
            Padding(
              padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (_pendingTeamInvitations.isNotEmpty) {
                        _showTeamInvitationPopup();
                      } else {
                        _showFriendsDialog(context);
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black54,
                            child: Icon(
                              Icons.people_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                        if (_pendingTeamInvitations.isNotEmpty)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 18,
                                minHeight: 18,
                              ),
                              child: Text(
                                '${_pendingTeamInvitations.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  Row(
                    spacing: 8,
                    children: [
                      GestureDetector(
                        onTap: () => _showSubscribedFriendsList(),
                        child: Row(
                          children: fSubscribeToGame.asMap().entries.map((
                            entry,
                          ) {
                            final index = entry.key;
                            final friend = entry.value;
                            final avatarUrl = friend['avatar_url'];
                            return Transform.translate(
                              offset: Offset(index == 0 ? 0 : -8.0 * index, 0),
                              child: CircleAvatar(
                                radius: 14,
                                backgroundColor: Colors.white24,
                                backgroundImage:
                                    avatarUrl != null && avatarUrl.isNotEmpty
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
                            );
                          }).toList(),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ProfileScreen(),
                            ),
                          );
                        },
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
                                backgroundImage:
                                    avatarUrl != null && avatarUrl.isNotEmpty
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
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PurchaseScreen(),
                            ),
                          );
                        },
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
              ),
            ),

            // Logo
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(
                child: Image.asset("assets/images/logo.png", height: 200),
              ),
            ),

            const SizedBox(height: 20),

            // Les cartes au centre
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: GameChoices(),
              ),
            ),

            // Signature en bas
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                "by SDS",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
