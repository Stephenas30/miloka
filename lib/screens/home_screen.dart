import 'package:flutter/material.dart';
import 'package:miloka/service/friends_service.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/game_choice.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loadingfriends = false;
  bool loadingSfriends = false;
  List<bool> loadingAfriends = [];

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
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
                            loadingAfriends =
                                List<bool>.filled(suggestedFriends.length, false);
                          });

                          final menuItems = suggestedFriends.isNotEmpty
                              ? suggestedFriends
                                  .asMap()
                                  .entries
                                  .map<PopupMenuEntry<dynamic>>((entry) {
                                  final i = entry.key;
                                  final friend = entry.value;
                                  return PopupMenuItem(
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundImage:
                                            friend['avatar_url'] != null &&
                                                    friend['avatar_url']
                                                        .isNotEmpty
                                            ? NetworkImage(friend['avatar_url'])
                                            : null,
                                        child:
                                            friend['avatar_url'] == null ||
                                                    friend['avatar_url']
                                                        .isEmpty
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
