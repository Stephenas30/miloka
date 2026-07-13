import 'dart:async';

import 'package:flutter/material.dart';
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
  RealtimeChannel? _gameRequestChannel;
  RealtimeChannel? _gameResponseChannel;

  bool loadingfriends = false;
  bool loadingSfriends = false;

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
    _gameRequestChannel = SupabaseService().client.channel('game_pending_channel');
    final currentUser = SupabaseService().getCurrentUser();
    print(currentUser?.id);

    _gameRequestChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_ami',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        if (!mounted) return;
        final data = payload.newRecord;
        if (data['send_partie'] == 'pending') {
          showGameRequestPopup(data);
        }
        if (data['send_partie'] == 'none') {
          if (!mounted) return;
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
          showGameDeclinedPopup(data);
          if (!mounted) return;
          setState(() {
            fSubscribeToGame = [];
          });
        }
        if (data['send_partie'] == 'accepted') {
          if (!mounted) return;
          showWaitingGame();
          final fsg = await FriendsService().getHoteSubscribeToGam();
          if (!mounted) return;
          setState(() {
            fSubscribeToGame = fsg;
          });
        }
      },
    );
    _gameRequestChannel!.subscribe();
  }

  void _responseToGameRequests() {
    _gameResponseChannel = SupabaseService().client.channel('game_response_channel');
    final currentUser = SupabaseService().getCurrentUser();
    print(currentUser?.id);

    _gameResponseChannel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'amis',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id_user',
        value: currentUser?.id,
      ),
      callback: (payload) async {
        if (!mounted) return;
        final data = payload.newRecord;
        if (data['send_partie'] == 'declined') {
          if (!mounted) return;
          showGameDeclinedPopup(data);
        }
        if (data['send_partie'] == 'accepted' || data['send_partie'] == 'none') {
          final fsg = await FriendsService().getFriendsSubscribeToGam();
          if (!mounted) return;
          print(fsg);
          setState(() {
            fSubscribeToGame = fsg;
          });
        }
      },
    );
    _gameResponseChannel!.subscribe();
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
      print('Cancel');
      await SupabaseService().updateIsOffline();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _gameRequestChannel?.unsubscribe();
    _gameResponseChannel?.unsubscribe();
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
