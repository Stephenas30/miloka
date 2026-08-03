import 'dart:async';

import 'package:flutter/material.dart';
import 'package:miloka/service/friends_service.dart';

void showFriendsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Dialog(
          backgroundColor: Colors.black87,
          child: DefaultTabController(
            length: 3,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 450),
              child: Column(
                children: [
                  const TabBar(
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    indicatorColor: Colors.amber,
                    tabs: [
                      Tab(text: 'Amis'),
                      Tab(text: 'Demande'),
                      Tab(text: 'Recherche'),
                    ],
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _FriendsTabContent(),
                        _RequestsTabContent(),
                        _SearchTabContent(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _FriendsTabContent extends StatefulWidget {
  @override
  State<_FriendsTabContent> createState() => _FriendsTabContentState();
}

class _FriendsTabContentState extends State<_FriendsTabContent> {
  List<dynamic>? _friends;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    setState(() => _loading = true);
    try {
      _friends = await FriendsService().getFriendsList();
    } catch (_) {
      _friends = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_friends == null || _friends!.isEmpty) {
      return const Center(child: Text("Vous n'avez pas d'amis", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      itemCount: _friends!.length,
      itemBuilder: (ctx, i) {
        final f = _friends![i];
        final avatarUrl = f['avatar_url']?.toString();
        return Dismissible(
          key: ValueKey(f['id']),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: Colors.red,
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (ctx2) => AlertDialog(
                backgroundColor: Colors.grey[900],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text("Supprimer", style: TextStyle(color: Colors.white)),
                content: Text("Supprimer ${f['username']} de vos amis ?", style: const TextStyle(color: Colors.white70)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2, false),
                    child: const Text("Non", style: TextStyle(color: Colors.white54)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx2, true),
                    child: const Text("Oui", style: TextStyle(color: Colors.redAccent)),
                  ),
                ],
              ),
            );
          },
          onDismissed: (_) async {
            await FriendsService().removeFriend(f['id']);
            setState(() => _friends!.removeAt(i));
          },
          child: ListTile(
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
            title: Text(f['username'] ?? '', style: const TextStyle(color: Colors.white)),
            trailing: Icon(
              Icons.circle,
              color: f['is_connected'] == true ? Colors.green : Colors.red,
              size: 12,
            ),
            onTap: () {
              if (f['is_connected'] == true) {
                showDialog(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: const Text("Invitation de jeu"),
                    content: Text("Tu veux vraiment envoyer une invitation à ${f['username']} ?"),
                    actions: [
                      TextButton(
                        onPressed: () async {
                          await FriendsService().sendGameRequest(f['id']);
                          Navigator.pop(ctx2);
                        },
                        child: const Text("Accepter"),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2),
                        child: const Text("Refuser"),
                      ),
                    ],
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Votre ami n'est pas en ligne !")),
                );
              }
            },
          ),
        );
      },
    );
  }
}

class _RequestsTabContent extends StatefulWidget {
  @override
  State<_RequestsTabContent> createState() => _RequestsTabContentState();
}

class _RequestsTabContentState extends State<_RequestsTabContent> {
  List<dynamic>? _requests;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);
    try {
      _requests = await FriendsService().getFriendRequests();
    } catch (_) {
      _requests = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requests == null || _requests!.isEmpty) {
      return const Center(child: Text("Aucune demande d'ami", style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      itemCount: _requests!.length,
      itemBuilder: (ctx, i) {
        final req = _requests![i];
        final avatarUrl = req['avatar_url']?.toString();
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
          title: Text(req['username'] ?? '', style: const TextStyle(color: Colors.white)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.check_circle, color: Colors.green),
                onPressed: () async {
                  await FriendsService().acceptFriendRequest(req['id']);
                  _loadRequests();
                },
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red),
                onPressed: () async {
                  await FriendsService().declineFriendRequest(req['id']);
                  _loadRequests();
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SearchTabContent extends StatefulWidget {
  @override
  State<_SearchTabContent> createState() => _SearchTabContentState();
}

class _SearchTabContentState extends State<_SearchTabContent> {
  final TextEditingController _controller = TextEditingController();
  List<dynamic> _results = [];
  Set<String> _friendIds = {};
  Set<String> _pendingSentIds = {};
  bool _searching = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadFriendIds();
  }

  Future<void> _loadFriendIds() async {
    try {
      final friends = await FriendsService().getFriendsList();
      final pendingSent = await FriendsService().getPendingSentFriendIds();
      if (mounted) {
        setState(() {
          _friendIds = friends.map<String>((f) => f['id'].toString()).toSet();
          _pendingSentIds = pendingSent;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _searching = true);
      try {
        final r = await FriendsService().searchUsers(query.trim());
        if (mounted) setState(() => _results = r);
      } catch (_) {
        if (mounted) setState(() => _results = []);
      }
      if (mounted) setState(() => _searching = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _controller,
            onChanged: _onSearchChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Rechercher par pseudo...",
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? const Center(child: Text("Aucun résultat", style: TextStyle(color: Colors.white54)))
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final u = _results[i];
                        final avatarUrl = u['avatar_url']?.toString();
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
                          title: Text(u['username'] ?? '', style: const TextStyle(color: Colors.white)),
                          trailing: _friendIds.contains(u['id'].toString())
                              ? const Icon(Icons.check, color: Colors.green, size: 20)
                              : _pendingSentIds.contains(u['id'].toString())
                                  ? const Icon(Icons.hourglass_empty, color: Colors.orange, size: 20)
                                  : IconButton(
                                      icon: const Icon(Icons.person_add, color: Colors.amber),
                                      onPressed: () async {
                                        try {
                                          await FriendsService().addFriend(u['id']);
                                          setState(() => _pendingSentIds.add(u['id'].toString()));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Demande d\'ami envoyée !')),
                                          );
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text("Erreur: $e")),
                                          );
                                        }
                                      },
                                    ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
