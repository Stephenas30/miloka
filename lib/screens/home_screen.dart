import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:miloka/service/supabase_service.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../providers/auth_provider.dart';
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

  bool loadingfriends = false;
  bool loadingSfriends = false;

  List<dynamic> fSubscribeToGame = [];

  List<bool> loadingAfriends = [];

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startHeartbeat();
    _subscribeToGameRequests();
    _responseToGameRequests();
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
          showGameDeclinedPopup(data);
          setState(() {
            fSubscribeToGame = [];
          });
        }
        if (data['send_partie'] == 'accepted') {
          final fsg = await FriendsService().getHoteSubscribeToGam();
          setState(() {
            fSubscribeToGame = fsg;
          });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider?>(context);
    final coins =
        int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ??
        0;
    final avatarUrl = authProvider?.userProfile?['avatarUrl']?.toString();
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
                  Column(
                    children: [
                      GestureDetector(
                        onTap: () async {
                          setState(() {
                            loadingfriends = true;
                          });
                          var friends = await FriendsService().getFriendsList();
                          setState(() {
                            loadingfriends = false;
                          });
                          final menuItems = friends.isNotEmpty
                              ? friends.map<PopupMenuEntry<dynamic>>((friend) {
                                  return PopupMenuItem(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundImage:
                                            friend['avatar_url'] != null &&
                                                friend['avatar_url'].isNotEmpty
                                            ? NetworkImage(friend['avatar_url'])
                                            : null,
                                        child:
                                            friend['avatar_url'] == null ||
                                                friend['avatar_url'].isEmpty
                                            ? const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        friend['username'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      trailing: friend['is_connected']
                                          ? const Icon(
                                              Icons.circle,
                                              color: Colors.green,
                                              size: 12,
                                            )
                                          : const Icon(
                                              Icons.circle,
                                              color: Colors.red,
                                              size: 12,
                                            ),
                                    ),
                                    onTap: () async {
                                      if (friend['is_connected']) {
                                        showDialog(
                                          context: context,
                                          builder: (context) {
                                            return AlertDialog(
                                              title: Text("Invitation de jeu"),
                                              content: Text(
                                                "Tu veux vraiment envoyer un invitation à ${friend['username']} !",
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () async {
                                                    await FriendsService()
                                                        .sendGameRequest(
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
                                      } else {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Votre ami n\'est pas en ligne!',
                                            ),
                                            backgroundColor: Colors.amberAccent,
                                          ),
                                        );
                                      }
                                    },
                                  );
                                }).toList()
                              : [
                                  const PopupMenuItem(
                                    child: Text(
                                      'Vous n\'avez pas d\'amis',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ];
                          showMenu(
                            context: context,
                            items: menuItems,
                            position: RelativeRect.fromRect(
                              Rect.fromLTWH(0, 0, 100, 100),
                              Offset.zero & Size.zero,
                            ),
                            color: Colors.black54,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black54,
                            child: loadingfriends
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    Icons.people_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          setState(() {
                            loadingSfriends = true;
                            loadingAfriends = [];
                          });
                          var suggestedFriends = await FriendsService()
                              .getSuggestedFriends();
                          setState(() {
                            loadingSfriends = false;
                            loadingAfriends = List<bool>.filled(
                              suggestedFriends.length,
                              false,
                            );
                          });

                          final menuItems = suggestedFriends.isNotEmpty
                              ? suggestedFriends.asMap().entries.map<
                                  PopupMenuEntry<dynamic>
                                >((entry) {
                                  final i = entry.key;
                                  final friend = entry.value;
                                  return PopupMenuItem(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundImage:
                                            friend['avatar_url'] != null &&
                                                friend['avatar_url'].isNotEmpty
                                            ? NetworkImage(friend['avatar_url'])
                                            : null,
                                        child:
                                            friend['avatar_url'] == null ||
                                                friend['avatar_url'].isEmpty
                                            ? const Icon(
                                                Icons.person,
                                                color: Colors.white,
                                              )
                                            : null,
                                      ),
                                      title: Text(
                                        friend['username'],
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                      trailing: IconButton(
                                        onPressed: () async {
                                          setState(() {
                                            loadingAfriends[i] = true;
                                          });
                                          try {
                                            await FriendsService().addFriend(
                                              friend['id'],
                                            );
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  '${friend['username']} a été ajouté à vos amis.',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'Erreur lors de l\'ajout de ${friend['username']} à vos amis: $e',
                                                ),
                                              ),
                                            );
                                          } finally {
                                            print(loadingAfriends);
                                            setState(() {
                                              loadingAfriends[i] = false;
                                            });
                                          }
                                        },
                                        icon: loadingAfriends[i]
                                            ? const CircularProgressIndicator(
                                                color: Colors.white,
                                              )
                                            : const Icon(
                                                Icons.person_add,
                                                color: Colors.white,
                                              ),
                                      ),
                                    ),
                                  );
                                }).toList()
                              : [
                                  const PopupMenuItem(
                                    child: Text('Aucun ami suggéré'),
                                  ),
                                ];
                          showMenu(
                            context: context,
                            items: menuItems,
                            position: RelativeRect.fromRect(
                              Rect.fromLTWH(0, 0, 100, 100),
                              Offset.zero & Size.zero,
                            ),
                            color: Colors.black54,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black54,
                            child: loadingSfriends
                                ? const CircularProgressIndicator(
                                    color: Colors.white,
                                  )
                                : const Icon(
                                    Icons.person_add,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ),
                    ],
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

            // Logo en haut
            Padding(
              padding: const EdgeInsets.only(top: 0),
              child: Center(
                child: Image.asset("assets/images/logo.png", height: 200),
              ),
            ),

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
