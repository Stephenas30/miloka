import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/friends_dialog.dart';
import '../widgets/game_choice_card.dart';
import '../widgets/game_mode_popup.dart';
import 'profile_screen.dart';
import 'purchase_screen.dart';

class BeloteScreen extends StatefulWidget {
  const BeloteScreen({super.key});

  @override
  State<BeloteScreen> createState() => _BeloteScreenState();
}

class _BeloteScreenState extends State<BeloteScreen> {
  // Déclare les clés ici
  final GlobalKey<GameChoiceCardState> card1Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card2Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card3Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card4Key = GlobalKey<GameChoiceCardState>();
  final GlobalKey<GameChoiceCardState> card5Key = GlobalKey<GameChoiceCardState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF006400),
        onPressed: () => Navigator.pop(context),
        child: const Icon(Icons.arrow_back, color: Colors.white),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage("assets/images/background.png"),
            fit: BoxFit.cover,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color.fromARGB(255, 255, 255, 255), Color.fromARGB(255, 255, 255, 255)],
              ).createShader(bounds),
              child: const Text(
                "Sélectionne ton défi",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GameChoiceCard(
                  key: card1Key,
                  title: "1 vs 1",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "1 vs 1",
                        onClosePopup: () {
                          card1Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card2Key,
                  title: "Classique",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Classique",
                        onClosePopup: () {
                          card2Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card3Key,
                  title: "Tournoi",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Tournoi",
                        onClosePopup: () {
                          card3Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 30),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GameChoiceCard(
                  key: card4Key,
                  title: "En ligne",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "En ligne",
                        onClosePopup: () {
                          card4Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
                const SizedBox(width: 20),
                GameChoiceCard(
                  key: card5Key,
                  title: "Contre IA",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => GameModePopup(
                        mode: "Contre IA",
                        onClosePopup: () {
                          card5Key.currentState?.resetCard();
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildTopBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final authProvider = context.read<AuthProvider?>();
    final coins = int.tryParse((authProvider?.userProfile?['coins'] ?? '0').toString()) ?? 0;
    final avatarUrl = authProvider?.userProfile?['avatar_url']?.toString();
    final username = authProvider?.userProfile?['username']?.toString() ?? 'Profil';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => showFriendsDialog(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const CircleAvatar(
              radius: 14,
              backgroundColor: Colors.black54,
              child: Icon(Icons.people_alt, color: Colors.white, size: 20),
            ),
          ),
        ),
        Row(
          spacing: 8,
          children: [
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl == null || avatarUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white, size: 16)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(username, style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseScreen())),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.monetization_on, color: Colors.amber, size: 20),
                    const SizedBox(width: 6),
                    Text('$coins', style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
