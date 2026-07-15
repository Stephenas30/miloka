import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miloka/screens/ludo_screen.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:miloka/service/supabase_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
import '../widgets/friends_dialog.dart';
import '../widgets/game_choice.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _heartbeatTimer;

  List<dynamic> fSubscribeToGame = [];

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
    _subscribeToGameRequests();
    _responseToGameRequests();
    _subscribeToFriendNotifications();
  }

  void _subscribeToGameRequests() {
    final channel = SupabaseService().client.channel('game_pending_channel');
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
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => HomeScreen()));
          }
        }
        if (data['send_partie'] == 'accepted') {
          showWaitingGame();
          final fsg = await FriendsService().getHoteSubscribeToGam();
          setState(() {
            fSubscribeToGame = fsg;
          });
        }
        if (data['send_partie'] == 'playing') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LudoScreen(beginGame: true,)));
        }
        //print(data);
      },
    );
    channel.subscribe();
  }

  void _responseToGameRequests() {
    final channel = SupabaseService().client.channel('game_response_channel');
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
        if (data['send_partie'] == 'accepted' || data['send_partie'] == 'none') {
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
                content: Text("${userResp['username']} a accepté votre demande d'ami !"),
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
                content: Text("${userResp['username']} a refusé votre demande d'ami."),
              ),
            );
          }
        }
      },
    );

    channel.subscribe();
  }

  void showFriendRequestPopup(String requesterId, String username) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Demande d'ami", style: TextStyle(color: Colors.white)),
        content: Text(
          "$username vous a envoyé une demande d'ami !",
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text("Voir plus tard", style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () async {
              try {
                await FriendsService().acceptFriendRequest(requesterId);
                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Vous êtes maintenant ami avec $username !")),
                  );
                }
              } catch (e) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Erreur: $e")),
                );
              }
            },
            child: const Text("Accepter", style: TextStyle(color: Colors.greenAccent)),
          ),
        ],
      ),
    );
  }

  void showWaitingGame(){
    showDialog(context: context, barrierDismissible: false, builder: (context) {
      return AlertDialog(
        content: Text('En attente du lancement de jeu ...')
      );
    });
  }

  void showGameDeclinedPopup(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Invitation de jeu"),
          content: Text(request['send_partie'] == "declined" ? "Ton ami a réfusé votre demande !" : "Votre ami vous avait fait sorti"),
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

  void showGameRequestPopup(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Invitation de jeu"),
          content: Text(request['send_partie'] == "pending" ? "Ton ami veut jouer avec toi !" : "Veux-tu faire sortie ton ami?"),
          actions: [
            TextButton(
              onPressed: () async {
                await Supabase.instance.client
                    .from('amis')
                    .update({'send_partie': request['send_partie'] == "pending" ? 'accepted' : 'none'})
                    .eq('id_ami', request['id_ami'])
                    .eq('id_user', request['id_user']);
                Navigator.pop(context);
              },
              child: Text("Accepter"),
            ),
            TextButton(
              onPressed: () async {
                if(request['send_partie'] == "pending"){
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
      await SupabaseService().updateIsOnline();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Mettre is_online à false quand l’app est quittée
      await SupabaseService().updateIsOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  void _showFriendsDialog(BuildContext context) => showFriendsDialog(context);

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
                    onTap: () => _showFriendsDialog(context),
                    child: Container(
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
                  ),

                  Row(
                    spacing: 8,
                    children: [
                      Stack(
                        children: [
                          ...fSubscribeToGame.map((friend) {
                            final avatarUrl = friend['avatar_url'];
                            return GestureDetector(
                              onTap: () {
                                showDialog(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: Text("Invitation de jeu"),
                                              content: Text(
                                                "Tu veux vraiment faire sortir ${friend['username']} !",
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () async {
                                                    await FriendsService()
                                                        .removeFriendSubscribeToGam(
                                                          friend['id'],
                                                        );
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text("Accepter"),
                                                ),
                                                TextButton(
                                                  onPressed: () async {
                                                    Navigator.pop(context);
                                                  },
                                                  child: Text("Refuser"),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                              },
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
                              )
                            );
                          },)
                          
                        ],
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
